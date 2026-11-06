import Foundation

/// Display metadata for AxonHub channel types (mirrors `ChannelType` in the upstream schema).
struct ChannelProvider: Hashable, Identifiable, Sendable {
    enum APIFormat: String, Sendable {
        case openai = "OpenAI"
        case responses = "Responses"
        case anthropic = "Anthropic"
        case gemini = "Gemini"
        case other = "其他"
    }

    let type: String
    let name: String
    let defaultBaseURL: String?
    let format: APIFormat
    /// Whether the channel can be created with a plain API key (others need OAuth / cloud credentials).
    let apiKeyBased: Bool

    var id: String { type }

    static func of(_ type: String) -> ChannelProvider {
        catalog.first { $0.type == type } ?? ChannelProvider(
            type: type,
            name: type.replacingOccurrences(of: "_", with: " ").capitalized,
            defaultBaseURL: nil,
            format: inferFormat(type),
            apiKeyBased: true
        )
    }

    static var creatable: [ChannelProvider] { catalog.filter(\.apiKeyBased) }

    private static func inferFormat(_ type: String) -> APIFormat {
        if type.hasSuffix("_anthropic") || type.hasPrefix("anthropic") { return .anthropic }
        if type.hasSuffix("_responses") { return .responses }
        if type.hasPrefix("gemini") { return .gemini }
        return .openai
    }

    private static func p(_ type: String, _ name: String, _ url: String?, _ format: APIFormat, apiKey: Bool = true) -> ChannelProvider {
        ChannelProvider(type: type, name: name, defaultBaseURL: url, format: format, apiKeyBased: apiKey)
    }

    static let catalog: [ChannelProvider] = [
        p("openai", "OpenAI", "https://api.openai.com/v1", .openai),
        p("openai_responses", "OpenAI Responses", "https://api.openai.com/v1", .responses),
        p("anthropic", "Anthropic", "https://api.anthropic.com", .anthropic),
        p("gemini", "Gemini", "https://generativelanguage.googleapis.com/v1beta", .gemini),
        p("gemini_openai", "Gemini (OpenAI 兼容)", "https://generativelanguage.googleapis.com/v1beta/openai", .openai),
        p("deepseek", "DeepSeek", "https://api.deepseek.com/v1", .openai),
        p("deepseek_anthropic", "DeepSeek (Anthropic)", "https://api.deepseek.com/anthropic", .anthropic),
        p("openrouter", "OpenRouter", "https://openrouter.ai/api/v1", .openai),
        p("moonshot", "Moonshot", "https://api.moonshot.cn/v1", .openai),
        p("moonshot_anthropic", "Moonshot (Anthropic)", "https://api.moonshot.cn/anthropic", .anthropic),
        p("moonshot_coding", "Kimi Coding", "https://api.kimi.com/coding", .anthropic),
        p("zhipu", "智谱", "https://open.bigmodel.cn/api/paas/v4", .openai),
        p("zhipu_anthropic", "智谱 (Anthropic)", "https://open.bigmodel.cn/api/anthropic", .anthropic),
        p("zai", "Z.ai", "https://api.z.ai/api/paas/v4", .openai),
        p("zai_anthropic", "Z.ai (Anthropic)", "https://api.z.ai/api/anthropic", .anthropic),
        p("bailian", "阿里云百炼", "https://dashscope.aliyuncs.com/compatible-mode/v1", .openai),
        p("bailian_responses", "百炼 Responses", "https://dashscope.aliyuncs.com/compatible-mode/v1", .responses),
        p("bailian_anthropic", "百炼 (Anthropic)", "https://dashscope.aliyuncs.com/apps/anthropic", .anthropic),
        p("doubao", "豆包", "https://ark.cn-beijing.volces.com/api/v3", .openai),
        p("doubao_anthropic", "豆包 (Anthropic)", "https://ark.cn-beijing.volces.com/api/compatible", .anthropic),
        p("volcengine", "火山引擎", "https://ark.cn-beijing.volces.com/api/v3", .openai),
        p("volcengine_anthropic", "火山引擎 (Anthropic)", "https://ark.cn-beijing.volces.com/api/coding", .anthropic),
        p("siliconflow", "硅基流动", "https://api.siliconflow.cn/v1", .openai),
        p("minimax", "MiniMax", "https://api.minimaxi.com/v1", .openai),
        p("minimax_anthropic", "MiniMax (Anthropic)", "https://api.minimaxi.com/anthropic", .anthropic),
        p("xai", "xAI", "https://api.x.ai/v1", .openai),
        p("xai_responses", "xAI Responses", "https://api.x.ai/v1", .responses),
        p("xiaomi", "小米 MiMo", "https://api.xiaomimimo.com/v1", .openai),
        p("xiaomi_anthropic", "小米 MiMo (Anthropic)", "https://token-plan-cn.xiaomimimo.com/anthropic", .anthropic),
        p("qiniu", "七牛云", "https://api.qnaigc.com/v1", .openai),
        p("qiniu_anthropic", "七牛云 (Anthropic)", "https://api.qnaigc.com", .anthropic),
        p("ppio", "PPIO", "https://api.ppinfra.com/openai/v1", .openai),
        p("modelscope", "ModelScope", "https://api-inference.modelscope.cn/v1", .openai),
        p("longcat", "LongCat", "https://api.longcat.chat/openai/v1", .openai),
        p("longcat_anthropic", "LongCat (Anthropic)", "https://api.longcat.chat/anthropic", .anthropic),
        p("groq", "Groq", "https://api.groq.com/openai/v1", .openai),
        p("cerebras", "Cerebras", "https://api.cerebras.ai/v1", .openai),
        p("fireworks", "Fireworks", "https://api.fireworks.ai/inference/v1", .openai),
        p("deepinfra", "DeepInfra", "https://api.deepinfra.com/v1/openai", .openai),
        p("vercel", "Vercel AI Gateway", "https://ai-gateway.vercel.sh/v1", .openai),
        p("aihubmix", "AiHubMix", "https://aihubmix.com/v1", .openai),
        p("aihubmix_anthropic", "AiHubMix (Anthropic)", "https://aihubmix.com", .anthropic),
        p("zenmux", "ZenMux", "https://zenmux.ai/api/v1", .openai),
        p("zenmux_responses", "ZenMux Responses", "https://zenmux.ai/api/v1", .responses),
        p("zenmux_anthropic", "ZenMux (Anthropic)", "https://zenmux.ai/api/anthropic", .anthropic),
        p("zenmux_gemini", "ZenMux (Gemini)", "https://zenmux.ai/api/vertex-ai", .gemini),
        p("nanogpt", "NanoGPT", "https://nano-gpt.com/api/v1", .openai),
        p("nanogpt_responses", "NanoGPT Responses", "https://nano-gpt.com/api/v1", .responses),
        p("evolink", "EvoLink", "https://direct.evolink.ai/v1", .openai),
        p("evolink_anthropic", "EvoLink (Anthropic)", "https://direct.evolink.ai", .anthropic),
        p("opencode_go", "OpenCode Go", "https://opencode.ai/zen/go", .openai),
        p("opencode_go_anthropic", "OpenCode Go (Anthropic)", "https://opencode.ai/zen/go", .anthropic),
        p("ollama", "Ollama", "https://ollama.com", .openai),
        p("ollama_anthropic", "Ollama (Anthropic)", "https://ollama.com", .anthropic),
        p("atlascloud", "AtlasCloud", "https://api.atlascloud.ai/v1", .openai),
        p("cline", "Cline", "https://api.cline.bot/api/v1", .openai),
        p("fenno", "Fenno", "https://api.fenno.ai", .openai),
        p("burncloud", "BurnCloud", "https://ai.burncloud.com/v1", .openai),
        p("commandcode", "CommandCode", "https://api.commandcode.ai/provider/v1", .openai),
        p("commandcode_anthropic", "CommandCode (Anthropic)", "https://api.commandcode.ai/provider/v1", .anthropic),
        p("jina", "Jina", "https://api.jina.ai/v1", .other),
        p("github", "GitHub Models", "https://models.github.ai/inference", .openai),
        p("typesafe", "TypeSafe", "https://api.typesafe.ai/v1", .openai),
        p("cloudflare", "Cloudflare Workers AI", "https://api.cloudflare.com/client/v4/accounts/<account_id>/ai", .openai),
        p("anthropic_fake", "Anthropic (模拟)", "https://api.anthropic.com/v1", .anthropic),
        p("openai_fake", "OpenAI (模拟)", "https://api.openai.com/v1", .openai),
        // Credential types that need OAuth or cloud service accounts; shown but not creatable on iOS.
        p("codex", "Codex", nil, .responses, apiKey: false),
        p("claudecode", "Claude Code", nil, .anthropic, apiKey: false),
        p("github_copilot", "GitHub Copilot", nil, .openai, apiKey: false),
        p("antigravity", "Antigravity", nil, .gemini, apiKey: false),
        p("xai_subscription", "xAI 订阅", nil, .openai, apiKey: false),
        p("gemini_vertex", "Gemini Vertex", nil, .gemini, apiKey: false),
        p("anthropic_aws", "Anthropic (Bedrock)", nil, .anthropic, apiKey: false),
        p("anthropic_gcp", "Anthropic (Vertex)", nil, .anthropic, apiKey: false),
        p("zenmux_video", "ZenMux Video", nil, .other, apiKey: false),
    ]
}
