import Foundation

/// Turns stored request / response payloads into what the detail screens show.
enum PayloadText {
    struct HeaderLine: Hashable, Sendable {
        let name: String
        let value: String
    }

    /// AxonHub stores headers as `{"Name": ["value", ...]}` (Go's http.Header); older rows may hold
    /// plain strings or a JSON-encoded string. Returns the lines sorted by name.
    static func headerLines(_ headers: JSONValue?) -> [HeaderLine] {
        guard let headers else { return [] }
        guard case .object(let object) = JSONValue.unwrapped(headers) else { return [] }
        return object.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }.map { name in
            let value: String
            switch object[name] {
            case .array(let values)?:
                value = values.map { $0.stringValue ?? $0.compactText }.joined(separator: ", ")
            case .string(let text)?:
                value = text
            case .null?, nil:
                value = ""
            case let other?:
                value = other.compactText
            }
            return HeaderLine(name: name, value: value)
        }
    }

    /// The body to show, or nil when the server returned nothing (`{}`, `null`, `""`).
    static func body(_ payload: JSONValue?) -> JSONValue? {
        guard let payload, !payload.isEmptyPayload else { return nil }
        let unwrapped = JSONValue.unwrapped(payload)
        if unwrapped.isEmptyPayload { return nil }
        return unwrapped
    }

    /// First `lines` lines of the pretty-printed body, for an inline preview.
    static func preview(_ text: String, lines: Int = 24, maxCharacters: Int = 4_000) -> (text: String, truncated: Bool) {
        var result: [Substring] = []
        var truncated = false
        for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            if index >= lines { truncated = true; break }
            result.append(line)
        }
        var joined = result.joined(separator: "\n")
        if joined.count > maxCharacters {
            joined = String(joined.prefix(maxCharacters))
            truncated = true
        }
        return (joined, truncated)
    }

    /// Why a body is empty, in the words of AxonHub's own rules.
    static func emptyBodyReason(isResponse: Bool, status: RequestStatus) -> String {
        if isResponse, status != .completed {
            switch status {
            case .processing, .pending:
                return "请求还没完成，完成后才能看到响应体。"
            default:
                return "AxonHub 只保存成功完成的响应体，这条请求是“\(status.label)”，没有响应体；失败原因见上游执行里的报错。"
            }
        }
        return "服务器没有这条请求的\(isResponse ? "响应体" : "请求体")。开启存储前产生的请求不会补存；也请确认 AxonHub 系统设置的存储策略里勾选了“保存\(isResponse ? "响应体" : "请求体")”。"
    }
}
