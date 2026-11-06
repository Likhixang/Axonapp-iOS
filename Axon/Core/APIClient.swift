import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum APIError: LocalizedError, Equatable {
    case invalidURL
    case unauthorized(String?)
    case forbidden(String?)
    case http(status: Int, message: String?)
    case graphQL([String])
    case decoding(String)
    case transport(String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "服务器地址无效"
        case .unauthorized(let message):
            return message ?? "登录已失效，请重新登录"
        case .forbidden(let message):
            return message ?? "没有权限执行这个操作"
        case .http(let status, let message):
            return message.map { "\($0) (HTTP \(status))" } ?? "请求失败 (HTTP \(status))"
        case .graphQL(let messages):
            return messages.joined(separator: "\n")
        case .decoding(let detail):
            return "响应解析失败：\(detail)"
        case .transport(let detail):
            return detail
        case .emptyResponse:
            return "服务器返回了空响应"
        }
    }

    var isUnauthorized: Bool {
        if case .unauthorized = self { return true }
        return false
    }
}

/// Thread-safe holder for mutable session state shared by the client.
final class Locked<Value>: @unchecked Sendable {
    private var value: Value
    private let lock = NSLock()

    init(_ value: Value) { self.value = value }

    func get() -> Value {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    func set(_ newValue: Value) {
        lock.lock(); defer { lock.unlock() }
        value = newValue
    }
}

struct HealthInfo: Decodable, Sendable {
    struct Build: Decodable, Sendable {
        let version: String?
        let commit: String?
        let buildTime: String?
        let goVersion: String?
        let platform: String?

        enum CodingKeys: String, CodingKey {
            case version, commit
            case buildTime = "build_time"
            case goVersion = "go_version"
            case platform
        }
    }

    let status: String
    let timestamp: String?
    let version: String?
    let build: Build?
    let uptime: String?
}

struct SystemStatus: Decodable, Sendable {
    let isInitialized: Bool
}

struct SignInResponse: Decodable, Sendable {
    let user: UserInfo
    let token: String
}

/// Low level HTTP client for an AxonHub server.
///
/// - `POST /admin/auth/signin`, `POST /admin/auth/refresh`, `GET /admin/system/status`, `GET /health`
/// - `POST /admin/graphql` for every management query / mutation
/// - `POST /admin/playground/chat` for streamed chat in the playground
final class APIClient: @unchecked Sendable {
    let baseURL: URL
    let session: URLSession

    private let tokenStore: Locked<String>
    private let projectStore: Locked<String?>

    /// Called whenever the server issues a renewed JWT.
    var onTokenRefresh: (@Sendable (String) -> Void)?
    /// Called when the token can no longer be used.
    var onUnauthorized: (@Sendable () -> Void)?

    init(baseURL: URL, token: String, projectID: String? = nil, session: URLSession = APIClient.makeSession()) {
        self.baseURL = baseURL
        self.session = session
        self.tokenStore = Locked(token)
        self.projectStore = Locked(projectID)
    }

    var token: String { tokenStore.get() }
    var projectID: String? { projectStore.get() }

    func setProjectID(_ id: String?) { projectStore.set(id) }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 600
        configuration.httpAdditionalHeaders = ["User-Agent": "AxonHub-iOS/2.0"]
        return URLSession(configuration: configuration)
    }

    // MARK: - URL helpers

    /// Accepts things like `axon.example.com`, `https://axon.example.com/`, `http://10.0.0.2:8090/admin`.
    static func normalizeBaseURL(_ input: String) -> URL? {
        var text = input.trimmed
        guard !text.isEmpty else { return nil }
        if !text.lowercased().hasPrefix("http://") && !text.lowercased().hasPrefix("https://") {
            text = "https://" + text
        }
        while text.hasSuffix("/") { text.removeLast() }
        for suffix in ["/admin", "/v1"] where text.lowercased().hasSuffix(suffix) {
            text.removeLast(suffix.count)
        }
        guard let url = URL(string: text), let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    static func endpoint(_ baseURL: URL, _ path: String) -> URL {
        path.split(separator: "/").reduce(baseURL) { $0.appendingPathComponent(String($1)) }
    }

    func endpoint(_ path: String) -> URL { Self.endpoint(baseURL, path) }

    // MARK: - Unauthenticated endpoints

    static func health(baseURL: URL, session: URLSession = .shared) async throws -> HealthInfo {
        var request = URLRequest(url: endpoint(baseURL, "health"))
        request.timeoutInterval = 15
        let (data, response) = try await perform(request, session: session)
        guard (200..<300).contains(response.statusCode) || response.statusCode == 503 else {
            throw error(for: response.statusCode, data: data)
        }
        return try decode(HealthInfo.self, from: data)
    }

    static func systemStatus(baseURL: URL, session: URLSession = .shared) async throws -> SystemStatus {
        var request = URLRequest(url: endpoint(baseURL, "admin/system/status"))
        request.timeoutInterval = 15
        let (data, response) = try await perform(request, session: session)
        guard (200..<300).contains(response.statusCode) else { throw error(for: response.statusCode, data: data) }
        return try decode(SystemStatus.self, from: data)
    }

    static func signIn(baseURL: URL, email: String, password: String, session: URLSession = .shared) async throws -> SignInResponse {
        var request = URLRequest(url: endpoint(baseURL, "admin/auth/signin"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["email": email, "password": password])
        request.timeoutInterval = 30
        let (data, response) = try await perform(request, session: session)
        guard (200..<300).contains(response.statusCode) else {
            if response.statusCode == 401 {
                throw APIError.unauthorized(serverMessage(data) ?? "邮箱或密码不正确")
            }
            throw error(for: response.statusCode, data: data)
        }
        return try decode(SignInResponse.self, from: data)
    }

    // MARK: - Authenticated transport

    func authorizedRequest(_ path: String, method: String = "GET", body: Data? = nil, includeProject: Bool = true) -> URLRequest {
        var request = URLRequest(url: endpoint(path))
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if includeProject, let projectID, !projectID.isEmpty {
            request.setValue(projectID, forHTTPHeaderField: "X-Project-ID")
        }
        request.httpBody = body
        return request
    }

    /// Sends an authorized request; on `401` tries one token refresh and replays.
    func send(_ makeRequest: () -> URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await Self.perform(makeRequest(), session: session)
        guard response.statusCode == 401 else { return (data, response) }

        if try await refreshToken() {
            let (retryData, retryResponse) = try await Self.perform(makeRequest(), session: session)
            if retryResponse.statusCode != 401 { return (retryData, retryResponse) }
        }
        onUnauthorized?()
        throw APIError.unauthorized(Self.serverMessage(data))
    }

    /// `POST /admin/auth/refresh` — returns `true` when a new token was issued.
    @discardableResult
    func refreshToken() async throws -> Bool {
        var request = URLRequest(url: endpoint("admin/auth/refresh"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let (data, response) = try? await Self.perform(request, session: session),
              response.statusCode == 200 else { return false }
        struct Refresh: Decodable { let token: String }
        guard let refreshed = try? JSONDecoder().decode(Refresh.self, from: data), !refreshed.token.isEmpty else {
            return false
        }
        tokenStore.set(refreshed.token)
        onTokenRefresh?(refreshed.token)
        return true
    }

    // MARK: - GraphQL

    func graphQL<T: Decodable>(_ query: String, variables: [String: JSONValue] = [:], as type: T.Type = T.self) async throws -> T {
        let payload = JSONValue.object([
            "query": .string(query),
            "variables": .object(variables),
        ])
        let body = try JSONEncoder().encode(payload)
        let (data, response) = try await send { authorizedRequest("admin/graphql", method: "POST", body: body) }

        guard (200..<300).contains(response.statusCode) || response.statusCode == 422 || response.statusCode == 400 else {
            throw Self.error(for: response.statusCode, data: data)
        }
        let envelope: GraphQLEnvelope<T>
        do {
            envelope = try JSONDecoder.axon.decode(GraphQLEnvelope<T>.self, from: data)
        } catch {
            if let messages = try? JSONDecoder().decode(GraphQLErrorsOnly.self, from: data).errors, !messages.isEmpty {
                throw APIError.graphQL(messages.map(\.message))
            }
            throw APIError.decoding(Self.describe(error))
        }
        if let errors = envelope.errors, !errors.isEmpty {
            let messages = errors.map(\.message)
            if messages.contains(where: { $0.localizedCaseInsensitiveContains("permission") || $0.localizedCaseInsensitiveContains("forbidden") }) {
                throw APIError.forbidden(messages.joined(separator: "\n"))
            }
            throw APIError.graphQL(messages)
        }
        guard let data = envelope.data else { throw APIError.emptyResponse }
        return data
    }

    // MARK: - Shared helpers

    static func perform(_ request: URLRequest, session: URLSession) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw APIError.emptyResponse }
            return (data, http)
        } catch let error as APIError {
            throw error
        } catch let error as URLError {
            throw APIError.transport(describe(urlError: error))
        } catch {
            if error is CancellationError { throw error }
            throw APIError.transport(error.localizedDescription)
        }
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder.axon.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(describe(error))
        }
    }

    static func error(for status: Int, data: Data) -> APIError {
        let message = serverMessage(data)
        switch status {
        case 401: return .unauthorized(message)
        case 403: return .forbidden(message)
        default: return .http(status: status, message: message)
        }
    }

    /// Extracts `error.message`, `message` or the first GraphQL error from an error body.
    static func serverMessage(_ data: Data) -> String? {
        guard !data.isEmpty, let value = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            let text = String(data: data, encoding: .utf8)?.trimmed ?? ""
            return text.isEmpty || text.count > 300 ? nil : text
        }
        if let message = value["error"]?["message"]?.stringValue { return message }
        if let message = value["error"]?.stringValue { return message }
        if let message = value["message"]?.stringValue { return message }
        if case .array(let errors)? = value["errors"], let message = errors.first?["message"]?.stringValue { return message }
        return nil
    }

    static func describe(urlError: URLError) -> String {
        switch urlError.code {
        case .notConnectedToInternet: return "网络不可用"
        case .timedOut: return "连接超时"
        case .cannotFindHost, .dnsLookupFailed: return "找不到服务器，请检查地址"
        case .cannotConnectToHost: return "无法连接到服务器"
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot:
            return "TLS 握手失败，请检查证书或改用 http://"
        case .appTransportSecurityRequiresSecureConnection: return "系统拦截了不安全的 HTTP 连接"
        case .cancelled: return "请求已取消"
        default: return urlError.localizedDescription
        }
    }

    static func describe(_ error: Error) -> String {
        guard let decodingError = error as? DecodingError else { return error.localizedDescription }
        func path(_ codingPath: [CodingKey]) -> String {
            codingPath.map { $0.intValue.map { "[\($0)]" } ?? $0.stringValue }.joined(separator: ".")
        }
        switch decodingError {
        case .keyNotFound(let key, let context):
            return "缺少字段 \(path(context.codingPath + [key]))"
        case .typeMismatch(_, let context), .valueNotFound(_, let context):
            return "字段类型不匹配 \(path(context.codingPath))"
        case .dataCorrupted(let context):
            return context.debugDescription
        @unknown default:
            return error.localizedDescription
        }
    }
}

private struct GraphQLEnvelope<T: Decodable>: Decodable {
    struct GQLError: Decodable { let message: String }

    let data: T?
    let errors: [GQLError]?

    enum CodingKeys: String, CodingKey { case data, errors }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        errors = try container.decodeIfPresent([GQLError].self, forKey: .errors)
        if let errors, !errors.isEmpty {
            data = try? container.decodeIfPresent(T.self, forKey: .data)
        } else {
            data = try container.decodeIfPresent(T.self, forKey: .data)
        }
    }
}

private struct GraphQLErrorsOnly: Decodable {
    struct GQLError: Decodable { let message: String }
    let errors: [GQLError]?
}
