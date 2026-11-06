import SwiftUI

struct RequestsView: View {
    @Environment(SessionStore.self) private var session
    @State private var loader = PagedLoader<RequestLog>()
    @State private var filter = AxonService.RequestFilter()
    @State private var modelQuery = ""
    @State private var autoRefresh = false

    private static let sources: [(String, String)] = [("api", "API"), ("playground", "调试"), ("test", "测试")]

    var body: some View {
        List {
            if let total = loader.totalCount, !loader.items.isEmpty {
                Text("共 \(Fmt.grouped(total)) 条")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
            }
            ForEach(loader.items) { request in
                NavigationLink(value: request.id) {
                    RequestRow(request: request)
                }
                .task { await loader.loadMoreIfNeeded(current: request) }
            }
            LoadMoreFooter(isLoading: loader.isLoadingMore)
        }
        .listStyle(.insetGrouped)
        .overlay {
            ListStateOverlay(loader: loader, emptyTitle: filter.isActive ? "没有匹配的请求" : "暂无请求", emptyImage: "tray")
        }
        .navigationTitle("请求")
        .navigationDestination(for: String.self) { id in
            RequestDetailView(requestID: id)
        }
        .searchable(text: $modelQuery, prompt: "按模型筛选")
        .onSubmit(of: .search) { filter.model = modelQuery }
        .onChange(of: modelQuery) { _, value in
            if value.isEmpty { filter.model = "" }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { ProjectPicker() }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    autoRefresh.toggle()
                } label: {
                    Image(systemName: autoRefresh ? "dot.radiowaves.left.and.right" : "pause.circle")
                        .symbolEffect(.variableColor.iterative, isActive: autoRefresh)
                }
                .accessibilityLabel(autoRefresh ? "停止自动刷新" : "自动刷新")
                filterMenu
            }
        }
        .refreshable { await loader.reload() }
        .task(id: ReloadKey(filter: filter, project: session.selectedProjectID)) {
            configure()
            await loader.reload()
        }
        .task(id: autoRefresh) {
            guard autoRefresh else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                if Task.isCancelled { break }
                await loader.reload()
            }
        }
    }

    private struct ReloadKey: Hashable {
        let filter: AxonService.RequestFilter
        let project: String?
    }

    private var filterMenu: some View {
        Menu {
            Picker("状态", selection: $filter.status) {
                Text("全部状态").tag(RequestStatus?.none)
                ForEach(RequestStatus.allCases, id: \.self) { status in
                    Text(status.label).tag(RequestStatus?.some(status))
                }
            }
            Picker("来源", selection: $filter.source) {
                Text("全部来源").tag(String?.none)
                ForEach(Self.sources, id: \.0) { source in
                    Text(source.1).tag(String?.some(source.0))
                }
            }
            if filter.isActive {
                Divider()
                Button("清除筛选", systemImage: "xmark.circle", role: .destructive) {
                    filter = .init()
                    modelQuery = ""
                }
            }
        } label: {
            Image(systemName: filter.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
    }

    private func configure() {
        guard let service = session.service else { return }
        let filter = filter
        loader.fetch = { cursor in try await service.requests(after: cursor, filter: filter) }
    }
}

struct RequestRow: View {
    let request: RequestLog

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                StatusDot(color: Theme.color(for: request.requestStatus))
                Text(request.modelID)
                    .font(.callout.weight(.medium).monospaced())
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(Fmt.shortTime(request.createdAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            HStack(spacing: 10) {
                if let channel = request.channel {
                    Label(channel.name, systemImage: "server.rack").lineLimit(1)
                }
                if let usage = request.usage {
                    Label(Fmt.compact(usage.totalTokens), systemImage: "text.word.spacing")
                }
                if let latency = request.metricsLatencyMs {
                    Label(Fmt.latency(latency), systemImage: "timer")
                }
                if request.stream {
                    Image(systemName: "water.waves").accessibilityLabel("流式")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .labelStyle(CompactLabelStyle())
            if request.requestStatus != .completed {
                StatusBadge(request.requestStatus)
            }
        }
        .padding(.vertical, 2)
    }
}

struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon.imageScale(.small)
            configuration.title
        }
    }
}
