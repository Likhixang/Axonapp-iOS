import SwiftUI
import Charts

/// The landing screen is a visual dashboard, not a GraphQL field inspector.
/// Each card loads independently: one unavailable endpoint does not hide other statistics.
struct ManagementDashboardView: View {
    @ObservedObject var store: AxonStore
    @ObservedObject private var model: DashboardCacheModel
    init(store: AxonStore) { self.store = store; self.model = store.dashboard }
    private var values: [String: JSON] { model.values }
    private var failures: [String: String] { model.failures }
    private var window: String { model.window }
    private var distribution: String { model.distribution }
    private var trendMetric: String { model.trendMetric }
    private var loading: Bool { model.loading }
    private var updated: Date? { model.updated }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if store.selectedInstance == nil {
                    ManagementEmptyView(symbol: "network", title: "请先连接管理员实例。")
                } else {
                    overviewCards
                    trendCard
                    distributionCard
                    healthCard
                    performanceCard
                    NavigationLink { ObservabilityAnalyticsView(store: store) } label: {
                        HStack {
                            Label("多维用量分析", systemImage: "chart.xyaxis.line").foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, minHeight: 44)
                    }.buttonStyle(.plain)
                }
            }.padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("仪表盘")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { model.refresh(store) } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(loading).accessibilityLabel("刷新")
            }
        }
        .task { model.activate(store) }
        .refreshable { await model.refreshAndWait(store) }
        .onChange(of: window) { _ in model.activate(store) }
        .onChange(of: distribution) { _ in model.activate(store) }
        .onChange(of: store.selectedInstance) { _ in model.activate(store) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.selectedInstance?.name ?? "AxonHub").font(.headline)
                    if let updated = updated { Text(DisplayFormat.date(updated)).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                if loading { ProgressView() }
            }
            Picker("时间范围", selection: $model.window) {
                Text("今日").tag("day"); Text("本周").tag("week"); Text("本月").tag("month")
            }.pickerStyle(.segmented)
            if let error = failures["connection"] { ObservabilityErrorView(message: error) }
        }
    }
    private var overviewCards: some View {
        let overview = values["overview"] ?? .null
        let stats = overview["requestStats"]
        let requests = stats[window == "week" ? "requestsThisWeek" : window == "month" ? "requestsThisMonth" : "requestsToday"]
        let totals = values["totals"] ?? .null
        return LazyVGrid(columns: [GridItem(.flexible(minimum: 0), spacing: 12), GridItem(.flexible(minimum: 0), spacing: 12)], spacing: 12) {
            StatCardView(title: obsText("请求数"), value: ManagementFormat.number(requests), icon: "arrow.up.arrow.down", tint: .blue)
            StatCardView(title: obsText("Token 用量"), value: ManagementFormat.number(totals["totalTokens"]), icon: "sparkles", tint: .purple)
            StatCardView(title: obsText("费用"), value: ManagementFormat.cost(totals["totalCost"]), icon: "dollarsign.circle", tint: .orange)
            StatCardView(title: obsText("执行成功率"), value: ChannelHealthStatistics(rows: (values["health"] ?? .null).array).percentage, icon: "checkmark.shield", tint: .green)
        }.monospacedDigit()
    }
    private var trendCard: some View {
        ManagementChartCard(title: "近期趋势", failure: failures["daily"]) {
            Picker("指标", selection: $model.trendMetric) {
                Text("请求数").tag("count"); Text("Token 用量").tag("tokens"); Text("费用").tag("cost")
            }.pickerStyle(.segmented)
            let rows = (values["daily"] ?? .null).array
            if rows.isEmpty { chartEmpty }
            else {
                Chart(Array(rows.enumerated()), id: \.offset) { _, row in
                    AreaMark(x: .value("Date", row["date"].string), y: .value("Value", Double(row[trendMetric].string) ?? row[trendMetric].number))
                        .foregroundStyle(LinearGradient(colors: [.accentColor.opacity(0.3), .accentColor.opacity(0.01)], startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Date", row["date"].string), y: .value("Value", Double(row[trendMetric].string) ?? row[trendMetric].number))
                        .foregroundStyle(Color.accentColor)
                    PointMark(x: .value("Date", row["date"].string), y: .value("Value", Double(row[trendMetric].string) ?? row[trendMetric].number))
                        .symbolSize(18).foregroundStyle(Color.accentColor)
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine(); AxisTick()
                        AxisValueLabel { if let text = value.as(String.self) { Text(NativeDisplay.date(text)) } }
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine(); AxisTick()
                        AxisValueLabel { if let number = value.as(Double.self) { Text(trendMetric == "tokens" ? DisplayFormat.compact(number) : trendMetric == "cost" ? DisplayFormat.money(number) : DisplayFormat.number(number)) } }
                    }
                }
                .frame(height: 210).accessibilityLabel("每日真实用量趋势")
            }
        }
    }
    private var distributionCard: some View {
        ManagementChartCard(title: "请求分布", failure: failures["distribution"]) {
            Picker("分析维度", selection: $model.distribution) {
                Text("渠道").tag("channel"); Text("模型").tag("model"); Text("API 密钥").tag("apiKey")
            }.pickerStyle(.segmented)
            let rows = (values["distribution"] ?? .null).array.sorted { $0["count"].number > $1["count"].number }
            if rows.isEmpty { chartEmpty }
            else {
                Chart(Array(rows.prefix(8).enumerated()), id: \.offset) { _, row in
                    BarMark(x: .value("Requests", row["count"].number), y: .value("Name", chartName(row)))
                        .foregroundStyle(Color.accentColor.gradient).cornerRadius(4)
                }.frame(height: CGFloat(max(3, min(rows.count, 8))) * 34)
                ForEach(Array(rows.prefix(8).enumerated()), id: \.offset) { _, row in
                    HStack { Text(chartName(row)).lineLimit(1); Spacer(); Text(ManagementFormat.number(row["count"])).monospacedDigit() }.font(.caption)
                }
            }
        }
    }
    private var healthCard: some View {
        ManagementChartCard(title: "渠道健康", failure: failures["health"]) {
            let rows = (values["health"] ?? .null).array
            if rows.isEmpty { chartEmpty }
            else {
                ChannelHealthSummary(rows: rows)
                ForEach(Array(rows.sorted { $0["failedCount"].number > $1["failedCount"].number }.prefix(5).enumerated()), id: \.offset) { _, row in
                    Divider()
                    ChannelHealthRow(row: row)
                }
                NavigationLink { ObservabilityDashboardView(store: store) } label: {
                    HStack {
                        Text("查看全部渠道与筛选").font(.subheadline).foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }.frame(minHeight: 44)
                }.buttonStyle(.plain)
            }
        }
    }
    private var performanceCard: some View {
        ManagementChartCard(title: "最快渠道", failure: failures["performance"]) {
            let rows = (values["performance"] ?? .null).array
            if rows.isEmpty { chartEmpty }
            else {
                Chart(Array(rows.enumerated()), id: \.offset) { _, row in
                    BarMark(x: .value("Tokens/s", row["throughput"].number), y: .value("Channel", row["channelName"].string))
                        .foregroundStyle(Color.teal.gradient).cornerRadius(4)
                }.frame(height: CGFloat(max(3, rows.count)) * 34)
                Text("Token / s").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    @ViewBuilder private var chartEmpty: some View {
        if loading { ProgressView("正在读取服务器数据").frame(maxWidth: .infinity, minHeight: 120) }
        else { ManagementEmptyView(symbol: "chart.xyaxis.line", title: "所选范围没有统计数据") }
    }
    private func chartName(_ row: JSON) -> String {
        for key in ["channelName", "modelId", "apiKeyName"] where !row[key].string.isEmpty {
            if key == "modelId" { return store.entityNames.label(row[key], field: key, store: store) ?? "—" }
            return row[key].string
        }
        return "—"
    }

}

struct ManagementChartCard<Content: View>: View {
    let title: LocalizedStringKey
    var failure: String? = nil
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.headline)
            if let failure = failure { ObservabilityErrorView(message: failure) }
            content
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .neutralCard()
    }
}

struct ManagementEmptyView: View {
    let symbol: String
    let title: LocalizedStringKey
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).symbolVariant(.fill).font(.system(size: 30)).foregroundStyle(Color.accentColor)
            Text(title).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity, minHeight: 120).padding()
    }
}

enum ManagementFormat {
    static func number(_ value: JSON) -> String {
        value.isNull ? "—" : DisplayFormat.compact(Double(value.string) ?? value.number)
    }
    static func cost(_ value: JSON) -> String {
        guard !value.isNull else { return "—" }
        if case .string(let text) = value { return DisplayFormat.money(text) ?? "—" }
        return DisplayFormat.money(value.number)
    }
}
