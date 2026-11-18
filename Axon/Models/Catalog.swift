import Foundation

// MARK: - Option search

/// Search helper shared by every picker: case-insensitive "contains" match,
/// exact match first, then prefix matches, then the rest in their original order.
enum OptionSearch {
    static func filter(_ options: [String], query: String, limit: Int? = nil) -> [String] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var seen = Set<String>()
        let unique = options.filter { !$0.isEmpty && seen.insert($0).inserted }
        guard !q.isEmpty else { return limit.map { Array(unique.prefix($0)) } ?? unique }
        var exact: [String] = [], prefix: [String] = [], rest: [String] = []
        for option in unique {
            let lower = option.lowercased()
            if lower == q { exact.append(option) }
            else if lower.hasPrefix(q) { prefix.append(option) }
            else if lower.contains(q) { rest.append(option) }
        }
        let result = exact + prefix + rest
        return limit.map { Array(result.prefix($0)) } ?? result
    }

    /// True when the typed text is a value the user may add on top of the known options.
    static func canAddCustom(_ query: String, to options: [String]) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return !q.isEmpty && !options.contains(q)
    }

    /// Merges option lists, keeping the first occurrence of each value.
    static func merge(_ lists: [String]...) -> [String] {
        var seen = Set<String>()
        return lists.flatMap { $0 }.filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}

// MARK: - Developers (same list and icons as the web console)

enum DeveloperCatalog {
    /// `DEVELOPER_IDS` in frontend/src/features/models/data/constants.ts.
    static let ids = [
        "deepseek", "alibaba", "tencent", "zai", "openai", "moonshot", "anthropic", "google", "minimax",
        "kwaipilot", "xiaomi", "longcat", "mistral", "nvidia", "xai", "bytedance", "stepfun", "meta", "ibm",
        "poolside", "inclusionai", "thinkingmachines",
    ]

    /// `DEVELOPER_ICONS` in the same file; developers without an entry use their id.
    static let icons: [String: String] = [
        "moonshot": "Moonshot", "xai": "XAI", "zai": "ZAI", "deepseek": "DeepSeek", "google": "Gemini",
        "anthropic": "Claude", "openai": "OpenAI", "minimax": "Minimax", "kwaipilot": "KwaiKAT", "alibaba": "Qwen",
        "tencent": "Hunyuan", "xiaomi": "XiaomiMiMo", "longcat": "LongCat", "mistral": "Mistral", "nvidia": "Nvidia",
        "bytedance": "Doubao", "stepfun": "Stepfun", "meta": "Meta", "ibm": "IBM",
    ]

    /// `models.developers.*` in the zh-CN locale.
    static let labels: [String: String] = [
        "alibaba": "阿里巴巴", "anthropic": "Anthropic", "tencent": "腾讯", "deepseek": "深度求索", "google": "Google",
        "kwaipilot": "快手", "meta": "Meta", "minimax": "稀宇科技", "mistral": "Mistral", "moonshot": "月之暗面",
        "openai": "OpenAI", "stepfun": "阶跃星辰", "xai": "xAI", "xiaomi": "小米", "longcat": "LongCat",
        "nvidia": "NVIDIA", "bytedance": "字节跳动", "zai": "智谱", "ibm": "IBM", "inclusionai": "Inclusion AI",
        "poolside": "Poolside", "thinkingmachines": "Thinking Machines",
    ]

    static func label(_ id: String) -> String { labels[id] ?? id }
    static func icon(for id: String) -> String { icons[id] ?? id }
}

// MARK: - Model icons

/// Icon ids the web console offers: @lobehub/icons entries in the `provider` and `model` groups
/// (the version pinned in frontend/pnpm-lock.yaml).
enum ModelIconCatalog {
    static let all: [String] = [
        "Ace", "AgentVoice", "Ai2", "Ai21", "Ai302", "Ai360", "AiHubMix", "AiMass", "AionLabs", "AiStudio",
        "AkashChat", "AlephAlpha", "Alibaba", "AlibabaCloud", "AntGroup", "Anthropic", "Anyscale", "Apertis",
        "Apple", "Arcee", "AssemblyAI", "AtlasCloud", "Aws", "Aya", "Azure", "AzureAI", "BAAI", "Baichuan",
        "Baidu", "BaiduCloud", "Bailian", "Baseten", "Bedrock", "Bfl", "Bilibili", "BilibiliIndex", "BriaAI",
        "BurnCloud", "ByteDance", "CentML", "Cerebras", "ChatGLM", "Civitai", "Claude", "Cloudflare",
        "CodeGeeX", "Codex", "CogVideo", "CogView", "Cohere", "CometAPI", "CommandA", "Crusoe", "Dalle",
        "Dbrx", "DeepCogito", "DeepInfra", "DeepMind", "DeepSeek", "Dolphin", "Doubao", "ElevenLabs",
        "EssentialAI", "Exa", "Fal", "Featherless", "Fireworks", "FishAudio", "Flux", "Friendli", "Gemini",
        "Gemma", "GiteeAI", "Github", "GLMV", "Google", "GoogleCloud", "Grok", "Groq", "Higress", "Huawei",
        "HuaweiCloud", "HuggingFace", "Hunyuan", "Hyperbolic", "IBM", "IFlyTekCloud", "Inception",
        "Inference", "Infermatic", "Infinigence", "Inflection", "InternLM", "Jina", "Kluster", "Kolors",
        "KwaiKAT", "Kwaipilot", "Lambda", "LeptonAI", "LG", "Liquid", "LLaVA", "LlmApi", "LmStudio",
        "LobeHub", "LongCat", "Magic", "Menlo", "Meshy", "Meta", "Microsoft", "Minimax", "Mistral",
        "ModelScope", "Moonshot", "Morph", "NanoBanana", "Nebius", "NewAPI", "NousResearch", "Nova", "Novita",
        "NPLCloud", "Nvidia", "Ollama", "OpenAI", "OpenChat", "OpenRouter", "PaLM", "Parasail", "Perplexity",
        "Phind", "PPIO", "PrunaAI", "Qiniu", "Qwen", "Relace", "Replicate", "Reve", "Rwkv", "SambaNova",
        "Search1API", "SearchApi", "SenseNova", "SiliconCloud", "Skywork", "Snowflake", "SophNet", "Sora",
        "Spark", "SpeedAI", "Stability", "StateCloud", "Stepfun", "Straico", "StreamLake", "SubModel",
        "Targon", "Tencent", "TencentCloud", "TII", "Together", "Upstage", "Vercel", "VertexAI", "Vllm",
        "Volcengine", "Voyage", "Wenxin", "WorkersAI", "XAI", "XiaomiMiMo", "Xinference", "Xpay", "Xuanyuan",
        "Yandex", "Yi", "ZenMux", "ZeroOne", "Zhipu",    ]
}

// MARK: - Providers catalog (`providersCatalog` query)

struct CatalogProvider: Decodable, Hashable, Sendable, Identifiable {
    var id: String
    var name: String?
    var displayName: String?
    var models: [CatalogModel]

    enum CodingKeys: String, CodingKey { case id, name, displayName = "display_name", models }

    init(id: String, name: String? = nil, displayName: String? = nil, models: [CatalogModel]) {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.models = models
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? ""
        name = try? c.decode(String.self, forKey: .name)
        displayName = try? c.decode(String.self, forKey: .displayName)
        models = (try? c.decode(LossyArray<CatalogModel>.self, forKey: .models).items) ?? []
    }
}

struct CatalogModel: Decodable, Hashable, Sendable, Identifiable {
    struct Reasoning: Decodable, Hashable, Sendable { var supported: Bool?; var `default`: Bool? }
    struct ReasoningOption: Decodable, Hashable, Sendable { var type: String?; var values: [String]? }
    struct Modalities: Decodable, Hashable, Sendable { var input: [String]?; var output: [String]? }
    struct Cost: Decodable, Hashable, Sendable {
        var input: Double?; var output: Double?; var cacheRead: Double?; var cacheWrite: Double?
        enum CodingKeys: String, CodingKey { case input, output, cacheRead = "cache_read", cacheWrite = "cache_write" }
    }
    struct Limit: Decodable, Hashable, Sendable { var context: Double?; var output: Double? }

    var id: String
    var name: String?
    var displayName: String?
    var family: String?
    var type: String?
    var reasoning: Reasoning?
    var reasoningOptions: [ReasoningOption]?
    var toolCall: Bool?
    var temperature: Bool?
    var vision: Bool?
    var modalities: Modalities?
    var cost: Cost?
    var limit: Limit?
    var knowledge: String?
    var releaseDate: String?
    var lastUpdated: String?

    enum CodingKeys: String, CodingKey {
        case id, name, family, type, reasoning, temperature, vision, modalities, cost, limit, knowledge
        case displayName = "display_name", reasoningOptions = "reasoning_options", toolCall = "tool_call"
        case releaseDate = "release_date", lastUpdated = "last_updated"
    }

    init(id: String, name: String? = nil, displayName: String? = nil, family: String? = nil, type: String? = nil) {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.family = family
        self.type = type
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try? c.decode(String.self, forKey: .name)
        displayName = try? c.decode(String.self, forKey: .displayName)
        family = try? c.decode(String.self, forKey: .family)
        type = try? c.decode(String.self, forKey: .type)
        reasoning = try? c.decode(Reasoning.self, forKey: .reasoning)
        reasoningOptions = try? c.decode([ReasoningOption].self, forKey: .reasoningOptions)
        toolCall = try? c.decode(Bool.self, forKey: .toolCall)
        temperature = try? c.decode(Bool.self, forKey: .temperature)
        vision = try? c.decode(Bool.self, forKey: .vision)
        modalities = try? c.decode(Modalities.self, forKey: .modalities)
        cost = try? c.decode(Cost.self, forKey: .cost)
        limit = try? c.decode(Limit.self, forKey: .limit)
        knowledge = try? c.decode(String.self, forKey: .knowledge)
        releaseDate = try? c.decode(String.self, forKey: .releaseDate)
        lastUpdated = try? c.decode(String.self, forKey: .lastUpdated)
    }

    /// `resolveVision` in providers.schema.ts.
    var resolvedVision: Bool { vision ?? (modalities?.input?.contains("image") ?? false) }

    /// `deriveReasoningEfforts` in reasoning-efforts.ts: only an `effort` option lists levels.
    var derivedReasoningEfforts: [String] {
        guard let values = reasoningOptions?.first(where: { $0.type == "effort" })?.values, !values.isEmpty else { return [] }
        return ProvidersCatalog.reasoningEfforts.filter { values.contains($0) }
    }

    /// `isSuggestedModel` in model-suggestions.ts: hides superseded MiniMax text models.
    var isSuggested: Bool { ProvidersCatalog.isSuggestedModel(id) }
}

struct ProvidersCatalog: Hashable, Sendable {
    var providers: [CatalogProvider]
    var source: String?

    static let empty = ProvidersCatalog(providers: [], source: nil)
    static let reasoningEfforts = ["none", "minimal", "low", "medium", "high", "xhigh", "max"]

    /// Decodes the `data` field of `providersCatalog`: `{ "providers": { "<id>": { ..., "models": [...] } } }`.
    static func decode(_ data: JSONValue, source: String? = nil) -> ProvidersCatalog {
        var value = data
        if case .string(let text) = data, let raw = text.data(using: .utf8),
           let parsed = try? JSONDecoder().decode(JSONValue.self, from: raw) {
            value = parsed
        }
        guard case .object(let map)? = value["providers"] else { return .empty }
        var providers: [CatalogProvider] = []
        for (key, entry) in map {
            guard let raw = try? JSONEncoder().encode(entry),
                  var provider = try? JSONDecoder().decode(CatalogProvider.self, from: raw) else { continue }
            if provider.id.isEmpty { provider.id = key }
            providers.append(provider)
        }
        return ProvidersCatalog(providers: providers.sorted { $0.id < $1.id }, source: source)
    }

    func provider(_ id: String) -> CatalogProvider? { providers.first { $0.id == id } }

    /// Model id suggestions for a developer, as the web console's model-id autocomplete shows them.
    func modelIDs(for developer: String) -> [String] {
        provider(developer)?.models.filter(\.isSuggested).map(\.id) ?? []
    }

    func model(developer: String, id: String) -> CatalogModel? {
        provider(developer)?.models.first { $0.id == id }
    }

    /// Developer ids offered in the developer picker: the fixed list first, then any other catalog provider.
    var developerIDs: [String] {
        OptionSearch.merge(DeveloperCatalog.ids, providers.map(\.id))
    }

    static func isSuggestedModel(_ modelID: String) -> Bool {
        let id = modelID.lowercased()
        let name = id.split(separator: "/").last.map(String.init) ?? id
        let isMiniMaxText = name.range(of: #"^(minimax[-_](m\d|text|vl-\d)|abab\d)"#, options: .regularExpression) != nil
        guard isMiniMaxText else { return true }
        return ["minimax-m3", "minimax-m3.1-flash", "minimax-m3.1-flash:free", "minimax-m3.1-flash-free"].contains(name)
    }
}

/// Decodes an array, skipping elements that fail to decode.
struct LossyArray<Element: Decodable>: Decodable {
    var items: [Element]
    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var items: [Element] = []
        while !container.isAtEnd {
            if let item = try? container.decode(Element.self) { items.append(item) } else { _ = try? container.decode(JSONValue.self) }
        }
        self.items = items
    }
}

// MARK: - Model draft auto-fill (models-action-dialog.tsx)

extension ModelDraft {
    /// Choosing a developer while creating: set the developer's icon and clear the model fields.
    mutating func selectDeveloper(_ id: String, isEditing: Bool) {
        developer = id
        guard !isEditing else { return }
        icon = DeveloperCatalog.icon(for: id)
        modelID = ""
        name = ""
        group = ""
    }

    /// Choosing a model id while creating fills name, group, type and the model card from the catalog,
    /// as `handleModelIdChange` does on the web.
    mutating func selectModelID(_ id: String, catalog: ProvidersCatalog, isEditing: Bool) {
        modelID = id
        guard !isEditing, let model = catalog.model(developer: developer, id: id) else { return }
        name = model.displayName ?? model.name ?? ""
        group = model.family ?? developer
        if let raw = model.type?.replacingOccurrences(of: "-", with: "_"), ModelType(rawValue: raw) != nil {
            type = raw
        }
        reasoningSupported = model.reasoning?.supported ?? false
        reasoningDefault = model.reasoning?.default ?? false
        reasoningEfforts = model.derivedReasoningEfforts
        toolCall = model.toolCall ?? false
        temperature = model.temperature ?? false
        inputModalities = model.modalities?.input ?? []
        outputModalities = model.modalities?.output ?? []
        vision = model.resolvedVision
        costInput = Self.catalogText(model.cost?.input ?? 0)
        costOutput = Self.catalogText(model.cost?.output ?? 0)
        costCacheRead = Self.catalogText(model.cost?.cacheRead)
        costCacheWrite = Self.catalogText(model.cost?.cacheWrite)
        contextLimit = Self.catalogText(model.limit?.context ?? 0)
        outputLimit = Self.catalogText(model.limit?.output ?? 0)
        knowledge = model.knowledge ?? ""
        releaseDate = model.releaseDate ?? ""
        lastUpdated = model.lastUpdated ?? ""
    }

    static func catalogText(_ v: Double?) -> String {
        guard let v, v != 0 else { return "" }
        return v == v.rounded() && abs(v) < 1e15 ? String(Int64(v)) : String(v)
    }
}

// MARK: - Channel model options

extension ChannelOption {
    /// Request model names a channel answers to (`allModelEntries`), falling back to its supported models.
    var requestModels: [String] {
        if let entries = allModelEntries, !entries.isEmpty { return OptionSearch.merge(entries.map(\.requestModel)) }
        return supportedModels ?? []
    }

    /// Options for an association's model field: the chosen channel's models for channel-bound kinds,
    /// every known model otherwise (models-association-dialog.tsx `modelOptions`).
    static func associationModelOptions(kind: AssociationKind, channelID: Int?, channels: [ChannelOption], allModels: [String]) -> [String] {
        switch kind {
        case .channelModel:
            guard let channelID, let channel = channels.first(where: { $0.numericID == channelID }) else { return [] }
            return channel.requestModels
        default:
            return OptionSearch.merge(allModels, channels.flatMap(\.requestModels))
        }
    }

    /// Channels the playground offers: enabled ones that answer to at least one model (index.tsx on the web).
    static func playgroundChannels(_ channels: [ChannelOption]) -> [ChannelOption] {
        channels.filter { $0.status == "enabled" && !$0.requestModels.isEmpty }
    }

    /// Keeps the chosen model when the new list has it, else the first one.
    static func resolveModel(_ current: String, in models: [String]) -> String {
        models.contains(current) ? current : (models.first ?? "")
    }

    /// Models the playground can call through one channel (`selection.ts` on the web).
    static func playgroundModels(channelID: Int?, channels: [ChannelOption], fallback: [String]) -> [String] {
        guard let channelID, let channel = channels.first(where: { $0.numericID == channelID }) else { return fallback }
        let models = channel.requestModels
        return models.isEmpty ? fallback : models
    }
}

/// A default test model must be one of the channel's models; otherwise the first one.
enum ChannelTestModel {
    static func resolve(_ current: String, models: [String]) -> String {
        models.contains(current) ? current : (models.first ?? "")
    }
}
