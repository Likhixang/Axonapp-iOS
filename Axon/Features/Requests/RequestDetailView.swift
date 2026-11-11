import SwiftUI

struct RequestDetailView: View {
    @Environment(SessionStore.self) private var session
    let requestID: String
    @State private var state: Loadable<RequestDetail> = .idle
    @State private var payloadTab: PayloadTab = .request

    enum PayloadTab: String, CaseIterable, Identifiable {
        case request = "请求", response = "响应"
        var id: String { rawValue }
    }

    var body: some View {
        Group {
            switch state {
            case .idle, .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ErrorStateView(message: message) { await load() }
            case .loaded(let detail):
                content(detail)
            }
        }
        .navigationTitle("请求 \(GUID.short(requestID))")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        guard let service = session.service else { return }
        if state.value == nil { state = .loading }
        do {
            state = .loaded(try await service.requestDetail(id: requestID))
        } catch {
            if state.value == nil { state = .failed(error.localizedDescription) }
        }
    }

    private func content(_ detail: RequestDetail) -> some View {
        List {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(detail.modelID).font(.headline.monospaced()).textSelection(.enabled)
                        Text(Fmt.dateTime(detail.createdAt)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusBadge(detail.requestStatus)
                }
            }

            Section("概要") {
                KeyValueRow(key: "渠道", value: detail.channel?.name ?? "—")
                KeyValueRow(key: "API 密钥", value: detail.apiKey?.name ?? "—")
                KeyValueRow(key: "接口格式", value: detail.format, monospaced: true)
                KeyValueRow(key: "来源", value: detail.source)
                KeyValueRow(key: "流式", value: detail.stream ? "是" : "否")
                if let effort = detail.reasoningEffort?.nilIfBlank {
                    KeyValueRow(key: "推理强度", value: effort)
                }
                if let ip = detail.clientIP?.nilIfBlank {
                    KeyValueRow(key: "客户端 IP", value: ip, monospaced: true)
                }
                if let agent = detail.userAgent?.nilIfBlank {
                    KeyValueRow(key: "User-Agent", value: agent)
                }
                if let trace = detail.traceID?.nilIfBlank {
                    KeyValueRow(key: "Trace", value: GUID.short(trace), monospaced: true)
                }
            }

            Section("性能") {
                KeyValueRow(key: "总耗时", value: Fmt.latency(detail.metricsLatencyMs))
                KeyValueRow(key: "首 Token", value: Fmt.latency(detail.metricsFirstTokenLatencyMs))
                if let reasoning = detail.metricsReasoningDurationMs {
                    KeyValueRow(key: "推理耗时", value: Fmt.latency(reasoning))
                }
            }

            if let usage = detail.usage {
                Section("用量") {
                    KeyValueRow(key: "输入 Token", value: Fmt.grouped(usage.promptTokens))
                    KeyValueRow(key: "输出 Token", value: Fmt.grouped(usage.completionTokens))
                    if let cached = usage.promptCachedTokens, cached > 0 {
                        KeyValueRow(key: "缓存命中", value: Fmt.grouped(cached))
                    }
                    if let reasoning = usage.completionReasoningTokens, reasoning > 0 {
                        KeyValueRow(key: "推理 Token", value: Fmt.grouped(reasoning))
                    }
                    KeyValueRow(key: "合计", value: Fmt.grouped(usage.totalTokens))
                    KeyValueRow(key: "费用", value: Fmt.cost(usage.totalCost))
                }
            }

            let executions = detail.executions?.items ?? []
            if !executions.isEmpty {
                Section("上游执行 (\(executions.count))") {
                    ForEach(Array(executions.enumerated()), id: \.element.id) { index, execution in
                        NavigationLink {
                            ExecutionPayloadView(index: index + 1, execution: execution)
                        } label: {
                            ExecutionRow(index: index + 1, execution: execution)
                        }
                    }
                }
            }

            Section {
                Picker("内容", selection: $payloadTab) {
                    ForEach(PayloadTab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            } footer: {
                if detail.contentSaved == false {
                    Text("服务器没有保存这次请求的内容（AxonHub 系统设置里可以打开内容存储）。")
                }
            }

            if payloadTab == .request {
                PayloadSections(kind: .request, headers: detail.requestHeaders, payload: detail.requestBody, chunks: nil)
            } else {
                PayloadSections(kind: .response, headers: detail.responseHeaders, payload: detail.responseBody,
                                chunks: detail.responseChunks)
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await load() }
    }
}

private struct ExecutionRow: View {
    let index: Int
    let execution: RequestExecution

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("#\(index)").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                Text(execution.channel?.name ?? "未知渠道").font(.callout).lineLimit(1)
                Spacer()
                StatusBadge(execution.requestStatus)
            }
            HStack(spacing: 10) {
                Text(execution.upstreamModelID?.nilIfBlank ?? execution.modelID).font(.caption.monospaced()).lineLimit(1)
                if let code = execution.responseStatusCode, code > 0 {
                    Text("HTTP \(code)").font(.caption.monospaced())
                        .foregroundStyle(code >= 400 ? Theme.danger : .secondary)
                }
                if let latency = execution.metricsLatencyMs {
                    Text(Fmt.latency(latency)).font(.caption)
                }
            }
            .foregroundStyle(.secondary)
            if let error = execution.errorMessage?.nilIfBlank {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Theme.danger)
                    .lineLimit(4)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 2)
    }
}

