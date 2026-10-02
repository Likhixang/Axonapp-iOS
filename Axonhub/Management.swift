import Foundation

/// Captured when an editor/action opens; switching away and back also invalidates it.
struct ManagementTarget: Identifiable {
    let id = UUID()
    let instance: AxonInstance
    let connectionRevision: UUID
    let entityID: String?
    let kind: ManagementKind
}

enum ManagementKind: Equatable { case channel, model }

enum ManagementError: Error, LocalizedError {
    case changedTarget, invalidFields, noRoute, verification, busy, unsafeCredentials
    var errorDescription: String? {
        switch self {
        case .changedTarget: return NSLocalizedString("目标实例或连接已改变，请关闭并重新打开编辑器。", comment: "")
        case .invalidFields: return NSLocalizedString("请填写必填字段，并检查 URL、整数及 JSON 格式。", comment: "")
        case .noRoute: return NSLocalizedString("路由没有匹配到可用渠道，请先配置渠道及其支持模型。", comment: "")
        case .verification: return NSLocalizedString("服务器写入结果未能验证。请刷新确认后再操作，避免重复新增。", comment: "")
        case .busy: return NSLocalizedString("另一项管理操作正在执行，请稍后重试。", comment: "")
        case .unsafeCredentials: return NSLocalizedString("凭据替换会覆盖整个凭据对象，请先授权读取原有凭据或确认完整替换。", comment: "")
        }
    }
}

/// Complete official beta10 channel types.
enum ChannelType: String, CaseIterable, Identifiable {
    case openai, openai_responses, atlascloud, cline, codex, vercel, anthropic, anthropic_aws, anthropic_gcp
    case gemini_openai, gemini, gemini_vertex, deepseek, deepseek_anthropic, deepinfra, qiniu, fireworks
    case doubao, doubao_anthropic, moonshot, moonshot_anthropic, zhipu, zai, zhipu_anthropic, zai_anthropic
    case anthropic_fake, openai_fake, openrouter, xiaomi, xiaomi_anthropic, xai, xai_responses, xai_subscription
    case ppio, siliconflow, volcengine, volcengine_anthropic, longcat, longcat_anthropic, minimax, minimax_anthropic
    case aihubmix, aihubmix_anthropic, burncloud, modelscope, bailian, bailian_anthropic, moonshot_coding, jina
    case github, github_copilot, claudecode, cerebras, antigravity, nanogpt, nanogpt_responses, opencode_go
    case opencode_go_anthropic, ollama, ollama_anthropic, evolink, evolink_anthropic, groq, qiniu_anthropic, fenno
    case zenmux, zenmux_responses, zenmux_anthropic, zenmux_gemini, commandcode, commandcode_anthropic
    var id: String { rawValue }
    static let singleKeyTypes: [ChannelType] = [.openai, .openai_responses, .anthropic, .deepseek, .openrouter, .gemini]
}

enum ModelType: String, CaseIterable, Identifiable {
    case chat, embedding, rerank, image_generation, video_generation
    var id: String { rawValue }
}

struct ChannelDraft {
    var name = "", baseURL = "", type = "openai", supportedModels = "", defaultTestModel = ""
    var tags = "", orderingWeight = "0", remark = "", apiKey = ""
    var autoSync = false, syncPattern = "", manualModels = ""
    var settings: JSON = .object([:]), policies: JSON = .object(["stream": .string("unlimited")]), endpoints: JSON = .array([])
    var credentials: JSON = .object([:])
    var secretsLoaded = false, authorizeReadback = false, replaceCredentials = false, migrationConfirmed = false
    var original: JSON?
    var originalCredentials: JSON?
    var originalSettings: JSON?
    var duplicateSourceID: String?
    init(detail: JSON? = nil) {
        original = detail
        guard let d = detail else { return }
        name = d["name"].string; baseURL = d["baseURL"].string; type = d["type"].string
        supportedModels = d["supportedModels"].array.map(\.string).joined(separator: "\n")
        defaultTestModel = d["defaultTestModel"].string
        tags = d["tags"].array.map(\.string).joined(separator: "\n")
        orderingWeight = String(d["orderingWeight"].int); remark = d["remark"].string
        autoSync = d["autoSyncSupportedModels"].bool; syncPattern = d["autoSyncModelPattern"].string
        manualModels = d["manualModels"].array.map(\.string).joined(separator: "\n")
        settings = d["settings"].isNull ? .object([:]) : d["settings"]
        policies = d["policies"].isNull ? .object([:]) : d["policies"]
        endpoints = d["endpoints"].isNull ? .array([]) : d["endpoints"]
    }
    mutating func loadSecrets(_ secret: JSON) {
        credentials = secret["credentials"].withoutNulls
        originalCredentials = credentials
        settings = secret["settings"].isNull ? .object([:]) : secret["settings"]
        originalSettings = settings
        secretsLoaded = true
    }
    var editableKeys: [String] {
        let keys = credentials["apiKeys"].array.map(\.string)
        if !keys.isEmpty { return keys }
        return [secretsLoaded ? credentials["apiKey"].string : apiKey]
    }
    mutating func setKey(_ text: String, at index: Int) {
        var keys = editableKeys
        guard keys.indices.contains(index) else { return }
        keys[index] = text
        if keys.count == 1 && credentials["apiKeys"].array.isEmpty {
            if secretsLoaded { var fields = credentials.object; fields["apiKey"] = .string(text); credentials = .object(fields) }
            else { apiKey = text }
        } else { storeKeys(keys) }
    }
    mutating func appendKey() { storeKeys(editableKeys + [""]) }
    mutating func removeKey(at index: Int) {
        var keys = editableKeys
        guard keys.count > 1, keys.indices.contains(index) else { return }
        keys.remove(at: index); storeKeys(keys)
    }
    private mutating func storeKeys(_ keys: [String]) {
        var fields = credentials.object
        fields["apiKeys"] = .array(keys.map(JSON.string)); fields["apiKey"] = .string("")
        credentials = .object(fields); apiKey = ""
    }
    mutating func migrate(to newType: String) {
        guard type != newType else { return }
        type = newType
        if original == nil { baseURL = ChannelDefaults.urls[newType] ?? "" }
        endpoints = .array([]) // endpoint defaults must follow the new provider.
        var s = settings.object; s["modelProtocols"] = .array([]); s["providerQuota"] = .null
        settings = .object(s); migrationConfirmed = original == nil
        if newType == "xai_subscription" { baseURL = ChannelDefaults.urls[newType] ?? "" }
    }
    func payload() throws -> [String: JSON] {
        guard !name.trimmed.isEmpty, let weight = Int(orderingWeight), (-2147483648...2147483647).contains(weight),
              ChannelType(rawValue: type) != nil else { throw ManagementError.invalidFields }
        let baseline = ChannelDraft(detail: original)
        let models = supportedModels.lines
        if original == nil && duplicateSourceID != nil && !secretsLoaded { throw ManagementError.unsafeCredentials }
        if type == "xai_subscription" {
            guard baseURL.trimmed.isEmpty || baseURL.trimmed == ChannelDefaults.urls[type], endpoints.array.isEmpty else { throw ManagementError.invalidFields }
        }
        if original == nil || supportedModels != baseline.supportedModels || defaultTestModel != baseline.defaultTestModel {
            guard !defaultTestModel.trimmed.isEmpty, models.isEmpty || models.contains(defaultTestModel.trimmed) else { throw ManagementError.invalidFields }
        }
        if !baseURL.trimmed.isEmpty { try ChannelSemantics.url(baseURL.trimmed, websocket: type == "codex" || type == "openai_responses") }
        if !syncPattern.isEmpty { try ChannelSemantics.regex(syncPattern) }
        if original == nil || manualModels != baseline.manualModels || supportedModels != baseline.supportedModels {
            guard manualModels.lines.allSatisfy({ models.contains($0) }) else { throw ManagementError.invalidFields }
        }
        try ChannelInputSchema.validate(policies, type: "ChannelPoliciesInput!")
        try ChannelInputSchema.validate(endpoints, type: "[ChannelEndpointInput!]!")
        try ChannelSemantics.policies(policies)
        try ChannelSemantics.endpoints(endpoints)
        var p: [String: JSON] = ["name": .string(name.trimmed), "baseURL": .string(baseURL.trimmed),
            "type": .string(type), "supportedModels": .array(models.map(JSON.string)),
            "defaultTestModel": .string(defaultTestModel.trimmed), "tags": .array(tags.lines.map(JSON.string)),
            "orderingWeight": .number(Double(weight)), "remark": .string(remark),
            "autoSyncSupportedModels": .bool(autoSync), "autoSyncModelPattern": .string(syncPattern),
            "manualModels": .array(manualModels.lines.map(JSON.string)), "policies": policies, "endpoints": endpoints]
        if let original = original {
            let changed: Set<String> = Set([
                name != baseline.name ? "name" : nil, baseURL != baseline.baseURL ? "baseURL" : nil,
                type != baseline.type ? "type" : nil, supportedModels != baseline.supportedModels ? "supportedModels" : nil,
                defaultTestModel != baseline.defaultTestModel ? "defaultTestModel" : nil,
                tags != baseline.tags ? "tags" : nil, orderingWeight != baseline.orderingWeight ? "orderingWeight" : nil,
                remark != baseline.remark ? "remark" : nil, autoSync != baseline.autoSync ? "autoSyncSupportedModels" : nil,
                syncPattern != baseline.syncPattern ? "autoSyncModelPattern" : nil, manualModels != baseline.manualModels ? "manualModels" : nil,
                policies != baseline.policies ? "policies" : nil, endpoints != baseline.endpoints ? "endpoints" : nil
            ].compactMap { $0 })
            p = p.filter { key, value in changed.contains(key) && value != original[key] }
            // beta10 biz ignores clearBaseURL. An explicit empty string reaches SetNillableBaseURL.
            if type != baseline.type {
                guard migrationConfirmed, secretsLoaded || replaceCredentials else { throw ManagementError.unsafeCredentials }
                p["endpoints"] = endpoints
            }
            if (secretsLoaded && settings != originalSettings) || (settings != baseline.settings && type != baseline.type) {
                guard secretsLoaded else { throw ManagementError.unsafeCredentials }
                try ChannelSemantics.settings(ChannelSemantics.normalizedSettings(settings, models: models, type: type), models: models, endpoints: endpoints, defaults: original["defaultEndpoints"])
                p["settings"] = settings
            }
        } else {
            if baseURL.trimmed.isEmpty { p.removeValue(forKey: "baseURL") }
            try ChannelSemantics.settings(settings, models: models, endpoints: endpoints, defaults: .array([]))
            p["settings"] = settings
        }
        var c = credentials.object
        if !apiKey.isEmpty { c["apiKey"] = .string(apiKey.trimmed) }
        let shouldSendCredentials = original == nil || .object(c) != (originalCredentials ?? .object([:]))
        if shouldSendCredentials {
            guard original == nil || secretsLoaded || replaceCredentials else { throw ManagementError.unsafeCredentials }
            guard original == nil || secretsLoaded || authorizeReadback else { throw ManagementError.unsafeCredentials }
            let full = JSON.object(c)
            try ChannelInputSchema.validate(full, type: "ChannelCredentialsInput!")
            try ChannelSemantics.credentials(full, type: type)
            p["credentials"] = full // Go replaces all fields, only ZenMux management key is preserved server-side.
        }
        if let policies = p["policies"] { p["policies"] = ChannelSemantics.normalizedPolicies(policies) }
        if let settings = p["settings"] { p["settings"] = ChannelSemantics.normalizedSettings(settings, models: models, type: type) }
        return p
    }
}

struct ModelDraft {
    var name = "", modelID = "", developer = "", type = "chat", group = "", icon = "", remark = ""
    var routeModelID = "", modelCard = "{}", associationsJSON = "[]"
    var disableInheritance = false, loadBalancer = "default", sticky = "default"
    var settingsOriginal: JSON = .object([:])
    var original: JSON?
    init(detail: JSON? = nil) {
        original = detail
        guard let d = detail else { return }
        name = d["name"].string; modelID = d["modelID"].string; developer = d["developer"].string
        type = d["type"].string; group = d["group"].string; icon = d["icon"].string; remark = d["remark"].string
        modelCard = d["modelCard"].prettyJSON
        settingsOriginal = d["settings"]
        associationsJSON = d["settings"]["associations"].prettyJSON
        disableInheritance = d["settings"]["disableDeveloperSettingsInheritance"].bool
        loadBalancer = d["settings"]["loadBalancerStrategy"].string.isEmpty ? "default" : d["settings"]["loadBalancerStrategy"].string
        sticky = d["settings"]["traceStickyMode"].string.isEmpty ? "default" : d["settings"]["traceStickyMode"].string
    }
    var associations: JSON {
        if !routeModelID.trimmed.isEmpty { return .array([.object(["type": .string("model"), "priority": .number(0), "disabled": .bool(false),
                        "modelId": .object(["modelId": .string(routeModelID.trimmed)])])]) }
        return JSON.from(associationsJSON) ?? .null
    }
    var settings: JSON {
        var fields = settingsOriginal.object
        fields["associations"] = associations
        fields["disableDeveloperSettingsInheritance"] = .bool(disableInheritance)
        fields["loadBalancerStrategy"] = .string(loadBalancer)
        fields["traceStickyMode"] = .string(sticky)
        return .object(fields)
    }
    func payload() throws -> [String: JSON] {
        guard [name, modelID, developer, group, icon].allSatisfy({ !$0.trimmed.isEmpty }), ModelType(rawValue: type) != nil else { throw ManagementError.invalidFields }
        var p: [String: JSON] = ["name": .string(name.trimmed), "modelID": .string(modelID.trimmed),
            "developer": .string(developer.trimmed), "type": .string(type), "group": .string(group.trimmed),
            "icon": .string(icon.trimmed), "remark": .string(remark)]
        if let original = original {
            let baseline = ModelDraft(detail: original)
            let changed: Set<String> = Set([
                name != baseline.name ? "name" : nil, modelID != baseline.modelID ? "modelID" : nil,
                developer != baseline.developer ? "developer" : nil, type != baseline.type ? "type" : nil,
                group != baseline.group ? "group" : nil, icon != baseline.icon ? "icon" : nil,
                remark != baseline.remark ? "remark" : nil
            ].compactMap { $0 })
            p = p.filter { key, value in changed.contains(key) && value != original[key] }
        }
        // Complete recursive associations are loaded before any settings replacement.
        if original == nil || modelCard != original?["modelCard"].prettyJSON {
            guard let card = JSON.from(modelCard), case .object = card, Self.validCard(card) else { throw ManagementError.invalidFields }
            p["modelCard"] = Self.normalizedCard(card)
        }
        if original == nil || associationsJSON != ModelDraft(detail: original).associationsJSON || disableInheritance != ModelDraft(detail: original).disableInheritance || loadBalancer != ModelDraft(detail: original).loadBalancer || sticky != ModelDraft(detail: original).sticky || !routeModelID.isEmpty {
            try ChannelInputSchema.validate(settings, type: "ModelSettingsInput!")
            try ChannelSemantics.modelSettings(settings)
            p["settings"] = settings
        }
        return p
    }
    /// Go value structs reset omitted fields. Normalize before sending and exact readback.
    static func normalizedCard(_ card: JSON) -> JSON {
        let defaults: [String: JSON] = [
            "reasoning": .object(["supported": .bool(false), "default": .bool(false)]),
            "toolCall": .bool(false), "temperature": .bool(false), "vision": .bool(false),
            "modalities": .object(["input": .array([]), "output": .array([])]),
            "cost": .object(["input": .number(0), "output": .number(0), "cacheRead": .number(0), "cacheWrite": .number(0)]),
            "limit": .object(["context": .number(0), "output": .number(0)]),
            "knowledge": .string(""), "releaseDate": .string(""), "lastUpdated": .string("")]
        return .object(defaults.mapValues { $0 }.merging(card.object) { original, provided in
            if case .object(let fields) = original { return .object(fields.merging(provided.object) { _, value in value }) }
            return provided
        })
    }
    static func validCard(_ card: JSON) -> Bool {
        let shapes: [String: Set<String>] = ["reasoning": ["supported", "default"], "modalities": ["input", "output"],
            "cost": ["input", "output", "cacheRead", "cacheWrite"], "limit": ["context", "output"]]
        let allowed = Set(shapes.keys).union(["toolCall", "temperature", "vision", "knowledge", "releaseDate", "lastUpdated"])
        for (key, value) in card.object {
            guard allowed.contains(key) else { return false }
            if value.isNull { return false }
            if let nested = shapes[key] {
                guard case .object(let fields) = value, Set(fields.keys).isSubset(of: nested) else { return false }
                for (_, field) in fields {
                    if field.isNull { return false }
                    switch key {
                    case "reasoning": guard case .bool = field else { return false }
                    case "modalities": guard case .array(let items) = field, items.allSatisfy({ if case .string = $0 { return true }; return false }) else { return false }
                    case "limit": guard case .number(let n) = field, n >= 0, n <= 2147483647, n.rounded() == n else { return false }
                    default: guard case .number(let n) = field, n >= 0 else { return false }
                    }
                }
            } else if ["toolCall", "temperature", "vision"].contains(key) {
                guard case .bool = value else { return false }
            } else { guard case .string = value else { return false } }
        }
        return true
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var lines: [String] { var seen = Set<String>(); return components(separatedBy: .newlines).map(\.trimmed).filter { !$0.isEmpty && seen.insert($0).inserted } }
}
extension JSON {
    var withoutNulls: JSON {
        switch self {
        case .object(let o): return .object(o.filter { !$0.value.isNull }.mapValues { $0.withoutNulls })
        case .array(let a): return .array(a.map { $0.withoutNulls })
        default: return self
        }
    }
    var prettyJSON: String {
        do { return String(decoding: try JSONEncoder.pretty.encode(self), as: UTF8.self) }
        catch { return "{}" }
    }
    func foundationObject() throws -> Any { try JSONSerialization.jsonObject(with: JSONEncoder().encode(self), options: [.fragmentsAllowed]) }
}
private extension JSONEncoder {
    static var pretty: JSONEncoder { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; return encoder }
}

extension AxonClient {
    func channelDetail(id: String) async throws -> JSON? {
        let query = """
        query ChannelDetail($id: ID!) {
          channels(first: 1, where: {id: $id}) { edges { node {
            id name type baseURL status supportedModels defaultTestModel tags orderingWeight remark errorMessage
            autoSyncSupportedModels autoSyncModelPattern manualModels updatedAt
            endpoints { apiFormat path baseURL transport } defaultEndpoints { apiFormat path baseURL transport }
            policies { stream apiKeyAutoDisableRules { statusCodes keywordPatterns times action disableDurationMinutes disableUntilCron disableUntilTimezone } }
            settings {
              extraModelPrefix modelMappings { from to } autoTrimedModelPrefixes hideOriginalModels hideMappedModels lowercaseModelId
              proxy { type disableConnectionReuse }
              transformOptions { forceArrayInstructions forceArrayInputs replaceDeveloperRoleWithSystem reasoningEffortMapping { from to } }
              passThroughUserAgent passThroughBody rateLimit { rpm tpm maxConcurrent queueSize queueTimeoutMs }
              retryableStatusCodes retryableErrorPatterns { pattern regex } modelProtocols { model apiFormats enabled }
            }
          } } }
        }
        """
        let data = try await graphql(query: query, variables: ["id": id])
        guard case .array = data["channels"]["edges"] else { throw AxonAPIError.invalidResponse }
        return data["channels"]["edges"].array.first?["node"]
    }
    func modelDetail(id: String) async throws -> JSON? {
        let query = """
        query ModelDetail($id: ID!) {
          models(first: 1, where: {id: $id}) { edges { node {
            id name modelID developer type group icon status remark associatedChannelCount
            modelCard {
              reasoning { supported default } toolCall temperature vision modalities { input output }
              cost { input output cacheRead cacheWrite } limit { context output } knowledge releaseDate lastUpdated
            }
            settings { disableDeveloperSettingsInheritance loadBalancerStrategy traceStickyMode
              associations { type priority disabled
                channelModel { channelId modelId } channelRegex { channelId pattern }
                regex { pattern exclude { channelNamePattern channelIds channelTags } }
                modelId { modelId exclude { channelNamePattern channelIds channelTags } }
                channelTagsModel { channelTags modelId } channelTagsRegex { channelTags pattern }
                when { enabled condition { type logic field operator value
                  conditions { type logic field operator value
                    conditions { type logic field operator value conditions { type } }
                  }
                } }
              }
            }
          } } }
        }
        """
        var expanded = query
        for _ in 0..<256 {
            let data = try await graphql(query: expanded, variables: ["id": id])
            guard case .array = data["models"]["edges"] else { throw AxonAPIError.invalidResponse }
            guard let node = data["models"]["edges"].array.first?["node"] else { return nil }
            if !Self.hasTruncatedCondition(node["settings"]) { return node }
            // Expand the selected leaf, re-read the whole object (never combine versions).
            expanded = expanded.replacingOccurrences(of: "conditions { type }", with: "conditions { type logic field operator value conditions { type } }")
        }
        throw ManagementError.invalidFields // fail closed, never submit a truncated tree.
    }
    static func hasTruncatedCondition(_ value: JSON) -> Bool {
        if case .object(let object) = value {
            if object["type"] != nil && object.keys.count == 1 { return true }
            return object.values.contains(where: hasTruncatedCondition)
        }
        return value.array.contains(where: hasTruncatedCondition)
    }
    func routeMatches(associations: JSON) async throws -> Bool {
        let query = """
        query CheckModelRoute($associations: [ModelAssociationInput!]!) {
          queryModelChannelConnections(associations: $associations) { channel { id status } models { requestModel actualModel } }
        }
        """
        let data = try await graphql(query: query, variables: ["associations": associations.foundationObject()])
        return data["queryModelChannelConnections"].array.contains { $0["channel"]["status"].string == "enabled" && !$0["models"].array.isEmpty }
    }
    func createChannel(input: [String: JSON]) async throws -> String {
        let mutation = """
        mutation CreateChannel($input: CreateChannelInput!) { createChannel(input: $input) { id } }
        """
        let data = try await graphql(query: mutation, variables: ["input": JSON.object(input).foundationObject()])
        guard !data["createChannel"]["id"].string.isEmpty else { throw ManagementError.verification }
        return data["createChannel"]["id"].string
    }
    func editChannel(id: String, input: [String: JSON]) async throws {
        let mutation = """
        mutation EditChannel($id: ID!, $input: UpdateChannelInput!) { updateChannel(id: $id, input: $input) { id } }
        """
        let data = try await graphql(query: mutation, variables: ["id": id, "input": JSON.object(input).foundationObject()])
        guard data["updateChannel"]["id"].string == id else { throw ManagementError.verification }
    }
    func deleteChannel(id: String) async throws {
        let mutation = """
        mutation DeleteChannel($id: ID!) { deleteChannel(id: $id) }
        """
        let data = try await graphql(query: mutation, variables: ["id": id])
        guard data["deleteChannel"].bool else { throw ManagementError.verification }
    }
    func createModel(input: [String: JSON]) async throws -> String {
        let mutation = """
        mutation CreateModel($input: CreateModelInput!) { createModel(input: $input) { id } }
        """
        let data = try await graphql(query: mutation, variables: ["input": JSON.object(input).foundationObject()])
        guard !data["createModel"]["id"].string.isEmpty else { throw ManagementError.verification }
        return data["createModel"]["id"].string
    }
    func editModel(id: String, input: [String: JSON]) async throws {
        let mutation = """
        mutation EditModel($id: ID!, $input: UpdateModelInput!) { updateModel(id: $id, input: $input) { id } }
        """
        let data = try await graphql(query: mutation, variables: ["id": id, "input": JSON.object(input).foundationObject()])
        guard data["updateModel"]["id"].string == id else { throw ManagementError.verification }
    }
    func deleteModel(id: String) async throws {
        let mutation = """
        mutation DeleteModel($id: ID!) { deleteModel(id: $id) }
        """
        let data = try await graphql(query: mutation, variables: ["id": id])
        guard data["deleteModel"].bool else { throw ManagementError.verification }
    }
}
