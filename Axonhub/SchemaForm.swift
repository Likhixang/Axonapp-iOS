import Foundation
import SwiftUI

struct AdminField: Decodable, Identifiable {
    let name: String
    let type: String
    let description: String
    let hasDefault: Bool
    let `default`: JSON?
    var id: String { name }
    var required: Bool { type.hasSuffix("!") }
}

struct AdminSchemaType: Decodable {
    let kind: String
    let fields: [AdminField]
    let values: [String]
}

struct AdminOperation: Decodable, Identifiable {
    let id: String
    let name: String
    let documentKey: String
    let root: String
    let kind: String
    let group: String
    let variables: [AdminField]
    let entity: String
    let verification: String
    let destructive: Bool
    let replacement: Bool
    let allowedInputFields: [String]
    let source: String
    let secretRead: Bool
    let asyncEffect: Bool
    var mutation: Bool { kind == "mutation" }
    var document: String { AdminDocuments.document(documentKey) ?? "" }
    var title: String { NativeAdminLabels.operation(id) }
}

struct AdminSchema: Decodable {
    let revision: String
    let types: [String: AdminSchemaType]
    let operations: [AdminOperation]
    static let loaded: Result<AdminSchema, Error> = Result {
        guard let url = Bundle.main.url(forResource: "AdminSchema", withExtension: "json") else {
            throw AdminError.schemaMissing
        }
        return try JSONDecoder().decode(AdminSchema.self, from: Data(contentsOf: url))
    }
    func operation(_ id: String) throws -> AdminOperation {
        guard let value = operations.first(where: { $0.id == id }), !value.document.isEmpty else {
            throw AdminError.schemaMissing
        }
        return value
    }
    func base(_ type: String) -> String { type.replacingOccurrences(of: "!", with: "").replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: "") }
    func element(_ type: String) -> String {
        let plain = type.hasSuffix("!") ? String(type.dropLast()) : type
        guard plain.hasPrefix("["), plain.hasSuffix("]") else { return plain }
        return String(plain.dropFirst().dropLast())
    }
    func defaultValue(_ type: String, depth: Int = 0) -> JSON {
        if type.hasPrefix("[") { return .array([]) }
        let name = base(type)
        guard depth < 20 else { return .object([:]) }
        if let info = types[name] {
            if info.kind == "enum" { return .string(info.values.first ?? "") }
            if info.kind == "object" {
                return .object(Dictionary(uniqueKeysWithValues: info.fields.compactMap { field in
                    if field.hasDefault, let value = field.default { return (field.name, value) }
                    return field.required ? (field.name, defaultValue(field.type, depth: depth + 1)) : nil
                }))
            }
        }
        switch name {
        case "Boolean": return .bool(false)
        case "Int", "Float": return .number(0)
        case "JSONRawMessage", "JSONRawMessageInput": return .object([:])
        default: return .string("")
        }
    }
    /// Only declared input keys; never put response IDs/__typename/output-only fields into writes.
    func project(_ value: JSON, type: String) -> JSON {
        if value.isNull { return value }
        if type.hasPrefix("[") { return .array(value.array.map { project($0, type: element(type)) }) }
        guard let info = types[base(type)], info.kind == "object" else { return value }
        var output: [String: JSON] = [:]
        for field in info.fields {
            if let v = value.object[field.name], !v.isNull { output[field.name] = project(v, type: field.type) }
        }
        return .object(output)
    }
    func validate(_ value: JSON, fields: [AdminField], mutation: Bool) throws {
        guard case .object(let object) = value else { throw AdminError.invalidInput }
        let names = Set(fields.map(\.name))
        guard Set(object.keys).isSubset(of: names) else { throw AdminError.invalidInput }
        for field in fields {
            guard let v = object[field.name] else {
                if field.required && !field.hasDefault { throw AdminError.required(field.name) }
                continue
            }
            try validateValue(v, type: field.type, path: field.name, mutation: mutation)
        }
    }
    func validateValue(_ value: JSON, type: String, path: String, mutation: Bool) throws {
        if value.isNull {
            // Explicit GraphQL null is not an Ent clear operation. Keep optional omission and clear flags separate.
            if type.hasSuffix("!") || mutation { throw AdminError.nullUnsupported(path) }
            return
        }
        if type.hasPrefix("[") {
            guard case .array(let items) = value else { throw AdminError.required(path) }
            for (index, item) in items.enumerated() { try validateValue(item, type: element(type), path: "\(path)[\(index)]", mutation: mutation) }
            return
        }
        let name = base(type)
        if let info = types[name] {
            if info.kind == "object" { try validate(value, fields: info.fields, mutation: mutation); return }
            if info.kind == "enum" {
                guard case .string(let text) = value, info.values.contains(text) else { throw AdminError.required(path) }
                return
            }
        }
        switch name {
        case "Boolean": guard case .bool = value else { throw AdminError.required(path) }
        case "Int":
            guard case .number(let number) = value, number.isFinite, number.rounded() == number,
                  number >= -2147483648, number <= 2147483647 else { throw AdminError.required(path) }
        case "Float": guard case .number(let number) = value, number.isFinite else { throw AdminError.required(path) }
        case "Decimal", "DecimalInput":
            guard case .string(let text) = value, Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) != nil else { throw AdminError.required(path) }
        case "JSONRawMessageInput", "JSONRawMessage": break
        case "Time":
            guard case .string(let text) = value, ISO8601DateFormatter().date(from: text) != nil else { throw AdminError.required(path) }
        default:
            guard case .string(let text) = value else { throw AdminError.required(path) }
            if type.hasSuffix("!") && text.isEmpty && (name == "ID" || ["name", "password", "newPassword", "email", "pattern"].contains(path)) { throw AdminError.required(path) }
        }
    }
    static func sensitive(_ name: String) -> Bool {
        let key = name.lowercased()
        return key == "key" || key == "dsn" || key == "credential" || key == "authorization" || key == "value" || key == "headers" ||
            key.contains("password") || key.contains("secret") || key.contains("token") && !key.contains("tokens") ||
            key.contains("apikey") && !key.contains("id") || key == "accesskey" || key == "authcookie" || key == "jsondata"
    }
}

enum AdminError: LocalizedError {
    case schemaMissing, changedTarget, busy, invalidInput, verification, notFound, required(String), nullUnsupported(String)
    var errorDescription: String? {
        switch self {
        case .schemaMissing: return NSLocalizedString("管理表单资源缺失，请重新安装 App。", comment: "")
        case .changedTarget: return NSLocalizedString("实例或凭据已改变，请关闭页面重新进入。", comment: "")
        case .busy: return NSLocalizedString("操作正在执行，请勿重复提交。", comment: "")
        case .invalidInput: return NSLocalizedString("表单包含不支持的字段或值。", comment: "")
        case .verification: return NSLocalizedString("写入已发出，但精确读回未确认预期结果。请刷新目标，勿盲目重试。", comment: "")
        case .notFound: return NSLocalizedString("目标不存在或没有读取权限。", comment: "")
        case .required(let field): return String(format: NSLocalizedString("请检查字段：%@", comment: ""), NativeAdminLabels.path(field))
        case .nullUnsupported(let field): return String(format: NSLocalizedString("字段 %@ 不支持用 null 清空，请省略或使用 clear 字段。", comment: ""), NativeAdminLabels.path(field))
        }
    }
}

/// Native recursive editor: input objects, enums, typed scalars, arrays, omission and explicit null.
/// No secrets persist outside the in-memory SwiftUI session. Every nested editor opens a native sheet.
struct AdminSchemaForm: View {
    let schema: AdminSchema
    let fields: [AdminField]
    @Binding var value: JSON
    var allowNull = false
    var fieldRestrictions: [String: Set<String>] = [:]
    var body: some View {
        ForEach(fields) { field in
            AdminFieldRow(schema: schema, field: field, value: fieldBinding(field), allowNull: allowNull,
                allowedFields: fieldRestrictions[field.name])
        }
    }
    private func fieldBinding(_ field: AdminField) -> Binding<JSON?> {
        Binding(get: { value.object[field.name] }, set: { new in
            var object = value.object
            if let new = new { object[field.name] = new } else { object.removeValue(forKey: field.name) }
            value = .object(object)
        })
    }
}

private struct AdminFieldRow: View {
    let schema: AdminSchema
    let field: AdminField
    @Binding var value: JSON?
    let allowNull: Bool
    var allowedFields: Set<String>? = nil
    @State private var editing = false
    @State private var numberText = ""
    @State private var numberError = false
    @State private var revealed = false
    private var info: AdminSchemaType? { schema.types[schema.base(field.type)] }
    private var scalarString: Binding<String> {
        Binding(get: { value?.string ?? "" }, set: { value = .string($0) })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(NativeAdminLabels.field(field.name)).font(.subheadline.weight(.medium))
                Spacer()
                if field.required { Text("必填").font(.caption).foregroundStyle(.secondary) }
                if !field.required {
                    Menu {
                        Button("编辑字段") { value = schema.defaultValue(field.type) }
                        Button("省略字段（不提交）") { value = nil }
                        if allowNull { Button("发送 null") { value = .null } }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            if value == nil {
                Button("配置") { value = field.default ?? schema.defaultValue(field.type) }
            } else if value?.isNull == true {
                Label("null", systemImage: "minus.circle").foregroundStyle(.secondary)
            } else if field.type.hasPrefix("[") || info?.kind == "object" {
                Button {
                    editing = true
                } label: {
                    HStack {
                        Text(field.type.hasPrefix("[") ? String(format: NSLocalizedString("%lld 项", comment: ""), Int64(value?.array.count ?? 0)) : NSLocalizedString("编辑对象", comment: ""))
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                }
            } else if info?.kind == "enum" {
                Picker(NativeAdminLabels.field(field.name), selection: scalarString) {
                    ForEach(info?.values ?? [], id: \.self) { item in Text(field.name == "type" && item == "user" ? obsText("项目密钥") : NativeAdminLabels.value(item)).tag(item) }
                }.pickerStyle(.menu)
            } else if schema.base(field.type) == "Boolean" {
                Toggle(NativeAdminLabels.field(field.name), isOn: Binding(get: { value?.bool ?? false }, set: { value = .bool($0) }))
            } else if ["Int", "Float"].contains(schema.base(field.type)) {
                TextField(NativeAdminLabels.field(field.name), text: $numberText)
                    .keyboardType(.numbersAndPunctuation)
                    .onAppear { numberText = value.map { String($0.number) } ?? "0" }
                    .onChange(of: numberText) { text in
                        if let number = Double(text), number.isFinite { value = .number(number); numberError = false }
                        else { value = .string(text); numberError = true }
                    }
                if numberError { Text("请输入有效数字").font(.caption).foregroundStyle(.red) }
            } else if ["JSONRawMessageInput", "JSONRawMessage"].contains(schema.base(field.type)) {
                Button("编辑结构化值") { editing = true }
            } else if AdminSchema.sensitive(field.name) {
                if revealed { TextField(NativeAdminLabels.field(field.name), text: scalarString).textInputAutocapitalization(.never).autocorrectionDisabled() }
                else { SecureField(NativeAdminLabels.field(field.name), text: scalarString).textInputAutocapitalization(.never).autocorrectionDisabled() }
                Button(revealed ? "隐藏秘密" : "显示秘密（请注意周围环境）") { revealed.toggle() }.font(.caption)
            } else if ["content", "pattern", "replacement", "description", "body", "customMessage", "testSystemPrompt", "testUserPrompt", "regex"].contains(field.name) {
                TextEditor(text: scalarString).frame(minHeight: 100).font(.body.monospaced())
            } else {
                TextField(NativeAdminLabels.field(field.name), text: scalarString).textInputAutocapitalization(.never).autocorrectionDisabled()
                if schema.base(field.type) == "Time" { Text("ISO 8601，例如 2026-01-01T00:00:00Z").font(.caption).foregroundStyle(.secondary) }
            }

        }
        .padding(.vertical, 3)
        .sheet(isPresented: $editing) {
            NavigationStack {
                AnyView(AdminNestedForm(schema: schema, title: NativeAdminLabels.field(field.name), type: field.type,
                    value: Binding(get: { value ?? schema.defaultValue(field.type) }, set: { value = $0 }), allowNull: allowNull, allowedFields: allowedFields))
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { editing = false } } }
            }
        }
    }
}

private struct AdminNestedForm: View {
    let schema: AdminSchema
    let title: String
    let type: String
    @Binding var value: JSON
    let allowNull: Bool
    var allowedFields: Set<String>? = nil
    @State private var advanced = ""
    @State private var advancedError = false
    var body: some View {
        Form {
            if type.hasPrefix("[") {
                ForEach(Array(value.array.indices), id: \.self) { index in
                    let field = AdminField(name: "item", type: schema.element(type), description: "", hasDefault: false, default: nil)
                    Section {
                        AdminFieldRow(schema: schema, field: field,
                            value: Binding(get: { value.array.indices.contains(index) ? value.array[index] : nil }, set: { new in
                                var items = value.array
                                guard items.indices.contains(index) else { return }
                                if let new = new { items[index] = new } else { items.remove(at: index) }
                                value = .array(items)
                            }), allowNull: allowNull)
                        Button("移除此项", role: .destructive) {
                            var items = value.array
                            if items.indices.contains(index) { items.remove(at: index); value = .array(items) }
                        }
                    }
                }
                Button("添加一项") {
                    value = .array(value.array + [schema.defaultValue(schema.element(type))])
                }
            } else if let info = schema.types[schema.base(type)], info.kind == "object" {
                AdminSchemaForm(schema: schema, fields: info.fields.filter { allowedFields == nil || allowedFields!.contains($0.name) }, value: $value, allowNull: allowNull)
            } else {
                // Custom raw JSON scalar only; schema input objects never degrade to a bare JSON shell.
                TextEditor(text: $advanced).font(.body.monospaced()).frame(minHeight: 240)
                Button("应用结构化值") {
                    if let decoded = JSON.from(advanced) { value = decoded; advancedError = false }
                    else { advancedError = true }
                }
                if advancedError { Text("JSON 格式不正确，原值未改变。").foregroundStyle(.red) }
            }
        }
        .navigationTitle(title)
        .onAppear { advanced = value.prettyJSON }
    }
}
