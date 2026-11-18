import Foundation

/// A value + label pair for a fixed select, the way the web console's `<SelectItem>`s are written.
struct Choice: Hashable, Sendable, Identifiable {
    let value: String
    let label: String
    var detail: String? = nil
    var id: String { value }
}

struct ProxyPreset: Decodable, Hashable, Sendable, Identifiable {
    let name: String?
    let url: String
    let username: String?
    let password: String?
    var id: String { url }
    var title: String { name?.nilIfBlank ?? url }
}

/// The selects of the web console's channel dialogs (`channels-action-dialog.tsx`,
/// `channel-api-key-strategy.tsx`, `channels-proxy-dialog.tsx`), with their zh-CN labels.
enum ChannelChoices {
    // MARK: Key strategy

    static let apiKeyStrategies: [Choice] = [
        Choice(value: "sticky", label: "粘性", detail: "同一 trace ID 固定同一 Key，无 trace 时随机"),
        Choice(value: "random", label: "随机", detail: "每次请求随机选一个 Key"),
        Choice(value: "round_robin", label: "轮询", detail: "每次请求计数"),
        Choice(value: "round_robin_success", label: "轮询（仅成功）", detail: "仅成功请求计数"),
        Choice(value: "priority", label: "优先级", detail: "始终使用第一个可用 Key"),
        Choice(value: "fixed", label: "固定", detail: "默认当前 Key，被禁用后切下一个"),
    ]
    static let defaultAPIKeyStrategy = "sticky"

    static func isRoundRobin(_ strategy: String) -> Bool {
        strategy == "round_robin" || strategy == "round_robin_success"
    }

    // MARK: Quota routing

    static let quotaRoutingModes: [Choice] = [
        Choice(value: "INHERIT", label: "继承全局默认值", detail: "未单独设置时，使用系统设置中的默认限额调度模式。"),
        Choice(value: "IGNORE_QUOTA", label: "忽略限额状态", detail: "不检查该渠道的限额状态，无论余量如何都参与调度。"),
        Choice(value: "REMOVE_ON_EXHAUSTED", label: "达到限额后摘除", detail: "额度耗尽后，将该渠道从候选渠道中摘除，直至限额窗口重置。"),
        Choice(value: "BACKPRESSURE", label: "基于用量和时长限流", detail: "按用量和剩余时长限流：临近耗尽的渠道不再承接新会话，仅保留已有会话。"),
    ]

    /// The INHERIT option names the system default when it is known (`INHERIT_WITH_MODE`).
    static func quotaRoutingLabel(_ value: String, systemDefault: String?) -> String {
        let label = quotaRoutingModes.first { $0.value == value }?.label ?? value
        guard value == "INHERIT", let systemDefault,
              let current = quotaRoutingModes.first(where: { $0.value == systemDefault }) else { return label }
        return "\(label)（当前：\(current.label)）"
    }

    static func quotaRoutingMode(from settings: ChannelSettings?) -> String {
        let raw = settings?.quotaRoutingMode ?? "INHERIT"
        return quotaRoutingModes.contains { $0.value == raw } ? raw : "INHERIT"
    }

    // MARK: Stream policy

    static let streamPolicies: [Choice] = [
        Choice(value: "unlimited", label: "没有限制（遵循请求）"),
        Choice(value: "require", label: "仅允许 stream"),
        Choice(value: "forbid", label: "禁止 stream"),
    ]

    static func streamPolicy(from policies: JSONValue?) -> String {
        let raw = policies?["stream"]?.stringValue ?? "unlimited"
        return streamPolicies.contains { $0.value == raw } ? raw : "unlimited"
    }

    /// `policies` input that changes only `stream` and keeps the stored auto-disable mode and rules.
    static func policiesInput(existing: JSONValue?, stream: String) -> JSONValue {
        var object: [String: JSONValue] = [:]
        if case .object(let stored)? = existing {
            for (key, value) in stored where value != .null { object[key] = value }
        }
        object["stream"] = .string(stream)
        return .object(object)
    }

    // MARK: Proxy

    static let proxyTypes: [Choice] = [
        Choice(value: "disabled", label: "禁用", detail: "渠道将直接连接，不使用任何代理"),
        Choice(value: "environment", label: "环境变量", detail: "使用 HTTP_PROXY、HTTPS_PROXY、NO_PROXY 里的代理设置"),
        Choice(value: "url", label: "自定义 URL", detail: "使用指定代理"),
    ]

    /// Stored proxy types can come back upper-cased; the web console writes them lower-case.
    static func proxyType(_ raw: String?) -> String {
        let value = (raw ?? "").lowercased()
        return proxyTypes.contains { $0.value == value } ? value : "disabled"
    }

    static func proxyInput(type: String, url: String, username: String, password: String, disableConnectionReuse: Bool) -> JSONValue {
        var object: [String: JSONValue] = ["type": .string(type)]
        if type == "url" {
            object["url"] = .string(url.trimmed)
            if let username = username.trimmed.nilIfBlank { object["username"] = .string(username) }
            if !password.isEmpty { object["password"] = .string(password) }
            if disableConnectionReuse { object["disableConnectionReuse"] = .bool(true) }
        }
        return .object(object)
    }

    // MARK: Settings written by the channel form

    /// The settings the channel dialog owns, as one object: the whole `settings` on create,
    /// the `updateChannelSettings` patch on edit.
    static func settingsFields(apiKeyStrategy: String, switchAfter: Int, quotaRoutingMode: String, proxy: JSONValue) -> [String: JSONValue] {
        var fields: [String: JSONValue] = [
            "apiKeyStrategy": .string(apiKeyStrategy),
            "quotaRoutingMode": .string(quotaRoutingMode),
            "proxy": proxy,
        ]
        if isRoundRobin(apiKeyStrategy) { fields["apiKeyRoundRobinSwitchAfter"] = .int(max(1, switchAfter)) }
        return fields
    }

    // MARK: Tags and quick-add models

    /// Tag suggestions: every tag in use (`allChannelTags`) plus the ones already on this channel, minus the chosen ones.
    static func tagSuggestions(all: [String], selected: [String], query: String) -> [String] {
        let pool = OptionSearch.merge(all, selected).filter { !selected.contains($0) }
        return OptionSearch.filter(pool, query: query)
    }

    /// Splits typed text into tags the way the web input does: on newline, comma or space.
    static func parseTags(_ text: String) -> [String] {
        text.split(whereSeparator: { $0 == "," || $0 == "，" || $0.isWhitespace }).map(String.init).filter { !$0.isEmpty }
    }

    static func addTags(_ text: String, to tags: [String]) -> [String] {
        OptionSearch.merge(tags, parseTags(text))
    }

    /// The provider's suggested models (`defaultModels` on the web) that the channel does not list yet.
    static func quickAddModels(type: String, existing: [String]) -> [String] {
        ChannelDefaultModels.models(for: type).filter { !existing.contains($0) }
    }
}
