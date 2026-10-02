import Foundation

struct PlaygroundChoice: Identifiable, Sendable, Hashable {
    let id: String
    let name: String
}
struct PlaygroundChannel: Identifiable, Sendable, Hashable {
    let id: String
    let name: String
    let models: [PlaygroundChoice]
}
struct PlaygroundIdentity: Sendable {
    var projects: [PlaygroundChoice] = []
    var canUseGateway = false
}
struct PlaygroundCatalog: Sendable {
    var channels: [PlaygroundChannel] = []
    var models: [PlaygroundChoice] = []
}

/// Own ephemeral transport: no disk cache, cookies, credential storage or redirects.
/// Receives credentials exclusively from AxonStore.ensureClient(), never saves keys.
final class PlaygroundService: @unchecked Sendable {
    private let session: URLSession
    init(configuration: URLSessionConfiguration = .ephemeral) {
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 90
        configuration.timeoutIntervalForResource = 600
        session = URLSession(configuration: configuration, delegate: NoRedirectDelegate(), delegateQueue: nil)
    }
    deinit { session.invalidateAndCancel() }

    static let identityQuery = """
    query PlaygroundIdentity {
      me { isOwner scopes }
      myProjects { id name status }
    }
    """
    static let channelQuery = """
    query PlaygroundChannels {
      allChannelSummarys(includeArchived: false) {
        id name allModelEntries { requestModel }
      }
    }
    """
    static let modelQuery = """
    query PlaygroundModels($after: Cursor) {
      models(first: 200, after: $after, orderBy: { field: NAME, direction: ASC },
        where: { statusIn: [enabled], typeIn: [chat] }) {
        edges { node { modelID name } }
        pageInfo { hasNextPage endCursor }
      }
    }
    """

    static func request(client: AxonClient, path: String, method: String,
                        project: String = "", channel: String = "", payload: JSON? = nil) throws -> URLRequest {
        guard !client.token.isEmpty else { throw AxonAPIError.invalidCredentials }
        var request = URLRequest(url: AxonClient.endpoint(baseURL: client.baseURL, path: path))
        request.httpMethod = method
        request.setValue("Bearer \(client.token)", forHTTPHeaderField: "Authorization")
        if client.authType == .adminJWT {
            if !project.isEmpty { request.setValue(project, forHTTPHeaderField: "X-Project-ID") }
            if !channel.isEmpty { request.setValue(channel, forHTTPHeaderField: "X-Channel-ID") }
        } else if !project.isEmpty || !channel.isEmpty { throw AxonAPIError.forbidden }
        if let payload = payload {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(payload)
        }
        return request
    }
    private func status(_ response: URLResponse) throws -> HTTPURLResponse {
        guard let http = response as? HTTPURLResponse else { throw AxonAPIError.invalidResponse }
        if http.statusCode == 401 { throw AxonAPIError.unauthorized }
        if http.statusCode == 403 { throw AxonAPIError.forbidden }
        guard (200...299).contains(http.statusCode) else { throw AxonAPIError.httpStatus(http.statusCode) }
        return http
    }
    private func fetch(_ request: URLRequest) async throws -> JSON {
        let (data, response) = try await session.data(for: request)
        _ = try status(response)
        try Task.checkCancellation()
        guard let json = try? JSONDecoder().decode(JSON.self, from: data) else { throw AxonAPIError.invalidResponse }
        return json
    }
    private func graphql(client: AxonClient, query: String, project: String = "", variables: JSON = .object([:])) async throws -> JSON {
        guard client.authType == .adminJWT else { throw AxonAPIError.forbidden }
        let result = try await fetch(Self.request(client: client, path: "admin/graphql", method: "POST", project: project,
            payload: .object(["query": .string(query), "variables": variables])))
        guard result["errors"].array.isEmpty, !result["data"].isNull else { throw AxonAPIError.invalidResponse }
        return result["data"]
    }
    func identity(client: AxonClient) async throws -> PlaygroundIdentity {
        guard client.authType == .adminJWT else { return PlaygroundIdentity() }
        let data = try await graphql(client: client, query: Self.identityQuery)
        let scopes = data["me"]["scopes"].array.map(\.string)
        return PlaygroundIdentity(projects: data["myProjects"].array.filter { $0["status"].string == "active" }.map {
            PlaygroundChoice(id: $0["id"].string, name: $0["name"].string)
        }, canUseGateway: data["me"]["isOwner"].bool || scopes.contains("*") || scopes.contains("read_channels"))
    }
    private static func unique(_ choices: [PlaygroundChoice]) -> [PlaygroundChoice] {
        var seen = Set<String>()
        return choices.filter { !$0.id.isEmpty && seen.insert($0.id).inserted }
    }
    func catalog(client: AxonClient, project: String, canUseGateway: Bool) async throws -> PlaygroundCatalog {
        if client.authType == .apiKey {
            let result = try await fetch(Self.request(client: client, path: "v1/models", method: "GET"))
            guard case .array = result["data"] else { throw AxonAPIError.invalidResponse }
            return PlaygroundCatalog(models: Self.unique(result["data"].array.map { PlaygroundChoice(id: $0["id"].string, name: $0["id"].string) }))
        }
        let data = try await graphql(client: client, query: Self.channelQuery, project: project)
        let channels = data["allChannelSummarys"].array.compactMap { node -> PlaygroundChannel? in
            let models = Self.unique(node["allModelEntries"].array.map { PlaygroundChoice(id: $0["requestModel"].string, name: $0["requestModel"].string) })
            guard !models.isEmpty else { return nil }
            return PlaygroundChannel(id: node["id"].string, name: node["name"].string, models: models)
        }
        var models: [PlaygroundChoice] = []
        if canUseGateway {
            var cursor: JSON = .null
            var seen = Set<String>()
            repeat {
                let page = try await graphql(client: client, query: Self.modelQuery, project: project, variables: .object(["after": cursor]))
                models.append(contentsOf: page["models"]["edges"].array.map {
                    let node = $0["node"]
                    return PlaygroundChoice(id: node["modelID"].string, name: node["name"].string.isEmpty ? node["modelID"].string : node["name"].string)
                })
                if !page["models"]["pageInfo"]["hasNextPage"].bool { break }
                cursor = page["models"]["pageInfo"]["endCursor"]
                guard !cursor.string.isEmpty, seen.insert(cursor.string).inserted else { throw AxonAPIError.invalidResponse }
            } while true
        }
        return PlaygroundCatalog(channels: channels, models: Self.unique(models))
    }

    static func chatRequest(client: AxonClient, parameters: PlaygroundParameters, messages: [PlaygroundMessage],
                            project: String = "", channel: String = "") throws -> URLRequest {
        let path = client.authType == .adminJWT ? "admin/playground/chat" : "v1/chat/completions"
        var request = try Self.request(client: client, path: path, method: "POST", project: project, channel: channel,
                                      payload: parameters.payload(auth: client.authType, messages: messages))
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        return request
    }
    /// Only called by an explicit user send/regenerate action. No automatic retry.
    func stream(client: AxonClient, parameters: PlaygroundParameters, messages: [PlaygroundMessage],
                project: String, channel: String,
                update: @MainActor @Sendable (PlaygroundStreamAccumulator) throws -> Void) async throws {
        let request = try Self.chatRequest(client: client, parameters: parameters, messages: messages, project: project, channel: channel)
        let (bytes, response) = try await session.bytes(for: request)
        defer { bytes.task.cancel() } // Also close the connection on finish, cancellation or malformed SSE.
        let http = try status(response)
        guard http.value(forHTTPHeaderField: "Content-Type")?.lowercased().contains("text/event-stream") == true else {
            throw AxonAPIError.invalidResponse
        }
        var parser = PlaygroundSSEParser()
        var result = PlaygroundStreamAccumulator()
        var lastPublish = Date.distantPast
        for try await byte in bytes {
            try Task.checkCancellation()
            if let event = try parser.feed(byte) {
                try result.consume(event, auth: client.authType)
                // At most 30 native view updates/sec; publish completion regardless.
                if result.complete || Date().timeIntervalSince(lastPublish) >= 1.0 / 30.0 {
                    try await update(result); lastPublish = Date()
                }
                // Admin finish is terminal; OpenAI usage can follow finish_reason before DONE.
                if result.complete { break }
            }
        }
        if !result.complete, let event = try parser.finish() { try result.consume(event, auth: client.authType) }
        try await update(result)
        guard result.complete else { throw PlaygroundError.interrupted }
    }
}
