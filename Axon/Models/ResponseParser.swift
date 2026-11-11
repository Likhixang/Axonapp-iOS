import Foundation

/// The readable part of a model response: the reply text, the reasoning, and tool calls.
struct ParsedResponse: Hashable, Sendable {
    struct ToolCall: Hashable, Sendable {
        var id: String?
        var name: String
        var arguments: String
    }

    var content = ""
    var reasoning = ""
    var toolCalls: [ToolCall] = []

    var isEmpty: Bool { content.isEmpty && reasoning.isEmpty && toolCalls.isEmpty }
}

/// Port of the console's `utils/response-parser.ts`: understands OpenAI chat / completions /
/// Responses API, Anthropic, Gemini and AxonHub (AI SDK) bodies, and rebuilds a streamed reply
/// from the stored `responseChunks` when the body itself is empty.
enum ResponseParser {
    static func parse(body: JSONValue?, chunks: [JSONValue]?) -> ParsedResponse {
        var result = ParsedResponse()
        if let body = body.map(JSONValue.unwrapped), !body.isEmptyPayload {
            parseBody(body, into: &result)
        }
        if result.isEmpty, let chunks, !chunks.isEmpty {
            parseChunks(chunks.map(JSONValue.unwrapped), into: &result)
        }
        return result
    }

    // MARK: - Final bodies

    private static func parseBody(_ body: JSONValue, into r: inout ParsedResponse) {
        if case .string(let text) = body {
            r.content = text
            return
        }

        // AxonHub / AI SDK `parts`
        if case .array(let parts)? = body["parts"] {
            for part in parts {
                switch part["type"]?.stringValue {
                case "text": r.content += part["text"]?.stringValue ?? ""
                case "reasoning": r.reasoning += part["text"]?.stringValue ?? ""
                default: break
                }
            }
        }

        // OpenAI chat message, or an Anthropic message (role + content)
        var message: JSONValue?
        if case .array(let choices)? = body["choices"], let first = choices.first, let m = first["message"], m != .null {
            message = m
        } else if body["role"] != nil, let content = body["content"], content != .null {
            message = body
        }
        if let message {
            switch message["content"] {
            case .array(let parts)?:
                for part in parts {
                    let type = part["type"]?.stringValue ?? ""
                    if type == "text" {
                        r.content += part["text"]?.stringValue ?? ""
                    } else if type == "thinking" {
                        r.reasoning += part["thinking"]?.stringValue ?? ""
                    } else if type == "reasoning" {
                        r.reasoning += part["text"]?.stringValue ?? part["reasoning"]?.stringValue ?? ""
                    } else if type == "tool_use" || type.hasSuffix("_tool_use") {
                        r.toolCalls.append(.init(id: part["id"]?.stringValue,
                                                 name: part["name"]?.stringValue ?? "unknown",
                                                 arguments: argumentsText(part["input"])))
                    }
                }
            case .string(let text)?:
                if r.content.isEmpty { r.content = text }
            default:
                break
            }
            if r.reasoning.isEmpty, let reasoning = message["reasoning_content"]?.stringValue {
                r.reasoning = reasoning
            }
            if case .array(let calls)? = message["tool_calls"] {
                r.toolCalls = calls.map { call in
                    .init(id: call["id"]?.stringValue,
                          name: call["function"]?["name"]?.stringValue ?? "unknown",
                          arguments: argumentsText(call["function"]?["arguments"]))
                }
            }
        }

        // Gemini
        if r.content.isEmpty, r.reasoning.isEmpty, case .array(let candidates)? = body["candidates"],
           let first = candidates.first, case .array(let parts)? = first["content"]?["parts"] {
            for part in parts {
                if part["thought"]?.boolValue == true {
                    r.reasoning += part["text"]?.stringValue ?? ""
                } else {
                    r.content += part["text"]?.stringValue ?? ""
                }
            }
        }

        // OpenAI Responses API
        let output = body["output"] ?? body["response"]?["output"]
        if r.isEmpty, case .array(let items)? = output {
            for item in items {
                switch item["type"]?.stringValue {
                case "reasoning":
                    if case .array(let summary)? = item["summary"] {
                        for s in summary where s["type"]?.stringValue == "summary_text" {
                            r.reasoning += s["text"]?.stringValue ?? ""
                        }
                    }
                case "message":
                    if case .array(let content)? = item["content"] {
                        for c in content where c["type"]?.stringValue == "output_text" {
                            r.content += c["text"]?.stringValue ?? ""
                        }
                    }
                case "function_call":
                    r.toolCalls.append(.init(id: item["call_id"]?.stringValue ?? item["id"]?.stringValue,
                                             name: item["name"]?.stringValue ?? "unknown",
                                             arguments: item["arguments"]?.stringValue ?? "{}"))
                default:
                    break
                }
            }
        }

        // Legacy completions
        if r.content.isEmpty, case .array(let choices)? = body["choices"], let text = choices.first?["text"]?.stringValue {
            r.content = text
        }

        if r.content.isEmpty, let text = body["content"]?.stringValue {
            r.content = text
        }
    }

    // MARK: - Streaming chunks

    private struct Block { var type: String; var content = ""; var id: String?; var name: String? }

    private static func parseChunks(_ chunks: [JSONValue], into r: inout ParsedResponse) {
        var openAITools: [Int: ParsedResponse.ToolCall] = [:]
        var anthropicBlocks: [Int: Block] = [:]
        var isAnthropic = false
        var responsesTools: [(key: String, call: ParsedResponse.ToolCall)] = []
        var geminiTools: [(key: String, call: ParsedResponse.ToolCall)] = []

        for chunk in chunks {
            if case .string(let text) = chunk {
                r.content += text
                continue
            }
            let data: JSONValue = {
                if let d = chunk["data"], d != .null { return JSONValue.unwrapped(d) }
                return chunk
            }()
            let event = chunk["event"]?.stringValue
            let eventType = data["type"]?.stringValue ?? event ?? ""

            if eventType.hasPrefix("response.") {
                switch eventType {
                case "response.reasoning_summary_text.delta":
                    r.reasoning += data["delta"]?.stringValue ?? ""
                case "response.output_text.delta":
                    r.content += data["delta"]?.stringValue ?? ""
                case "response.function_call_arguments.delta":
                    let itemID = data["item_id"]?.stringValue ?? ""
                    if let index = responsesTools.firstIndex(where: { $0.key == itemID }) {
                        responsesTools[index].call.arguments += data["delta"]?.stringValue ?? ""
                    }
                case "response.output_item.added":
                    if let item = data["item"], item["type"]?.stringValue == "function_call" {
                        let key = item["id"]?.stringValue ?? item["call_id"]?.stringValue ?? ""
                        responsesTools.append((key, .init(id: item["call_id"]?.stringValue ?? item["id"]?.stringValue,
                                                          name: item["name"]?.stringValue ?? "unknown",
                                                          arguments: item["arguments"]?.stringValue ?? "")))
                    }
                default:
                    break
                }
                continue
            }

            switch eventType {
            case "message_start", "content_block_stop", "message_delta", "message_stop":
                isAnthropic = true
                continue
            case "content_block_start":
                isAnthropic = true
                let index = data["index"]?.intValue ?? 0
                let block = data["content_block"]
                anthropicBlocks[index] = Block(type: block?["type"]?.stringValue ?? "text",
                                               id: block?["id"]?.stringValue, name: block?["name"]?.stringValue)
                continue
            case "content_block_delta":
                isAnthropic = true
                let index = data["index"]?.intValue ?? 0
                let delta = data["delta"]
                let deltaType = delta?["type"]?.stringValue ?? ""
                if anthropicBlocks[index] == nil {
                    let type = deltaType == "thinking_delta" ? "thinking" : deltaType == "input_json_delta" ? "tool_use" : "text"
                    anthropicBlocks[index] = Block(type: type)
                }
                switch deltaType {
                case "thinking_delta": anthropicBlocks[index]?.content += delta?["thinking"]?.stringValue ?? ""
                case "text_delta": anthropicBlocks[index]?.content += delta?["text"]?.stringValue ?? ""
                case "input_json_delta": anthropicBlocks[index]?.content += delta?["partial_json"]?.stringValue ?? ""
                default: break
                }
                continue
            default:
                break
            }

            if data["type"]?.stringValue == "text-delta", let delta = data["delta"]?.stringValue {
                r.content += delta
            } else if data["type"]?.stringValue == "reasoning-delta", let delta = data["delta"]?.stringValue {
                r.reasoning += delta
            } else if case .array(let choices)? = data["choices"], let first = choices.first, let delta = first["delta"], delta != .null {
                r.content += delta["content"]?.stringValue ?? ""
                r.reasoning += delta["reasoning_content"]?.stringValue ?? ""
                if case .array(let calls)? = delta["tool_calls"] {
                    for call in calls {
                        let index = call["index"]?.intValue ?? 0
                        let name = call["function"]?["name"]?.stringValue
                        let args = call["function"]?["arguments"]?.stringValue
                        if var existing = openAITools[index] {
                            if let id = call["id"]?.stringValue { existing.id = id }
                            if let name, !name.isEmpty { existing.name = name }
                            if let args { existing.arguments += args }
                            openAITools[index] = existing
                        } else {
                            openAITools[index] = .init(id: call["id"]?.stringValue, name: name ?? "", arguments: args ?? "")
                        }
                    }
                }
            } else if case .array(let choices)? = data["choices"], let text = choices.first?["text"]?.stringValue {
                r.content += text
            } else if case .array(let candidates)? = data["candidates"], let first = candidates.first {
                if case .array(let parts)? = first["content"]?["parts"] {
                    for (index, part) in parts.enumerated() {
                        if let text = part["text"]?.stringValue, !text.isEmpty {
                            if part["thought"]?.boolValue == true { r.reasoning += text } else { r.content += text }
                        } else if let call = part["functionCall"] {
                            let name = call["name"]?.stringValue ?? "unknown"
                            let key = "\(name)_\(index)"
                            let tool = ParsedResponse.ToolCall(id: key, name: name, arguments: argumentsText(call["args"]))
                            if let existing = geminiTools.firstIndex(where: { $0.key == key }) {
                                geminiTools[existing].call = tool
                            } else {
                                geminiTools.append((key, tool))
                            }
                        }
                    }
                }
            }
        }

        r.toolCalls.append(contentsOf: responsesTools.map(\.call))
        r.toolCalls.append(contentsOf: geminiTools.map(\.call))
        if isAnthropic {
            for index in anthropicBlocks.keys.sorted() {
                guard let block = anthropicBlocks[index] else { continue }
                if block.type == "thinking" {
                    r.reasoning += block.content
                } else if block.type == "text" {
                    r.content += block.content
                } else if block.type == "tool_use" || block.type.hasSuffix("_tool_use") {
                    r.toolCalls.append(.init(id: block.id, name: block.name ?? "unknown", arguments: block.content))
                }
            }
        }
        if !openAITools.isEmpty, r.toolCalls.isEmpty {
            r.toolCalls = openAITools.keys.sorted().compactMap { openAITools[$0] }
        }
    }

    private static func argumentsText(_ value: JSONValue?) -> String {
        guard let value, value != .null else { return "{}" }
        if case .string(let text) = value { return text }
        guard let data = try? JSONEncoder().encode(value), let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }
}

extension JSONValue {
    var intValue: Int? {
        if case .number(let value) = self { return Int(value) }
        if case .string(let value) = self { return Int(value) }
        return nil
    }

    /// A JSON document that was stored as a string (`"{\"a\":1}"`) is parsed into its tree;
    /// anything else is returned unchanged.
    static func unwrapped(_ value: JSONValue) -> JSONValue {
        guard case .string(let text) = value else { return value }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first, first == "{" || first == "[",
              let data = trimmed.data(using: .utf8),
              let parsed = try? JSONDecoder().decode(JSONValue.self, from: data) else { return value }
        return parsed
    }
}

/// Extracts chat messages from common request bodies (OpenAI, Anthropic, Gemini, Responses API).
enum RequestPreview {
    struct Message { let role: String; let text: String }

    static func messages(in body: JSONValue?) -> [Message]? {
        guard let body else { return nil }
        var result: [Message] = []
        if let system = body["system"] {
            let text = text(of: system)
            if !text.isEmpty { result.append(Message(role: "system", text: text)) }
        }
        if let instructions = body["instructions"]?.stringValue, !instructions.isEmpty {
            result.append(Message(role: "instructions", text: instructions))
        }
        if case .array(let messages)? = body["messages"] {
            for m in messages {
                result.append(Message(role: m["role"]?.stringValue ?? "?", text: text(of: m["content"])))
            }
        } else if case .array(let contents)? = body["contents"] {
            for c in contents {
                result.append(Message(role: c["role"]?.stringValue ?? "user", text: text(of: c["parts"])))
            }
        } else if let input = body["input"] {
            if case .string(let text) = input {
                result.append(Message(role: "user", text: text))
            } else if case .array(let items) = input {
                for item in items {
                    let role = item["role"]?.stringValue ?? item["type"]?.stringValue ?? "?"
                    let content = item["content"] ?? item["output"] ?? item["arguments"]
                    result.append(Message(role: role, text: text(of: content)))
                }
            }
        } else if let prompt = body["prompt"] {
            result.append(Message(role: "prompt", text: text(of: prompt)))
        }
        return result
    }

    private static func text(of value: JSONValue?) -> String {
        guard let value else { return "" }
        switch value {
        case .string(let text): return text
        case .array(let parts):
            return parts.map { part -> String in
                if case .string(let text) = part { return text }
                if let text = part["text"]?.stringValue { return text }
                if let thinking = part["thinking"]?.stringValue { return "〔思考〕" + thinking }
                let type = part["type"]?.stringValue ?? ""
                if type.contains("image") || part["inlineData"] != nil { return "〔图片〕" }
                if type == "tool_use" || type == "function_call" { return "〔调用工具 \(part["name"]?.stringValue ?? "")〕" }
                if type == "tool_result" || type == "function_call_output" { return "〔工具结果〕 " + text(of: part["content"] ?? part["output"]) }
                if let call = part["functionCall"] { return "〔调用工具 \(call["name"]?.stringValue ?? "")〕" }
                return type.isEmpty ? "" : "〔\(type)〕"
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        case .null: return ""
        default: return value.prettyPrinted
        }
    }
}

extension JSONValue {
    /// Single-line JSON (used for stream chunks, one per line).
    var compactText: String {
        if case .string(let text) = self { return text }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(self), let text = String(data: data, encoding: .utf8) else { return "" }
        return text
    }
}
