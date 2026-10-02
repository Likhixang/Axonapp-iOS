import SwiftUI

/// Images copied from the same brand library used by AxonHub Web.
/// Explicit model.icon is authoritative; never infer a provider from a model name.
enum BrandIdentity {
    static let channelIcons: [String: String] = [
        "aihubmix": "aihubmix",
        "aihubmix_anthropic": "aihubmix",
        "anthropic": "anthropic",
        "anthropic_aws": "anthropic",
        "anthropic_gcp": "anthropic",
        "antigravity": "google",
        "atlascloud": "atlascloud",
        "bailian": "bailian",
        "bailian_anthropic": "bailian",
        "bailian_responses": "bailian",
        "burncloud": "burncloud",
        "cerebras": "cerebras",
        "claudecode": "claude",
        "cline": "cline",
        "codex": "openai",
        "commandcode": "commandcode",
        "commandcode_anthropic": "commandcode",
        "deepinfra": "deepinfra",
        "deepseek": "deepseek",
        "deepseek_anthropic": "deepseek",
        "doubao": "doubao",
        "doubao_anthropic": "doubao",
        "evolink": "evolink",
        "evolink_anthropic": "evolink",
        "fenno": "fenno",
        "fireworks": "fireworks",
        "gemini": "google",
        "gemini_openai": "google",
        "gemini_vertex": "google",
        "github": "github",
        "github_copilot": "github",
        "groq": "groq",
        "jina": "jina",
        "longcat": "longcat",
        "longcat_anthropic": "longcat",
        "minimax": "minimax",
        "minimax_anthropic": "minimax",
        "modelscope": "modelscope",
        "moonshot": "moonshot",
        "moonshot_anthropic": "moonshot",
        "moonshot_coding": "moonshot",
        "nanogpt": "nanogpt",
        "nanogpt_responses": "nanogpt",
        "ollama": "ollama",
        "ollama_anthropic": "ollama",
        "openai": "openai",
        "openai_responses": "openai",
        "opencode_go": "opencode",
        "opencode_go_anthropic": "opencode",
        "openrouter": "openrouter",
        "ppio": "ppio",
        "qiniu": "qiniu",
        "qiniu_anthropic": "qiniu",
        "siliconflow": "siliconcloud",
        "typesafe": "typesafe",
        "vercel": "vercel",
        "volcengine": "volcengine",
        "volcengine_anthropic": "volcengine",
        "xai": "xai",
        "xai_responses": "xai",
        "xai_subscription": "xai",
        "xiaomi": "xiaomimimo",
        "xiaomi_anthropic": "xiaomimimo",
        "zai": "zai",
        "zai_anthropic": "zai",
        "zenmux": "zenmux",
        "zenmux_anthropic": "zenmux",
        "zenmux_gemini": "zenmux",
        "zenmux_responses": "zenmux",
        "zenmux_video": "zenmux",
        "zhipu": "zhipu",
        "zhipu_anthropic": "zhipu",
    ]
    static let available: Set<String> = [
        "ace", "adobe", "adobefirefly", "agentvoice", "agnesai", "agui", "ai2", "ai21", "ai302", "ai360", "aihubmix", "aimass", "aionlabs", "airjelly", "aistudio", "akashchat", "alephalpha", "alibaba", "alibabacloud", "amdradeoncloud", "amp", "anspire", "antgroup", "anthropic", "antigravity", "anyscale", "apertis", "apple", "arcee", "askverdict", "assemblyai", "atlascloud", "automatic", "aws", "aya", "azure", "azureai", "baai", "baichuan", "baidu", "baiducloud", "bailian", "baseten", "bedrock", "bfl", "bilibili", "bilibiliindex", "bing", "bocha", "brave", "briaai", "browserless", "burncloud", "bytedance", "capcut", "celestoai", "centml", "cerebras", "chatglm", "cherrystudio", "chutes", "civitai", "claude", "claudecode", "cline", "clipdrop", "cloudflare", "codebuddy", "codeflicker", "codegeex", "codex", "cogvideo", "cogview", "cohere", "colab", "cometapi", "comfyui", "commanda", "commandcode", "copilot", "copilotkit", "coqui", "coze", "crewai", "crusoe", "cursor", "cybercut", "dalle", "dbrx", "decart", "deepai", "deepcogito", "deepinfra", "deepl", "deepmind", "deepseek", "devin", "dify", "digitalocean", "doc2x", "docsearch", "dolphin", "dotsstudio", "doubao", "dreammachine", "elevenlabs", "elevenx", "essentialai", "evolink", "exa", "fal", "fastgpt", "featherless", "fenno", "figma", "firecrawl", "fireworks", "fishaudio", "flora", "flowith", "flux", "friendli", "gemini", "geminicli", "gemma", "giteeai", "github", "githubcopilot", "glama", "glif", "glmv", "gmicloud", "google", "googlecloud", "goose", "gradio", "greptile", "grok", "groq", "hailuo", "haiper", "happyhorse", "hedra", "hermesagent", "higress", "huawei", "huaweicloud", "huggingface", "hunyuan", "hyperbolic", "ibm", "ideogram", "iflytekcloud", "inception", "inceptron", "inference", "infermatic", "infinigence", "inflection", "internlm", "ionet", "jimeng", "jina", "junie", "kagi", "kilocode", "kimi", "kiro", "kling", "kluster", "kolors", "krea", "kwaikat", "kwaipilot", "lambda", "langchain", "langfuse", "langgraph", "langsmith", "leptonai", "lg", "lightricks", "liquid", "livekit", "llamaindex", "llava", "llmapi", "lmstudio", "lobehub", "longcat", "lovable", "lovart", "luma", "magic", "make", "manus", "mastra", "mcp", "mcpso", "menlo", "meshy", "meta", "metaai", "metagpt", "microsoft", "midjourney", "minimax", "mistral", "modelscope", "monica", "moonshot", "morph", "moxt", "myshell", "n8n", "nanobanana", "nanogpt", "nebius", "newapi", "nextbit", "notebooklm", "notion", "nousresearch", "nova", "novelai", "novita", "nplcloud", "nvidia", "obsidian", "ollama", "openai", "openchat", "openclaw", "opencode", "openhands", "openhuman", "openrouter", "openwebui", "palm", "parasail", "perceptron", "perplexity", "phala", "phidata", "phind", "pi", "pika", "pixverse", "player2", "poe", "pollinations", "poolside", "ppio", "prunaai", "pydanticai", "qingyan", "qiniu", "qoder", "qwen", "railway", "recraft", "reka", "relace", "replicate", "replit", "reve", "roocode", "rsshub", "runway", "rwkv", "sakana", "sambanova", "search1api", "searchapi", "searxng", "sensenova", "siliconcloud", "sillytavern", "skywork", "slock", "smithery", "snowflake", "sophnet", "sora", "spark", "speedai", "stability", "statecloud", "stepfun", "straico", "streamlake", "submodel", "suno", "sync", "targon", "tavily", "tencent", "tencentcloud", "tiangong", "tii", "together", "topazlabs", "trae", "tripo", "turix", "typesafe", "udio", "unionalpha", "unsloth", "unstructured", "upstage", "v0", "vectorizerai", "venice", "vercel", "vertexai", "vidu", "viggle", "vllm", "volcengine", "voyage", "wafer", "wandb", "wavespeed", "wenxin", "windsurf", "workersai", "worldrouter", "xai", "xiaomimimo", "xinference", "xpay", "xuanyuan", "yandex", "yi", "youmind", "yuanbao", "zai", "zapier", "zeabur", "zencoder", "zenmux", "zeroone", "zhipu"
    ]
    static func asset(icon: String?) -> String? {
        guard let icon = icon, !icon.isEmpty, available.contains(icon.lowercased()) else { return nil }
        return "Brand-" + icon.lowercased()
    }
    static func channel(_ type: String) -> String? { asset(icon: channelIcons[type]) }
}

struct BrandMark: View {
    let asset: String?
    let name: String
    var size: CGFloat = 32
    var body: some View {
        Group {
            if let asset = asset {
                Image(asset).resizable().scaledToFit().foregroundStyle(.primary)
            } else {
                // No image in upstream metadata: plain initial, not a fake brand or SF Symbol.
                Text(String(name.prefix(1))).font(.system(size: size * 0.7, weight: .semibold)).foregroundStyle(.secondary)
            }
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}
