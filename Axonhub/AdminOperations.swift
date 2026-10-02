import Foundation
import SwiftUI

/// Immutable connection snapshot. Never resolve the mutable selection inside a write.
struct AdminConnection {
    let instance: AxonInstance
    let client: AxonClient
    let projectID: String?
    @MainActor init(store: AxonStore, projectID: String? = nil) throws {
        guard let instance = store.selectedInstance, instance.authType == .adminJWT else { throw AxonAPIError.forbidden }
        self.instance = instance
        self.client = try store.ensureClient()
        self.projectID = projectID?.isEmpty == false ? projectID : nil
    }
    @MainActor func validate(store: AxonStore, invalidated: Bool) throws {
        guard !invalidated, store.selectedID == instance.id, store.selectedInstance == instance else { throw AdminError.changedTarget }
        let current = try store.ensureClient()
        guard current.token == client.token, current.baseURL == client.baseURL, current.authType == client.authType else { throw AdminError.changedTarget }
        try Task.checkCancellation()
    }
    func graphql(_ operation: AdminOperation, variables: JSON) async throws -> JSON {
        let parameters: [String: Any] = (try variables.foundationObject() as? [String: Any]) ?? [:]
        if let projectID = projectID {
            return try await client.adminScopedGraphql(query: operation.document, variables: parameters, projectID: projectID)
        }
        return try await client.graphql(query: operation.document, variables: parameters)
    }
}

extension AxonClient {
    /// The official project UI sends X-Project-ID. Core's unscoped API has no header seam.
    /// Ephemeral, no redirect, no cookies, safe errors; unscoped queries still reuse Core.graphql.
    func adminScopedGraphql(query: String, variables: [String: Any], projectID: String) async throws -> JSON {
        guard authType == .adminJWT, !projectID.contains("\n"), !projectID.contains("\r") else { throw AxonAPIError.forbidden }
        var request = URLRequest(url: Self.endpoint(baseURL: baseURL, path: "admin/graphql"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(projectID, forHTTPHeaderField: "X-Project-ID")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": query, "variables": variables])
        return try await adminSend(request)
    }
    func adminSend(_ request: URLRequest, graphql: Bool = true) async throws -> JSON {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        let session = URLSession(configuration: config, delegate: NoRedirectDelegate(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch is CancellationError { throw CancellationError() }
        catch { throw AxonAPIError.transport }
        guard let http = response as? HTTPURLResponse else { throw AxonAPIError.invalidResponse }
        if http.statusCode == 401 { throw AxonAPIError.unauthorized }
        if http.statusCode == 403 { throw AxonAPIError.forbidden }
        guard (200...299).contains(http.statusCode) else { throw AxonAPIError.httpStatus(http.statusCode) }
        guard let root = JSON.from(String(decoding: data, as: UTF8.self)) else { throw AxonAPIError.invalidResponse }
        if graphql {
            guard root["errors"].array.isEmpty, !root["data"].isNull else { throw AxonAPIError.invalidResponse }
            return root["data"]
        }
        return root
    }
}

@MainActor final class AdminSession: ObservableObject {
    let store: AxonStore
    let connection: AdminConnection
    let schema: AdminSchema
    @Published private(set) var busy = false
    @Published private(set) var invalidated = false
    @Published var error: String?
    @Published var result: JSON = .null
    @Published var status: String = ""
    private var task: Task<Void, Never>?
    init(store: AxonStore, schema: AdminSchema, projectID: String? = nil) throws {
        self.store = store
        self.schema = schema
        self.connection = try AdminConnection(store: store, projectID: projectID)
    }
    func invalidate() {
        invalidated = true
        task?.cancel()
        result = .null
        status = ""
        error = AdminError.changedTarget.localizedDescription
    }
    func validate() throws { try connection.validate(store: store, invalidated: invalidated) }
    func read(_ id: String, variables: JSON = .object([:]), cached: Bool = false) async throws -> JSON {
        try validate()
        let operation = try schema.operation(id)
        let publicReads: Set<String> = ["myProjects", "projects", "users", "roles", "apiKeys", "apiKeyProfileTemplates", "prompts", "promptProtectionRules", "dataStorages", "allScopes", "modelCatalog", "projectUsers"]
        let mayCache = cached && !operation.mutation && publicReads.contains(id)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let encoded = (try? encoder.encode(variables).base64EncodedString()) ?? ""
        let key = "admin/" + (connection.projectID ?? "system") + "/" + id + "/" + encoded
        if mayCache, let value = store.pageCache.value(key) { return value }
        let revision = store.pageCache.revision
        let data = try await connection.graphql(operation, variables: variables)
        try validate()
        guard data.object[operation.root] != nil else { throw AxonAPIError.invalidResponse }
        if mayCache && revision == store.pageCache.revision { store.pageCache.save(data[operation.root], key: key) }
        return data[operation.root]
    }
    func detail(_ entity: String, id: String) async throws -> JSON {
        let value = try await read("detail" + entity, variables: .object(["id": .string(id)]))
        // node returns null for both missing and no read access: only pre-authorized deletion may regard null as absence.
        if !value.isNull && value["id"].string != id { throw AdminError.verification }
        return value
    }
    func start(_ action: @escaping @MainActor () async throws -> Void) {
        guard !busy, !invalidated else { return }
        busy = true
        error = nil
        task = Task { @MainActor [weak self] in
            guard let self = self else { return }
            defer { self.busy = false; self.task = nil }
            do { try self.validate(); try await action() }
            catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }
    func clearTransient() { result = .null; error = nil; status = "" }
    func execute(_ operation: AdminOperation, variables original: JSON, baseline: JSON = .null) async throws -> JSON {
        try validate()
        var variables = original
        try schema.validate(variables, fields: operation.variables, mutation: operation.mutation)
        if operation.mutation {
            store.pageCache.invalidate()
            variables = try AdminWritePolicy.prepare(operation, variables: variables, baseline: baseline, schema: schema)
            try schema.validate(variables, fields: operation.variables, mutation: true)
            // Existence/read authority checked before mutations so null after delete cannot masquerade as a success.
            var identities = AdminWritePolicy.targetIDs(variables)
            if operation.root == "loadApiKeyProfileTemplate" { identities = [variables["input"]["apiKeyID"].string] }
            if operation.entity == "ProjectUser" {
                let project = try await detail("Project", id: variables["input"]["projectId"].string)
                guard !project.isNull else { throw AdminError.notFound }
                if operation.root != "addUserToProject" {
                    guard case .array(let members) = project["projectUsers"], members.contains(where: { $0["userID"].string == variables["input"]["userId"].string }) else { throw AdminError.notFound }
                }
            }
            if !operation.entity.isEmpty && operation.entity != "ProjectUser" && !operation.root.hasPrefix("create") {
                for id in identities {
                    guard !(try await detail(operation.entity, id: id)).isNull else { throw AdminError.notFound }
                }
            }
        }
        let data = try await connection.graphql(operation, variables: variables)
        try validate()
        guard let value = data.object[operation.root], !value.isNull else { throw AxonAPIError.invalidResponse }
        if operation.mutation && operation.root != "previewPromptProtectionRule" {
            if case .bool(let accepted) = value, !accepted { throw AdminError.verification }
            if !value["success"].isNull && !value["success"].bool { throw AdminError.verification }
            try await verify(operation, variables: variables, response: value, baseline: baseline)
        }
        return value
    }
    private func verify(_ operation: AdminOperation, variables: JSON, response: JSON, baseline: JSON) async throws {
        let root = operation.root
        if operation.entity == "ProjectUser" {
            let input = variables["input"]
            let projectID = input["projectId"].string
            let userID = input["userId"].string
            guard !projectID.isEmpty, !userID.isEmpty else { throw AdminError.verification }
            let project = try await detail("Project", id: projectID)
            guard project["id"].string == projectID, case .array(let members) = project["projectUsers"] else { throw AdminError.verification }
            let target = members.first { $0["userID"].string == userID && $0["projectID"].string == projectID }
            if root == "removeUserFromProject" { guard target == nil else { throw AdminError.verification } }
            else {
                guard let target = target else { throw AdminError.verification }
                try AdminWritePolicy.verifyFields(input.object.filter { ["isOwner", "scopes"].contains($0.key) }, actual: target)
                try AdminWritePolicy.verifyRelations(input: input, actual: target["user"], relation: "Role")
            }
            status = NSLocalizedString("已精确读回确认", comment: "")
            return
        }
        if !operation.entity.isEmpty {
            var ids = AdminWritePolicy.targetIDs(variables)
            if root.hasPrefix("create") { ids = [response["id"].string] }
            if root == "loadApiKeyProfileTemplate" { ids = [variables["input"]["apiKeyID"].string] }
            guard !ids.isEmpty, ids.allSatisfy({ !$0.isEmpty }) else { throw AdminError.verification }
            for id in ids {
                let actual = try await detail(operation.entity, id: id)
                if root.lowercased().contains("delete") {
                    guard actual.isNull else { throw AdminError.verification }
                    continue
                }
                guard actual["id"].string == id else { throw AdminError.verification }
                if root == "rotateAPIKey" {
                    guard actual["id"].string == response["id"].string else { throw AdminError.verification }
                    let reveal = try await read("revealAPIKey", variables: .object(["id": .string(id)]))
                    guard !response["key"].string.isEmpty, reveal["key"].string == response["key"].string else { throw AdminError.verification }
                } else if root == "loadApiKeyProfileTemplate" {
                    guard actual["profiles"] == response["profiles"] else { throw AdminError.verification }
                } else {
                    var expected = variables["input"].object
                    if root.hasSuffix("ApiKeyProfileTemplate") && !variables["profile"].isNull {
                        var profile = variables["profile"].object
                        profile["name"] = expected["name"] ?? baseline["name"]
                        profile.removeValue(forKey: "templateID"); profile.removeValue(forKey: "templateName")
                        expected["profile"] = .object(profile)
                    }
                    if !variables["status"].isNull { expected["status"] = variables["status"] }
                    if root.hasPrefix("bulk") {
                        expected["status"] = .string(root.contains("Enable") ? "enabled" : root.contains("Archive") ? "archived" : "disabled")
                    }
                    if root == "updateAPIKeyProfiles" || root == "updateProjectProfiles" {
                        var expectedProfiles = variables["input"].object
                        expectedProfiles["profiles"] = .array(variables["input"]["profiles"].array.map { profile in
                            .object(profile.object.filter { $0.key != "templateID" && $0.key != "templateName" })
                        })
                        try AdminWritePolicy.verifyFields(["profiles": .object(expectedProfiles)], actual: actual)
                        // Modified linked API key profiles may detach template IDs in the business service.
                        guard actual["profiles"]["activeProfile"] == variables["input"]["activeProfile"] else { throw AdminError.verification }
                    } else {
                        try AdminWritePolicy.verifyFields(expected, actual: actual, baseline: baseline)

                    }
                }
            }
            status = NSLocalizedString("已精确读回确认", comment: "")
            return
        }
        if root == "backup" {
            guard response["success"].bool, let backup = JSON.from(response["data"].string), !backup["version"].string.isEmpty else { throw AdminError.verification }
            _ = try await read("systemVersion")
            status = NSLocalizedString("备份数据已生成并校验格式；不修改服务器状态。", comment: "")
            return
        }
        guard !operation.verification.isEmpty else { throw AdminError.verification }
        var readVariables = JSON.object([:])
        if root == "triggerGcCleanup" { readVariables = variables }
        if root == "clearCache" { readVariables = .object(["input": variables["input"]]) }
        let actual = try await read(operation.verification, variables: readVariables)
        if root == "updateDefaultDataStorage" {
            guard actual.string == variables["input"]["dataStorageID"].string else { throw AdminError.verification }
        } else if root == "saveProxyPreset" || root == "deleteProxyPreset" {
            guard case .array(let entries) = actual else { throw AdminError.verification }
            let url = root == "deleteProxyPreset" ? variables["url"].string : variables["input"]["url"].string
            let target = entries.first { $0["url"].string == url }
            if root == "deleteProxyPreset" { guard target == nil else { throw AdminError.verification } }
            else { guard let target = target else { throw AdminError.verification }; try AdminWritePolicy.verifyFields(variables["input"].object, actual: target) }
        } else if root == "unlinkOIDCIdentity" {
            guard case .array(let identities) = actual["oidcIdentities"], !identities.contains(where: { $0["id"].string == variables["id"].string }) else { throw AdminError.verification }
        } else if root.hasPrefix("complete") {
            let target = root == "completeOnboarding" ? actual : actual[root == "completeSystemModelSettingOnboarding" ? "systemModelSetting" : "autoDisableChannel"]
            guard target["onboarded"].bool else { throw AdminError.verification }
        } else if root == "refreshProvidersCatalog" {
            guard actual["fetchedAt"] == response["fetchedAt"], actual["data"] == response["data"] else { throw AdminError.verification }
        } else if !operation.asyncEffect {
            try AdminWritePolicy.verifyFields(variables["input"].object, actual: actual, baseline: baseline)
        }
        // GC is asynchronous, cache diagnostic exposes no revision, passwords intentionally cannot be read back.
        status = operation.asyncEffect ? NSLocalizedString("服务器已接受，已读取目标状态；完成效果无法通过 API 精确证明。", comment: "") : NSLocalizedString("已精确读回确认", comment: "")
    }
}

/// Service-derived rules: do not confuse nullable SDL fields with implemented clears.
enum AdminWritePolicy {
    static func containsTruncatedObject(_ value: JSON) -> Bool {
        switch value {
        case .object(let fields): return (fields.count == 1 && fields["__typename"] != nil) || fields.values.contains(where: containsTruncatedObject)
        case .array(let items): return items.contains(where: containsTruncatedObject)
        default: return false
        }
    }
    static func removingSecrets(_ value: JSON) -> JSON {
        switch value {
        case .object(let fields): return .object(fields.filter { !AdminSchema.sensitive($0.key) }.mapValues(removingSecrets))
        case .array(let values): return .array(values.map(removingSecrets))
        default: return value
        }
    }
    static func targetIDs(_ variables: JSON) -> [String] {
        if !variables["id"].string.isEmpty { return [variables["id"].string] }
        return variables["ids"].array.map(\.string)
    }
    static func prepare(_ op: AdminOperation, variables: JSON, baseline: JSON, schema: AdminSchema) throws -> JSON {
        var vars = variables.object
        var input = vars["input"]?.object ?? [:]
        guard !containsTruncatedObject(baseline) else { throw AdminError.invalidInput }
        if !op.allowedInputFields.isEmpty {
            guard Set(input.keys).isSubset(of: Set(op.allowedInputFields)) else { throw AdminError.invalidInput }
        }
        if op.replacement, let field = op.variables.first(where: { $0.name == "input" }) {
            guard !baseline.isNull || op.root == "saveProxyPreset" else { throw AdminError.notFound }
            var merged = schema.project(baseline, type: field.type).object
            for (key, value) in input { merged[key] = value }
            input = merged
        }
        if op.root == "updateDataStorage", let patch = input["settings"] {
            var settings = baseline["settings"].object
            for (key, value) in patch.object {
                if ["s3", "gcs", "webdav"].contains(key) {
                    var nested = settings[key]?.object ?? [:]
                    for (k, v) in value.object { nested[k] = v }
                    settings[key] = .object(nested)
                } else { settings[key] = value }
            }
            if let field = op.variables.first(where: { $0.name == "input" }),
               let settingsField = schema.types[schema.base(field.type)]?.fields.first(where: { $0.name == "settings" }) {
                input["settings"] = schema.project(.object(settings), type: settingsField.type)
            } else { throw AdminError.schemaMissing }
        }
        if op.root == "updateAPIKey" {
            for key in ["scopes", "allowedIps"] {
                if let value = input[key], value.array.isEmpty {
                    input.removeValue(forKey: key)
                    input[key == "scopes" ? "clearScopes" : "clearAllowedIps"] = .bool(true)
                }
            }
            if baseline["type"].string != "service_account", input.keys.contains(where: { $0.lowercased().contains("scopes") }) { throw AdminError.invalidInput }
        }
        if op.root == "createAPIKey", input["type"]?.string != "service_account", input["scopes"] != nil { throw AdminError.invalidInput }
        if op.root == "updateSecuritySettings", let ips = input["blockedIPs"] {
            var seen = Set<String>()
            input["blockedIPs"] = .array(ips.array.map(\.string).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty && seen.insert($0).inserted }.map(JSON.string))
        }
        if op.root == "updateCatalogSettings" {
            if let url = input["upstreamURL"] { input["upstreamURL"] = .string(url.string.trimmingCharacters(in: .whitespacesAndNewlines)) }
            if let seconds = input["refreshSeconds"] { input["refreshSeconds"] = .number(seconds.number <= 0 ? 3600 : min(604800, max(60, seconds.number))) }
        }
        if op.root == "updateVideoStorageSettings" {
            for key in ["scanIntervalMinutes", "scanLimit"] where input[key]?.number ?? 1 <= 0 { throw AdminError.invalidInput }
        }
        if op.root == "updateRetryPolicy" {
            if let strategy = input["loadBalancerStrategy"], !["adaptive", "failover", "circuit-breaker", "round-robin", "weighted"].contains(strategy.string) { throw AdminError.invalidInput }
            if input["loadBalancerStrategy"]?.string == "weighted" { input["loadBalancerStrategy"] = .string("failover") }
            for key in ["streamFirstEventTimeoutSeconds", "nonStreamResponseTimeoutSeconds"] {
                if let value = input[key] { input[key] = .number(min(600, max(0, value.number))) }
            }
            if input["upstreamErrorPolicy"]?["mode"].string == "custom", input["upstreamErrorPolicy"]?["customMessage"].string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
                var policy = input["upstreamErrorPolicy"]!.object; policy["mode"] = .string("hidden"); input["upstreamErrorPolicy"] = .object(policy)
            }
        }
        if op.root == "updateAPIKeyProfiles", let profiles = input["profiles"] {
            input["profiles"] = .array(try profiles.array.map(normalizeProfile))
        }
        if let profile = vars["profile"], !profile.isNull { vars["profile"] = try normalizeProfile(profile) }
        if vars["input"] != nil { vars["input"] = .object(input) }
        // Dedicated profile writes are whole object replacements; preserve all fields with the native baseline editor.
        return .object(vars)
    }
    static func normalizeProfile(_ value: JSON) throws -> JSON {
        var profile = value.object
        for (key, allowed) in [("loadBalanceStrategy", ["default", "adaptive", "failover", "circuit-breaker", "round-robin"]), ("traceStickyMode", ["default", "disabled", "prefer_previous_channel"])] {
            let text = profile[key]?.string ?? "default"
            let normalized = ["", "system_default"].contains(text) ? "default" : text
            guard allowed.contains(normalized) else { throw AdminError.invalidInput }
            profile[key] = .string(normalized)
        }
        return .object(profile)
    }
    static func matches(_ actual: JSON, _ expected: JSON) -> Bool {
        switch expected {
        case .object(let fields):
            guard case .object = actual else { return false }
            return fields.allSatisfy { matches(actual[$0.key], $0.value) }
        case .array(let values):
            guard case .array(let items) = actual, items.count == values.count else { return false }
            return zip(items, values).allSatisfy { matches($0.0, $0.1) }
        default: return actual == expected
        }
    }
    static func verifyFields(_ input: [String: JSON], actual: JSON, baseline: JSON = .null) throws {
        for (key, expected) in input {
            if AdminSchema.sensitive(key) && key != "value" && key != "headers" { continue } // write-only; never pretend we read stored hashes/cloud credentials.
            if key == "projectID" || key == "userID" || key == "type", actual.object[key] == nil { continue }
            if key.hasPrefix("add") || key.hasPrefix("remove") || key.hasPrefix("clear") || key.hasPrefix("append") || ["roleIDs", "userIDs"].contains(key) { continue }
            if key == "settings" || key == "profile" { try verifyFields(expected.object, actual: actual[key]); continue }
            if ["s3", "gcs", "webdav", "proxy"].contains(key) { try verifyFields(expected.object, actual: actual[key]); continue }
            guard matches(actual[key], expected) else { throw AdminError.verification }
        }
        for (clear, key) in [("clearScopes", "scopes"), ("clearAllowedIps", "allowedIps"), ("clearAvatar", "avatar"), ("clearRoles", "roles"), ("clearUsers", "users")] where input[clear]?.bool == true {
            let value = actual[key]
            if key == "avatar" { guard value.isNull || value.string.isEmpty else { throw AdminError.verification } }
            else if ["roles", "users"].contains(key) {
                guard case .array(let edges) = value["edges"], edges.isEmpty else { throw AdminError.verification }
            } else { guard value.isNull || { if case .array(let list) = value { return list.isEmpty }; return false }() else { throw AdminError.verification } }
        }
        for (append, key) in [("appendScopes", "scopes"), ("appendAllowedIps", "allowedIps")] {
            if let added = input[append] {
                guard case .array(let actualItems) = actual[key] else { throw AdminError.verification }
                let base = baseline[key].array
                guard actualItems == base + added.array else { throw AdminError.verification }
            }
        }
        let object = JSON.object(input)
        try verifyRelations(input: object, actual: actual, relation: "Role")
        try verifyRelations(input: object, actual: actual, relation: "User")
    }
    static func verifyRelations(input: JSON, actual: JSON, relation: String) throws {
        let add = "add\(relation)IDs", remove = "remove\(relation)IDs", create = "\(relation.lowercased())IDs"
        guard input.object[add] != nil || input.object[remove] != nil || input.object[create] != nil else { return }
        let key = relation.lowercased() + "s"
        guard case .array(let edges) = actual[key]["edges"] else { throw AdminError.verification }
        let ids = Set(edges.map { $0["node"]["id"].string })
        for item in input[add].array + input[create].array { guard ids.contains(item.string) else { throw AdminError.verification } }
        for item in input[remove].array { guard !ids.contains(item.string) else { throw AdminError.verification } }
    }
}
