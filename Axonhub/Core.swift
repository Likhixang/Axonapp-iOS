import Foundation
import Security

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A lossless JSON representation for dynamic payload handling.
indirect enum JSON: Codable, Sendable, Hashable {
    case object([String: JSON]), array([JSON]), string(String), number(Double), bool(Bool), null

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let decoded = try? value.decode(Bool.self) { self = .bool(decoded) }
        else if let decoded = try? value.decode(Double.self) { self = .number(decoded) }
        else if let decoded = try? value.decode(String.self) { self = .string(decoded) }
        else if let decoded = try? value.decode([JSON].self) { self = .array(decoded) }
        else { self = .object(try value.decode([String: JSON].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .object(let v): try value.encode(v)
        case .array(let v): try value.encode(v)
        case .string(let v): try value.encode(v)
        case .number(let v): try value.encode(v)
        case .bool(let v): try value.encode(v)
        case .null: try value.encodeNil()
        }
    }

    subscript(_ key: String) -> JSON {
        if case .object(let dict) = self { return dict[key] ?? .null }
        return .null
    }

    var string: String { if case .string(let v) = self { return v }; return "" }
    var number: Double { if case .number(let v) = self { return v }; return 0 }
    var int: Int { Int(number) }
    var bool: Bool { if case .bool(let v) = self { return v }; return false }
    var array: [JSON] { if case .array(let v) = self { return v }; return [] }
    var object: [String: JSON] { if case .object(let v) = self { return v }; return [:] }
    var isNull: Bool { if case .null = self { return true }; return false }

    static func from(_ string: String) -> JSON? {
        try? JSONDecoder().decode(JSON.self, from: Data(string.utf8))
    }
}

/// Safe user-facing errors that never echo credentials or sensitive headers.
enum AxonAPIError: Error, LocalizedError, Equatable {
    case invalidURL
    case insecureURL
    case invalidCredentials
    case unauthorized
    case forbidden
    case transport
    case timedOut
    case httpStatus(Int)
    case invalidResponse
    case graphQLError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return NSLocalizedString("请输入有效的 AxonHub 地址，不允许包含账号密码或查询参数。", comment: "")
        case .insecureURL:
            return NSLocalizedString("默认要求 HTTPS 连接。仅在受信局域网内可勾选允许 HTTP。", comment: "")
        case .invalidCredentials:
            return NSLocalizedString("凭据不能为空或格式不正确。", comment: "")
        case .unauthorized:
            return NSLocalizedString("认证失败或登录状态已过期，请重新登录。", comment: "")
        case .forbidden:
            return NSLocalizedString("权限不足，无法执行此操作。", comment: "")
        case .transport:
            return NSLocalizedString("无法连接到 AxonHub 服务器，请检查网络、域名与证书。", comment: "")
        case .timedOut:
            return NSLocalizedString("请求超时，请检查网关连接状态。", comment: "")
        case .httpStatus(let code):
            return String(format: NSLocalizedString("服务器返回 HTTP %lld 错误。", comment: "HTTP status code"), Int64(code))
        case .invalidResponse:
            return NSLocalizedString("网关返回了非预期的响应格式。", comment: "")
        case .graphQLError(let message):
            return String(format: NSLocalizedString("GraphQL 错误：%@。", comment: "GraphQL error"), message)
        }
    }
}

/// Authentication type for connecting to AxonHub.
enum AxonAuthType: String, Codable, CaseIterable, Identifiable, Sendable {
    case adminJWT = "admin"
    case apiKey = "apiKey"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .adminJWT: return NSLocalizedString("管理员账号", comment: "")
        case .apiKey: return NSLocalizedString("API Key 直连", comment: "")
        }
    }
}

/// Data model representing an AxonHub gateway instance.
struct AxonInstance: Codable, Identifiable, Hashable, Sendable {
    var id: String = UUID().uuidString
    var name: String
    var address: String
    var allowHTTP: Bool = false
    var authType: AxonAuthType = .adminJWT
    var adminEmail: String = ""
    var createdAt: Date = Date()
}

/// Channel summary data item.
struct ChannelItem: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let type: String
    let baseURL: String?
    let status: String
    let supportedModels: [String]
    let orderingWeight: Int
    let errorMessage: String?
    let autoDisabledAt: String?
    let tags: [String]
    let remark: String?

    var isEnabled: Bool { status.lowercased() == "enabled" }
}

/// Model catalog item.
struct ModelItem: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let modelID: String
    let name: String
    let developer: String
    let type: String
    let group: String
    let icon: String?
    let status: String
    let remark: String?

    var isEnabled: Bool { status.lowercased() == "enabled" }
}

/// Live request log entry.
struct RequestLogItem: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let createdAt: String
    let modelID: String
    let source: String
    let format: String
    let status: String
    let stream: Bool
    let clientIP: String
    let userAgent: String
    let latencyMs: Int?
    let firstTokenLatencyMs: Int?
    let reasoningDurationMs: Int?
    let errorMessage: String?

    var isSuccess: Bool {
        let s = status.lowercased()
        return s == "completed" || s == "success" || s == "200"
    }
}

/// API Key summary item.
struct APIKeyItem: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let key: String
    let type: String
    let status: String
    let scopes: [String]
    let createdAt: String

    var isEnabled: Bool { status.lowercased() == "enabled" }
}

/// Dashboard analytics snapshot.
struct AxonDashboardStats: Codable, Hashable, Sendable {
    var totalRequests: Int = 0
    var failedRequests: Int = 0
    var averageResponseTime: Double = 0
    var requestsToday: Int = 0
    var requestsThisWeek: Int = 0
    var requestsThisMonth: Int = 0

    var totalInputTokensToday: Int = 0
    var totalOutputTokensToday: Int = 0
    var totalCachedTokensToday: Int = 0
    var totalInputTokensThisMonth: Int = 0
    var totalOutputTokensThisMonth: Int = 0
    var totalCachedTokensThisMonth: Int = 0
    var totalInputTokensAllTime: Int = 0
    var totalOutputTokensAllTime: Int = 0
    var totalCachedTokensAllTime: Int = 0
}

/// Aggregated data snapshot for an AxonHub instance.
struct AxonSnapshot: Codable, Hashable, Sendable {
    var dashboard: AxonDashboardStats = AxonDashboardStats()
    var channels: [ChannelItem] = []
    var models: [ModelItem] = []
    var requests: [RequestLogItem] = []
    var apiKeys: [APIKeyItem] = []
}

/// Non-redirect delegate preventing token leakage over redirection.
final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

private final class APITransport: @unchecked Sendable {
    let session: URLSession

    init(configuration: URLSessionConfiguration) {
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        session = URLSession(configuration: configuration, delegate: NoRedirectDelegate(), delegateQueue: nil)
    }

    deinit {
        session.invalidateAndCancel()
    }
}

/// Keys are local-only; credentials stay in iOS Keychain and never enter backups.
enum Keychain {
    static func save(key: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(key.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw AxonAPIError.invalidCredentials }
    }

    static func load(account: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data, let str = String(data: data, encoding: .utf8) else {
            throw AxonAPIError.unauthorized
        }
        return str
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// Client performing authenticated queries against an AxonHub gateway.
struct AxonClient: Sendable {
    let baseURL: URL
    let authType: AxonAuthType
    let token: String
    private let transport: APITransport

    init(baseURL: String, authType: AxonAuthType, token: String, allowHTTP: Bool = false, configuration: URLSessionConfiguration = .ephemeral) throws {
        let clean = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: clean),
              let scheme = url.scheme?.lowercased(),
              let host = url.host, !host.isEmpty else {
            throw AxonAPIError.invalidURL
        }
        if scheme == "http" && !allowHTTP {
            throw AxonAPIError.insecureURL
        }
        guard scheme == "https" || scheme == "http" else {
            throw AxonAPIError.invalidURL
        }
        guard url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else {
            throw AxonAPIError.invalidURL
        }
        self.baseURL = url
        self.authType = authType
        self.token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        self.transport = APITransport(configuration: configuration)
    }

    /// Resolves an endpoint URL relative to the deployment base path without path component escaping issues.
    static func endpoint(baseURL: URL, path: String) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) ?? URLComponents()
        var prefix = components.percentEncodedPath
        while prefix.hasSuffix("/") { prefix.removeLast() }
        let cleanPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        components.percentEncodedPath = prefix + "/" + cleanPath
        return components.url ?? baseURL.appendingPathComponent(path)
    }

    /// Sign in with administrator email and password to obtain a JWT token.
    static func signIn(baseURL: String, email: String, password: String, allowHTTP: Bool = false) async throws -> String {
        let validated = try AxonClient(baseURL: baseURL, authType: .adminJWT, token: "", allowHTTP: allowHTTP)
        let signinURL = endpoint(baseURL: validated.baseURL, path: "admin/auth/signin")
        var req = URLRequest(url: signinURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: String] = ["email": email, "password": password]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let transport = APITransport(configuration: .ephemeral)
        let (data, response) = try await transport.session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw AxonAPIError.invalidResponse
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw AxonAPIError.unauthorized
        }
        guard http.statusCode == 200 else {
            throw AxonAPIError.httpStatus(http.statusCode)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["token"] as? String, !token.isEmpty else {
            throw AxonAPIError.invalidResponse
        }
        return token
    }

    /// Execute a GraphQL query or mutation against AxonHub.
    func graphql(query: String, variables: [String: Any] = [:]) async throws -> JSON {
        guard authType == .adminJWT else { throw AxonAPIError.forbidden }
        let path = "admin/graphql"
        let endpoint = Self.endpoint(baseURL: baseURL, path: path)
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        var payload: [String: Any] = ["query": query]
        if !variables.isEmpty {
            payload["variables"] = variables
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await transport.session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw AxonAPIError.invalidResponse
        }
        if http.statusCode == 401 { throw AxonAPIError.unauthorized }
        if http.statusCode == 403 { throw AxonAPIError.forbidden }
        let root = JSON.from(String(decoding: data, as: UTF8.self))
        // gqlgen sends validation errors as HTTP 422; decode before status handling.
        if !(root?["errors"].array.isEmpty ?? true) {
            // Upstream validation/resolver messages can echo credential variables,
            // OAuth tokens or proxy passwords. Never show untrusted server prose.
            let codes = root?["errors"].array.map { $0["extensions"]["code"].string } ?? []
            if codes.contains("FORBIDDEN") { throw AxonAPIError.forbidden }
            if codes.contains("UNAUTHENTICATED") { throw AxonAPIError.unauthorized }
            throw AxonAPIError.graphQLError(NSLocalizedString("请求被服务器拒绝，请检查权限与输入。", comment: ""))
        }
        guard (200...299).contains(http.statusCode) else {
            throw AxonAPIError.httpStatus(http.statusCode)
        }
        guard let root = root, !root["data"].isNull else {
            throw AxonAPIError.invalidResponse
        }
        return root["data"]
    }

    /// Fixed admin OAuth routes only, never an arbitrary URL supplied by a server.
    func channelOAuth(provider: String, action: String, body: JSON) async throws -> JSON {
        let allowed: [String: Set<String>] = ["codex": ["oauth/start", "oauth/exchange", "auth/decode"],
            "claudecode": ["oauth/start", "oauth/exchange"], "antigravity": ["oauth/start", "oauth/exchange"],
            "xai": ["oauth/start", "oauth/exchange", "oauth/sso"], "copilot": ["oauth/start", "oauth/poll"]]
        guard authType == .adminJWT, allowed[provider]?.contains(action) == true else { throw AxonAPIError.forbidden }
        var req = URLRequest(url: Self.endpoint(baseURL: baseURL, path: "admin/" + provider + "/" + action))
        req.httpMethod = "POST"; req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONEncoder().encode(body)
        let (bytes, response) = try await transport.session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw AxonAPIError.invalidResponse }
        guard (200...299).contains(http.statusCode) else { throw AxonAPIError.httpStatus(http.statusCode) }
        guard let result = JSON.from(String(decoding: bytes, as: UTF8.self)) else { throw AxonAPIError.invalidResponse }
        return result
    }

    /// Load full gateway dashboard, channel, model and audit metrics.
    func fetchSnapshot() async throws -> AxonSnapshot {
        if authType == .apiKey {
            return try await fetchAPIKeySnapshot()
        }
        return try await fetchAdminSnapshot()
    }

    private func fetchAdminSnapshot() async throws -> AxonSnapshot {
        let query = """
        query AxonOverview {
          dashboardOverview {
            totalRequests
            failedRequests
            averageResponseTime
            requestStats {
              requestsToday
              requestsThisWeek
              requestsLastWeek
              requestsThisMonth
            }
          }
          tokenStats {
            totalInputTokensToday
            totalOutputTokensToday
            totalCachedTokensToday
            totalInputTokensThisMonth
            totalOutputTokensThisMonth
            totalCachedTokensThisMonth
            totalInputTokensAllTime
            totalOutputTokensAllTime
            totalCachedTokensAllTime
          }
          allChannelSummarys(includeArchived: true) {
            id
            name
            type
            baseURL
            status
            supportedModels
            orderingWeight
            errorMessage
            autoDisabledAt
            tags
            remark
          }
          models(first: 100, orderBy: { direction: DESC, field: CREATED_AT }) {
            edges {
              node {
                id
                modelID
                name
                developer
                type
                group
                icon
                status
                remark
              }
            }
          }
          requests(first: 50, orderBy: { direction: DESC, field: CREATED_AT }) {
            edges {
              node {
                id
                createdAt
                modelID
                source
                format
                status
                stream
                clientIP
                metricsLatencyMs
                metricsFirstTokenLatencyMs
                metricsReasoningDurationMs
                executions(first: 1, orderBy: { direction: DESC, field: CREATED_AT }) {
                  edges { node { errorMessage } }
                }
              }
            }
          }
          apiKeys(first: 50, orderBy: { direction: DESC, field: CREATED_AT }) {
            edges {
              node {
                id
                name
                type
                status
                scopes
                createdAt
              }
            }
          }
        }
        """

        let data = try await graphql(query: query)
        var snapshot = AxonSnapshot()

        // Parse dashboard overview
        let dash = data["dashboardOverview"]
        let reqStats = dash["requestStats"]
        snapshot.dashboard.totalRequests = dash["totalRequests"].int
        snapshot.dashboard.failedRequests = dash["failedRequests"].int
        snapshot.dashboard.averageResponseTime = dash["averageResponseTime"].number
        snapshot.dashboard.requestsToday = reqStats["requestsToday"].int
        snapshot.dashboard.requestsThisWeek = reqStats["requestsThisWeek"].int
        snapshot.dashboard.requestsThisMonth = reqStats["requestsThisMonth"].int

        // Parse token statistics
        let tStats = data["tokenStats"]
        snapshot.dashboard.totalInputTokensToday = tStats["totalInputTokensToday"].int
        snapshot.dashboard.totalOutputTokensToday = tStats["totalOutputTokensToday"].int
        snapshot.dashboard.totalCachedTokensToday = tStats["totalCachedTokensToday"].int
        snapshot.dashboard.totalInputTokensThisMonth = tStats["totalInputTokensThisMonth"].int
        snapshot.dashboard.totalOutputTokensThisMonth = tStats["totalOutputTokensThisMonth"].int
        snapshot.dashboard.totalCachedTokensThisMonth = tStats["totalCachedTokensThisMonth"].int
        snapshot.dashboard.totalInputTokensAllTime = tStats["totalInputTokensAllTime"].int
        snapshot.dashboard.totalOutputTokensAllTime = tStats["totalOutputTokensAllTime"].int
        snapshot.dashboard.totalCachedTokensAllTime = tStats["totalCachedTokensAllTime"].int

        // Parse channels
        snapshot.channels = data["allChannelSummarys"].array.map { c in
            ChannelItem(
                id: c["id"].string,
                name: c["name"].string,
                type: c["type"].string,
                baseURL: c["baseURL"].isNull ? nil : c["baseURL"].string,
                status: c["status"].string,
                supportedModels: c["supportedModels"].array.map { $0.string },
                orderingWeight: c["orderingWeight"].int,
                errorMessage: c["errorMessage"].isNull ? nil : c["errorMessage"].string,
                autoDisabledAt: c["autoDisabledAt"].isNull ? nil : c["autoDisabledAt"].string,
                tags: c["tags"].array.map { $0.string },
                remark: c["remark"].isNull ? nil : c["remark"].string
            )
        }

        // Parse models
        snapshot.models = try await allManagedModels()

        // Parse requests
        snapshot.requests = data["requests"]["edges"].array.map { e in
            let r = e["node"]
            return RequestLogItem(
                id: r["id"].string,
                createdAt: r["createdAt"].string,
                modelID: r["modelID"].string,
                source: r["source"].string,
                format: r["format"].string,
                status: r["status"].string,
                stream: r["stream"].bool,
                clientIP: r["clientIP"].string,
                userAgent: "",
                latencyMs: r["metricsLatencyMs"].isNull ? nil : r["metricsLatencyMs"].int,
                firstTokenLatencyMs: r["metricsFirstTokenLatencyMs"].isNull ? nil : r["metricsFirstTokenLatencyMs"].int,
                reasoningDurationMs: r["metricsReasoningDurationMs"].isNull ? nil : r["metricsReasoningDurationMs"].int,
                errorMessage: r["executions"]["edges"].array.first.flatMap {
                    let message = $0["node"]["errorMessage"]
                    return message.isNull ? nil : message.string
                }
            )
        }

        // Parse API keys
        snapshot.apiKeys = data["apiKeys"]["edges"].array.map { e in
            let k = e["node"]
            return APIKeyItem(
                id: k["id"].string,
                name: k["name"].string,
                key: "",
                type: k["type"].string,
                status: k["status"].string,
                scopes: k["scopes"].array.map { $0.string },
                createdAt: k["createdAt"].string
            )
        }

        return snapshot
    }

    private func fetchAPIKeySnapshot() async throws -> AxonSnapshot {
        // Ordinary user API keys authenticate /v1/models, not the service-account
        // OpenAPI management surface. Never invent dashboard totals from quotas.
        var snapshot = AxonSnapshot()
        snapshot.models = try await fetchV1Models()
        return snapshot
    }

    func fetchV1Models() async throws -> [ModelItem] {
        let endpoint = Self.endpoint(baseURL: baseURL, path: "v1/models")
        var req = URLRequest(url: endpoint)
        req.httpMethod = "GET"
        if !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await transport.session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw AxonAPIError.invalidResponse }
        if http.statusCode == 401 { throw AxonAPIError.unauthorized }
        if http.statusCode == 403 { throw AxonAPIError.forbidden }
        guard (200...299).contains(http.statusCode) else { throw AxonAPIError.httpStatus(http.statusCode) }
        guard let root = JSON.from(String(decoding: data, as: UTF8.self)),
              case .array = root["data"] else {
            throw AxonAPIError.invalidResponse
        }
        return root["data"].array.map { item in
            let id = item["id"].string
            return ModelItem(
                id: id,
                modelID: id,
                name: id,
                developer: "OpenAI-Compatible",
                type: "llm",
                group: "default",
                icon: nil,
                status: "enabled",
                remark: nil
            )
        }
    }

    /// Toggle a channel between ENABLED and DISABLED.
    func updateChannelStatus(id: String, enabled: Bool) async throws {
        let status = enabled ? "enabled" : "disabled"
        let mutation = """
        mutation UpdateChannelStatus($id: ID!, $status: ChannelStatus!) {
          updateChannelStatus(id: $id, status: $status) {
            id
            status
          }
        }
        """
        let data = try await graphql(query: mutation, variables: ["id": id, "status": status])
        guard data["updateChannelStatus"]["id"].string == id,
              data["updateChannelStatus"]["status"].string == status else { throw ManagementError.verification }
    }

    /// Toggle a model between ENABLED and DISABLED.
    func updateModelStatus(id: String, enabled: Bool) async throws {
        let status = enabled ? "enabled" : "disabled"
        let mutation = """
        mutation UpdateModelStatus($id: ID!, $status: ModelStatus!) {
          updateModelStatus(id: $id, status: $status)
        }
        """
        let data = try await graphql(query: mutation, variables: ["id": id, "status": status])
        guard data["updateModelStatus"].bool else { throw ManagementError.verification }
    }

    /// Test a channel connection and latency.
    func testChannel(id: String, model: String? = nil) async throws -> (success: Bool, latencyMs: Int, error: String?) {
        let mutation = """
        mutation TestChannel($input: TestChannelInput!) {
          testChannel(input: $input) {
            success
            latency
            error
          }
        }
        """
        var input: [String: Any] = ["channelID": id]
        if let model = model, !model.isEmpty {
            input["modelID"] = model
        }
        let data = try await graphql(query: mutation, variables: ["input": input])
        let res = data["testChannel"]
        return (
            success: res["success"].bool,
            latencyMs: Int((res["latency"].number * 1000).rounded()),
            error: res["error"].isNull ? nil : res["error"].string
        )
    }
}
