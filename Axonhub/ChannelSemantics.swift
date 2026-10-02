import Foundation

/// Semantic constraints in addition to generated GraphQL input coercion.
enum ChannelSemantics {
    static func url(_ s: String, websocket: Bool = false) throws {
        guard let u = URL(string: s), u.host != nil, u.user == nil, u.password == nil,
              u.query == nil, ["https", "http"].contains(u.scheme ?? "") || websocket && ["ws", "wss"].contains(u.scheme ?? "") else { throw ManagementError.invalidFields }
        // Codex frontend deliberately uses a terminal # to suppress /v1 normalization.
        guard u.fragment == nil || u.fragment == "" else { throw ManagementError.invalidFields }
    }
    static func regex(_ s: String) throws {
        // RE2 rejects lookaround and backreferences. Do not silently broaden patterns.
        guard !s.contains("(?="), !s.contains("(?!"), !s.contains("(?<"),
              s.range(of: #"\\[1-9]"#, options: .regularExpression) == nil else { throw ManagementError.invalidFields }
        do { _ = try NSRegularExpression(pattern: s) } catch { throw ManagementError.invalidFields }
    }
    static func credentials(_ c: JSON, type: String) throws {
        if type == "anthropic_gcp" || (type == "gemini_vertex" && !c["gcp"].isNull) {
            let g = c["gcp"]
            guard !g["region"].string.isEmpty, !g["projectID"].string.isEmpty,
                  let data = JSON.from(g["jsonData"].string), case .object = data else { throw ManagementError.invalidFields }
        } else if type != "anthropic_aws" {
            guard !c["apiKey"].string.trimmed.isEmpty || c["apiKeys"].array.contains(where: { !$0.string.trimmed.isEmpty }) || !c["oauth"]["accessToken"].string.isEmpty else { throw ManagementError.invalidFields }
        }
        for key in c["apiKeys"].array { guard !key.string.trimmed.isEmpty else { throw ManagementError.invalidFields } }
        if ["codex", "claudecode", "antigravity", "github_copilot", "xai_subscription"].contains(type) {
            let key = c["apiKey"].string
            if c["oauth"]["accessToken"].string.isEmpty && (type == "xai_subscription" || key.trimmed.hasPrefix("{")) {
                guard let j = JSON.from(key), !j["access_token"].string.isEmpty,
                      ["github_copilot", "xai_subscription"].contains(type) || !j["refresh_token"].string.isEmpty else { throw ManagementError.invalidFields }
            }
        }
    }
    static func endpoints(_ e: JSON) throws {
        var formats = Set<String>()
        for endpoint in e.array {
            let f = endpoint["apiFormat"].string
            guard !f.isEmpty, formats.insert(f).inserted else { throw ManagementError.invalidFields }
            if !endpoint["baseURL"].string.isEmpty { try url(endpoint["baseURL"].string, websocket: endpoint["transport"].string == "websocket") }
            guard endpoint["transport"].isNull || ["", "http", "websocket"].contains(endpoint["transport"].string) else { throw ManagementError.invalidFields }
        }
    }
    static func policies(_ p: JSON) throws {
        for rule in p["apiKeyAutoDisableRules"].array {
            guard rule["times"].int > 0, !rule["statusCodes"].array.isEmpty || rule["keywordPatterns"].array.contains(where: { !$0.string.trimmed.isEmpty }) else { throw ManagementError.invalidFields }
            guard rule["statusCodes"].array.allSatisfy({ (100...599).contains($0.int) }) else { throw ManagementError.invalidFields }
            if rule["action"].string == "temporary_disable" { guard rule["disableDurationMinutes"].int > 0 else { throw ManagementError.invalidFields } }
            if rule["action"].string == "disable_until_cron" { guard !rule["disableUntilCron"].string.trimmed.isEmpty else { throw ManagementError.invalidFields } }
        }
    }
    static func settings(_ s: JSON, models: [String], endpoints: JSON, defaults: JSON) throws {
        try ChannelInputSchema.validate(s, type: "ChannelSettingsInput!")
        let nonNullable: Set<String> = ["extraModelPrefix", "hideOriginalModels", "hideMappedModels", "lowercaseModelId", "transformOptions"]
        for key in nonNullable where s.object[key]?.isNull == true { throw ManagementError.invalidFields }
        for key in ["forceArrayInstructions", "forceArrayInputs", "replaceDeveloperRoleWithSystem"] where s["transformOptions"].object[key]?.isNull == true { throw ManagementError.invalidFields }
        for key in ["url", "username", "password"] where s["proxy"].object[key]?.isNull == true { throw ManagementError.invalidFields }
        for v in s["rateLimit"].object.values where !v.isNull { guard v.number >= 0 else { throw ManagementError.invalidFields } }
        guard s["retryableStatusCodes"].array.allSatisfy({ (400...599).contains($0.int) }) else { throw ManagementError.invalidFields }
        for pattern in s["retryableErrorPatterns"].array {
            guard !pattern["pattern"].string.isEmpty else { throw ManagementError.invalidFields }
            if pattern["regex"].bool { try regex(pattern["pattern"].string) }
        }
        if s["proxy"]["type"].string == "URL" {
            let address = s["proxy"]["url"].string
            guard let u = URL(string: address), u.host != nil, ["http", "https", "socks5", "socks5h"].contains(u.scheme ?? "") else { throw ManagementError.invalidFields }
        }
        let formats = Set((endpoints.array.isEmpty ? defaults : endpoints).array.map { $0["apiFormat"].string })
        for p in s["modelProtocols"].array {
            guard models.contains(p["model"].string), !p["apiFormats"].array.isEmpty else { throw ManagementError.invalidFields }
            if !formats.isEmpty { guard Set(p["apiFormats"].array.map(\.string)).isSubset(of: formats) else { throw ManagementError.invalidFields } }
        }
        for key in ["bodyOverrideOperations", "headerOverrideOperations"] {
            for op in s[key].array {
                let kind = op["op"].string
                guard ["set", "set_if_absent", "delete", "rename", "copy", "array_append", "array_prepend", "array_insert", "array_remove"].contains(kind) else { throw ManagementError.invalidFields }
                if ["rename", "copy"].contains(kind) { guard !op["from"].string.isEmpty, !op["to"].string.isEmpty else { throw ManagementError.invalidFields } }
                else { guard !op["path"].string.isEmpty else { throw ManagementError.invalidFields } }
                if ["set", "set_if_absent", "array_append", "array_prepend", "array_insert"].contains(kind) { guard !op["value"].isNull else { throw ManagementError.invalidFields } }
            }
        }
    }
    static func normalizedPolicies(_ p: JSON) -> JSON {
        var fields = p.object
        if fields["stream"] == nil || fields["stream"]?.isNull == true { fields["stream"] = .string("unlimited") }
        if fields["apiKeyAutoDisableRules"] != nil {
            fields["apiKeyAutoDisableRules"] = .array(p["apiKeyAutoDisableRules"].array.map { rule in
                var r = rule.object
                r["statusCodes"] = .array(Set(rule["statusCodes"].array.map(\.int)).sorted().map { .number(Double($0)) })
                var seen = Set<String>()
                r["keywordPatterns"] = .array(rule["keywordPatterns"].array.map { $0.string.trimmed }.filter { !$0.isEmpty && seen.insert($0).inserted }.map(JSON.string))
                let action = rule["action"].string
                if action == "disable_until_cron" {
                    r["disableDurationMinutes"] = .null
                    r["disableUntilCron"] = .string(rule["disableUntilCron"].string.trimmed)
                    r["disableUntilTimezone"] = .string(rule["disableUntilTimezone"].string.trimmed)
                } else {
                    r["disableUntilCron"] = .string(""); r["disableUntilTimezone"] = .string("")
                    if action != "temporary_disable" { r["disableDurationMinutes"] = .null }
                }
                return .object(r)
            })
        }
        return .object(fields)
    }
    static func normalizedSettings(_ s: JSON, models: [String], type: String) -> JSON {
        var fields = s.object
        if fields["retryableStatusCodes"] != nil {
            fields["retryableStatusCodes"] = .array(Set(s["retryableStatusCodes"].array.map(\.int)).sorted().map { .number(Double($0)) })
        }
        if fields["retryableErrorPatterns"] != nil {
            var seen = Set<String>()
            fields["retryableErrorPatterns"] = .array(s["retryableErrorPatterns"].array.compactMap { item in
                let pattern = item["pattern"].string.trimmed, flag = item["regex"].bool
                guard !pattern.isEmpty, seen.insert("\(flag)\0\(pattern)").inserted else { return nil }
                return .object(["pattern": .string(pattern), "regex": .bool(flag)])
            })
        }
        if fields["modelProtocols"] != nil && !models.isEmpty { fields["modelProtocols"] = .array(s["modelProtocols"].array.filter { models.contains($0["model"].string) }) }
        if !["commandcode", "commandcode_anthropic"].contains(type) { fields.removeValue(forKey: "providerQuota") }
        return .object(fields)
    }
    static func modelSettings(_ s: JSON) throws {
        guard ["default", "adaptive", "failover", "circuit-breaker", "round-robin"].contains(s["loadBalancerStrategy"].string),
              ["default", "disabled", "prefer_previous_channel"].contains(s["traceStickyMode"].string) else { throw ManagementError.invalidFields }
        let fields = ["channel_model": "channelModel", "channel_regex": "channelRegex", "model": "modelId", "regex": "regex", "channel_tags_model": "channelTagsModel", "channel_tags_regex": "channelTagsRegex"]
        for a in s["associations"].array {
            guard let field = fields[a["type"].string], !a[field].isNull, (0...100).contains(a["priority"].int) else { throw ManagementError.invalidFields }
            let v = a[field]
            if field.lowercased().contains("regex") { guard !v["pattern"].string.isEmpty else { throw ManagementError.invalidFields }; try regex(v["pattern"].string) }
            else { guard !v["modelId"].string.isEmpty else { throw ManagementError.invalidFields } }
            if field.hasPrefix("channel") && !field.hasPrefix("channelTags") { guard v["channelId"].int > 0 else { throw ManagementError.invalidFields } }
            if field.hasPrefix("channelTags") { guard !v["channelTags"].array.isEmpty else { throw ManagementError.invalidFields } }
            if a["when"]["enabled"].bool { try condition(a["when"]["condition"]) }
        }
    }
    static func condition(_ c: JSON, depth: Int = 1) throws {
        if c.isNull { throw ManagementError.invalidFields } // beta10 requires a condition when enabled.
        if c["type"].string == "group" {
            guard depth <= 3, ["", "and", "or"].contains(c["logic"].string), !c["conditions"].array.isEmpty else { throw ManagementError.invalidFields }
            for child in c["conditions"].array { try condition(child, depth: depth + 1) }
        } else {
            guard depth > 1, c["type"].string == "condition" else { throw ManagementError.invalidFields }
            let field = c["field"].string, op = c["operator"].string, value = c["value"]
            let eq = ["eq", "ne", "=", "==", "!="]
            switch field {
            case "prompt_tokens":
                guard ["lt", "lte", "gt", "gte", "<", "<=", ">", ">="].contains(op), case .number(let n) = value, n >= 0, n.rounded() == n else { throw ManagementError.invalidFields }
            case "stream", "has_image", "has_video", "has_document", "has_audio":
                guard eq.contains(op), case .bool = value else { throw ManagementError.invalidFields }
            case "request_format":
                guard eq.contains(op), !value.string.isEmpty else { throw ManagementError.invalidFields }
            case "daily_time":
                guard ["within", "not_within"].contains(op), value.string.range(of: #"^(?:[01][0-9]|2[0-3]):[0-5][0-9]-(?:[01][0-9]|2[0-3]):[0-5][0-9]$"#, options: .regularExpression) != nil else { throw ManagementError.invalidFields }
            default:
                guard field.hasPrefix("request_header."), field.count > "request_header.".count,
                      eq.contains(op) || ["<>", "contains", "not_contains", "start_with", "end_with"].contains(op), !value.string.isEmpty else { throw ManagementError.invalidFields }
                let header = String(field.dropFirst("request_header.".count)).lowercased()
                guard !["authorization", "proxy-authorization", "cookie", "set-cookie", "x-api-key", "api-key"].contains(header) else { throw ManagementError.invalidFields }
            }
        }
    }
}
