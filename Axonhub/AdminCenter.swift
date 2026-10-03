import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// Parent integration entry: native-only administration; no URL launch or WebView.
struct AdminCenterView: View {
    @ObservedObject var store: AxonStore
    @State private var schema: AdminSchema?
    @State private var failure: String?
    @State private var projectID = ""
    @State private var generation = UUID()
    var body: some View {
        Group {
            if let schema = schema {
                AdminWorkspaceView(store: store, schema: schema, projectID: projectID)
                    .id(generation)
            } else if let failure = failure {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(failure)
                }.padding()
            } else { ProgressView() }
        }
        .navigationTitle("管理中心")
        .task {
            do { schema = try AdminSchema.loaded.get() }
            catch { failure = error.localizedDescription }
        }
    }
}

private struct AdminWorkspaceView: View {
    @ObservedObject var store: AxonStore
    let schema: AdminSchema
    @StateObject private var owner: AdminSessionOwner
    @State private var projectID = ""
    @State private var projectOptions: [JSON] = []
    @State private var search = ""
    init(store: AxonStore, schema: AdminSchema, projectID: String) {
        self.store = store
        self.schema = schema
        _owner = StateObject(wrappedValue: AdminSessionOwner(store: store, schema: schema, projectID: projectID))
        _projectID = State(initialValue: projectID)
    }
    private let groups = ["API Keys", "API Key Templates", "Users", "Roles", "Projects", "Project Users", "Project Roles", "Prompts", "Prompt Protection", "Data Storage", "System Settings", "Account"]
    var body: some View {
        List {
            if let session = owner.session {
                Section {
                    Text(session.connection.instance.name).font(.headline)
                    Text(session.connection.instance.address).font(.caption).foregroundStyle(.secondary)
                    Picker("项目作用域", selection: $projectID) {
                        Text("系统作用域").tag("")
                        ForEach(projectOptions, id: \.self) { project in
                            Text(project["name"].string).tag(project["id"].string)
                        }
                    }.pickerStyle(.menu)
                    if session.invalidated {
                        Text(AdminError.changedTarget.localizedDescription).foregroundStyle(.red)
                        Button("重新绑定当前实例") { owner.rebind(projectID: projectID) }
                    }
                }
                ForEach(groups, id: \.self) { group in
                    Section(group) {
                        if group == "Project Roles" {
                            NavigationLink("项目角色（查询与编辑）") {
                                AdminOperationView(session: session, operation: try! schema.operation("roles"), scopeRoles: true)
                            }.disabled(projectID.isEmpty || session.invalidated)
                            NavigationLink("创建项目角色") {
                                AdminOperationView(session: session, operation: try! schema.operation("createRole"), seed: .object(["input": .object(["level": .string("project"), "projectID": .string(projectID), "name": .string(""), "scopes": .array([])])]))
                            }.disabled(projectID.isEmpty || session.invalidated)
                        }
                        ForEach(visibleOperations(group)) { operation in
                            NavigationLink {
                                AdminOperationView(session: session, operation: operation)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(operation.title)
                                }
                            }.disabled(session.invalidated || requiresProject(operation) && projectID.isEmpty)
                        }
                        if group == "Project Users" {
                            NavigationLink("创建项目邀请") { AdminInvitationView(session: session) }
                                .disabled(projectID.isEmpty || session.invalidated)
                        }
                        if group == "System Settings" {
                            NavigationLink("从备份文件恢复") { AdminRestoreView(session: session) }.disabled(session.invalidated)
                        }
                    }
                }
            } else {
                Text(owner.failure ?? NSLocalizedString("请先连接管理员实例。", comment: "")).foregroundStyle(.red)
                Button("重试") { owner.rebind(projectID: projectID) }
            }
        }
        .searchable(text: $search, prompt: "搜索管理操作")
        .onChange(of: store.selectedID) { _ in owner.session?.invalidate() }
        .onChange(of: store.selectedInstance) { _ in owner.session?.invalidate() }
        .onChange(of: projectID) { next in
            owner.session?.invalidate()
            owner.rebind(projectID: next)
        }
        .task {
            guard let session = owner.session else { return }
            do {
                let data = try await session.read("myProjects")
                guard case .array = data else { throw AxonAPIError.invalidResponse }
                projectOptions = data.array
            } catch { owner.failure = error.localizedDescription }
        }
    }
    private func visibleOperations(_ group: String) -> [AdminOperation] {
        schema.operations.filter { operation in
            operation.group == group && !operation.secretRead && operation.root != "restore" &&
            (search.isEmpty || operation.title.localizedCaseInsensitiveContains(search))
        }
    }
    private func requiresProject(_ operation: AdminOperation) -> Bool {
        ["API Keys", "API Key Templates", "Project Users", "Prompts"].contains(operation.group)
    }
}

@MainActor private final class AdminSessionOwner: ObservableObject {
    let store: AxonStore
    let schema: AdminSchema
    @Published var session: AdminSession?
    @Published var failure: String?
    init(store: AxonStore, schema: AdminSchema, projectID: String) {
        self.store = store; self.schema = schema; rebind(projectID: projectID)
    }
    func rebind(projectID: String) {
        do { session = try AdminSession(store: store, schema: schema, projectID: projectID); failure = nil }
        catch { session = nil; failure = error.localizedDescription }
    }
}

struct AdminOperationView: View {
    @ObservedObject var session: AdminSession
    let operation: AdminOperation
    var scopeRoles = false
    @State private var variables: JSON
    @State private var baseline: JSON = .null
    @State private var result: JSON = .null
    @State private var rows: [JSON] = []
    @State private var loaded = false
    @State private var confirmation = false
    @State private var secretConfirmation = false
    @State private var detailTarget: AdminDetailTarget?
    @State private var localError: String?
    @State private var querySearch = ""
    @State private var secretAccess = false
    @State private var revealResult = false
    @State private var revealResultConfirmation = false
    @State private var export: AdminExportDocument?
    @State private var exporting = false
    init(session: AdminSession, operation: AdminOperation, seed: JSON = .object([:]), scopeRoles: Bool = false) {
        self.session = session; self.operation = operation; self.scopeRoles = scopeRoles
        _variables = State(initialValue: Self.initial(session: session, operation: operation, seed: seed))
    }
    private static func initial(session: AdminSession, operation: AdminOperation, seed: JSON) -> JSON {
        var object = seed.object
        for field in operation.variables where object[field.name] == nil {
            if field.required || field.hasDefault { object[field.name] = field.default ?? session.schema.defaultValue(field.type) }
        }
        if let field = operation.variables.first(where: { $0.name == "input" }), !operation.allowedInputFields.isEmpty,
           let info = session.schema.types[session.schema.base(field.type)] {
            object["input"] = .object((object["input"]?.object ?? [:]).filter { operation.allowedInputFields.contains($0.key) })
            for f in info.fields where f.required && operation.allowedInputFields.contains(f.name) && object["input"]?.object[f.name] == nil {
                var input = object["input"]?.object ?? [:]
                input[f.name] = f.default ?? session.schema.defaultValue(f.type); object["input"] = .object(input)
            }
        }
        if operation.variables.contains(where: { $0.name == "first" }) { object["first"] = .number(20) }
        if let projectID = session.connection.projectID {
            var input = object["input"]?.object ?? [:]
            if let field = operation.variables.first(where: { $0.name == "input" }),
               let type = session.schema.types[session.schema.base(field.type)] {
                for key in ["projectID", "projectId"] where type.fields.contains(where: { $0.name == key }) { input[key] = .string(projectID) }
                if !input.isEmpty { object["input"] = .object(input) }
            }
            if operation.variables.contains(where: { $0.name == "projectId" }) { object["projectId"] = .string(projectID) }
            if ["apiKeys", "apiKeyProfileTemplates", "roles", "prompts"].contains(operation.root) {
                object["where"] = .object(["projectID": .string(projectID)])
            }
        }
        return .object(object)
    }
    private var formFields: [AdminField] { operation.variables }
    private var needsSecretBaseline: Bool { ["updateWebhookNotifierConfig", "saveProxyPreset"].contains(operation.root) }
    private var destructive: Bool {
        operation.destructive || Self.containsDestructiveChange(variables)
    }
    private static func containsDestructiveChange(_ value: JSON) -> Bool {
        switch value {
        case .object(let object):
            return object.contains { key, val in
                (key.hasPrefix("clear") && val.bool) || (key == "status" && ["archived", "disabled", "deactivated"].contains(val.string)) || containsDestructiveChange(val)
            }
        case .array(let items): return items.contains(where: containsDestructiveChange)
        default: return false
        }
    }
    var body: some View {
        Form {
            Section("绑定目标") {
                Text(session.connection.instance.name)
                Text(session.connection.projectID.flatMap { session.store.entityNames.names[$0] } ?? NSLocalizedString("系统作用域", comment: "")).font(.caption)
            }
            if !operation.variables.isEmpty {
                Section("输入") {
                    if operation.variables.contains(where: { $0.name == "where" }) {
                        TextField("按名称搜索", text: $querySearch).textInputAutocapitalization(.never)
                    }
                    AdminSchemaForm(schema: session.schema, fields: formFields, value: $variables, allowNull: !operation.mutation,
                        fieldRestrictions: operation.allowedInputFields.isEmpty ? [:] : ["input": Set(operation.allowedInputFields)])
                    if operation.mutation && (!operation.entity.isEmpty || operation.replacement || needsSecretBaseline) {
                        Button("读取精确目标并填入当前值") {
                            if needsSecretBaseline && !secretAccess { secretConfirmation = true }
                            else { loadBaseline() }
                        }.disabled(session.busy || session.invalidated)
                    }
                }
            }
            if operation.root == "saveProxyPreset" {
                Text("保存代理预设会按 URL 替换整项，包括凭据；请填写完整配置或先读取旧项。")
                    .font(.caption).foregroundStyle(.orange)
            }
            if operation.root == "updateDataStorage" {
                Text("更换存储凭据为只写操作，服务端不返回凭据。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let localError = localError { Section { Text(localError).foregroundStyle(.red) } }
            if let error = session.error { Section { Text(error).foregroundStyle(.red) } }
            Section {
                Button(operation.mutation ? "提交操作" : "查询") {
                    localError = nil
                    if destructive { confirmation = true } else {
                        if !operation.mutation { var object = variables.object; object.removeValue(forKey: "after"); variables = .object(object) }
                        perform()
                    }
                }.disabled(session.busy || session.invalidated || needsSecretBaseline && !secretAccess)
                if session.busy { ProgressView() }
                if !session.status.isEmpty { Text(session.status).font(.caption).foregroundStyle(.secondary) }
                if needsSecretBaseline && !secretAccess {
                    Button("授权读取完整配置（含秘密）") { secretConfirmation = true }
                }
            }
            if !rows.isEmpty || result.object["edges"] != nil {
                Section("结果") {
                    if !result["totalCount"].isNull { Text(String(format: NSLocalizedString("总计 %lld", comment: ""), Int64(result["totalCount"].int))) }
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, item in
                        Button {
                            guard let entity = Self.entityForList(operation.root), !item["id"].string.isEmpty else { return }
                            detailTarget = AdminDetailTarget(entity: entity, id: item["id"].string)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(Self.label(item)).foregroundStyle(.primary)
                                if !item["status"].string.isEmpty { Text(NativeAdminLabels.value(item["status"].string)).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    }
                    if result["pageInfo"]["hasNextPage"].bool {
                        Button("加载下一页") { nextPage() }.disabled(session.busy)
                    }
                }
            } else if !result.isNull {
                Section("结果") {
                    AdminResultTree(value: result, hideSecrets: !revealResult)
                    if !operation.mutation && ["proxyPresets", "webhookNotifierConfig", "getCacheDiagnostics"].contains(operation.root) {
                        Button(revealResult ? "隐藏配置秘密" : "授权读取并显示配置秘密") {
                            if revealResult { revealResult = false; result = AdminWritePolicy.removingSecrets(result) }
                            else { revealResultConfirmation = true }
                        }
                    }
                    if operation.mutation, !operation.entity.isEmpty, !result["id"].string.isEmpty {
                        Button("查看写入目标详情") { detailTarget = AdminDetailTarget(entity: operation.entity, id: result["id"].string) }
                    }
                    if operation.root == "backup" {
                        Button("导出加密前备份（包含秘密，请安全保存）") {
                            guard !result["data"].string.isEmpty else { return }
                            export = AdminExportDocument(text: result["data"].string)
                            exporting = true
                        }
                    }
                }
            }
            DisclosureGroup(obsText("技术信息")) {
                Text(operation.source).font(.caption.monospaced()).foregroundStyle(.secondary)
                Text("AxonHub beta10 · " + session.schema.revision).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
        }
        .navigationTitle(operation.title)
        .disabled(session.invalidated)
        .alert("确认破坏性操作", isPresented: $confirmation) {
            Button("确认执行", role: .destructive) { perform() }
            Button("取消", role: .cancel) { }
        } message: {
            Text(operation.title + "\n" + session.connection.instance.name + "\n" + Self.targetSummary(variables, projectID: session.connection.projectID) + "\n" + NSLocalizedString("撤销、删除、重生成或清空可能不可恢复，旧凭据可能立即失效。", comment: ""))
        }
        .alert("读取配置中的秘密", isPresented: $secretConfirmation) {
            Button("读取并仅在当前表单中使用") { secretAccess = true; loadBaseline() }
            Button("取消", role: .cancel) { }
        } message: { Text("秘密将进入内存中的 SecureField，不自动展示、不记录日志、不写入偏好。请确认当前实例。") }
        .alert("显示配置秘密", isPresented: $revealResultConfirmation) {
            Button("读取并显示") {
                session.start {
                    let root = operation.root
                    result = try await session.read(root == "getCacheDiagnostics" ? root : "reveal" + root, variables: variables)
                    revealResult = true
                }
            }
            Button("取消", role: .cancel) { }
        } message: { Text("读取配置") }
        .sheet(item: $detailTarget) { target in
            NavigationStack { AdminDetailView(session: session, target: target) }
        }
        .fileExporter(isPresented: $exporting, document: export, contentType: .json, defaultFilename: "axonhub-backup") { outcome in
            if case .failure = outcome { localError = NSLocalizedString("文件导出失败，备份仍保留在当前页面。", comment: "") }
        }
        .task {
            guard !loaded else { return }; loaded = true
            if operation.mutation && operation.replacement && !needsSecretBaseline { loadBaseline() }
            else if !operation.mutation && operation.variables.allSatisfy({ !$0.required || $0.hasDefault || $0.name == "first" || !variables[$0.name].string.isEmpty }) { perform() }
        }
        .onChange(of: session.invalidated) { invalid in if invalid { variables = .object([:]); baseline = .null; result = .null; rows = []; export = nil } }
        .onDisappear { secretAccess = false; export = nil; revealResult = false; result = AdminWritePolicy.removingSecrets(result) }
    }
    private func loadBaseline() {
        session.start {
            let root = operation.root
            let id = variables["id"].string
            let value: JSON
            if !operation.entity.isEmpty && operation.entity != "ProjectUser", !id.isEmpty {
                value = try await session.detail(operation.entity, id: id)
            } else if !operation.verification.isEmpty {
                value = try await session.read(operation.verification)
            } else { throw AdminError.required("id") }
            guard !value.isNull else { throw AdminError.notFound }
            guard !AdminWritePolicy.containsTruncatedObject(value) else { throw AdminError.invalidInput }
            if root == "saveProxyPreset" {
                guard case .array = value else { throw AxonAPIError.invalidResponse }
                let url = variables["input"]["url"].string
                baseline = value.array.first { $0["url"].string == url } ?? .object([:])
            } else { baseline = value }
            var vars = variables.object
            if let field = operation.variables.first(where: { $0.name == "input" }) {
                let source = ["updateAPIKeyProfiles", "updateProjectProfiles"].contains(root) ? baseline["profiles"] : baseline
                var input = session.schema.project(source, type: field.type).object
                if !operation.allowedInputFields.isEmpty { input = input.filter { operation.allowedInputFields.contains($0.key) } }
                if root == "updateAPIKey", baseline["type"].string != "service_account" {
                    input = input.filter { !$0.key.lowercased().contains("scopes") }
                }
                // Preserve typed identity inputs from the explicit target but never copy output fields.
                for (key, v) in vars["input"]?.object ?? [:] where key == "projectID" || key == "projectId" || key == "userId" { input[key] = v }
                vars["input"] = .object(input)
            }
            if let field = operation.variables.first(where: { $0.name == "profile" }), !baseline["profile"].isNull {
                vars["profile"] = session.schema.project(baseline["profile"], type: field.type)
            }
            variables = .object(vars)
        }
    }
    private func submittedVariables() throws -> JSON {
        var vars = variables.object
        if !operation.mutation, operation.variables.contains(where: { $0.name == "where" }) {
            var whereInput = vars["where"]?.object ?? [:]
            if !querySearch.isEmpty {
                let typeName = operation.variables.first { $0.name == "where" }!.type
                let fields = session.schema.types[session.schema.base(typeName)]?.fields ?? []
                let key = fields.contains(where: { $0.name == "nameContainsFold" }) ? "nameContainsFold" : "emailContainsFold"
                if fields.contains(where: { $0.name == key }) { whereInput[key] = .string(querySearch) }
            }
            if let projectID = session.connection.projectID, ["apiKeys", "apiKeyProfileTemplates", "roles", "prompts"].contains(operation.root) { whereInput["projectID"] = .string(projectID) }
            if scopeRoles { whereInput["level"] = .string("project") }
            vars["where"] = .object(whereInput)
        }
        // Project identity is immutable for this session, not user-overridable from advanced fields.
        if let projectID = session.connection.projectID, let field = operation.variables.first(where: { $0.name == "input" }) {
            let fields = session.schema.types[session.schema.base(field.type)]?.fields ?? []
            var input = vars["input"]?.object ?? [:]
            for key in ["projectID", "projectId"] where fields.contains(where: { $0.name == key }) {
                guard input[key] == nil || input[key]?.string == projectID else { throw AdminError.changedTarget }
                input[key] = .string(projectID)
            }
            if !input.isEmpty { vars["input"] = .object(input) }
        }
        return .object(vars)
    }
    private func perform(append: Bool = false) {
        guard !session.busy else { return }
        session.start {
            let submitted = try submittedVariables()
            // Exact baseline fetch for individual mutations even if user skipped the fill button.
            if operation.mutation, baseline.isNull, !operation.entity.isEmpty, operation.entity != "ProjectUser", !submitted["id"].string.isEmpty {
                baseline = try await session.detail(operation.entity, id: submitted["id"].string)
            }
            if operation.root == "updateAPIKeyProfiles" || operation.root == "updateProjectProfiles" {
                guard !baseline.isNull else { throw AdminError.notFound }
            }
            let value = try await session.execute(operation, variables: submitted, baseline: baseline)
            result = value
            if case .array(let edges) = value["edges"] {
                let nodes = edges.map { $0["node"] }
                guard nodes.allSatisfy({ !$0["id"].string.isEmpty }) else { throw AxonAPIError.invalidResponse }
                rows = append ? rows + nodes : nodes
            } else { rows = [] }
            if operation.mutation { variables = AdminWritePolicy.removingSecrets(submitted) }
        }
    }
    private func nextPage() {
        let cursor = result["pageInfo"]["endCursor"].string
        guard !cursor.isEmpty, operation.variables.contains(where: { $0.name == "after" }) else {
            localError = AxonAPIError.invalidResponse.localizedDescription; return
        }
        var vars = variables.object; vars["after"] = .string(cursor); variables = .object(vars)
        perform(append: true)
    }
    static func entityForList(_ root: String) -> String? {
        ["apiKeys": "APIKey", "apiKeyProfileTemplates": "APIKeyProfileTemplate", "users": "User", "roles": "Role", "projects": "Project", "dataStorages": "DataStorage", "prompts": "Prompt", "promptProtectionRules": "PromptProtectionRule"][root]
    }
    static func label(_ item: JSON) -> String {
        for key in ["name", "email", "firstName"] where !item[key].string.isEmpty { return item[key].string }
        return NativeDisplay.name(item)
    }
    static func targetSummary(_ variables: JSON, projectID: String?) -> String {
        var parts = AdminWritePolicy.targetIDs(variables).map { "ID: " + $0 }
        if let projectID = projectID { parts.append("Project ID: " + projectID) }
        for key in ["projectId", "userId", "apiKeyID", "templateID"] where !variables["input"][key].string.isEmpty {
            parts.append(key + ": " + variables["input"][key].string)
        }
        if parts.isEmpty { parts = [NSLocalizedString("当前系统或个人配置", comment: "")] }
        return parts.joined(separator: "\n")
    }
}

private struct AdminDetailTarget: Identifiable {
    let entity: String
    let id: String
}

private struct AdminDetailView: View {
    @ObservedObject var session: AdminSession
    let target: AdminDetailTarget
    @Environment(\.dismiss) private var dismiss
    @State private var detail: JSON = .null

    var body: some View {
        List {
            Section("精确目标") {
                Text(NativeDisplay.name(detail))
                Text(session.connection.instance.name)
                if !detail.isNull { AdminResultTree(value: detail, hideSecrets: true) }
            }
            if target.entity == "APIKey" {
                Section("API Key") {
                    APIKeyValueRow(read: revealSecret).id(session.invalidated).disabled(session.busy || session.invalidated)
                }
            }
            Section("目标操作") {
                ForEach(session.schema.operations.filter { $0.entity == target.entity && $0.mutation && !$0.root.hasPrefix("create") }) { operation in
                    NavigationLink(operation.title) {
                        AdminOperationView(session: session, operation: operation, seed: seed(operation))
                    }.disabled(session.busy || session.invalidated)
                }
            }
            if let error = session.error { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle("详情")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
        .task { session.start { detail = try await session.detail(target.entity, id: target.id); guard !detail.isNull else { throw AdminError.notFound } } }
        .onChange(of: session.invalidated) { invalid in if invalid { detail = .null } }
    }
    @MainActor private func revealSecret() async throws -> String {
        let revealed = try await session.read("revealAPIKey", variables: .object(["id": .string(target.id)]))
        guard revealed["id"].string == target.id, !revealed["key"].string.isEmpty else { throw AdminError.notFound }
        return revealed["key"].string
    }
    private func seed(_ operation: AdminOperation) -> JSON {
        var result: [String: JSON] = [:]
        if operation.variables.contains(where: { $0.name == "id" }) { result["id"] = .string(target.id) }
        if operation.variables.contains(where: { $0.name == "ids" }) { result["ids"] = .array([.string(target.id)]) }
        if operation.root == "loadApiKeyProfileTemplate" { result["input"] = .object(["apiKeyID": .string(target.id)]) }
        return .object(result)
    }
}

/// Read-only native object hierarchy. Sensitive fields hidden even if returned inside a mutation.
struct AdminResultTree: View {
    let value: JSON
    var hideSecrets = true
    var depth = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch value {
            case .object(let fields):
                ForEach(fields.keys.filter { !NativeDisplay.identifier($0) }.sorted(), id: \.self) { key in
                    if hideSecrets && (AdminSchema.sensitive(key) || key == "data" || key == "content" && fields["fileName"] != nil) {
                        HStack { Text(NativeAdminLabels.field(key)); Spacer(); Text("••••••••").foregroundStyle(.secondary) }
                    } else if let field = fields[key] {
                        switch field {
                        case .object, .array:
                            DisclosureGroup(NativeAdminLabels.field(key)) { AnyView(AdminResultTree(value: field, hideSecrets: hideSecrets, depth: depth + 1)) }
                        default:
                            VStack(alignment: .leading, spacing: 2) {
                                Text(NativeAdminLabels.field(key)).font(.caption).foregroundStyle(.secondary)
                                Text(NativeAdminLabels.scalar(field, key: key)).textSelection(.enabled)
                            }
                        }
                    }
                }
            case .array(let items):
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    DisclosureGroup(String(format: obsText("第 %lld 项"), Int64(index + 1))) { AnyView(AdminResultTree(value: item, hideSecrets: hideSecrets, depth: depth + 1)) }
                }
                if items.isEmpty { Text("空列表").foregroundStyle(.secondary) }
            default: Text(Self.scalar(value)).textSelection(.enabled)
            }
        }
    }
    static func scalar(_ value: JSON) -> String {
        switch value {
        case .string(let text): return text
        case .number(let number): return DisplayFormat.number(number)
        case .bool(let flag): return obsText(flag ? "是" : "否")
        case .null: return "—"
        default: return ""
        }
    }
}

struct AdminExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .plainText] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw AxonAPIError.invalidResponse }
        text = String(decoding: data, as: UTF8.self)
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: Data(text.utf8)) }
}
