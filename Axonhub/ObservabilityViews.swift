import SwiftUI

struct ObservabilityCenterView: View {
    @ObservedObject var store: AxonStore
    var body: some View {
        List {
            Section(obsText("审计与历史")) {
                ForEach(ObservabilityKind.allCases) { kind in
                    NavigationLink(kind.title) { ObservabilityListView(store: store, kind: kind) }
                }
                NavigationLink(obsText("聊天历史")) {
                    ObservabilityListView(store: store, kind: .threads, chatHistory: true)
                }
            }
            Section(obsText("分析")) {
                NavigationLink(obsText("多维用量分析")) { ObservabilityAnalyticsView(store: store) }
                NavigationLink(obsText("渠道成功率与性能")) { ObservabilityDashboardView(store: store) }
            }
        }
        .navigationTitle(obsText("可观测性"))
    }
}

struct ObservabilityListView: View {
    @ObservedObject var store: AxonStore
    let kind: ObservabilityKind
    var chatHistory = false
    @StateObject private var model = ObservabilityListModel()
    @State private var filters = ObservabilityFilters()
    @State private var showFilters = false

    var body: some View {
        List {
            Section {
                if model.session.busy { ProgressView(obsText("正在读取服务器数据")) }
                if let error = model.session.error ?? model.filterError { ObservabilityErrorView(message: error) }
                if let total = model.total { Text(String(format: obsText("共 %lld 条 · 第 %lld 页"), Int64(total), Int64(model.page + 1))).monospacedDigit() }
                if model.records.isEmpty && !model.session.busy && model.total != nil {
                    Text(obsText("没有符合条件的记录")).foregroundStyle(.secondary)
                }
                ForEach(model.session.invalidated ? [] : model.records) { record in
                    NavigationLink {
                        ObservabilityDetailView(store: store, kind: kind, id: record.id, origin: model.session)
                    } label: { ObservabilityRecordRow(record: record) }
                }
            }
            if model.total != nil {
                Section {
                    HStack {
                        Button(obsText("上一页")) { Task { await load(-1) } }.disabled(model.page == 0)
                        Spacer()
                        Button(obsText("下一页")) { Task { await load(1) } }.disabled(model.next == nil)
                    }.disabled(model.session.busy || model.session.invalidated)
                }
            }
        }
        .navigationTitle(chatHistory ? obsText("聊天历史") : kind.title)
        .searchable(text: $filters.search, prompt: obsText("模型或追踪/线程 ID"))
        .onSubmit(of: .search) { Task { await load() } }
        .toolbar {
            Button { showFilters = true } label: { Label(obsText("筛选"), systemImage: "line.3.horizontal.decrease.circle") }
                .disabled(model.session.invalidated)
            Button { store.pageCache.invalidate(); Task { await load() } } label: { Label(obsText("刷新"), systemImage: "arrow.clockwise") }
                .disabled(model.session.busy || model.session.invalidated)
        }
        .sheet(isPresented: $showFilters) {
            ObservabilityFilterView(store: store, kind: kind, filters: $filters) {
                showFilters = false
                Task { await load() }
            }
        }
        .task {
            guard model.session.instance == nil else { return }
            do { try model.session.bind(store); await load() }
            catch { model.session.error = error.localizedDescription }
        }
        .refreshable { store.pageCache.invalidate(); await load() }
        .onChange(of: store.selectedInstance) { _ in
            model.session.invalidate(); model.reset(); showFilters = false
        }
    }
    private func load(_ move: Int = 0) async {
        await model.load(store: store, kind: kind, filters: filters, move: move)
    }
}

struct ObservabilityRecordRow: View {
    let record: ObservabilityRecord
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(record.title).font(.headline).lineLimit(2)
            HStack {
                if !record.value["status"].string.isEmpty { Text(NativeAdminLabels.value(record.value["status"].string)) }
                Text(NativeAdminLabels.value(record.value["source"].string))
                Spacer()
                if !record.value["metricsLatencyMs"].isNull {
                    Text("\(record.value["metricsLatencyMs"].int) ms").monospacedDigit()
                }
            }.font(.caption).foregroundStyle(.secondary)
            Text(NativeDisplay.date(record.value["createdAt"].string)).font(.caption2).foregroundStyle(.secondary)
        }.padding(.vertical, 5)
    }
}

struct ObservabilityErrorView: View {
    let message: String
    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
    }
}

struct ObservabilityFilterView: View {
    @ObservedObject var store: AxonStore
    let kind: ObservabilityKind
    @Binding var filters: ObservabilityFilters
    let apply: () -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section(obsText("时间与分页")) {
                    Toggle(obsText("指定时间范围"), isOn: $filters.useDateRange)
                    if filters.useDateRange {
                        DatePicker(obsText("开始时间"), selection: $filters.start)
                        DatePicker(obsText("结束时间"), selection: $filters.end)
                    }
                    Toggle(obsText("按创建时间升序"), isOn: $filters.ascending)
                    Picker(obsText("每页条数"), selection: $filters.size) {
                        ForEach([10, 25, 50, 100], id: \.self) { Text("\($0)").tag($0) }
                    }
                }
                if kind != .usage {
                    Section(obsText("状态（多选）")) {
                        ForEach(kind == .requests ? ["pending", "processing", "completed", "failed", "canceled"] : ["active", "archived", "retained"], id: \.self) { status in
                            Toggle(NativeAdminLabels.value(status), isOn: membership(status, in: $filters.statuses))
                        }
                    }
                }
                Section(obsText("项目与标识")) {
                    NativeNamedFilter(store: store, kind: "projects", title: obsText("项目"), identifiers: $filters.projects)
                    if kind == .requests || kind == .usage {
                        NativeNamedFilter(store: store, kind: "channels", title: obsText("渠道"), identifiers: $filters.channels)
                        NativeNamedFilter(store: store, kind: "apiKeys", title: obsText("API 密钥"), identifiers: $filters.apiKeys, numeric: kind == .usage)
                        TextField(obsText("请求格式"), text: $filters.format)
                    }
                    if kind == .requests {
                        TextField(obsText("客户端 IP"), text: $filters.clientIP)
                        TextField(obsText("上游请求 ID"), text: $filters.externalID)
                        Picker(obsText("流式请求"), selection: $filters.stream) {
                            Text(obsText("全部")).tag("all")
                            Text(obsText("是")).tag("yes")
                            Text(obsText("否")).tag("no")
                        }
                    }
                }.textInputAutocapitalization(.never).autocorrectionDisabled()
                if kind == .requests || kind == .usage {
                    Section(obsText("来源（多选）")) {
                        ForEach(["api", "playground", "test"], id: \.self) { source in
                            Toggle(NativeAdminLabels.value(source), isOn: membership(source, in: $filters.sources))
                        }
                    }
                }
                Button(obsText("重置筛选")) { filters = ObservabilityFilters() }
            }
            .navigationTitle(obsText("服务器筛选"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(obsText("取消")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(obsText("应用"), action: apply) }
            }
        }
    }
    private func membership(_ value: String, in selection: Binding<Set<String>>) -> Binding<Bool> {
        Binding(get: { selection.wrappedValue.contains(value) }, set: { selected in
            if selected { selection.wrappedValue.insert(value) } else { selection.wrappedValue.remove(value) }
        })
    }
}

struct ObservabilityFieldsView: View {
    let value: JSON
    var body: some View {
        ForEach(value.object.keys.filter { !NativeDisplay.identifier($0) }.sorted(), id: \.self) { key in
            if value[key].object.isEmpty && value[key].array.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 20) {
                    Text(key == "totalTokens" ? obsText("Token 用量") : NativeAdminLabels.field(key)).foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text(value[key].isNull ? "—" : NativeAdminLabels.scalar(value[key], key: key))
                        .multilineTextAlignment(.trailing).monospacedDigit().textSelection(.enabled)
                }.font(.subheadline).padding(.vertical, 5)
            } else {
                DisclosureGroup(NativeAdminLabels.field(key)) {
                    if case .array(let items) = value[key] {
                        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                            if case .object = item { AnyView(ObservabilityFieldsView(value: item)) }
                            else { Text(NativeAdminLabels.scalar(item, key: key)) }
                        }
                    } else { AnyView(ObservabilityFieldsView(value: value[key])) }
                }
            }
        }
    }
}

struct ObservabilityJSONView: View {
    let value: JSON
    var body: some View {
        if value.isNull { Text(obsText("服务器未保存此内容")).foregroundStyle(.secondary) }
        else {
            ReadablePayloadView(value: value)
            DisclosureGroup(obsText("原始 JSON（技术数据）")) {
                ScrollView(.horizontal) {
                    Text(ObservabilityRedaction.printable(value))
                        .font(.caption.monospaced()).textSelection(.enabled).padding(.vertical, 4)
                }
            }
        }
    }
}

struct ObservabilityDetailView: View {
    @ObservedObject var store: AxonStore
    let kind: ObservabilityKind
    let id: String
    let origin: ObservabilitySession
    @StateObject private var session = ObservabilitySession()
    @State private var record: JSON?
    @State private var content: JSON?
    @State private var pendingAction: String?
    @State private var actionVerified = false

    var body: some View {
        List {
            if session.busy { ProgressView(obsText("正在读取服务器数据")) }
            if let error = session.error { ObservabilityErrorView(message: error) }
            if let record = record, !session.invalidated {
                Section(obsText("详情")) { NativeDetailFieldsView(store: store, value: record) }
                Section(obsText("关联记录")) {
                    if kind == .requests {
                        NavigationLink(obsText("全部执行尝试")) { ObservabilityRelatedView(store: store, id: id, relation: .executions, origin: session) }
                        NavigationLink(obsText("请求 Token、费用与用量明细")) { ObservabilityRelatedView(store: store, id: id, relation: .usageLogs, origin: session) }
                        if !record["traceID"].isNull {
                            NavigationLink(obsText("所属追踪")) { ObservabilityDetailView(store: store, kind: .traces, id: record["traceID"].string, origin: session) }
                        }
                    }
                    if kind == .traces {
                        NavigationLink(obsText("全部关联请求")) { ObservabilityRelatedView(store: store, id: id, relation: .requests, origin: session) }
                        if !record["threadID"].isNull {
                            NavigationLink(obsText("所属线程")) { ObservabilityDetailView(store: store, kind: .threads, id: record["threadID"].string, origin: session) }
                        }
                    }
                    if kind == .threads {
                        NavigationLink(obsText("全部追踪与聊天轮次")) { ObservabilityRelatedView(store: store, id: id, relation: .traces, origin: session) }
                    }
                    if kind == .usage {
                        NavigationLink(obsText("原始请求")) { ObservabilityDetailView(store: store, kind: .requests, id: record["requestID"].string, origin: session) }
                    }
                }
                if kind == .requests || kind == .traces {
                    Section {
                        Text(obsText("内容可能包含用户数据；仅主动读取后展示，所有请求头值与可识别凭据会遮盖。"))
                            .font(.footnote).foregroundStyle(.secondary)
                        Button(obsText("读取请求、响应与诊断内容")) { Task { await reveal() } }
                            .disabled(session.busy || session.invalidated)
                        if let content = content {
                            Button(obsText("隐藏内容")) { self.content = nil }
                            if kind == .requests { ObservabilityConversationView(content: content) }
                            if kind == .traces { ObservabilitySegmentView(segment: content["rawRootSegment"]) }
                            ForEach(content.object.keys.filter { $0 != "id" }.sorted(), id: \.self) { key in
                                DisclosureGroup(NativeAdminLabels.field(key)) { ObservabilityJSONView(value: content[key]) }
                            }
                        }
                    }
                }
                if kind == .traces || kind == .threads {
                    Section(obsText("保留与归档")) {
                        let status = record["status"].string
                        Button(status == "archived" ? obsText("取消归档") : obsText("归档")) { pendingAction = status == "archived" ? "unarchive" : "archive" }
                            .disabled(status == "retained")
                        Button(status == "retained" ? obsText("取消保留") : obsText("保护并保留")) { pendingAction = status == "retained" ? "unretain" : "retain" }
                            .disabled(status == "archived")
                        if actionVerified { Label(obsText("操作已读回验证"), systemImage: "checkmark.circle").foregroundStyle(.green) }
                    }.disabled(session.busy || session.invalidated)
                }
            }
        }
        .navigationTitle(kind.title)
        .toolbar { Button(obsText("刷新")) { Task { await refresh() } }.disabled(session.busy || session.invalidated) }
        .refreshable { await refresh() }
        .task {
            guard session.instance == nil else { return }
            do { _ = try origin.checkedClient(store); try session.bind(store, expected: origin.instance); await refresh() }
            catch { session.error = error.localizedDescription; session.invalidate() }
        }
        .onChange(of: store.selectedInstance) { _ in
            session.invalidate(); record = nil; content = nil; pendingAction = nil
        }
        .confirmationDialog(obsText("确认对当前实例的此记录执行操作？"), isPresented: Binding(get: { pendingAction != nil }, set: { if !$0 { pendingAction = nil } }), titleVisibility: .visible) {
            if let action = pendingAction {
                Button(obsText("确认执行"), role: action == "archive" ? .destructive : nil) {
                    pendingAction = nil
                    Task { await mutate(action) }
                }
            }
            Button(obsText("取消"), role: .cancel) { pendingAction = nil }
        } message: {
            Text(confirmationSummary)
        }
    }
    private var confirmationSummary: String {
        let instanceName = session.instance?.name ?? ""
        let recordName = record.map { ObservabilityRecord(value: $0).title } ?? "—"
        var summary = instanceName + " · " + recordName
        if kind == .threads { summary += "\n" + obsText("线程操作会级联修改关联追踪；取消保留也会取消单独保留的追踪。") }
        return summary
    }
    private func detail(_ client: AxonClient) async throws -> JSON {
        switch kind {
        case .requests: return try await client.observeRequestDetail(variables: ["id": id])
        case .traces: return try await client.observeTraceDetail(variables: ["id": id])
        case .threads: return try await client.observeThreadDetail(variables: ["id": id])
        case .usage: return try await client.observeUsageLogDetail(variables: ["id": id])
        }
    }
    private func refresh() async {
        guard !session.busy else { return }
        content = nil; actionVerified = false
        guard let data = await session.read(store, query: detail) else { return }
        guard data["node"]["id"].string == id else { record = nil; session.error = obsText("记录不存在或无权访问。"); return }
        record = session.sanitize(data["node"])
    }
    private func reveal() async {
        guard let data = await session.read(store, query: { client in
            if kind == .traces { return try await client.observeTraceContent(variables: ["id": id]) }
            return try await client.observeRequestContent(variables: ["id": id])
        }) else { return }
        guard data["node"]["id"].string == id else { session.error = obsText("记录不存在或无权访问。"); return }
        content = session.sanitize(data["node"])
    }
    private func mutate(_ action: String) async {
        store.pageCache.invalidate()
        actionVerified = false
        guard let data = await session.read(store, query: { client in
            var result: JSON
            let v: [String: Any] = ["id": id]
            if kind == .traces {
                switch action {
                case "archive": result = try await client.observeArchiveTrace(variables: v)
                case "unarchive": result = try await client.observeUnarchiveTrace(variables: v)
                case "retain": result = try await client.observeRetainTrace(variables: v)
                default: result = try await client.observeUnretainTrace(variables: v)
                }
            } else {
                switch action {
                case "archive": result = try await client.observeArchiveThread(variables: v)
                case "unarchive": result = try await client.observeUnarchiveThread(variables: v)
                case "retain": result = try await client.observeRetainThread(variables: v)
                default: result = try await client.observeUnretainThread(variables: v)
                }
            }
            _ = try session.checkedClient(store)
            let root = action + (kind == .traces ? "Trace" : "Thread")
            guard result[root].bool else { throw AxonAPIError.invalidResponse }
            let readback = try await detail(client)
            let expected = action == "archive" ? "archived" : action == "retain" ? "retained" : "active"
            guard readback["node"]["id"].string == id, readback["node"]["status"].string == expected else { throw AxonAPIError.invalidResponse }
            return readback
        }) else { return }
        record = session.sanitize(data["node"]); actionVerified = true; content = nil
    }
}

enum ObservabilityRelation: String {
    case executions, requests, traces, usageLogs
    var title: String { obsText(self == .executions ? "执行尝试" : self == .requests ? "关联请求" : self == .usageLogs ? "请求用量明细" : "追踪与聊天轮次") }
}

struct ObservabilityRelatedView: View {
    @ObservedObject var store: AxonStore
    let id: String
    let relation: ObservabilityRelation
    let origin: ObservabilitySession
    @StateObject private var session = ObservabilitySession()
    @State private var records: [ObservabilityRecord] = []
    @State private var next: String?
    @State private var total: Int?
    @State private var status = "all"
    @State private var selectedContent: JSON?
    @State private var pendingExecution: String?

    var body: some View {
        List {
            Section {
                if relation != .usageLogs {
                Picker(obsText("状态"), selection: $status) {
                    Text(obsText("全部")).tag("all")
                    ForEach(relation == .traces ? ["active", "archived", "retained"] : ["pending", "processing", "completed", "failed", "canceled"], id: \.self) { Text(NativeAdminLabels.value($0)).tag($0) }
                }.disabled(session.busy || session.invalidated)
                }
                if let total = total { Text(String(format: obsText("共 %lld 条，已读取 %lld 条"), Int64(total), Int64(records.count))).monospacedDigit() }
                if let error = session.error { ObservabilityErrorView(message: error) }
                if session.busy { ProgressView() }
                if records.isEmpty && total != nil && !session.busy { Text(obsText("没有符合条件的记录")) }
                ForEach(session.invalidated ? [] : records) { record in
                    if relation == .executions {
                        DisclosureGroup {
                            ObservabilityFieldsView(value: record.value)
                            Button(obsText("读取此执行的请求、响应与错误")) { pendingExecution = record.id; Task { await executionContent(record.id) } }
                                .disabled(session.busy || session.invalidated)
                        } label: { ObservabilityRecordRow(record: record) }
                    } else {
                        NavigationLink {
                            ObservabilityDetailView(store: store, kind: relation == .traces ? .traces : relation == .usageLogs ? .usage : .requests, id: record.id, origin: session)
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                ObservabilityRecordRow(record: record)
                                if relation == .traces {
                                    Text(record.value["firstUserQuery"].string).lineLimit(3)
                                    Text(record.value["firstText"].string).lineLimit(3).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                if next != nil { Button(obsText("读取下一页")) { Task { await load(more: true) } }.disabled(session.busy || session.invalidated) }
            }
        }
        .navigationTitle(relation.title)
        .toolbar { Button(obsText("刷新")) { Task { await load() } }.disabled(session.busy || session.invalidated) }
        .onChange(of: status) { _ in Task { await load() } }
        .onChange(of: store.selectedInstance) { _ in
            session.invalidate(); records = []; next = nil; total = nil; selectedContent = nil; pendingExecution = nil
        }
        .task {
            guard session.instance == nil else { return }
            do { _ = try origin.checkedClient(store); try session.bind(store, expected: origin.instance); await load() }
            catch { session.invalidate() }
        }
        .refreshable { store.pageCache.invalidate(); await load() }
        .sheet(isPresented: Binding(get: { selectedContent != nil }, set: { if !$0 { selectedContent = nil } })) {
            NavigationStack {
                List {
                    if let selectedContent = selectedContent, !session.invalidated {
                        ObservabilityConversationView(content: selectedContent)
                        ObservabilityFieldsView(value: selectedContent)
                    }
                }
                .navigationTitle(obsText("执行内容与诊断"))
                .toolbar { Button(obsText("关闭")) { selectedContent = nil } }
            }
        }
    }
    private func load(more: Bool = false) async {
        guard !session.busy else { return }
        selectedContent = nil
        var v: [String: Any] = ["id": id, "first": 25, "where": status == "all" ? [:] : ["status": status]]
        if more, let next = next { v["after"] = next } else { records = []; next = nil; total = nil }
        guard let data = await session.read(store, query: { client in
            switch relation {
            case .executions: return try await client.observeExecutions(variables: v)
            case .requests: return try await client.observeTraceRequests(variables: v)
            case .traces: return try await client.observeThreadTraces(variables: v)
            case .usageLogs:
                v.removeValue(forKey: "where")
                return try await client.observeRequestUsage(variables: v)
            }
        }) else { return }
        guard data["node"]["id"].string == id else { session.error = obsText("记录不存在或无权访问。"); return }
        let connection = data["node"][relation.rawValue]
        guard !connection.isNull else { session.error = obsText("记录不存在或无权访问。"); return }
        records += connection["edges"].array.map { ObservabilityRecord(value: session.sanitize($0["node"])) }
        total = connection["totalCount"].int
        next = connection["pageInfo"]["hasNextPage"].bool ? connection["pageInfo"]["endCursor"].string : nil
    }
    private func executionContent(_ executionID: String) async {
        guard let data = await session.read(store, query: { client in
            try await client.observeRequestExecutionContent(variables: ["id": executionID])
        }) else { return }
        guard pendingExecution == executionID, data["node"]["id"].string == executionID, data["node"]["requestID"].string == id else { return }
        selectedContent = session.sanitize(data["node"])
    }
}
