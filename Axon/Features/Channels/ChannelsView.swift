import SwiftUI

struct ChannelsView: View {
    @Environment(SessionStore.self) private var session
    @State private var loader = PagedLoader<Channel>()
    @State private var filter = AxonService.ChannelFilter()
    @State private var query = ""
    @State private var showCreate = false
    @State private var toast: Toast?
    @State private var testing: Set<String> = []
    @State private var pendingDelete: Channel?

    var body: some View {
        List {
            if !loader.items.isEmpty {
                summary
            }
            ForEach(loader.items) { channel in
                NavigationLink(value: channel) {
                    ChannelRow(channel: channel, isTesting: testing.contains(channel.id))
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button("删除", systemImage: "trash", role: .destructive) { pendingDelete = channel }
                    Button(channel.channelStatus == .enabled ? "停用" : "启用",
                           systemImage: channel.channelStatus == .enabled ? "pause.circle" : "play.circle") {
                        Task { await toggle(channel) }
                    }
                    .tint(channel.channelStatus == .enabled ? .orange : .green)
                }
                .swipeActions(edge: .leading) {
                    Button("测试", systemImage: "bolt.horizontal") { Task { await test(channel) } }
                        .tint(.blue)
                }
                .contextMenu {
                    Button("测试连接", systemImage: "bolt.horizontal") { Task { await test(channel) } }
                    Button(channel.channelStatus == .enabled ? "停用" : "启用",
                           systemImage: channel.channelStatus == .enabled ? "pause.circle" : "play.circle") {
                        Task { await toggle(channel) }
                    }
                    Button("删除", systemImage: "trash", role: .destructive) { pendingDelete = channel }
                }
                .task { await loader.loadMoreIfNeeded(current: channel) }
            }
            LoadMoreFooter(isLoading: loader.isLoadingMore)
        }
        .listStyle(.insetGrouped)
        .overlay {
            ListStateOverlay(loader: loader, emptyTitle: "还没有渠道", emptyImage: "server.rack",
                             emptyMessage: query.isEmpty ? "点右上角 + 添加第一个上游渠道" : nil)
        }
        .navigationTitle("渠道")
        .navigationDestination(for: Channel.self) { channel in
            ChannelDetailView(channelID: channel.id, initial: channel) { updated in
                if let updated { loader.replace(updated) } else { loader.remove(id: channel.id) }
            }
        }
        .searchable(text: $query, prompt: "搜索渠道名称")
        .onSubmit(of: .search) { filter.search = query }
        .onChange(of: query) { _, value in if value.isEmpty { filter.search = "" } }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Picker("状态", selection: $filter.status) {
                        Text("全部（不含归档）").tag(ResourceStatus?.none)
                        ForEach(ResourceStatus.allCases, id: \.self) { Text($0.label).tag(ResourceStatus?.some($0)) }
                    }
                } label: {
                    Image(systemName: filter.status == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showCreate = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showCreate) {
            ChannelFormView(mode: .create) { created in
                loader.prepend(created)
                toast = Toast(message: "已创建渠道 \(created.name)")
            }
        }
        .confirmationDialog("删除渠道？", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible, presenting: pendingDelete) { channel in
            Button("删除 \(channel.name)", role: .destructive) { Task { await delete(channel) } }
        } message: { _ in
            Text("删除后无法恢复，相关路由会立即失效。")
        }
        .toast($toast)
        .refreshable { await loader.reload() }
        .task(id: filter) {
            configure()
            await loader.reload()
        }
    }

    private var summary: some View {
        let enabled = loader.items.filter { $0.channelStatus == .enabled }.count
        let errored = loader.items.filter { $0.errorMessage?.nilIfBlank != nil }.count
        return HStack(spacing: 16) {
            Label("\(enabled) 启用", systemImage: "circle.fill").foregroundStyle(Theme.success)
            Label("\(loader.items.count - enabled) 停用", systemImage: "circle.fill").foregroundStyle(Theme.warning)
            if errored > 0 {
                Label("\(errored) 异常", systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.danger)
            }
        }
        .font(.caption)
        .labelStyle(CompactLabelStyle())
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
    }

    private func configure() {
        guard let service = session.service else { return }
        let filter = filter
        loader.fetch = { cursor in try await service.channels(after: cursor, filter: filter) }
    }

    private func toggle(_ channel: Channel) async {
        guard let service = session.service else { return }
        let target: ResourceStatus = channel.channelStatus == .enabled ? .disabled : .enabled
        do {
            try await service.setChannelStatus(id: channel.id, status: target)
            if let updated = try? await service.channel(id: channel.id) { loader.replace(updated) }
            toast = Toast(message: target == .enabled ? "已启用 \(channel.name)" : "已停用 \(channel.name)")
        } catch {
            toast = Toast(message: error.localizedDescription, isError: true)
        }
    }

    private func test(_ channel: Channel) async {
        guard let service = session.service, !testing.contains(channel.id) else { return }
        testing.insert(channel.id)
        defer { testing.remove(channel.id) }
        do {
            let result = try await service.testChannel(id: channel.id, model: channel.defaultTestModel)
            if result.success {
                toast = Toast(message: "\(channel.name) 连接正常 · \(Fmt.latency(result.latency * 1000))")
            } else {
                toast = Toast(message: result.error ?? result.message ?? "测试失败", isError: true)
            }
        } catch {
            toast = Toast(message: error.localizedDescription, isError: true)
        }
    }

    private func delete(_ channel: Channel) async {
        guard let service = session.service else { return }
        do {
            try await service.deleteChannel(id: channel.id)
            withAnimation { loader.remove(id: channel.id) }
            toast = Toast(message: "已删除 \(channel.name)")
        } catch {
            toast = Toast(message: error.localizedDescription, isError: true)
        }
    }
}

struct ChannelRow: View {
    let channel: Channel
    var isTesting = false

    var body: some View {
        HStack(spacing: 12) {
            ProviderIcon(provider: channel.provider)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(channel.name).font(.body.weight(.medium)).lineLimit(1)
                    if channel.errorMessage?.nilIfBlank != nil {
                        Image(systemName: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(Theme.danger)
                    }
                }
                HStack(spacing: 6) {
                    Text(channel.provider.name)
                    Text("·")
                    Text("\(channel.supportedModels.count) 个模型")
                    if let weight = channel.orderingWeight, weight != 0 {
                        Text("·")
                        Text("权重 \(weight)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                if let tags = channel.tags, !tags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(tags.prefix(3), id: \.self) { Tag(text: $0) }
                    }
                }
            }
            Spacer(minLength: 4)
            if isTesting {
                ProgressView().controlSize(.small)
            } else {
                StatusBadge(channel.channelStatus)
            }
        }
        .padding(.vertical, 2)
    }
}
