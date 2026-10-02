import SwiftUI
import Charts

struct ObservabilityAnalyticsView: View {
    @ObservedObject var store: AxonStore
    @StateObject private var session = ObservabilitySession()
    @State private var useDates = true
    @State private var start = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var end = Date()
    @State private var projectIDs = ""
    @State private var channelIDs = ""
    @State private var modelIDs = ""
    @State private var apiKeyIDs = ""
    @State private var userIDs = ""
    @State private var dimension = "channel"
    @State private var overview: JSON?
    @State private var daily: [JSON] = []
    @State private var breakdown: [JSON] = []
    @State private var earliest: String?
    @State private var page = 0
    @State private var chartMetric = "totalTokens"
    @State private var filtersOpen = true

    var body: some View {
        List {
            Section {
                DisclosureGroup(obsText("分析筛选"), isExpanded: $filtersOpen) {
                    Toggle(obsText("指定日期范围（服务器时区）"), isOn: $useDates)
                    if useDates {
                        DatePicker(obsText("开始日期"), selection: $start, displayedComponents: .date)
                        DatePicker(obsText("结束日期"), selection: $end, displayedComponents: .date)
                    }
                    NativeNamedFilter(store: store, kind: "projects", title: obsText("项目"), identifiers: $projectIDs)
                    NativeNamedFilter(store: store, kind: "channels", title: obsText("渠道"), identifiers: $channelIDs)
                    NativeNamedFilter(store: store, kind: "models", title: obsText("模型"), identifiers: $modelIDs)
                    NativeNamedFilter(store: store, kind: "apiKeys", title: obsText("API 密钥"), identifiers: $apiKeyIDs)
                    NativeNamedFilter(store: store, kind: "users", title: obsText("用户"), identifiers: $userIDs)
                    Picker(obsText("分析维度"), selection: $dimension) {
                        Text(obsText("渠道")).tag("channel")
                        Text(obsText("模型")).tag("model")
                        Text(obsText("API Keys")).tag("apiKey")
                        Text(obsText("用户")).tag("user")
                    }
                    Button(obsText("应用筛选")) { Task { await refresh() } }
                }.textInputAutocapitalization(.never).autocorrectionDisabled()
                    .disabled(session.busy || session.invalidated)
                if session.busy { ProgressView(obsText("正在读取服务器数据")) }
                if let error = session.error { ObservabilityErrorView(message: error) }
                if let earliest = earliest { Text(obsText("最早用量日期") + ": " + NativeDisplay.date(earliest)).font(.caption).foregroundStyle(.secondary) }
            }
            if let overview = overview, !session.invalidated {
                Section(obsText("用量概览")) {
                    ObservabilityFieldsView(value: overview)
                }
                Section(obsText("每日趋势")) {
                    Picker(obsText("指标"), selection: $chartMetric) {
                        ForEach(["totalTokens", "inputTokens", "cachedInputTokens", "uncachedInputTokens", "outputTokens", "requestCount", "cost"], id: \.self) { Text($0 == "totalTokens" ? obsText("Token 用量") : NativeAdminLabels.field($0)).tag($0) }
                    }
                    if daily.isEmpty { Text(obsText("所选范围没有用量数据")) }
                    else {
                        Chart(Array(daily.enumerated()), id: \.offset) { _, row in
                            LineMark(x: .value("date", row["date"].string), y: .value(chartMetric, row[chartMetric].number))
                        }
                        .chartXAxis {
                            AxisMarks { value in
                                AxisGridLine(); AxisTick()
                                AxisValueLabel { if let text = value.as(String.self) { Text(NativeDisplay.date(text)) } }
                            }
                        }
                        .chartYAxis {
                            AxisMarks { value in
                                AxisGridLine(); AxisTick()
                                AxisValueLabel { if let number = value.as(Double.self) { Text(DisplayFormat.isTokenQuantity(chartMetric) ? DisplayFormat.compact(number) : number.formatted()) } }
                            }
                        }.frame(height: 220).accessibilityLabel(obsText("每日真实用量趋势"))
                        DisclosureGroup(obsText("每日数据表")) {
                            ForEach(Array(daily.enumerated()), id: \.offset) { _, row in
                                DisclosureGroup(NativeDisplay.date(row["date"].string)) { ObservabilityFieldsView(value: row) }
                            }
                        }
                    }
                }
                Section(obsText("维度明细")) {
                    Text(String(format: obsText("共 %lld 条 · 第 %lld 页"), Int64(breakdown.count), Int64(page + 1))).monospacedDigit()
                    if breakdown.isEmpty { Text(obsText("所选范围没有用量数据")) }
                    if !breakdown.isEmpty {
                        Chart(Array(breakdown.prefix(10).enumerated()), id: \.offset) { _, row in
                            BarMark(x: .value("totalTokens", row["totalTokens"].number), y: .value("name", row["name"].string))
                        }
                        .chartXAxis {
                            AxisMarks { value in
                                AxisGridLine(); AxisTick()
                                AxisValueLabel { if let number = value.as(Double.self) { Text(DisplayFormat.compact(number)) } }
                            }
                        }.frame(height: 240).accessibilityLabel(obsText("维度 Token 分布（前十项）"))
                    }
                    ForEach(Array(breakdown.dropFirst(page * 25).prefix(25).enumerated()), id: \.offset) { _, row in
                        DisclosureGroup(row["name"].string) { ObservabilityFieldsView(value: row) }
                    }
                    HStack {
                        Button(obsText("上一页")) { page -= 1 }.disabled(page == 0)
                        Spacer()
                        Button(obsText("下一页")) { page += 1 }.disabled((page + 1) * 25 >= breakdown.count)
                    }
                }
            }
        }
        .navigationTitle(obsText("多维用量分析"))
        .toolbar { Button(obsText("刷新")) { store.pageCache.invalidate(); Task { await refresh() } }.disabled(session.busy || session.invalidated) }
        .task {
            guard session.instance == nil else { return }
            do { try session.bind(store); await refresh() }
            catch { session.error = error.localizedDescription }
        }
        .refreshable { store.pageCache.invalidate(); await refresh() }
        .onChange(of: store.selectedInstance) { _ in
            session.invalidate(); overview = nil; daily = []; breakdown = []; earliest = nil
        }
    }
    private func apply(_ data: JSON) {
        overview = data["overview"]; daily = data["daily"].array
        breakdown = data["breakdown"].array.sorted { $0["totalTokens"].number > $1["totalTokens"].number }
        earliest = data["metadata"]["earliestDate"].isNull ? nil : data["metadata"]["earliestDate"].string
        page = 0; filtersOpen = false
    }
    private func refresh() async {
        guard !session.busy else { return }
        guard !useDates || start <= end else { session.error = obsText("开始日期不能晚于结束日期。"); return }
        var filter: [String: Any] = [:]
        if useDates {
            let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
            filter["startTime"] = formatter.string(from: start)
            filter["endTime"] = formatter.string(from: end)
        }
        let parser = ObservabilityFilters()
        for (key, text) in [("projectIDs", projectIDs), ("channelIDs", channelIDs), ("modelIDs", modelIDs), ("apiKeyIDs", apiKeyIDs), ("userIDs", userIDs)] {
            if !parser.identifiers(text).isEmpty { filter[key] = parser.identifiers(text) }
        }
        let selectedDimension = dimension
        let v: [String: Any] = ["filter": filter]
        let key = "analytics/" + selectedDimension + "/" + ((try? JSONSerialization.data(withJSONObject: filter, options: [.sortedKeys]).base64EncodedString()) ?? "")
        do { _ = try session.checkedClient(store) } catch { return }
        if let cached = store.pageCache.value(key) { apply(cached); return }
        if let data = await session.read(store, query: { client in
            let metadata = try await client.observeAnalyticsMetadata()
            _ = try session.checkedClient(store)
            let totals = try await client.observeAnalyticsOverview(variables: v)
            _ = try session.checkedClient(store)
            let days = try await client.observeAnalyticsDailyStats(variables: v)
            _ = try session.checkedClient(store)
            let dimensions = try await client.observeAnalyticsDimensionStats(variables: ["filter": filter, "dimension": selectedDimension])
            return .object(["metadata": metadata["analyticsMetadata"], "overview": totals["analyticsOverview"], "daily": days["analyticsDailyStats"], "breakdown": dimensions["analyticsDimensionStats"]])
        }) {
            let safe = session.sanitize(data)
            store.pageCache.save(safe, key: key); apply(safe)
        }
    }
}

enum ObservabilityDashboardMetric: String, CaseIterable, Identifiable {
    case channelSuccessRates, requestStatsByChannel, requestStatsByModel, requestStatsByAPIKey
    case tokenStatsByChannel, tokenStatsByModel, tokenStatsByAPIKey
    case costStatsByChannel, costStatsByModel, costStatsByAPIKey, usageStatsByUser
    case dailyRequestStats, topRequestsProjects, modelPerformanceStats, channelPerformanceStats, fastestChannels, fastestModels
    var id: String { rawValue }
    var title: String {
        switch self {
        case .channelSuccessRates: return obsText("渠道成功率")
        case .requestStatsByChannel: return obsText("渠道请求统计")
        case .requestStatsByModel: return obsText("模型请求统计")
        case .requestStatsByAPIKey: return obsText("API Key 请求统计")
        case .tokenStatsByChannel: return obsText("渠道 Token 统计")
        case .tokenStatsByModel: return obsText("模型 Token 统计")
        case .tokenStatsByAPIKey: return obsText("API Key Token 统计")
        case .costStatsByChannel: return obsText("渠道费用")
        case .costStatsByModel: return obsText("模型费用")
        case .costStatsByAPIKey: return obsText("API Key 费用")
        case .usageStatsByUser: return obsText("用户用量统计")
        case .dailyRequestStats: return obsText("每日请求统计")
        case .topRequestsProjects: return obsText("项目请求排行")
        case .modelPerformanceStats: return obsText("模型性能趋势")
        case .channelPerformanceStats: return obsText("渠道性能趋势")
        case .fastestChannels: return obsText("最快渠道")
        case .fastestModels: return obsText("最快模型")
        }
    }
    var supportsWindow: Bool {
        ![Self.dailyRequestStats, .topRequestsProjects, .modelPerformanceStats, .channelPerformanceStats].contains(self)
    }
    var chartValue: String {
        switch self {
        case .channelSuccessRates: return "successRate"
        case .requestStatsByChannel, .requestStatsByModel, .requestStatsByAPIKey, .dailyRequestStats: return "count"
        case .costStatsByChannel, .costStatsByModel, .costStatsByAPIKey: return "cost"
        case .modelPerformanceStats, .channelPerformanceStats, .fastestChannels, .fastestModels: return "throughput"
        case .topRequestsProjects: return "requestCount"
        default: return "totalTokens"
        }
    }
    func fetch(_ client: AxonClient, window: String) async throws -> JSON {
        let v: [String: Any] = ["timeWindow": window]
        switch self {
        case .channelSuccessRates: return try await client.observeChannelSuccessRates(variables: ["timeWindow": window, "limit": NSNull()])
        case .requestStatsByChannel: return try await client.observeRequestsByChannel(variables: v)
        case .requestStatsByModel: return try await client.observeRequestsByModel(variables: v)
        case .requestStatsByAPIKey: return try await client.observeRequestsByAPIKey(variables: v)
        case .tokenStatsByChannel: return try await client.observeTokensByChannel(variables: v)
        case .tokenStatsByModel: return try await client.observeTokensByModel(variables: v)
        case .tokenStatsByAPIKey: return try await client.observeTokensByAPIKey(variables: v)
        case .costStatsByChannel: return try await client.observeCostByChannel(variables: v)
        case .costStatsByModel: return try await client.observeCostByModel(variables: v)
        case .costStatsByAPIKey: return try await client.observeCostByAPIKey(variables: v)
        case .usageStatsByUser: return try await client.observeUsageStatsByUser(variables: v)
        case .dailyRequestStats: return try await client.observeDailyRequestStats()
        case .topRequestsProjects: return try await client.observeTopProjects()
        case .modelPerformanceStats: return try await client.observeModelPerformanceStats()
        case .channelPerformanceStats: return try await client.observeChannelPerformanceStats()
        case .fastestChannels: return try await client.observeFastestChannels(variables: ["input": ["timeWindow": window, "limit": 5]])
        case .fastestModels: return try await client.observeFastestModels(variables: ["input": ["timeWindow": window, "limit": 5]])
        }
    }
}

struct ObservabilityDashboardView: View {
    @ObservedObject var store: AxonStore
    @StateObject private var session = ObservabilitySession()
    @State private var overview: JSON?
    @State private var tokens: JSON?
    @State private var rows: [JSON] = []
    @State private var metric = ObservabilityDashboardMetric.channelSuccessRates
    @State private var window = "day"
    @State private var search = ""
    @State private var channelType = "all"
    @State private var warningsOnly = false
    @State private var sortField = "successRate"
    @State private var descending = false
    @State private var page = 0
    @State private var updated: Date?

    private var visibleRows: [JSON] {
        rows.filter { row in
            let matchesSearch = search.isEmpty || name(row).localizedCaseInsensitiveContains(search)
            let matchesType = metric != .channelSuccessRates || channelType == "all" || row["channelType"].string == channelType
            let matchesWarning = metric != .channelSuccessRates || !warningsOnly || row["channelDisabled"].bool || ChannelHealthStatistics(row).needsAttention
            return matchesSearch && matchesType && matchesWarning
        }.sorted { left, right in
            let key = metric == .channelSuccessRates ? sortField : metric.chartValue
            return descending ? left[key].number > right[key].number : left[key].number < right[key].number
        }
    }
    var body: some View {
        List {
            Section {
                if session.busy { ProgressView(obsText("正在读取服务器数据")) }
                if let error = session.error { ObservabilityErrorView(message: error) }
                if let updated = updated { Text(obsText("更新于") + " " + DisplayFormat.date(updated)).font(.caption).foregroundStyle(.secondary) }
            }
            if let overview = overview, !session.invalidated {
                DisclosureGroup(obsText("网关概览（全局）")) {
                    LabeledContent(obsText("总请求数"), value: "\(overview["totalRequests"].int)")
                    LabeledContent(obsText("失败请求数"), value: "\(overview["failedRequests"].int)")
                    DisclosureGroup(obsText("各时间范围请求统计")) { ObservabilityFieldsView(value: overview["requestStats"]) }
                }.monospacedDigit()
            }
            if let tokens = tokens, !session.invalidated {
                DisclosureGroup(obsText("Token 用量概览")) {
                    ObservabilityFieldsView(value: tokens)
                }
            }
            DisclosureGroup(obsText("统计维度与时间范围")) {
                Picker(obsText("指标"), selection: $metric) { ForEach(ObservabilityDashboardMetric.allCases) { Text($0.title).tag($0) } }
                if metric.supportsWindow {
                    Picker(obsText("时间范围"), selection: $window) {
                        Text(obsText("今日")).tag("day")
                        Text(obsText("本周")).tag("week")
                        Text(obsText("本月")).tag("month")
                        }
                } else { Text(obsText("服务器固定范围")).font(.footnote).foregroundStyle(.secondary) }
                Toggle(obsText("按指标降序"), isOn: $descending)
                if metric == .channelSuccessRates {
                    Picker(obsText("渠道类型"), selection: $channelType) {
                        Text(obsText("全部")).tag("all")
                        ForEach(Array(Set(rows.map { $0["channelType"].string })).sorted(), id: \.self) { Text(NativeAdminLabels.field($0)).tag($0) }
                    }
                    Toggle(obsText("仅显示失败或已禁用渠道"), isOn: $warningsOnly)
                    Picker(obsText("排序字段"), selection: $sortField) {
                        ForEach(["successRate", "failedCount", "successCount", "totalCount", "inputTokens", "outputTokens", "totalTokens"], id: \.self) { Text($0 == "totalTokens" ? obsText("Token 用量") : NativeAdminLabels.field($0)).tag($0) }
                    }
                }
            }.disabled(session.busy || session.invalidated)
            if metric.supportsWindow {
                Picker(obsText("时间范围"), selection: $window) {
                    Text(obsText("今日")).tag("day"); Text(obsText("本周")).tag("week"); Text(obsText("本月")).tag("month")
                }.pickerStyle(.segmented).disabled(session.busy || session.invalidated)
            }
            if updated != nil && !session.invalidated {
                Section(metric.title) {
                    if visibleRows.isEmpty { Text(obsText("所选范围没有统计数据")).foregroundStyle(.secondary) }
                    if metric == .channelSuccessRates && !rows.isEmpty { ChannelHealthSummary(rows: rows) }
                    if metric != .channelSuccessRates && !visibleRows.isEmpty {
                        Chart(Array(visibleRows.prefix(15).enumerated()), id: \.offset) { _, row in
                            if !row[metric.chartValue].isNull {
                                BarMark(x: .value(metric.chartValue, row[metric.chartValue].number), y: .value("name", name(row)))
                            }
                        }
                        .chartXAxis {
                            AxisMarks { value in
                                AxisGridLine(); AxisTick()
                                AxisValueLabel { if let number = value.as(Double.self) { Text(DisplayFormat.isTokenQuantity(metric.chartValue) ? DisplayFormat.compact(number) : number.formatted()) } }
                            }
                        }.frame(height: 260).accessibilityLabel(metric.title)
                    }
                    Text(String(format: obsText("共 %lld 条 · 第 %lld 页"), Int64(visibleRows.count), Int64(page + 1))).monospacedDigit()
                    ForEach(Array(visibleRows.dropFirst(page * 25).prefix(25).enumerated()), id: \.offset) { _, row in
                        DisclosureGroup {
                            ObservabilityFieldsView(value: row)
                        } label: {
                            if metric == .channelSuccessRates { ChannelHealthRow(row: row) }
                            else { Text(name(row)).font(.headline) }
                        }
                    }
                    HStack {
                        Button(obsText("上一页")) { page -= 1 }.disabled(page == 0)
                        Spacer()
                        Button(obsText("下一页")) { page += 1 }.disabled((page + 1) * 25 >= visibleRows.count)
                    }
                }
            }
            Section {
                NavigationLink(obsText("多维用量分析")) { ObservabilityAnalyticsView(store: store) }
                NavigationLink(obsText("请求、追踪与聊天历史")) { ObservabilityCenterView(store: store) }
            }
        }
        .navigationTitle(obsText("渠道健康与性能"))
        .searchable(text: $search, prompt: obsText("搜索统计名称"))
        .onChange(of: search) { _ in page = 0 }
        .onChange(of: channelType) { _ in page = 0 }
        .onChange(of: warningsOnly) { _ in page = 0 }
        .onChange(of: descending) { _ in page = 0 }
        .onChange(of: sortField) { _ in page = 0 }
        .onChange(of: metric) { _ in Task { await refresh() } }
        .onChange(of: window) { _ in Task { await refresh() } }
        .toolbar { Button(obsText("刷新")) { store.pageCache.invalidate(); Task { await refresh() } }.disabled(session.busy || session.invalidated) }
        .refreshable { store.pageCache.invalidate(); await refresh() }
        .task {
            guard session.instance == nil else { return }
            do { try session.bind(store); await refresh() }
            catch { session.error = error.localizedDescription }
        }
        .onChange(of: store.selectedInstance) { _ in
            session.invalidate(); overview = nil; tokens = nil; rows = []; updated = nil
        }
    }
    private func applyStats(_ data: JSON) { overview = data["overview"]; tokens = data["tokens"]; rows = data["rows"].array; updated = Date() }
    private func name(_ row: JSON) -> String {
        for key in ["channelName", "modelName", "modelId", "apiKeyName", "userName", "projectName", "date"] {
            if !row[key].string.isEmpty {
                if key == "date" { return NativeDisplay.date(row[key].string) }
                return row[key].string + (row["date"].string.isEmpty ? "" : " · " + NativeDisplay.date(row["date"].string))
            }
        }
        return "—"
    }
    private func refresh() async {
        guard !session.busy else { return }
        page = 0; channelType = "all"
        let requestedMetric = metric, requestedWindow = window
        let key = "health/" + requestedMetric.rawValue + "/" + requestedWindow
        do { _ = try session.checkedClient(store) } catch { return }
        if let cached = store.pageCache.value(key) { applyStats(cached); return }
        if let data = await session.read(store, query: { client in
            let summary = try await client.observeDashboardStats()
            _ = try session.checkedClient(store)
            let tokenSummary = try await client.observeTokenStats()
            _ = try session.checkedClient(store)
            let statistics = try await requestedMetric.fetch(client, window: requestedWindow)
            var metricRows = statistics[requestedMetric.rawValue].array
            if requestedMetric == .channelSuccessRates {
                _ = try session.checkedClient(store)
                let channelTokens = try await client.observeTokensByChannel(variables: ["timeWindow": requestedWindow])
                var tokenByID: [String: JSON] = [:]
                for tokenRow in channelTokens["tokenStatsByChannel"].array { tokenByID[tokenRow["channelId"].string] = tokenRow }
                metricRows = metricRows.map { rate in
                    var merged = rate.object
                    if let tokenRow = tokenByID[rate["channelId"].string] {
                        for key in ["inputTokens", "outputTokens", "cachedTokens", "reasoningTokens", "totalTokens"] { merged[key] = tokenRow[key] }
                    }
                    return .object(merged)
                }
            }
            return .object(["overview": summary["dashboardOverview"], "tokens": tokenSummary["tokenStats"], "rows": .array(metricRows)])
        }) {
            let safe = session.sanitize(data); store.pageCache.save(safe, key: key); applyStats(safe)
        }
    }
}
