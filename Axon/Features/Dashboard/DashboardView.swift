import Charts
import SwiftUI

struct DashboardView: View {
    @Environment(SessionStore.self) private var session
    @State private var window: TimeWindow = .day
    @State private var state: Loadable<DashboardSnapshot> = .idle
    @State private var snapshot: DashboardSnapshot?
    @State private var trendMetric: TrendMetric = .requests

    enum TrendMetric: String, CaseIterable, Identifiable {
        case requests = "请求", tokens = "Token", cost = "费用"
        var id: String { rawValue }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("时间范围", selection: $window) {
                    ForEach(TimeWindow.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                if let snapshot {
                    content(snapshot)
                } else if case .failed(let message) = state {
                    ErrorStateView(message: message) { await load() }
                        .padding(.top, 40)
                } else {
                    ProgressView().padding(.top, 80)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("概览")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { ProjectPicker() }
        }
        .refreshable { await load() }
        .task(id: TaskKey(window: window, project: session.selectedProjectID)) { await load() }
    }

    private struct TaskKey: Hashable { let window: TimeWindow; let project: String? }

    private func load() async {
        guard let service = session.service else { return }
        if snapshot == nil { state = .loading }
        let result = await service.dashboard(window: window)
        if Task.isCancelled { return }
        if result.overview == nil && result.topModels.isEmpty, let error = result.partialErrors.first {
            state = .failed(error)
            if snapshot != nil { session.bannerMessage = error }
        } else {
            withAnimation(.snappy) { snapshot = result }
            state = .loaded(result)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(_ data: DashboardSnapshot) -> some View {
        metrics(data)
        trendCard(data.daily)
        if !data.topModels.isEmpty || !data.modelTokens.isEmpty {
            modelsCard(data)
        }
        if !data.channelHealth.isEmpty {
            channelHealthCard(data.channelHealth)
        }
        if !data.fastestModels.isEmpty {
            fastestCard(data.fastestModels)
        }
    }

    private func windowTokens(_ tokens: TokenStats?) -> (input: Int, output: Int, cached: Int)? {
        guard let tokens else { return nil }
        switch window {
        case .day: return (tokens.totalInputTokensToday, tokens.totalOutputTokensToday, tokens.totalCachedTokensToday)
        case .week: return (tokens.totalInputTokensThisWeek, tokens.totalOutputTokensThisWeek, tokens.totalCachedTokensThisWeek)
        case .month: return (tokens.totalInputTokensThisMonth, tokens.totalOutputTokensThisMonth, tokens.totalCachedTokensThisMonth)
        case .allTime: return (tokens.totalInputTokensAllTime, tokens.totalOutputTokensAllTime, tokens.totalCachedTokensAllTime)
        }
    }

    private func windowRequests(_ overview: DashboardOverview?) -> Int? {
        guard let overview else { return nil }
        switch window {
        case .day: return overview.requestStats.requestsToday
        case .week: return overview.requestStats.requestsThisWeek
        case .month: return overview.requestStats.requestsThisMonth
        case .allTime: return overview.totalRequests
        }
    }

    private func metrics(_ data: DashboardSnapshot) -> some View {
        let tokens = windowTokens(data.tokens)
        let totalCost = data.modelCosts.reduce(0) { $0 + $1.cost }
        let overview = data.overview
        let successRate: Double? = overview.flatMap { $0.totalRequests > 0 ? 1 - Double($0.failedRequests) / Double($0.totalRequests) : nil }

        var weekCaption: String?
        if let stats = overview?.requestStats, window == .week, stats.requestsLastWeek > 0 {
            let change = Double(stats.requestsThisWeek - stats.requestsLastWeek) / Double(stats.requestsLastWeek)
            weekCaption = String(format: "较上周 %@%.0f%%", change >= 0 ? "+" : "", change * 100)
        }

        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            MetricTile(title: "请求数", value: Fmt.compact(windowRequests(overview)),
                       caption: weekCaption ?? "累计 \(Fmt.compact(overview?.totalRequests))",
                       systemImage: "arrow.left.arrow.right")
            MetricTile(title: "Token", value: Fmt.compact(tokens.map { $0.input + $0.output }),
                       caption: tokens.map { "输入 \(Fmt.compact($0.input)) · 输出 \(Fmt.compact($0.output))" },
                       systemImage: "text.word.spacing", tint: .purple)
            MetricTile(title: "费用", value: Fmt.cost(totalCost),
                       caption: tokens.map { "缓存命中 \(Fmt.compact($0.cached))" },
                       systemImage: "dollarsign.circle", tint: .green)
            MetricTile(title: "成功率", value: Fmt.percent(successRate),
                       caption: overview?.averageResponseTime.map { "平均延迟 \(Fmt.latency($0))" } ?? "累计失败 \(Fmt.compact(overview?.failedRequests))",
                       systemImage: "checkmark.seal", tint: (successRate ?? 1) < 0.9 ? Theme.warning : Theme.success)
        }
    }

    private func trendValue(_ stat: DailyRequestStat) -> Double {
        switch trendMetric {
        case .requests: return Double(stat.count)
        case .tokens: return Double(stat.tokens)
        case .cost: return stat.cost
        }
    }

    private func trendCard(_ daily: [DailyRequestStat]) -> some View {
        Card(title: "近期趋势", systemImage: "chart.xyaxis.line") {
            Picker("指标", selection: $trendMetric) {
                ForEach(TrendMetric.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)

            if daily.isEmpty {
                Text("暂无数据").font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 140)
            } else {
                Chart(daily) { stat in
                    if let day = stat.day {
                        AreaMark(x: .value("日期", day, unit: .day), y: .value(trendMetric.rawValue, trendValue(stat)))
                            .foregroundStyle(LinearGradient(colors: [Theme.accent.opacity(0.35), Theme.accent.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.monotone)
                        LineMark(x: .value("日期", day, unit: .day), y: .value(trendMetric.rawValue, trendValue(stat)))
                            .foregroundStyle(Theme.accent)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                            .interpolationMethod(.monotone)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let number = value.as(Double.self) {
                                Text(trendMetric == .cost ? Fmt.cost(number) : Fmt.compact(number))
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: max(daily.count / 5, 1))) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month(.defaultDigits).day())
                    }
                }
                .frame(height: 180)
                .animation(.snappy, value: trendMetric)
            }
        }
    }

    private func modelsCard(_ data: DashboardSnapshot) -> some View {
        let top = Array(data.topModels.prefix(6))
        let maxCount = max(top.map(\.count).max() ?? 1, 1)
        let costs = Dictionary(data.modelCosts.map { ($0.modelId, $0.cost) }, uniquingKeysWith: +)
        let tokens = Dictionary(data.modelTokens.map { ($0.modelId, $0.totalTokens) }, uniquingKeysWith: +)

        return Card(title: "热门模型", systemImage: "cpu") {
            VStack(spacing: 12) {
                ForEach(top) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(item.modelId).font(.callout.monospaced()).lineLimit(1)
                            Spacer()
                            Text(Fmt.compact(item.count)).font(.callout.weight(.semibold)).monospacedDigit()
                        }
                        GeometryReader { proxy in
                            Capsule().fill(Color(.tertiarySystemFill))
                                .overlay(alignment: .leading) {
                                    Capsule().fill(Theme.accent.gradient)
                                        .frame(width: proxy.size.width * CGFloat(item.count) / CGFloat(maxCount))
                                }
                        }
                        .frame(height: 6)
                        HStack(spacing: 12) {
                            if let tokenCount = tokens[item.modelId] {
                                Text("\(Fmt.compact(tokenCount)) tokens")
                            }
                            if let cost = costs[item.modelId] {
                                Text(Fmt.cost(cost))
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                }
                if top.isEmpty {
                    Text("该时间段暂无请求").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func channelHealthCard(_ channels: [ChannelSuccessRate]) -> some View {
        Card(title: "渠道健康", systemImage: "waveform.path.ecg") {
            VStack(spacing: 10) {
                ForEach(channels) { channel in
                    HStack(spacing: 10) {
                        ProviderIcon(provider: .of(channel.channelType), size: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(channel.channelName).font(.callout).lineLimit(1)
                            Text("\(Fmt.compact(channel.successCount)) 成功 · \(Fmt.compact(channel.failedCount)) 失败")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(Fmt.percent(channel.successRate / 100))
                            .font(.callout.weight(.semibold)).monospacedDigit()
                            .foregroundStyle(rateColor(channel.successRate))
                        if channel.channelDisabled {
                            StatusBadge("停用", color: .secondary)
                        }
                    }
                }
            }
        }
    }

    private func rateColor(_ rate: Double) -> Color {
        let value = rate / 100
        if value >= 0.95 { return Theme.success }
        if value >= 0.8 { return Theme.warning }
        return Theme.danger
    }

    private func fastestCard(_ models: [FastestModel]) -> some View {
        Card(title: "吞吐最快", systemImage: "hare") {
            VStack(spacing: 10) {
                ForEach(Array(models.enumerated()), id: \.element.id) { index, model in
                    HStack(spacing: 10) {
                        Text("\(index + 1)")
                            .font(.caption.weight(.bold))
                            .frame(width: 22, height: 22)
                            .background(Color(.tertiarySystemFill), in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.modelName.isEmpty ? model.modelId : model.modelName).font(.callout).lineLimit(1)
                            Text("\(Fmt.compact(model.requestCount)) 次请求 · 延迟 \(Fmt.latency(model.latencyMs))")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(Fmt.throughput(model.throughput)).font(.caption.weight(.semibold)).monospacedDigit()
                    }
                }
            }
        }
    }
}
