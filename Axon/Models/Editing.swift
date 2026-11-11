import Foundation

// Editable shapes that mirror the AxonHub GraphQL output types *and* encode straight into the
// matching input types, so values the app does not edit (template ids, `when` conditions) survive
// a round trip unchanged.

// MARK: - Shared enums

enum LoadBalancerStrategy: String, CaseIterable, Identifiable, Sendable {
    case `default`
    case adaptive
    case failover
    case circuitBreaker = "circuit-breaker"
    case roundRobin = "round-robin"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .default: return "默认（继承）"
        case .adaptive: return "自适应"
        case .failover: return "故障转移"
        case .circuitBreaker: return "模型熔断"
        case .roundRobin: return "轮询"
        }
    }

    static func normalized(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty, LoadBalancerStrategy(rawValue: raw) != nil else { return "default" }
        return raw
    }
}

enum TraceStickyMode: String, CaseIterable, Identifiable, Sendable {
    case `default`
    case preferPreviousChannel = "prefer_previous_channel"
    case disabled

    var id: String { rawValue }
    var label: String {
        switch self {
        case .default: return "默认（继承）"
        case .preferPreviousChannel: return "优先最近选中渠道"
        case .disabled: return "禁用"
        }
    }

    static func normalized(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty, TraceStickyMode(rawValue: raw) != nil else { return "default" }
        return raw
    }
}

enum ChannelTagsMatchMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case any, all, none
    var id: String { rawValue }
    var label: String {
        switch self {
        case .any: return "包含任一标签"
        case .all: return "包含全部标签"
        case .none: return "不包含任一标签"
        }
    }
}

enum ModelType: String, CaseIterable, Identifiable, Sendable {
    case chat, embedding, rerank
    case imageGeneration = "image_generation"
    case videoGeneration = "video_generation"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .chat: return "对话"
        case .embedding: return "向量"
        case .rerank: return "重排"
        case .imageGeneration: return "图像生成"
        case .videoGeneration: return "视频生成"
        }
    }
}

enum Modality: String, CaseIterable, Identifiable, Sendable {
    case text, image, audio, video, pdf
    var id: String { rawValue }
    var label: String {
        switch self {
        case .text: return "文本"
        case .image: return "图像"
        case .audio: return "音频"
        case .video: return "视频"
        case .pdf: return "PDF"
        }
    }
}

enum ReasoningEffort: String, CaseIterable, Identifiable, Sendable {
    case none, minimal, low, medium, high, xhigh, max
    var id: String { rawValue }
}

// MARK: - Model settings / associations

struct ExcludeAssociation: Codable, Hashable, Sendable {
    var channelNamePattern: String?
    var channelIds: [Int]?
    var channelTags: [String]?

    var isEmpty: Bool {
        (channelNamePattern?.trimmed.isEmpty ?? true) && (channelIds ?? []).isEmpty && (channelTags ?? []).isEmpty
    }
}

struct ChannelModelAssociation: Codable, Hashable, Sendable { var channelId: Int; var modelId: String }
struct ChannelRegexAssociation: Codable, Hashable, Sendable { var channelId: Int; var pattern: String }
struct RegexAssociation: Codable, Hashable, Sendable { var pattern: String; var exclude: [ExcludeAssociation]? }
struct ModelIDAssociation: Codable, Hashable, Sendable { var modelId: String; var exclude: [ExcludeAssociation]? }
struct ChannelTagsModelAssociation: Codable, Hashable, Sendable { var channelTags: [String]; var modelId: String }
struct ChannelTagsRegexAssociation: Codable, Hashable, Sendable { var channelTags: [String]; var pattern: String }

enum AssociationKind: String, CaseIterable, Identifiable, Sendable {
    case channelModel = "channel_model"
    case channelRegex = "channel_regex"
    case regex
    case model
    case channelTagsModel = "channel_tags_model"
    case channelTagsRegex = "channel_tags_regex"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .channelModel: return "指定渠道 + 模型"
        case .channelRegex: return "指定渠道 + 正则"
        case .regex: return "所有渠道 + 正则"
        case .model: return "所有渠道 + 模型"
        case .channelTagsModel: return "渠道标签 + 模型"
        case .channelTagsRegex: return "渠道标签 + 正则"
        }
    }
    var usesChannel: Bool { self == .channelModel || self == .channelRegex }
    var usesTags: Bool { self == .channelTagsModel || self == .channelTagsRegex }
    var usesPattern: Bool { self == .channelRegex || self == .regex || self == .channelTagsRegex }
    var supportsExclude: Bool { self == .regex || self == .model }
}

struct ModelAssociation: Codable, Hashable, Sendable, Identifiable {
    var localID = UUID()
    var type: String
    var priority: Int?
    var disabled: Bool?
    /// Conditional routing (`when`) is kept verbatim; the app shows it but does not edit it.
    var when: JSONValue?
    var channelModel: ChannelModelAssociation?
    var channelRegex: ChannelRegexAssociation?
    var regex: RegexAssociation?
    var modelId: ModelIDAssociation?
    var channelTagsModel: ChannelTagsModelAssociation?
    var channelTagsRegex: ChannelTagsRegexAssociation?

    var id: UUID { localID }

    enum CodingKeys: String, CodingKey {
        case type, priority, disabled, when, channelModel, channelRegex, regex, modelId, channelTagsModel, channelTagsRegex
    }

    init(kind: AssociationKind, priority: Int = 0) {
        type = kind.rawValue
        self.priority = priority
        disabled = false
        setKind(kind)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decode(String.self, forKey: .type)
        priority = try c.decodeIfPresent(Int.self, forKey: .priority)
        disabled = try c.decodeIfPresent(Bool.self, forKey: .disabled)
        when = try c.decodeIfPresent(JSONValue.self, forKey: .when)
        if when == .null { when = nil }
        channelModel = try c.decodeIfPresent(ChannelModelAssociation.self, forKey: .channelModel)
        channelRegex = try c.decodeIfPresent(ChannelRegexAssociation.self, forKey: .channelRegex)
        regex = try c.decodeIfPresent(RegexAssociation.self, forKey: .regex)
        modelId = try c.decodeIfPresent(ModelIDAssociation.self, forKey: .modelId)
        channelTagsModel = try c.decodeIfPresent(ChannelTagsModelAssociation.self, forKey: .channelTagsModel)
        channelTagsRegex = try c.decodeIfPresent(ChannelTagsRegexAssociation.self, forKey: .channelTagsRegex)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(type, forKey: .type)
        try c.encodeIfPresent(priority, forKey: .priority)
        try c.encodeIfPresent(disabled, forKey: .disabled)
        try c.encodeIfPresent(when, forKey: .when)
        // Only the payload that matches `type` is sent.
        switch kind {
        case .channelModel?: try c.encodeIfPresent(channelModel, forKey: .channelModel)
        case .channelRegex?: try c.encodeIfPresent(channelRegex, forKey: .channelRegex)
        case .regex?: try c.encodeIfPresent(regex, forKey: .regex)
        case .model?: try c.encodeIfPresent(modelId, forKey: .modelId)
        case .channelTagsModel?: try c.encodeIfPresent(channelTagsModel, forKey: .channelTagsModel)
        case .channelTagsRegex?: try c.encodeIfPresent(channelTagsRegex, forKey: .channelTagsRegex)
        case nil:
            try c.encodeIfPresent(channelModel, forKey: .channelModel)
            try c.encodeIfPresent(channelRegex, forKey: .channelRegex)
            try c.encodeIfPresent(regex, forKey: .regex)
            try c.encodeIfPresent(modelId, forKey: .modelId)
            try c.encodeIfPresent(channelTagsModel, forKey: .channelTagsModel)
            try c.encodeIfPresent(channelTagsRegex, forKey: .channelTagsRegex)
        }
    }

    var kind: AssociationKind? { AssociationKind(rawValue: type) }

    /// Switches the association type, carrying over whatever values still make sense.
    mutating func setKind(_ kind: AssociationKind) {
        let channel = channelID ?? 0
        let model = modelValue
        let pattern = patternValue
        let tags = tagsValue
        let exclude = excludeValue
        type = kind.rawValue
        channelModel = nil; channelRegex = nil; regex = nil; modelId = nil; channelTagsModel = nil; channelTagsRegex = nil
        switch kind {
        case .channelModel: channelModel = .init(channelId: channel, modelId: model)
        case .channelRegex: channelRegex = .init(channelId: channel, pattern: pattern)
        case .regex: regex = .init(pattern: pattern, exclude: exclude)
        case .model: modelId = .init(modelId: model, exclude: exclude)
        case .channelTagsModel: channelTagsModel = .init(channelTags: tags, modelId: model)
        case .channelTagsRegex: channelTagsRegex = .init(channelTags: tags, pattern: pattern)
        }
    }

    /// Rewrites one value of the current association type, keeping the others.
    mutating func update(channel: Int? = nil, model: String? = nil, pattern: String? = nil,
                         tags: [String]? = nil) {
        let c = channel ?? channelID ?? 0
        let m = model ?? modelValue
        let p = pattern ?? patternValue
        let t = tags ?? tagsValue
        let e = excludeValue
        switch kind {
        case .channelModel?: channelModel = .init(channelId: c, modelId: m)
        case .channelRegex?: channelRegex = .init(channelId: c, pattern: p)
        case .regex?: regex = .init(pattern: p, exclude: e)
        case .model?: modelId = .init(modelId: m, exclude: e)
        case .channelTagsModel?: channelTagsModel = .init(channelTags: t, modelId: m)
        case .channelTagsRegex?: channelTagsRegex = .init(channelTags: t, pattern: p)
        case nil: break
        }
    }

    var channelID: Int? {
        get { channelModel?.channelId ?? channelRegex?.channelId }
        set {
            let v = newValue ?? 0
            if channelModel != nil { channelModel?.channelId = v }
            if channelRegex != nil { channelRegex?.channelId = v }
        }
    }

    var modelValue: String {
        get { channelModel?.modelId ?? modelId?.modelId ?? channelTagsModel?.modelId ?? "" }
        set {
            if channelModel != nil { channelModel?.modelId = newValue }
            if modelId != nil { modelId?.modelId = newValue }
            if channelTagsModel != nil { channelTagsModel?.modelId = newValue }
        }
    }

    var patternValue: String {
        get { channelRegex?.pattern ?? regex?.pattern ?? channelTagsRegex?.pattern ?? "" }
        set {
            if channelRegex != nil { channelRegex?.pattern = newValue }
            if regex != nil { regex?.pattern = newValue }
            if channelTagsRegex != nil { channelTagsRegex?.pattern = newValue }
        }
    }

    var tagsValue: [String] {
        get { channelTagsModel?.channelTags ?? channelTagsRegex?.channelTags ?? [] }
        set {
            if channelTagsModel != nil { channelTagsModel?.channelTags = newValue }
            if channelTagsRegex != nil { channelTagsRegex?.channelTags = newValue }
        }
    }

    var excludeValue: [ExcludeAssociation]? {
        get { regex?.exclude ?? modelId?.exclude }
        set {
            let cleaned = newValue?.filter { !$0.isEmpty }
            let v = (cleaned?.isEmpty ?? true) ? nil : cleaned
            if regex != nil { regex?.exclude = v }
            if modelId != nil { modelId?.exclude = v }
        }
    }

    var isEnabled: Bool { !(disabled ?? false) }
    var hasCondition: Bool {
        if case .object(let o)? = when { return o["enabled"]?.boolValue ?? false }
        return false
    }

    /// Returns a problem description, or nil when the association can be saved.
    var validationError: String? {
        guard let kind else { return nil }
        if kind.usesChannel && (channelID ?? 0) <= 0 { return "请选择渠道" }
        if kind.usesTags && tagsValue.isEmpty { return "请填写至少一个渠道标签" }
        if kind.usesPattern {
            let p = patternValue.trimmed
            if p.isEmpty { return "请填写正则表达式" }
            if (try? NSRegularExpression(pattern: p)) == nil { return "正则表达式无效" }
        } else if modelValue.trimmed.isEmpty {
            return "请填写模型 ID"
        }
        return nil
    }

    /// One-line description for lists.
    func summary(channelName: (Int) -> String?) -> String {
        guard let kind else { return type }
        var parts: [String] = []
        if kind.usesChannel, let id = channelID { parts.append(channelName(id) ?? "渠道 #\(id)") }
        if kind.usesTags { parts.append(tagsValue.map { "#" + $0 }.joined(separator: " ")) }
        if kind == .regex || kind == .model { parts.append("所有渠道") }
        parts.append(kind.usesPattern ? "/\(patternValue)/" : modelValue)
        return parts.joined(separator: " · ")
    }

    static func == (lhs: ModelAssociation, rhs: ModelAssociation) -> Bool {
        lhs.localID == rhs.localID && lhs.type == rhs.type && lhs.priority == rhs.priority && lhs.disabled == rhs.disabled
            && lhs.when == rhs.when && lhs.channelModel == rhs.channelModel && lhs.channelRegex == rhs.channelRegex
            && lhs.regex == rhs.regex && lhs.modelId == rhs.modelId && lhs.channelTagsModel == rhs.channelTagsModel
            && lhs.channelTagsRegex == rhs.channelTagsRegex
    }

    func hash(into hasher: inout Hasher) { hasher.combine(localID) }
}

struct ModelSettings: Codable, Hashable, Sendable {
    var disableDeveloperSettingsInheritance: Bool?
    var associations: [ModelAssociation]
    var loadBalancerStrategy: String?
    var traceStickyMode: String?

    static let empty = ModelSettings(disableDeveloperSettingsInheritance: false, associations: [],
                                     loadBalancerStrategy: "default", traceStickyMode: "default")
}

struct ModelChannelConnection: Decodable, Hashable, Sendable {
    struct ChannelRef: Decodable, Hashable, Sendable { let id: String; let name: String; let type: String? }
    let channel: ChannelRef
    let models: [ChannelModelEntry]
    let priority: Int
}

// MARK: - Model draft

/// Everything the model form edits, with conversion to `CreateModelInput` / `UpdateModelInput`.
struct ModelDraft: Hashable, Sendable {
    var developer = ""
    var modelID = ""
    var name = ""
    var type: String = ModelType.chat.rawValue
    var icon = ""
    var group = ""
    var remark = ""
    var toolCall = false
    var temperature = true
    var vision = false
    var reasoningSupported = false
    var reasoningDefault = false
    var reasoningEfforts: [String] = []
    var inputModalities: [String] = ["text"]
    var outputModalities: [String] = ["text"]
    var costInput = ""
    var costOutput = ""
    var costCacheRead = ""
    var costCacheWrite = ""
    var contextLimit = ""
    var outputLimit = ""
    var knowledge = ""
    var releaseDate = ""
    var lastUpdated = ""
    var loadBalancerStrategy = "default"
    var traceStickyMode = "default"
    /// Kept from the original model so an edit never drops associations.
    var settings: ModelSettings = .empty

    init() {}

    init(model: AIModel) {
        developer = model.developer
        modelID = model.modelID
        name = model.name
        type = model.type
        icon = model.icon ?? ""
        group = model.group ?? ""
        remark = model.remark ?? ""
        let card = model.modelCard
        toolCall = card?.toolCall ?? false
        temperature = card?.temperature ?? false
        vision = card?.vision ?? false
        reasoningSupported = card?.reasoning?.supported ?? false
        reasoningDefault = card?.reasoning?.default ?? false
        reasoningEfforts = card?.reasoningEfforts ?? []
        inputModalities = card?.modalities?.input ?? []
        outputModalities = card?.modalities?.output ?? []
        costInput = Self.text(card?.cost?.input)
        costOutput = Self.text(card?.cost?.output)
        costCacheRead = Self.text(card?.cost?.cacheRead)
        costCacheWrite = Self.text(card?.cost?.cacheWrite)
        contextLimit = Self.text(card?.limit?.context)
        outputLimit = Self.text(card?.limit?.output)
        knowledge = card?.knowledge ?? ""
        releaseDate = card?.releaseDate ?? ""
        lastUpdated = card?.lastUpdated ?? ""
        settings = model.settings ?? .empty
        loadBalancerStrategy = LoadBalancerStrategy.normalized(settings.loadBalancerStrategy)
        traceStickyMode = TraceStickyMode.normalized(settings.traceStickyMode)
    }

    private static func text(_ v: Double?) -> String {
        guard let v, v != 0 else { return "" }
        return v == v.rounded() && abs(v) < 1e15 ? String(Int64(v)) : String(v)
    }

    private static func text(_ v: Int?) -> String {
        guard let v, v != 0 else { return "" }
        return String(v)
    }

    static func number(_ s: String) -> Double? { Double(s.trimmed.replacingOccurrences(of: ",", with: "")) }
    static func integer(_ s: String) -> Int? {
        let t = s.trimmed.replacingOccurrences(of: ",", with: "").lowercased()
        if let v = Int(t) { return v }
        // Accept shorthands such as 128k / 1m for context windows.
        if let last = t.last, let base = Double(t.dropLast()) {
            switch last {
            case "k": return Int(base * 1_000)
            case "m": return Int(base * 1_000_000)
            default: return nil
            }
        }
        return nil
    }

    var validationError: String? {
        if developer.trimmed.isEmpty { return "请填写厂商" }
        if modelID.trimmed.isEmpty { return "请填写模型 ID" }
        for (label, value) in [("输入价格", costInput), ("输出价格", costOutput), ("缓存读取价格", costCacheRead), ("缓存写入价格", costCacheWrite)] {
            if !value.trimmed.isEmpty, Self.number(value) == nil { return "\(label)不是有效数字" }
        }
        for (label, value) in [("上下文长度", contextLimit), ("最大输出", outputLimit)] {
            if !value.trimmed.isEmpty, Self.integer(value) == nil { return "\(label)不是有效整数" }
        }
        return nil
    }

    var modelCardInput: JSONValue {
        var card: [String: JSONValue] = [
            "toolCall": .bool(toolCall),
            "temperature": .bool(temperature),
            "vision": .bool(vision),
            "reasoning": .object(["supported": .bool(reasoningSupported), "default": .bool(reasoningSupported && reasoningDefault)]),
            "reasoningEfforts": .array(reasoningSupported ? reasoningEfforts.map { .string($0) } : []),
            "modalities": .object([
                "input": .array(inputModalities.map { .string($0) }),
                "output": .array(outputModalities.map { .string($0) }),
            ]),
            "cost": .object([
                "input": .number(Self.number(costInput) ?? 0),
                "output": .number(Self.number(costOutput) ?? 0),
                "cacheRead": .number(Self.number(costCacheRead) ?? 0),
                "cacheWrite": .number(Self.number(costCacheWrite) ?? 0),
            ]),
            "limit": .object([
                "context": .number(Double(Self.integer(contextLimit) ?? 0)),
                "output": .number(Double(Self.integer(outputLimit) ?? 0)),
            ]),
        ]
        card["knowledge"] = .string(knowledge.trimmed)
        card["releaseDate"] = .string(releaseDate.trimmed)
        card["lastUpdated"] = .string(lastUpdated.trimmed)
        return .object(card)
    }

    var settingsInput: JSONValue {
        var s = settings
        s.loadBalancerStrategy = loadBalancerStrategy
        s.traceStickyMode = traceStickyMode
        return JSONValue(encoding: s) ?? .object(["associations": .array([])])
    }

    private var common: [String: JSONValue] {
        [
            "developer": .string(developer.trimmed),
            "modelID": .string(modelID.trimmed),
            "type": .string(type),
            "name": .string(name.trimmed.isEmpty ? modelID.trimmed : name.trimmed),
            "icon": .string(icon.trimmed),
            "group": .string(group.trimmed.isEmpty ? developer.trimmed : group.trimmed),
            "modelCard": modelCardInput,
            "settings": settingsInput,
        ]
    }

    var createInput: [String: JSONValue] {
        var input = common
        if let r = remark.nilIfBlank { input["remark"] = .string(r) }
        return input
    }

    var updateInput: [String: JSONValue] {
        var input = common
        if let r = remark.nilIfBlank { input["remark"] = .string(r) } else { input["clearRemark"] = .bool(true) }
        return input
    }
}

// MARK: - API key profiles

struct APIKeyQuotaPastDuration: Codable, Hashable, Sendable { var value: Int; var unit: String }
struct APIKeyQuotaCalendarDuration: Codable, Hashable, Sendable { var unit: String }

struct APIKeyQuotaPeriod: Codable, Hashable, Sendable {
    var type: String
    var pastDuration: APIKeyQuotaPastDuration?
    var calendarDuration: APIKeyQuotaCalendarDuration?

    static let allTime = APIKeyQuotaPeriod(type: "all_time")

    var label: String {
        switch type {
        case "past_duration":
            guard let p = pastDuration else { return "过去一段时间" }
            return "过去 \(p.value) \(Self.unitLabel(p.unit))"
        case "calendar_duration":
            return calendarDuration?.unit == "month" ? "每自然月" : "每自然日"
        default: return "总量"
        }
    }

    static func unitLabel(_ unit: String) -> String {
        switch unit {
        case "minute": return "分钟"
        case "hour": return "小时"
        case "day": return "天"
        case "month": return "月"
        default: return unit
        }
    }
}

struct APIKeyQuota: Codable, Hashable, Sendable {
    var requests: Int?
    var totalTokens: Int?
    var cost: Double?
    var period: APIKeyQuotaPeriod

    var isEmpty: Bool { requests == nil && totalTokens == nil && cost == nil }
}

struct APIKeyProfile: Codable, Hashable, Sendable, Identifiable {
    var localID = UUID()
    var name: String
    var templateID: Int?
    var templateName: String?
    var modelMappings: [ModelMapping]?
    var channelIDs: [Int]?
    var channelTags: [String]?
    var channelTagsMatchMode: ChannelTagsMatchMode?
    var modelIDs: [String]?
    var quota: APIKeyQuota?
    var loadBalanceStrategy: String?
    var traceStickyMode: String?

    var id: UUID { localID }

    enum CodingKeys: String, CodingKey {
        case name, templateID, templateName, modelMappings, channelIDs, channelTags, channelTagsMatchMode, modelIDs, quota,
             loadBalanceStrategy, traceStickyMode
    }

    init(name: String) { self.name = name }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        templateID = try c.decodeIfPresent(Int.self, forKey: .templateID)
        templateName = try c.decodeIfPresent(String.self, forKey: .templateName)
        modelMappings = try c.decodeIfPresent([ModelMapping].self, forKey: .modelMappings)
        channelIDs = try c.decodeIfPresent([Int].self, forKey: .channelIDs)
        channelTags = try c.decodeIfPresent([String].self, forKey: .channelTags)
        channelTagsMatchMode = try c.decodeIfPresent(ChannelTagsMatchMode.self, forKey: .channelTagsMatchMode)
        modelIDs = try c.decodeIfPresent([String].self, forKey: .modelIDs)
        quota = try c.decodeIfPresent(APIKeyQuota.self, forKey: .quota)
        loadBalanceStrategy = try c.decodeIfPresent(String.self, forKey: .loadBalanceStrategy)
        traceStickyMode = try c.decodeIfPresent(String.self, forKey: .traceStickyMode)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name.trimmed, forKey: .name)
        try c.encodeIfPresent(templateID, forKey: .templateID)
        try c.encodeIfPresent(templateName, forKey: .templateName)
        try c.encode(modelMappings ?? [], forKey: .modelMappings)
        try c.encode(channelIDs ?? [], forKey: .channelIDs)
        try c.encode(channelTags ?? [], forKey: .channelTags)
        if !(channelTags ?? []).isEmpty { try c.encode(channelTagsMatchMode ?? .any, forKey: .channelTagsMatchMode) }
        try c.encode(modelIDs ?? [], forKey: .modelIDs)
        if let quota, !quota.isEmpty { try c.encode(quota, forKey: .quota) }
        let lb = LoadBalancerStrategy.normalized(loadBalanceStrategy)
        if lb != "default" { try c.encode(lb, forKey: .loadBalanceStrategy) }
        let ts = TraceStickyMode.normalized(traceStickyMode)
        if ts != "default" { try c.encode(ts, forKey: .traceStickyMode) }
    }

    func hash(into hasher: inout Hasher) { hasher.combine(localID) }

    /// Short description of what the profile restricts.
    var summary: String {
        var parts: [String] = []
        if let m = modelMappings, !m.isEmpty { parts.append("\(m.count) 条映射") }
        if let ids = modelIDs, !ids.isEmpty { parts.append("\(ids.count) 个模型") }
        if let ch = channelIDs, !ch.isEmpty { parts.append("\(ch.count) 个渠道") }
        if let tags = channelTags, !tags.isEmpty { parts.append("\(tags.count) 个标签") }
        if let q = quota, !q.isEmpty { parts.append("配额·\(q.period.label)") }
        return parts.isEmpty ? "不限制" : parts.joined(separator: " · ")
    }
}

struct APIKeyProfileTemplate: Decodable, Hashable, Sendable, Identifiable {
    let id: String
    let name: String
    let description: String?
    let projectID: String?
    let linkedProfilesCount: Int?
    let profile: APIKeyProfile?
}

struct APIKeyProfiles: Codable, Hashable, Sendable {
    var activeProfile: String
    var profiles: [APIKeyProfile]?
}

/// Validates and builds `UpdateAPIKeyProfilesInput`.
enum ProfilesEditor {
    static func validationError(active: String, profiles: [APIKeyProfile]) -> String? {
        if profiles.isEmpty { return "至少需要一个配置" }
        var seen = Set<String>()
        for p in profiles {
            let name = p.name.trimmed
            if name.isEmpty { return "配置名称不能为空" }
            if !seen.insert(name.lowercased()).inserted { return "配置名称“\(name)”重复" }
            for m in p.modelMappings ?? [] where m.from.trimmed.isEmpty || m.to.trimmed.isEmpty {
                return "“\(name)”里有未填完的模型映射"
            }
            if let q = p.quota, q.period.type == "past_duration", (q.period.pastDuration?.value ?? 0) <= 0 {
                return "“\(name)”的配额时长必须大于 0"
            }
        }
        if !profiles.contains(where: { $0.name.trimmed == active.trimmed }) { return "请选择一个生效的配置" }
        return nil
    }

    static func input(active: String, profiles: [APIKeyProfile]) -> JSONValue {
        let encoded = profiles.compactMap { JSONValue(encoding: $0) }
        return .object(["activeProfile": .string(active.trimmed), "profiles": .array(encoded)])
    }
}

struct APIKeyQuotaUsageInfo: Decodable, Hashable, Sendable {
    struct Window: Decodable, Hashable, Sendable { let start: Date?; let end: Date? }
    struct Usage: Decodable, Hashable, Sendable { let requestCount: Int; let totalTokens: Int; let totalCost: Double }
    let profileName: String
    let quota: APIKeyQuota
    let window: Window
    let usage: Usage
}

/// Builds `UpdateAPIKeyInput` the way the web console does (scopes only for service accounts).
enum APIKeyEditor {
    static func updateInput(name: String, type: String, scopes: [String], allowedIps: [String]) -> [String: JSONValue] {
        var input: [String: JSONValue] = ["name": .string(name.trimmed)]
        if type == "service_account" { input["scopes"] = .array(scopes.map { .string($0) }) }
        let ips = allowedIps.map(\.trimmed).filter { !$0.isEmpty }
        if ips.isEmpty { input["clearAllowedIps"] = .bool(true) } else { input["allowedIps"] = .array(ips.map { .string($0) }) }
        return input
    }

    static func createInput(name: String, type: String, scopes: [String], allowedIps: [String]) -> [String: JSONValue] {
        var input: [String: JSONValue] = ["name": .string(name.trimmed), "type": .string(type)]
        if type == "service_account" { input["scopes"] = .array(scopes.map { .string($0) }) }
        let ips = allowedIps.map(\.trimmed).filter { !$0.isEmpty }
        if !ips.isEmpty { input["allowedIps"] = .array(ips.map { .string($0) }) }
        return input
    }
}

/// A scope as reported by `allScopes`.
struct ScopeInfo: Decodable, Hashable, Sendable, Identifiable {
    let scope: String
    let description: String
    let levels: [String]
    var id: String { scope }
}

/// Minimal channel info for pickers.
struct ChannelOption: Decodable, Hashable, Sendable, Identifiable {
    let id: String
    let name: String
    let type: String
    let status: String
    let tags: [String]?
    let supportedModels: [String]?

    var numericID: Int? { GUID.numeric(id) }

    static func allTags(_ channels: [ChannelOption]) -> [String] {
        Array(Set(channels.flatMap { $0.tags ?? [] })).sorted()
    }
}
