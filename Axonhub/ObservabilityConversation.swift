import SwiftUI

struct ObservabilityMessage: Identifiable {
    let id: Int
    let role: String
    let value: JSON
}

enum ObservabilityConversation {
    static func messages(_ content: JSON) -> [ObservabilityMessage] {
        var result: [ObservabilityMessage] = []
        func add(_ role: String, _ value: JSON) {
            guard !value.isNull else { return }
            result.append(ObservabilityMessage(id: result.count, role: role, value: value))
        }
        let request = content["requestBody"]
        if !request["instructions"].isNull { add("system", request["instructions"]) }
        if !request["system"].isNull { add("system", request["system"]) }
        if !request["systemInstruction"].isNull { add("system", request["systemInstruction"]) }
        for key in ["messages", "contents", "input"] {
            for message in request[key].array {
                let role = message["role"].string
                // Display the full sanitized message, including tools/thinking/multimodal parts.
                add(role.isEmpty ? message["type"].string : role, message)
            }
        }
        if !request["input"].isNull && request["input"].array.isEmpty { add("user", request["input"]) }
        if !request["prompt"].isNull { add("user", request["prompt"]) }
        let response = content["responseBody"]
        for choice in response["choices"].array {
            if !choice["message"].isNull { add("assistant", choice["message"]) }
            else if !choice["text"].isNull { add("assistant", choice["text"]) }
        }
        for output in response["output"].array { add(output["role"].string.isEmpty ? output["type"].string : output["role"].string, output) }
        if !response["content"].isNull { add("assistant", response["content"]) }
        if !response["message"].isNull { add("assistant", response["message"]) }
        for candidate in response["candidates"].array { add("assistant", candidate["content"]) }
        return result
    }
}

struct ObservabilityConversationView: View {
    let content: JSON
    private var messages: [ObservabilityMessage] { ObservabilityConversation.messages(content) }
    var body: some View {
        if !messages.isEmpty {
            DisclosureGroup(obsText("聊天历史（按保存内容）")) {
                ForEach(messages) { message in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(message.role.isEmpty ? obsText("消息") : NativeAdminLabels.value(message.role)).font(.caption.bold())
                        ObservabilityJSONView(value: message.value)
                    }.padding(10).frame(maxWidth: .infinity, alignment: .leading).liquidGlass()
                }
            }
        }
        if !content["responseChunks"].array.isEmpty {
            DisclosureGroup(obsText("流式响应分块")) {
                ForEach(Array(content["responseChunks"].array.enumerated()), id: \.offset) { index, chunk in
                    DisclosureGroup("#\(index + 1)") { ObservabilityJSONView(value: chunk) }
                }
            }
        }
    }
}

/// rawRootSegment avoids the typed SDL's finite recursion and missing newer span variants.
struct ObservabilitySegmentView: View {
    let segment: JSON
    private var segments: [ObservabilityMessage] {
        var rows: [ObservabilityMessage] = []
        func walk(_ node: JSON, depth: Int) {
            guard !node.isNull else { return }
            rows.append(ObservabilityMessage(id: rows.count, role: String(repeating: "  ", count: depth) + node["model"].string, value: node))
            for child in node["children"].array { walk(child, depth: depth + 1) }
        }
        walk(segment, depth: 0)
        return rows
    }
    var body: some View {
        if !segment.isNull {
            DisclosureGroup(obsText("追踪时间线与树")) {
                ForEach(segments) { row in
                    DisclosureGroup {
                        HStack {
                            Text(NativeDisplay.date(row.value["startTime"].string)).font(.caption2)
                            Spacer()
                            Text("\(row.value["duration"].int) ms").font(.caption).monospacedDigit()
                        }
                        ForEach(["requestSpans", "responseSpans"], id: \.self) { key in
                            ForEach(Array(row.value[key].array.enumerated()), id: \.offset) { _, span in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(NativeAdminLabels.value(span["type"].string)).font(.caption.bold())
                                    Text(NativeDisplay.date(span["startTime"].string)).font(.caption2).foregroundStyle(.secondary)
                                    ObservabilityJSONView(value: span["value"])
                                }
                            }
                        }
                        DisclosureGroup(obsText("Token 与元数据")) { ObservabilityJSONView(value: row.value["metadata"]) }
                    } label: { Text(row.role).font(.callout.monospaced()) }
                }
            }
        }
    }
}
