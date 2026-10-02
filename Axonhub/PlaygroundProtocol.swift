import Foundation

// Contract pinned to looplj/axonhub 939b2bc07cc05bdf7750d7ec872290d67784d13d:
// frontend/src/features/playground/index.tsx, llm/transformer/aisdk/{model,convert_request,convert_stream}.go.
// Admin Playground is AI SDK UI-message SSE, NOT OpenAI chat-completions SSE.
enum PlaygroundError: Error, LocalizedError {
    case invalidInput, imageLimit, unsupportedImage, interrupted, changedInstance, streamError
    var errorDescription: String? {
        switch self {
        case .invalidInput: return NSLocalizedString("请选择模型，输入有效参数，并填写消息或添加图片。", comment: "")
        case .imageLimit: return NSLocalizedString("每张图片最多 10 MB，每次最多添加 8 张图片。", comment: "")
        case .unsupportedImage: return NSLocalizedString("仅支持可识别的图片文件。 Playground 不支持音频、视频或文档输入。", comment: "")
        case .interrupted: return NSLocalizedString("响应流提前断开，已保留部分内容。可手动重新生成（会再次消耗额度）。", comment: "")
        case .changedInstance: return NSLocalizedString("实例或项目已改变，已停止原请求。", comment: "")
        case .streamError: return NSLocalizedString("模型响应失败，已保留部分内容。请检查模型能力、参数与服务端日志。", comment: "")
        }
    }
}

struct PlaygroundImage: Identifiable, Sendable, Hashable {
    let id: UUID
    let filename: String
    let mediaType: String
    let data: Data
    init(filename: String, mediaType: String, data: Data) throws {
        guard mediaType.hasPrefix("image/"), !data.isEmpty else { throw PlaygroundError.unsupportedImage }
        guard data.count <= 10 * 1024 * 1024 else { throw PlaygroundError.imageLimit }
        self.id = UUID(); self.filename = filename; self.mediaType = mediaType; self.data = data
    }
    var dataURL: String { "data:\(mediaType);base64,\(data.base64EncodedString())" }
    var part: JSON { .object(["type": .string("file"), "mediaType": .string(mediaType),
                              "filename": .string(filename), "url": .string(dataURL)]) }
}

struct PlaygroundMessage: Identifiable, Sendable, Hashable {
    var id = UUID().uuidString
    var role: String
    var parts: [JSON]
    var incomplete = false
    var json: JSON { .object(["id": .string(id), "role": .string(role), "parts": .array(parts)]) }
    var text: String { parts.filter { $0["type"].string == "text" }.map { $0["text"].string }.joined(separator: "\n") }
    static func user(text: String, images: [PlaygroundImage]) -> PlaygroundMessage {
        var parts: [JSON] = text.isEmpty ? [] : [.object(["type": .string("text"), "text": .string(text)])]
        parts.append(contentsOf: images.map(\.part))
        return PlaygroundMessage(role: "user", parts: parts)
    }
}

struct PlaygroundParameters: Sendable {
    var model = ""
    var temperature = 0.6
    var maxTokens = 4096
    var system = NSLocalizedString("你是一个有用的助手。", comment: "")
    func payload(auth: AxonAuthType, messages: [PlaygroundMessage]) throws -> JSON {
        guard !model.isEmpty, temperature.isFinite, (0...2).contains(temperature),
              maxTokens > 0, !messages.isEmpty, messages.last?.role == "user" else { throw PlaygroundError.invalidInput }
        var body: [String: JSON] = ["model": .string(model), "temperature": .number(temperature),
                                   "max_tokens": .number(Double(maxTokens)), "stream": .bool(true)]
        if auth == .adminJWT {
            body["system"] = .string(system)
            body["messages"] = .array(messages.map(\.json))
        } else {
            var wire: [JSON] = []
            if !system.isEmpty { wire.append(.object(["role": .string("system"), "content": .string(system)])) }
            for message in messages {
                var content: [JSON] = []
                for part in message.parts {
                    switch part["type"].string {
                    case "text": content.append(.object(["type": .string("text"), "text": part["text"]]))
                    case "file" where part["mediaType"].string.hasPrefix("image/"):
                        content.append(.object(["type": .string("image_url"), "image_url": .object(["url": part["url"]])]))
                    default: break // OpenAI does not accept AI SDK reasoning/step/tool parts as content.
                    }
                }
                if !content.isEmpty { wire.append(.object(["role": .string(message.role), "content": .array(content)])) }
            }
            body["messages"] = .array(wire)
        }
        return .object(body)
    }
}

/// Incremental byte-level SSE framing. Handles LF, CRLF, CR, UTF-8 split across chunks,
/// comments, and multi-line data. Data/line bounds prevent unbounded malformed streams.
struct PlaygroundSSEParser {
    private var line = Data()
    private var dataLines: [String] = []
    private var eventSize = 0
    private var skipLF = false
    mutating func feed(_ byte: UInt8) throws -> String? {
        if skipLF { skipLF = false; if byte == 10 { return nil } }
        if byte == 13 { skipLF = true; return try endLine() }
        if byte == 10 { return try endLine() }
        guard line.count < 1024 * 1024 else { throw AxonAPIError.invalidResponse }
        line.append(byte)
        return nil
    }
    private mutating func endLine() throws -> String? {
        guard let value = String(data: line, encoding: .utf8) else { throw AxonAPIError.invalidResponse }
        line.removeAll(keepingCapacity: true)
        if value.isEmpty {
            defer { dataLines.removeAll(keepingCapacity: true); eventSize = 0 }
            return dataLines.isEmpty ? nil : dataLines.joined(separator: "\n")
        }
        if value.hasPrefix("data:") || value == "data" {
            var data = value == "data" ? "" : String(value.dropFirst(5))
            if data.hasPrefix(" ") { data.removeFirst() }
            eventSize += data.utf8.count
            guard eventSize <= 4 * 1024 * 1024 else { throw AxonAPIError.invalidResponse }
            dataLines.append(data)
        }
        return nil
    }
    mutating func finish() throws -> String? {
        if !line.isEmpty { _ = try endLine() }
        defer { dataLines.removeAll(); eventSize = 0 }
        return dataLines.isEmpty ? nil : dataLines.joined(separator: "\n")
    }
}

struct PlaygroundStreamAccumulator {
    var message = PlaygroundMessage(role: "assistant", parts: [])
    private var indexes: [String: Int] = [:]
    private(set) var complete = false
    private(set) var finishReason = ""
    private(set) var usage: JSON = .null
    private mutating func appendDelta(kind: String, id: String, delta: String, metadata: JSON = .null) {
        let key = kind + ":" + id
        let index: Int
        if let existing = indexes[key] { index = existing }
        else {
            index = message.parts.count; indexes[key] = index
            message.parts.append(.object(["type": .string(kind), "text": .string("")]))
        }
        var part = message.parts[index].object
        part["text"] = .string((part["text"]?.string ?? "") + delta)
        if !metadata.isNull { part["providerMetadata"] = metadata }
        message.parts[index] = .object(part)
    }
    mutating func consume(_ data: String, auth: AxonAuthType) throws {
        if data == "[DONE]" { complete = true; return }
        guard let event = JSON.from(data) else { throw AxonAPIError.invalidResponse }
        if !event["error"].isNull { throw PlaygroundError.streamError }
        if auth == .adminJWT {
            switch event["type"].string {
            case "start": if !event["messageId"].string.isEmpty { message.id = event["messageId"].string }
            case "text-start", "reasoning-start", "text-delta", "reasoning-delta", "text-end", "reasoning-end":
                let kind = event["type"].string.hasPrefix("reasoning") ? "reasoning" : "text"
                appendDelta(kind: kind, id: event["id"].string, delta: event["delta"].string, metadata: event["providerMetadata"])
            case "file", "source-url", "source-document": message.parts.append(event)
            case "start-step": message.parts.append(.object(["type": .string("step-start")]))
            case "finish": complete = true; finishReason = event["finishReason"].string
            case "error", "abort": throw PlaygroundError.streamError
            default: break // No client tools supplied or executed by the official Playground.
            }
        } else {
            if !event["usage"].isNull { usage = event["usage"] }
            for choice in event["choices"].array where choice["index"].int == 0 {
                let delta = choice["delta"]
                appendDelta(kind: "text", id: "0", delta: delta["content"].string)
                if !delta["reasoning_content"].isNull { appendDelta(kind: "reasoning", id: "0", delta: delta["reasoning_content"].string) }
                if !choice["finish_reason"].isNull { finishReason = choice["finish_reason"].string }
            }
            if !event["id"].string.isEmpty { message.id = event["id"].string }
        }
    }
}
