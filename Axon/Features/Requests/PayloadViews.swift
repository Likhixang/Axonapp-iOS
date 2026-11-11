import SwiftUI

/// Headers, body, readable reply and stream chunks of a request or a response, shown inline.
struct PayloadSections: View {
    enum Kind {
        case request, response
        var title: String { self == .request ? "请求" : "响应" }
    }

    let kind: Kind
    var status: RequestStatus = .completed
    let headers: JSONValue?
    let payload: JSONValue?
    let chunks: [JSONValue]?

    private var storedBody: JSONValue? { PayloadText.body(payload) }

    var body: some View {
        let bodyValue = storedBody
        let parsed = kind == .response ? ResponseParser.parse(body: payload, chunks: chunks) : ParsedResponse()
        if kind == .response, !parsed.isEmpty {
            ParsedReplySection(parsed: parsed, rebuiltFromChunks: bodyValue == nil && !(chunks ?? []).isEmpty)
        }

        if kind == .request, let messages = RequestPreview.messages(in: bodyValue), !messages.isEmpty {
            Section("对话消息 (\(messages.count))") {
                ForEach(Array(messages.enumerated()), id: \.offset) { _, message in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(message.role).font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
                        Text(message.text.count > 2_000 ? String(message.text.prefix(2_000)) + "…" : message.text)
                            .font(.callout)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 2)
                }
            }
        }

        HeadersSection(title: "\(kind.title)头", headers: headers)

        Section {
            if let bodyValue {
                BodyPreview(title: "\(kind.title)体", text: bodyValue.prettyPrinted)
            } else {
                Text(PayloadText.emptyBodyReason(isResponse: kind == .response, status: status))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let chunks, !chunks.isEmpty {
                NavigationLink {
                    JSONTextView(title: "流式分片 (\(chunks.count))",
                                 text: chunks.map { JSONValue.unwrapped($0).compactText }.joined(separator: "\n"))
                } label: {
                    LabeledContent {
                        Text("\(chunks.count) 段").font(.caption)
                    } label: {
                        Label("流式分片", systemImage: "waveform")
                    }
                }
            }
        } header: {
            Text("\(kind.title)体")
        }
    }
}

/// Header lines listed in place; long values wrap and can be selected.
private struct HeadersSection: View {
    let title: String
    let headers: JSONValue?
    @State private var showAll = false
    private static let collapsedCount = 12

    var body: some View {
        let lines = PayloadText.headerLines(headers)
        Section {
            if lines.isEmpty {
                Text("没有\(title)").font(.footnote).foregroundStyle(.secondary)
            } else {
                let visible = showAll ? lines : Array(lines.prefix(Self.collapsedCount))
                ForEach(visible, id: \.self) { line in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(line.name).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(line.value.isEmpty ? "—" : line.value)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 1)
                }
                if lines.count > Self.collapsedCount {
                    Button(showAll ? "收起" : "显示全部 \(lines.count) 项") {
                        withAnimation { showAll.toggle() }
                    }
                    .font(.footnote)
                }
            }
        } header: {
            HStack {
                Text(title)
                Spacer()
                if !lines.isEmpty, let headers {
                    Button {
                        Clipboard.copy(JSONValue.unwrapped(headers).prettyPrinted)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .font(.caption)
                    .accessibilityLabel("拷贝\(title)")
                }
            }
        }
    }
}

/// The start of a body inline, with the whole text one tap away.
private struct BodyPreview: View {
    let title: String
    let text: String

    var body: some View {
        let preview = PayloadText.preview(text)
        Text(preview.text)
            .font(.caption.monospaced())
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contextMenu {
                Button("拷贝\(title)", systemImage: "doc.on.doc") { Clipboard.copy(text) }
                ShareLink(item: text) { Label("分享", systemImage: "square.and.arrow.up") }
            }
        NavigationLink {
            JSONTextView(title: title, text: text)
        } label: {
            LabeledContent {
                Text(Fmt.bytes(text.utf8.count)).font(.caption)
            } label: {
                Label(preview.truncated ? "查看完整\(title)" : "全屏查看", systemImage: "arrow.up.left.and.arrow.down.right")
            }
        }
    }
}

private struct ParsedReplySection: View {
    let parsed: ParsedResponse
    let rebuiltFromChunks: Bool
    @State private var showReasoning = false

    var body: some View {
        Section {
            if !parsed.reasoning.isEmpty {
                DisclosureGroup(isExpanded: $showReasoning) {
                    Text(parsed.reasoning)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                } label: {
                    Label("推理过程", systemImage: "brain")
                }
            }
            if !parsed.content.isEmpty {
                Text(parsed.content.count > 20_000 ? String(parsed.content.prefix(20_000)) + "\n…（过长，完整内容见原始响应）" : parsed.content)
                    .font(.callout)
                    .textSelection(.enabled)
                    .contextMenu {
                        Button("拷贝回复", systemImage: "doc.on.doc") { Clipboard.copy(parsed.content) }
                    }
            }
            ForEach(Array(parsed.toolCalls.enumerated()), id: \.offset) { _, call in
                VStack(alignment: .leading, spacing: 4) {
                    Label(call.name, systemImage: "wrench.and.screwdriver")
                        .font(.callout.weight(.medium))
                    Text(JSONValue.unwrapped(.string(call.arguments)).prettyPrinted)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(20)
                }
            }
        } header: {
            Text("回复内容")
        } footer: {
            if rebuiltFromChunks { Text("由流式分片拼出来的完整回复。") }
        }
    }
}

/// The payloads one upstream execution sent to and got back from its channel.
struct ExecutionPayloadView: View {
    @Environment(SessionStore.self) private var session
    let index: Int
    let execution: RequestExecution
    @State private var state: Loadable<ExecutionPayload> = .idle
    @State private var tab: PayloadSections.Kind = .response

    var body: some View {
        Group {
            switch state {
            case .idle, .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ErrorStateView(message: message) { await load() }
            case .loaded(let payload):
                List {
                    Section {
                        KeyValueRow(key: "渠道", value: execution.channel?.name ?? "—")
                        KeyValueRow(key: "上游模型", value: execution.upstreamModelID?.nilIfBlank ?? execution.modelID, monospaced: true)
                        if let url = execution.requestURL?.nilIfBlank {
                            KeyValueRow(key: "上游地址", value: url, monospaced: true)
                        }
                        if let code = execution.responseStatusCode, code > 0 {
                            KeyValueRow(key: "HTTP 状态", value: String(code), monospaced: true)
                        }
                        KeyValueRow(key: "耗时", value: Fmt.latency(execution.metricsLatencyMs))
                        if let error = execution.errorMessage?.nilIfBlank {
                            Text(error).font(.caption).foregroundStyle(Theme.danger).textSelection(.enabled)
                        }
                    }
                    Section {
                        Picker("内容", selection: $tab) {
                            Text("发给上游").tag(PayloadSections.Kind.request)
                            Text("上游返回").tag(PayloadSections.Kind.response)
                        }
                        .pickerStyle(.segmented)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                    }
                    if tab == .request {
                        PayloadSections(kind: .request, status: execution.requestStatus,
                                        headers: payload.requestHeaders, payload: payload.requestBody, chunks: nil)
                    } else {
                        PayloadSections(kind: .response, status: execution.requestStatus,
                                        headers: payload.responseHeaders, payload: payload.responseBody,
                                        chunks: payload.responseChunks)
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable { await load() }
            }
        }
        .navigationTitle("上游执行 #\(index)")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        guard let service = session.service else { return }
        if state.value == nil { state = .loading }
        do {
            state = .loaded(try await service.executionPayload(id: execution.id))
        } catch {
            if state.value == nil { state = .failed(error.localizedDescription) }
        }
    }
}

/// Full-screen viewer for long JSON / text, rendered in slices so large bodies stay smooth.
struct JSONTextView: View {
    let title: String
    let text: String
    @State private var wrap = true

    private static let limit = 1_000_000

    private var slices: [String] {
        let source = text.count > Self.limit ? String(text.prefix(Self.limit)) + "\n…（内容过长已截断，可用右上角分享导出完整内容）" : text
        var result: [String] = []
        var current: [Substring] = []
        for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
            current.append(line)
            if current.count == 80 {
                result.append(current.joined(separator: "\n"))
                current.removeAll(keepingCapacity: true)
            }
        }
        if !current.isEmpty { result.append(current.joined(separator: "\n")) }
        return result
    }

    var body: some View {
        ScrollView(wrap ? .vertical : [.vertical, .horizontal]) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(slices.enumerated()), id: \.offset) { _, slice in
                    Text(slice)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: wrap ? .infinity : nil, alignment: .leading)
                }
            }
            .padding()
        }
        .background(Color(.systemBackground))
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { wrap.toggle() } label: {
                    Image(systemName: wrap ? "text.alignleft" : "arrow.left.and.right.text.vertical")
                }
                Button { Clipboard.copy(text) } label: { Image(systemName: "doc.on.doc") }
                ShareLink(item: text) { Image(systemName: "square.and.arrow.up") }
            }
        }
    }
}
