import SwiftUI

struct ModelsView: View {
    @Environment(SessionStore.self) private var session
    @State private var loader = PagedLoader<AIModel>()
    @State private var filter = AxonService.ModelFilter()
    @State private var query = ""
    @State private var toast: Toast?
    @State private var pendingDelete: AIModel?

    var body: some View {
        List {
            ForEach(loader.items) { model in
                NavigationLink {
                    ModelDetailView(model: model)
                } label: {
                    ModelRow(model: model)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button("删除", systemImage: "trash", role: .destructive) { pendingDelete = model }
                    Button(model.modelStatus == .enabled ? "停用" : "启用",
                           systemImage: model.modelStatus == .enabled ? "pause.circle" : "play.circle") {
                        Task { await toggle(model) }
                    }
                    .tint(model.modelStatus == .enabled ? .orange : .green)
                }
                .task { await loader.loadMoreIfNeeded(current: model) }
            }
            LoadMoreFooter(isLoading: loader.isLoadingMore)
        }
        .listStyle(.insetGrouped)
        .overlay {
            ListStateOverlay(loader: loader, emptyTitle: "没有模型", emptyImage: "cpu",
                             emptyMessage: "模型在网页端或通过渠道同步后会出现在这里")
        }
        .navigationTitle("模型")
        .searchable(text: $query, prompt: "搜索模型 ID、名称或厂商")
        .onSubmit(of: .search) { filter.search = query }
        .onChange(of: query) { _, value in if value.isEmpty { filter.search = "" } }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("状态", selection: $filter.status) {
                        Text("全部（不含归档）").tag(ResourceStatus?.none)
                        ForEach(ResourceStatus.allCases, id: \.self) { Text($0.label).tag(ResourceStatus?.some($0)) }
                    }
                } label: {
                    Image(systemName: filter.status == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }
            }
        }
        .confirmationDialog("删除模型？", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible, presenting: pendingDelete) { model in
            Button("删除 \(model.modelID)", role: .destructive) { Task { await delete(model) } }
        }
        .toast($toast)
        .refreshable { await loader.reload() }
        .task(id: filter) {
            guard let service = session.service else { return }
            let filter = filter
            loader.fetch = { cursor in try await service.models(after: cursor, filter: filter) }
            await loader.reload()
        }
    }

    private func toggle(_ model: AIModel) async {
        guard let service = session.service else { return }
        let target: ResourceStatus = model.modelStatus == .enabled ? .disabled : .enabled
        do {
            try await service.setModelStatus(id: model.id, status: target)
            await loader.reload()
            toast = Toast(message: "\(model.modelID) \(target.label)")
        } catch {
            toast = Toast(message: error.localizedDescription, isError: true)
        }
    }

    private func delete(_ model: AIModel) async {
        guard let service = session.service else { return }
        do {
            try await service.deleteModel(id: model.id)
            withAnimation { loader.remove(id: model.id) }
        } catch {
            toast = Toast(message: error.localizedDescription, isError: true)
        }
    }
}

struct ModelRow: View {
    let model: AIModel

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(model.modelID).font(.callout.weight(.medium).monospaced()).lineLimit(1)
                Spacer(minLength: 4)
                if model.modelStatus != .enabled { StatusBadge(model.modelStatus) }
            }
            HStack(spacing: 8) {
                Text(model.developer)
                if let count = model.associatedChannelCount {
                    Label("\(count)", systemImage: "server.rack")
                }
                if let limit = model.modelCard?.limit, limit.context > 0 {
                    Label(Fmt.compact(limit.context), systemImage: "text.alignleft")
                }
                if let cost = model.modelCard?.cost {
                    Text("$\(Self.price(cost.input)) / $\(Self.price(cost.output))")
                }
                capabilityIcons
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .labelStyle(CompactLabelStyle())
            .lineLimit(1)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var capabilityIcons: some View {
        if let card = model.modelCard {
            if card.vision == true { Image(systemName: "eye") }
            if card.toolCall == true { Image(systemName: "wrench.and.screwdriver") }
            if card.reasoning?.supported == true { Image(systemName: "brain") }
        }
    }

    static func price(_ value: Double) -> String {
        value == value.rounded() ? String(format: "%.0f", value) : String(format: "%.2f", value)
    }
}

struct ModelDetailView: View {
    let model: AIModel

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.name.isEmpty ? model.modelID : model.name).font(.title3.weight(.semibold))
                    Text(model.modelID).font(.callout.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                    HStack {
                        StatusBadge(model.modelStatus)
                        Tag(text: model.type)
                    }
                }
                .padding(.vertical, 4)
            }
            Section("信息") {
                KeyValueRow(key: "厂商", value: model.developer)
                if let group = model.group?.nilIfBlank { KeyValueRow(key: "分组", value: group) }
                KeyValueRow(key: "关联渠道", value: String(model.associatedChannelCount ?? 0))
                if let remark = model.remark?.nilIfBlank { KeyValueRow(key: "备注", value: remark) }
                KeyValueRow(key: "创建时间", value: Fmt.dateTime(model.createdAt))
            }
            if let card = model.modelCard {
                Section("能力") {
                    capability("工具调用", card.toolCall)
                    capability("视觉", card.vision)
                    capability("推理", card.reasoning?.supported)
                    capability("温度参数", card.temperature)
                    if let input = card.modalities?.input, !input.isEmpty {
                        KeyValueRow(key: "输入模态", value: input.joined(separator: ", "))
                    }
                    if let output = card.modalities?.output, !output.isEmpty {
                        KeyValueRow(key: "输出模态", value: output.joined(separator: ", "))
                    }
                    if let knowledge = card.knowledge?.nilIfBlank { KeyValueRow(key: "知识截止", value: knowledge) }
                    if let release = card.releaseDate?.nilIfBlank { KeyValueRow(key: "发布日期", value: release) }
                }
                if let limit = card.limit {
                    Section("上下文") {
                        KeyValueRow(key: "上下文窗口", value: Fmt.grouped(limit.context))
                        KeyValueRow(key: "最大输出", value: Fmt.grouped(limit.output))
                    }
                }
                if let cost = card.cost {
                    Section {
                        KeyValueRow(key: "输入", value: "$" + ModelRow.price(cost.input))
                        KeyValueRow(key: "输出", value: "$" + ModelRow.price(cost.output))
                        if let read = cost.cacheRead { KeyValueRow(key: "缓存读取", value: "$" + ModelRow.price(read)) }
                        if let write = cost.cacheWrite { KeyValueRow(key: "缓存写入", value: "$" + ModelRow.price(write)) }
                    } header: {
                        Text("价格")
                    } footer: {
                        Text("单位：美元 / 百万 Token")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(model.modelID)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func capability(_ title: String, _ value: Bool?) -> some View {
        HStack {
            Text(title)
            Spacer()
            Image(systemName: value == true ? "checkmark.circle.fill" : "minus.circle")
                .foregroundStyle(value == true ? Theme.success : .secondary)
        }
    }
}
