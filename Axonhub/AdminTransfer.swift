import Foundation
import SwiftUI
import UniformTypeIdentifiers
import UIKit

extension AxonClient {
    func adminREST(path: String, method: String, body: JSON? = nil, projectID: String? = nil) async throws -> JSON {
        guard authType == .adminJWT else { throw AxonAPIError.forbidden }
        var request = URLRequest(url: Self.endpoint(baseURL: baseURL, path: path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let projectID = projectID { request.setValue(projectID, forHTTPHeaderField: "X-Project-ID") }
        if let body = body { request.httpBody = try JSONEncoder().encode(body) }
        return try await adminSend(request, graphql: false)
    }
    /// Official frontend restore uses GraphQL multipart request spec: operations + map + file field 0.
    func adminRestore(document: String, input: JSON, file: Data) async throws -> JSON {
        let boundary = "AxonAdmin-" + UUID().uuidString
        var request = URLRequest(url: Self.endpoint(baseURL: baseURL, path: "admin/graphql"))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let variables = JSON.object(["file": .null, "input": input])
        let operations = JSON.object(["query": .string(document), "variables": variables])
        var body = Data()
        func append(_ text: String) { body.append(Data(text.utf8)) }
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"operations\"\r\n\r\n")
        body.append(try JSONEncoder().encode(operations))
        append("\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"map\"\r\n\r\n{\"0\":[\"variables.file\"]}\r\n")
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"0\"; filename=\"backup.json\"\r\nContent-Type: application/json\r\n\r\n")
        body.append(file)
        append("\r\n--\(boundary)--\r\n")
        request.httpBody = body
        return try await adminSend(request)
    }
}

/// Native project invitation creation; secret token is never displayed until the user explicitly opts in.
struct AdminInvitationView: View {
    @ObservedObject var session: AdminSession
    @State private var projectName = ""
    @State private var roleID = ""
    @State private var roles: [JSON] = []
    @State private var expiresInHours = 168
    @State private var maxUses = 1
    @State private var token = ""
    @State private var metadata: JSON = .null
    @State private var revealed = false
    @State private var confirm = false
    var body: some View {
        Form {
            Section("绑定目标") {
                Text(session.connection.instance.name)
                Text(projectName.isEmpty ? "—" : projectName)
            }
            Section("邀请设置") {
                Picker("项目角色", selection: $roleID) {
                    Text("选择角色").tag("")
                    ForEach(roles, id: \.self) { role in Text(role["name"].string).tag(role["id"].string) }
                }.pickerStyle(.menu)
                Picker("有效期", selection: $expiresInHours) {
                    Text("1 小时").tag(1); Text("6 小时").tag(6); Text("24 小时").tag(24)
                    Text("7 天").tag(168); Text("永不过期").tag(0)
                }.pickerStyle(.menu)
                Picker("使用次数", selection: $maxUses) { Text("一次").tag(1); Text("不限").tag(0) }.pickerStyle(.menu)
                Button("创建邀请") { confirm = true }.disabled(roleID.isEmpty || session.busy || session.invalidated || !token.isEmpty)
                if session.busy { ProgressView() }
            }
            if !metadata.isNull { Section("结果") { NativeDetailFieldsView(store: session.store, value: metadata) } }
            if !token.isEmpty {
                Section("邀请秘密") {
                    Button(revealed ? "隐藏邀请链接" : "显示邀请链接（持有者可注册）") { revealed.toggle() }
                    if revealed {
                        Text(invitationURL).font(.caption.monospaced()).textSelection(.enabled)
                        Button("复制邀请链接") {
                            UIPasteboard.general.setItems([[UIPasteboard.typeAutomatic: invitationURL]], options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(60)])
                        }
                    }
                }
            }
            if let error = session.error { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle("创建项目邀请")
        .alert("确认创建注册邀请", isPresented: $confirm) {
            Button("创建") { create() }
            Button("取消", role: .cancel) { }
        } message: { Text(invitationSummary) }
        .task { session.start {
            guard let projectID = session.connection.projectID else { throw AdminError.required("projectID") }
            projectName = NativeDisplay.name(try await session.detail("Project", id: projectID))
            var after: String?
            repeat {
                var input: [String: JSON] = ["first": .number(100), "where": .object(["projectID": .string(projectID), "level": .string("project")])]
                if let after = after { input["after"] = .string(after) }
                let page = try await session.read("roles", variables: .object(input))
                guard case .array(let edges) = page["edges"] else { throw AxonAPIError.invalidResponse }
                roles.append(contentsOf: edges.map { $0["node"] })
                after = page["pageInfo"]["hasNextPage"].bool ? page["pageInfo"]["endCursor"].string : nil
                if after?.isEmpty == true { throw AxonAPIError.invalidResponse }
            } while after != nil
        } }
        .onChange(of: session.invalidated) { invalid in if invalid { token = ""; metadata = .null; roles = []; revealed = false } }
        .onDisappear { token = ""; revealed = false }
    }
    private var invitationSummary: String {
        let roleName = roles.first { $0["id"].string == roleID }?["name"].string ?? "—"
        let warning = NSLocalizedString("持有邀请链接的人可以注册并获得此项目角色。", comment: "")
        return [session.connection.instance.name, projectName, roleName, warning].joined(separator: "\n")
    }
    private var invitationURL: String {
        var components = URLComponents(url: AxonClient.endpoint(baseURL: session.connection.client.baseURL, path: "sign-up"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "invite", value: token)]
        return components?.url?.absoluteString ?? ""
    }
    private func create() {
        session.start {
            guard let projectID = session.connection.projectID,
                  let role = roles.first(where: { $0["id"].string == roleID }),
                  let numericID = Int(roleID.split(separator: "/").last.map(String.init) ?? ""), numericID > 0,
                  role["projectID"].string == projectID else { throw AdminError.invalidInput }
            let client = session.connection.client
            try session.validate()
            let response = try await client.adminREST(path: "admin/invitations", method: "POST", body: .object([
                "expiresInHours": .number(Double(expiresInHours)), "maxUses": .number(Double(maxUses)), "roleID": .number(Double(numericID))
            ]), projectID: projectID)
            try session.validate()
            let secret = response["token"].string
            guard !secret.isEmpty, secret.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else { throw AxonAPIError.invalidResponse }
            let exact = try await client.adminREST(path: "auth/invitations/" + secret, method: "GET")
            try session.validate()
            for key in ["projectName", "expiresAt", "maxUses", "usedCount", "remainingUses"] {
                guard response.object[key] != nil, exact.object[key] != nil, response[key] == exact[key] else { throw AdminError.verification }
            }
            token = secret
            metadata = exact
        }
    }
}

/// Native multipart restore with source document validation and selective exact readback.
/// A broad restore has no transaction revision API: never label it fully verified.
struct AdminRestoreView: View {
    @ObservedObject var session: AdminSession
    @State private var input: JSON
    @State private var file: Data?
    @State private var fileName = ""
    @State private var importing = false
    @State private var confirm = false
    @State private var report = ""
    @State private var error: String?
    init(session: AdminSession) {
        self.session = session
        _input = State(initialValue: session.schema.defaultValue("RestoreOptionsInput!"))
    }
    var body: some View {
        Form {
            Section("绑定目标") { Text(session.connection.instance.name); Text(session.connection.instance.address).font(.caption) }
            Section("备份文件") {
                Button("选择 JSON 备份文件") { importing = true }
                if !fileName.isEmpty { Text(fileName) }
                Text("备份可能包含 API Keys 和渠道凭据。恢复可能覆盖现有配置；请先导出备份。")
                    .font(.caption).foregroundStyle(.orange)
            }
            Section("恢复选项") {
                AdminSchemaForm(schema: session.schema, fields: session.schema.types["RestoreOptionsInput"]?.fields ?? [], value: $input)
            }
            Section {
                Button("恢复到此实例", role: .destructive) { confirm = true }.disabled(file == nil || session.busy || session.invalidated)
                if session.busy { ProgressView() }
                if !report.isEmpty { Text(report).font(.caption) }
                if let error = error { Text(error).foregroundStyle(.red) }
                if let error = session.error { Text(error).foregroundStyle(.red) }
            }
        }
        .navigationTitle("从备份恢复")
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .plainText], allowsMultipleSelection: false) { result in
            do {
                guard let url = try result.get().first else { return }
                let allowed = url.startAccessingSecurityScopedResource()
                defer { if allowed { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url)
                guard data.count <= 50 * 1024 * 1024,
                      let decoded = JSON.from(String(decoding: data, as: UTF8.self)),
                      !decoded["version"].string.isEmpty,
                      decoded.object["channels"] != nil, decoded.object["models"] != nil else { throw AdminError.invalidInput }
                file = data; fileName = url.lastPathComponent; error = nil
            } catch { self.error = error.localizedDescription }
        }
        .alert("确认恢复并可能覆盖配置", isPresented: $confirm) {
            Button("恢复", role: .destructive) { restore() }
            Button("取消", role: .cancel) { }
        } message: { Text(session.connection.instance.name + "\n" + session.connection.instance.address + "\n" + fileName + "\n" + NSLocalizedString("恢复会写入多个对象，overwrite 不可自动撤回。", comment: "")) }
        .onChange(of: session.invalidated) { invalid in if invalid { file = nil; input = .object([:]); report = "" } }
        .onDisappear { file = nil }
    }
    private func restore() {
        session.start {
            guard let file = file else { throw AdminError.invalidInput }
            let operation = try session.schema.operation("restore")
            try session.schema.validateValue(input, type: "RestoreOptionsInput!", path: "input", mutation: true)
            try session.validate()
            let response = try await session.connection.client.adminRestore(document: operation.document, input: input, file: file)
            try session.validate()
            guard response["restore"]["success"].bool else { throw AdminError.verification }
            // Exact system target read, never full snapshot / empty arrays as verification.
            let settings = try await session.read("systemVersion")
            guard !settings["version"].string.isEmpty else { throw AdminError.verification }
            report = NSLocalizedString("服务器报告恢复完成，请检查恢复目标。", comment: "")
        }
    }
}
