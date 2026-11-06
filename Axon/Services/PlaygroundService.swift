import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A chat turn sent to `POST /admin/playground/chat` (Vercel AI SDK UI-message format).
struct ChatTurn: Sendable, Equatable {
    enum Role: String, Sendable { case user, assistant }
    let role: Role
    let text: String
}

struct PlaygroundOptions: Sendable, Equatable {
    var model: String
    var systemPrompt: String = ""
    var temperature: Double?
    var maxTokens: Int?
    var channelID: Int?
}

enum StreamChunk: Sendable, Equatable {
    case text(String)
    case reasoning(String)
    case finish(reason: String?)
}

/// Parses AxonHub's playground stream: SSE frames carrying AI SDK UI-message chunks
/// (`text-delta`, `reasoning-delta`, `error`, `finish`) and `[DONE]`.
struct UIMessageStreamParser {
    private var eventName: String?
    private var dataLines: [String] = []

    /// Feeds one line (without trailing newline). Returns chunks completed by this line.
    mutating func feed(_ rawLine: String) throws -> [StreamChunk] {
        let line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : rawLine
        if line.isEmpty { return try flush() }
        if line.hasPrefix(":") { return [] }
        let (field, value) = Self.split(line)
        switch field {
        case "event": eventName = value
        case "data": dataLines.append(value)
        default: break
        }
        return []
    }

    mutating func finish() throws -> [StreamChunk] { try flush() }

    /// Splits text into lines. `\r\n` is a single `Character` in Swift, so split on `isNewline`.
    static func lines(_ text: String) -> [String] {
        text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
    }

    private static func split(_ line: String) -> (String, String) {
        guard let colon = line.firstIndex(of: ":") else { return (line, "") }
        let field = String(line[..<colon])
        var value = String(line[line.index(after: colon)...])
        if value.hasPrefix(" ") { value.removeFirst() }
        return (field, value)
    }

    private mutating func flush() throws -> [StreamChunk] {
        defer { eventName = nil; dataLines = [] }
        guard !dataLines.isEmpty else { return [] }
        let payload = dataLines.joined(separator: "\n")
        if payload == "[DONE]" { return [.finish(reason: nil)] }
        guard let data = payload.data(using: .utf8),
              let json = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            if eventName == "error" { throw APIError.transport(payload) }
            return []
        }
        if eventName == "error" {
            throw APIError.transport(Self.errorMessage(json) ?? payload)
        }
        switch json["type"]?.stringValue {
        case "text-delta":
            return [.text(json["delta"]?.stringValue ?? json["textDelta"]?.stringValue ?? "")]
        case "reasoning-delta":
            return [.reasoning(json["delta"]?.stringValue ?? "")]
        case "error":
            throw APIError.transport(json["errorText"]?.stringValue ?? Self.errorMessage(json) ?? "流式响应出错")
        case "finish":
            return [.finish(reason: json["finishReason"]?.stringValue)]
        default:
            if let message = Self.errorMessage(json) { throw APIError.transport(message) }
            return []
        }
    }

    private static func errorMessage(_ json: JSONValue) -> String? {
        json["error"]?["message"]?.stringValue ?? json["error"]?.stringValue ?? json["message"]?.stringValue
    }
}

struct PlaygroundService: Sendable {
    let client: APIClient

    static func body(turns: [ChatTurn], options: PlaygroundOptions) -> JSONValue {
        let messages: [JSONValue] = turns.enumerated().map { index, turn in
            [
                "id": .string("m\(index)"),
                "role": .string(turn.role.rawValue),
                "parts": [["type": "text", "text": .string(turn.text)]],
            ]
        }
        var body: [String: JSONValue] = [
            "model": .string(options.model),
            "messages": .array(messages),
            "stream": true,
        ]
        if let system = options.systemPrompt.nilIfBlank { body["system"] = .string(system) }
        if let temperature = options.temperature { body["temperature"] = .number(temperature) }
        if let maxTokens = options.maxTokens { body["max_tokens"] = .int(maxTokens) }
        return .object(body)
    }

    func stream(turns: [ChatTurn], options: PlaygroundOptions) -> AsyncThrowingStream<StreamChunk, Error> {
        let client = client
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let data = try JSONEncoder().encode(Self.body(turns: turns, options: options))
                    func makeRequest() -> URLRequest {
                        var request = client.authorizedRequest("admin/playground/chat", method: "POST", body: data)
                        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                        request.timeoutInterval = 300
                        if let channel = options.channelID {
                            request.setValue(String(channel), forHTTPHeaderField: "X-Channel-ID")
                        }
                        return request
                    }
                    try await Self.run(makeRequest(), client: client, continuation: continuation, allowRefresh: true, retry: makeRequest)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    #if canImport(FoundationNetworking)
    private static func run(_ request: URLRequest, client: APIClient, continuation: AsyncThrowingStream<StreamChunk, Error>.Continuation,
                            allowRefresh: Bool, retry: () -> URLRequest) async throws {
        // Linux test builds: no streaming bytes API, read the whole body.
        let (data, response) = try await APIClient.perform(request, session: client.session)
        guard (200..<300).contains(response.statusCode) else { throw APIClient.error(for: response.statusCode, data: data) }
        var parser = UIMessageStreamParser()
        for line in UIMessageStreamParser.lines(String(decoding: data, as: UTF8.self)) {
            for chunk in try parser.feed(line) { continuation.yield(chunk) }
        }
        for chunk in try parser.finish() { continuation.yield(chunk) }
    }
    #else
    private static func run(_ request: URLRequest, client: APIClient, continuation: AsyncThrowingStream<StreamChunk, Error>.Continuation,
                            allowRefresh: Bool, retry: () -> URLRequest) async throws {
        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await client.session.bytes(for: request)
        } catch let error as URLError {
            throw APIError.transport(APIClient.describe(urlError: error))
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.emptyResponse }
        if http.statusCode == 401, allowRefresh, try await client.refreshToken() {
            try await run(retry(), client: client, continuation: continuation, allowRefresh: false, retry: retry)
            return
        }
        guard (200..<300).contains(http.statusCode) else {
            var data = Data()
            for try await byte in bytes {
                data.append(byte)
                if data.count > 64 * 1024 { break }
            }
            if http.statusCode == 401 { client.onUnauthorized?() }
            throw APIClient.error(for: http.statusCode, data: data)
        }

        var parser = UIMessageStreamParser()
        var buffer = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            if byte == UInt8(ascii: "\n") {
                let line = String(decoding: buffer, as: UTF8.self)
                buffer.removeAll(keepingCapacity: true)
                for chunk in try parser.feed(line) { continuation.yield(chunk) }
            } else {
                buffer.append(byte)
            }
        }
        if !buffer.isEmpty {
            for chunk in try parser.feed(String(decoding: buffer, as: UTF8.self)) { continuation.yield(chunk) }
        }
        for chunk in try parser.finish() { continuation.yield(chunk) }
    }
    #endif
}
