import Foundation

// MARK: - REST: authentication

/// The REST endpoints serialize ids as `{"type": "user", "id": 1}` while GraphQL uses
/// `gid://axonhub/user/1`. This type accepts both and always exposes the GraphQL form.
struct FlexibleID: Decodable, Hashable, Sendable {
    let gid: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            gid = text
        } else if let number = try? container.decode(Int.self) {
            gid = String(number)
        } else {
            struct Object: Decodable { let type: String; let id: Int }
            let object = try container.decode(Object.self)
            gid = "gid://axonhub/\(object.type)/\(object.id)"
        }
    }
}

struct RoleInfo: Decodable, Hashable, Sendable {
    let name: String
}

struct UserProjectInfo: Decodable, Hashable, Sendable {
    let projectID: FlexibleID
    let isOwner: Bool?
    let scopes: [String]?
    let effectiveScopes: [String]?
    let roles: [RoleInfo]?
}

struct UserInfo: Decodable, Hashable, Sendable {
    let id: FlexibleID
    let email: String
    let firstName: String?
    let lastName: String?
    let isOwner: Bool
    let preferLanguage: String?
    let avatar: String?
    let scopes: [String]?
    let roles: [RoleInfo]?
    let projects: [UserProjectInfo]?
    let hasPassword: Bool?

    var displayName: String {
        let name = [firstName, lastName].compactMap { $0?.nilIfBlank }.joined(separator: " ")
        return name.isEmpty ? email : name
    }

    var initials: String {
        let source = displayName
        return String(source.prefix(1)).uppercased()
    }
}

// MARK: - GraphQL connection plumbing

struct PageInfo: Decodable, Hashable, Sendable {
    let hasNextPage: Bool
    let endCursor: String?
}

struct Connection<Node: Decodable & Sendable>: Decodable, Sendable {
    struct Edge: Decodable, Sendable {
        let node: Node?
    }

    let edges: [Edge]?
    let pageInfo: PageInfo
    let totalCount: Int?

    var nodes: [Node] { edges?.compactMap(\.node) ?? [] }
}

struct Page<Item: Sendable>: Sendable {
    var items: [Item]
    var hasMore: Bool
    var cursor: String?
    var totalCount: Int?
}

struct NamedRef: Decodable, Hashable, Sendable {
    let id: String
    let name: String
}

// MARK: - Projects & users

struct Project: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let description: String?
    let status: String?
    let createdAt: Date?

    var isActive: Bool { (status ?? "active") == "active" }
}

struct AxonUser: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let email: String
    let firstName: String?
    let lastName: String?
    let status: String
    let isOwner: Bool
    let createdAt: Date?

    var displayName: String {
        let name = [firstName, lastName].compactMap { $0?.nilIfBlank }.joined(separator: " ")
        return name.isEmpty ? email : name
    }

    var isActive: Bool { status == "activated" }
}

// MARK: - Channels

struct ModelMapping: Codable, Hashable, Sendable {
    var from: String
    var to: String
}

struct ChannelSettings: Decodable, Hashable, Sendable {
    let extraModelPrefix: String?
    let modelMappings: [ModelMapping]?
}

struct DisabledAPIKey: Decodable, Hashable, Sendable {
    let key: String
    let disabledAt: Date?
    let errorCode: Int?
    let reason: String?
}

struct ChannelModelEntry: Decodable, Hashable, Sendable {
    let requestModel: String
    let actualModel: String
    let source: String
}

struct Channel: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let createdAt: Date?
    let updatedAt: Date?
    let type: String
    let baseURL: String?
    let name: String
    let status: String
    let supportedModels: [String]
    let manualModels: [String]?
    let autoSyncSupportedModels: Bool?
    let tags: [String]?
    let defaultTestModel: String?
    let orderingWeight: Int?
    let errorMessage: String?
    let remark: String?
    let autoDisabledAt: Date?
    let settings: ChannelSettings?
    let allModelEntries: [ChannelModelEntry]?
    let disabledAPIKeys: [DisabledAPIKey]?

    var channelStatus: ResourceStatus { ResourceStatus(rawValue: status) ?? .disabled }
    var provider: ChannelProvider { ChannelProvider.of(type) }
}

struct ChannelTestResult: Decodable, Hashable, Sendable {
    let latency: Double
    let success: Bool
    let message: String?
    let error: String?
}

struct SyncModelsResult: Decodable, Hashable, Sendable {
    let supportedModels: [String]
    let manualModels: [String]
}

// MARK: - Models

struct ModelCost: Decodable, Hashable, Sendable {
    let input: Double
    let output: Double
    let cacheRead: Double?
    let cacheWrite: Double?
}

struct ModelLimit: Decodable, Hashable, Sendable {
    let context: Int
    let output: Int
}

struct ModelReasoning: Decodable, Hashable, Sendable {
    let supported: Bool?
    let `default`: Bool?
}

struct ModelModalities: Decodable, Hashable, Sendable {
    let input: [String]?
    let output: [String]?
}

struct ModelCard: Decodable, Hashable, Sendable {
    let toolCall: Bool?
    let temperature: Bool?
    let vision: Bool?
    let knowledge: String?
    let releaseDate: String?
    let lastUpdated: String?
    let reasoning: ModelReasoning?
    let reasoningEfforts: [String]?
    let modalities: ModelModalities?
    let cost: ModelCost?
    let limit: ModelLimit?
}

struct AIModel: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let createdAt: Date?
    let developer: String
    let modelID: String
    let type: String
    let name: String
    let icon: String?
    let group: String?
    let status: String
    let remark: String?
    let associatedChannelCount: Int?
    let modelCard: ModelCard?
    let settings: ModelSettings?

    var modelStatus: ResourceStatus { ResourceStatus(rawValue: status) ?? .disabled }
}

// MARK: - API keys

struct APIKey: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let createdAt: Date?
    let updatedAt: Date?
    let name: String
    let key: String
    let type: String
    let status: String
    let scopes: [String]?
    let allowedIps: [String]?
    let profiles: APIKeyProfiles?
    let project: NamedRef?

    var keyStatus: ResourceStatus { ResourceStatus(rawValue: status) ?? .disabled }

    var typeLabel: String {
        switch type {
        case "user": return "用户"
        case "service_account": return "服务账号"
        case "noauth": return "免鉴权"
        case "personal": return "个人"
        default: return type
        }
    }
}

// MARK: - Requests

struct UsageLog: Decodable, Hashable, Sendable {
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int
    let promptCachedTokens: Int?
    let completionReasoningTokens: Int?
    let totalCost: Double?
}

struct UsageLogList: Decodable, Hashable, Sendable {
    struct Edge: Decodable, Hashable, Sendable { let node: UsageLog? }
    let edges: [Edge]?
    var first: UsageLog? { edges?.compactMap(\.node).first }
}

struct RequestExecution: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let createdAt: Date?
    let modelID: String
    let upstreamModelID: String?
    let format: String?
    let status: String
    let stream: Bool?
    let errorMessage: String?
    let responseStatusCode: Int?
    let metricsLatencyMs: Int?
    let metricsFirstTokenLatencyMs: Int?
    let requestURL: String?
    let channel: NamedRef?

    var requestStatus: RequestStatus { RequestStatus(rawValue: status) ?? .pending }
}

/// One upstream attempt with the payloads AxonHub sent to and got back from the channel.
struct ExecutionPayload: Decodable, Hashable, Sendable {
    let id: String
    let requestHeaders: JSONValue?
    let requestBody: JSONValue?
    let responseBody: JSONValue?
    let responseChunks: [JSONValue]?
}

struct ExecutionList: Decodable, Hashable, Sendable {
    struct Edge: Decodable, Hashable, Sendable { let node: RequestExecution? }
    let edges: [Edge]?
    var items: [RequestExecution] { edges?.compactMap(\.node) ?? [] }
}

struct RequestLog: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let createdAt: Date
    let modelID: String
    let format: String
    let source: String
    let status: String
    let stream: Bool
    let clientIP: String?
    let userAgent: String?
    let reasoningEffort: String?
    let metricsLatencyMs: Int?
    let metricsFirstTokenLatencyMs: Int?
    let traceID: String?
    let channel: NamedRef?
    let apiKey: NamedRef?
    let usageLogs: UsageLogList?

    var requestStatus: RequestStatus { RequestStatus(rawValue: status) ?? .pending }
    var usage: UsageLog? { usageLogs?.first }
}

struct RequestDetail: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let createdAt: Date
    let modelID: String
    let format: String
    let source: String
    let status: String
    let stream: Bool
    let clientIP: String?
    let userAgent: String?
    let reasoningEffort: String?
    let metricsLatencyMs: Int?
    let metricsFirstTokenLatencyMs: Int?
    let metricsReasoningDurationMs: Int?
    let traceID: String?
    let contentSaved: Bool?
    let requestHeaders: JSONValue?
    let requestBody: JSONValue?
    let responseHeaders: JSONValue?
    let responseBody: JSONValue?
    let responseChunks: [JSONValue]?
    let channel: NamedRef?
    let apiKey: NamedRef?
    let usageLogs: UsageLogList?
    let executions: ExecutionList?

    var requestStatus: RequestStatus { RequestStatus(rawValue: status) ?? .pending }
    var usage: UsageLog? { usageLogs?.first }
}

enum RequestStatus: String, CaseIterable, Sendable {
    case pending, processing, completed, failed, canceled

    var label: String {
        switch self {
        case .pending: return "排队中"
        case .processing: return "处理中"
        case .completed: return "成功"
        case .failed: return "失败"
        case .canceled: return "已取消"
        }
    }
}

enum ResourceStatus: String, CaseIterable, Sendable {
    case enabled, disabled, archived

    var label: String {
        switch self {
        case .enabled: return "已启用"
        case .disabled: return "已停用"
        case .archived: return "已归档"
        }
    }
}

// MARK: - Dashboard

struct RequestStats: Decodable, Hashable, Sendable {
    let requestsToday: Int
    let requestsThisWeek: Int
    let requestsLastWeek: Int
    let requestsThisMonth: Int
}

struct DashboardOverview: Decodable, Hashable, Sendable {
    let totalRequests: Int
    let failedRequests: Int
    let averageResponseTime: Double?
    let requestStats: RequestStats
}

struct TokenStats: Decodable, Hashable, Sendable {
    let totalInputTokensToday: Int
    let totalOutputTokensToday: Int
    let totalCachedTokensToday: Int
    let totalInputTokensThisWeek: Int
    let totalOutputTokensThisWeek: Int
    let totalCachedTokensThisWeek: Int
    let totalInputTokensThisMonth: Int
    let totalOutputTokensThisMonth: Int
    let totalCachedTokensThisMonth: Int
    let totalInputTokensAllTime: Int
    let totalOutputTokensAllTime: Int
    let totalCachedTokensAllTime: Int
}

struct DailyRequestStat: Decodable, Hashable, Sendable, Identifiable {
    let date: String
    let count: Int
    let tokens: Int
    let cost: Double

    var id: String { date }

    var day: Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: String(date.prefix(10)))
    }
}

struct ModelRequestCount: Decodable, Hashable, Sendable, Identifiable {
    let modelId: String
    let count: Int
    var id: String { modelId }
}

struct ModelCost2: Decodable, Hashable, Sendable, Identifiable {
    let modelId: String
    let cost: Double
    var id: String { modelId }
}

struct ModelTokens: Decodable, Hashable, Sendable, Identifiable {
    let modelId: String
    let inputTokens: Int
    let outputTokens: Int
    let cachedTokens: Int
    let totalTokens: Int
    var id: String { modelId }
}

struct ChannelSuccessRate: Decodable, Hashable, Sendable, Identifiable {
    let channelId: String
    let channelName: String
    let channelType: String
    let channelDisabled: Bool
    let successCount: Int
    let failedCount: Int
    let totalCount: Int
    let successRate: Double
    var id: String { channelId }
}

struct FastestModel: Decodable, Hashable, Sendable, Identifiable {
    let modelId: String
    let modelName: String
    let throughput: Double
    let latencyMs: Int
    let requestCount: Int
    var id: String { modelId }
}

enum TimeWindow: String, CaseIterable, Identifiable, Sendable {
    case day, week, month, allTime

    var id: String { rawValue }

    var label: String {
        switch self {
        case .day: return "今天"
        case .week: return "本周"
        case .month: return "本月"
        case .allTime: return "全部"
        }
    }
}

struct DashboardSnapshot: Sendable {
    var overview: DashboardOverview?
    var tokens: TokenStats?
    var daily: [DailyRequestStat] = []
    var topModels: [ModelRequestCount] = []
    var modelCosts: [ModelCost2] = []
    var modelTokens: [ModelTokens] = []
    var channelHealth: [ChannelSuccessRate] = []
    var fastestModels: [FastestModel] = []
    var partialErrors: [String] = []
}

// MARK: - System

struct SystemVersion: Decodable, Hashable, Sendable {
    let version: String?
    let commit: String?
    let buildTime: String?
    let goVersion: String?
    let platform: String?
    let uptime: String?
}
