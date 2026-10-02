import SwiftUI

struct ChannelRowView<Actions: View>: View {
    let channel: ChannelItem
    let canManage: Bool
    let onToggle: (Bool) -> Void
    let onTest: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    @ViewBuilder var moreActions: () -> Actions
    @State private var showingMore = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 12) {
                    BrandMark(asset: BrandIdentity.channel(channel.type), name: channel.name)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(channel.name).font(.headline).lineLimit(2)
                        Text(NativeAdminLabels.value(channel.type)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer(minLength: 0)

                }
                    if let url = channel.baseURL, !url.isEmpty { Text(url).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                    HStack {
                        Text(String(format: NSLocalizedString("支持模型：%lld 个", comment: ""), Int64(channel.supportedModels.count)))
                        Spacer()
                        Label(NativeAdminLabels.value(channel.status), systemImage: channel.isEnabled ? "checkmark.circle" : "pause.circle")
                    }.font(.caption).foregroundStyle(.secondary)
                    if !channel.tags.isEmpty { Text(channel.tags.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) }
                    if channel.errorMessage != nil { Label("渠道存在服务端错误", systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange) }
            }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
        }.clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous)).neutralCard()
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if canManage {
                Button(action: onEdit) { Label("编辑", systemImage: "pencil") }.tint(Color(.darkGray))
                Button(action: onTest) { Label("测试连通性", systemImage: "bolt") }.tint(Color(.systemGray2))
                Button { onToggle(!channel.isEnabled) } label: {
                    Label(channel.isEnabled ? obsText("禁用") : obsText("启用"), systemImage: channel.isEnabled ? "pause.circle" : "play.circle")
                }.tint(channel.isEnabled ? Color(.systemGray) : .green)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if canManage {
                Button(action: onDelete) { Label("删除", systemImage: "trash") }.tint(.red)
                Button { showingMore = true } label: { Label("更多操作", systemImage: "ellipsis") }.tint(Color(.systemGray))
            }
        }
        .contextMenu {
            if canManage {
                Button(action: onEdit) { Label("编辑", systemImage: "pencil") }
                Button(action: onTest) { Label("测试连通性", systemImage: "bolt") }
                Button { onToggle(!channel.isEnabled) } label: { Label(channel.isEnabled ? obsText("禁用") : obsText("启用"), systemImage: "power") }
                moreActions()
                Button("永久删除", role: .destructive, action: onDelete)
            }
        }
        .confirmationDialog("更多操作", isPresented: $showingMore, titleVisibility: .visible) { moreActions() }
        .accessibilityAction(named: Text("编辑")) { if canManage { onEdit() } }
    }
}

struct ChannelsListView: View {
    @ObservedObject var store: AxonStore
    @State private var filterText = ""
    @State private var statusFilter = "all"
    @State private var message: String?
    @State private var editor: ManagementTarget?
    @State private var tools: ManagementTarget?
    @State private var keyTarget: ManagementTarget?
    @State private var detailTools: ManagementTarget?
    @State private var duplicateID: String?
    @State private var deletion: ManagementTarget?
    @State private var showDeletion = false
    @State private var actionBusy = false

    var filteredChannels: [ChannelItem] {
        store.snapshot.channels.filter { (statusFilter == "all" || (statusFilter == "enabled" ? $0.isEnabled : !$0.isEnabled)) && (filterText.isEmpty || $0.name.localizedCaseInsensitiveContains(filterText) ||
            $0.type.localizedCaseInsensitiveContains(filterText) || $0.tags.contains { $0.localizedCaseInsensitiveContains(filterText) } ) }
    }
    var body: some View {
        List {
            Section {
                Picker("状态筛选", selection: $statusFilter) {
                    Text("全部").tag("all"); Text("启用中").tag("enabled"); Text("已禁用").tag("disabled")
                }.pickerStyle(.segmented)
            }

            if let error = store.error { Text(error).font(.caption).foregroundStyle(.orange) }
            if store.loading && store.snapshot.channels.isEmpty { ProgressView("正在读取服务器数据") }
            if store.snapshot.channels.isEmpty && !store.loading { Text(NSLocalizedString("暂无可用渠道", comment: "")).foregroundStyle(.secondary) }
            ForEach(filteredChannels) { channel in
                ChannelRowView(channel: channel, canManage: store.canManage,
                    onToggle: { enabled in run(channel.id) { target in try await store.toggleChannel(id: channel.id, enabled: enabled, target: target) } },
                    onTest: { run(channel.id) { target in
                        let (ok, ms, error) = try await store.testChannel(id: channel.id, target: target)
                        message = ok ? String(format: NSLocalizedString("测试成功！延迟：%lld ms", comment: ""), Int64(ms)) : error
                    } },
                    onEdit: { open(channel.id) }, onDelete: { confirmDelete(channel.id) }) {
                        Button(NSLocalizedString("复制渠道", comment: "")) { do { duplicateID = channel.id; editor = try store.managementTarget(kind: .channel) } catch { message = error.localizedDescription } }
                        Button(NSLocalizedString("归档", comment: "")) { do { let t = try store.managementTarget(kind: .channel, entityID: channel.id); tools = t } catch { message = error.localizedDescription } }
                        Button(NSLocalizedString("测试模型与价格", comment: "")) { do { detailTools = try store.managementTarget(kind: .channel, entityID: channel.id) } catch { message = error.localizedDescription } }
                        Button(NSLocalizedString("渠道密钥与禁用凭据", comment: "")) { do { keyTarget = try store.managementTarget(kind: .channel, entityID: channel.id) } catch { message = error.localizedDescription } }

                    }
                    .disabled(actionBusy || store.managementBusy)
                    .listRowInsets(EdgeInsets(top: 7, leading: 0, bottom: 7, trailing: 0))
                    .listRowSeparator(.hidden).listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $filterText, prompt: NSLocalizedString("搜索渠道名称、类型或标签", comment: ""))
        .refreshable { await store.refresh() }
        .navigationTitle(NSLocalizedString("渠道管理", comment: ""))
        .toolbar { if store.canManage {
            Button { open(nil) } label: { Label(NSLocalizedString("新增渠道", comment: ""), systemImage: "plus") }.disabled(actionBusy || store.managementBusy)
            Button { do { tools = try store.managementTarget(kind: .channel) } catch { message = error.localizedDescription } } label: {
                Label(NSLocalizedString("批量与工具", comment: ""), systemImage: "ellipsis.circle")
            }
        } }
        .sheet(item: $editor) { ManagementEditor(store: store, target: $0, duplicateID: duplicateID) }
        .sheet(item: $tools) { target in NavigationStack { ChannelModelToolsView(store: store, target: target) } }
        .sheet(item: $keyTarget) { target in NavigationStack { ChannelKeysView(store: store, target: target) } }
        .sheet(item: $detailTools) { target in NavigationStack { ChannelDetailToolsView(store: store, target: target) } }
        .confirmationDialog(NSLocalizedString("删除渠道", comment: ""), isPresented: $showDeletion, titleVisibility: .visible) {
            Button(NSLocalizedString("永久删除", comment: ""), role: .destructive) {
                guard let target = deletion else { return }
                actionBusy = true
                Task { defer { actionBusy = false; deletion = nil }; do { try await store.deleteManagedEntity(target) } catch { message = error.localizedDescription } }
            }
            Button(NSLocalizedString("取消", comment: ""), role: .cancel) { deletion = nil }
        } message: {
            Text(NSLocalizedString("这将从打开操作时的目标实例永久删除服务端渠道，可能中断模型路由。无法撤销。", comment: ""))
            if let target = deletion { Text(target.instance.name + " · " + (store.snapshot.channels.first { $0.id == target.entityID }?.name ?? "—")) }
        }
        .alert(NSLocalizedString("操作结果", comment: ""), isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button(NSLocalizedString("确定", comment: ""), role: .cancel) {}
        } message: { Text(message ?? "") }
    }
    private func open(_ id: String?) { do { duplicateID = nil; editor = try store.managementTarget(kind: .channel, entityID: id) } catch { message = error.localizedDescription } }
    private func confirmDelete(_ id: String) { do { deletion = try store.managementTarget(kind: .channel, entityID: id); showDeletion = true } catch { message = error.localizedDescription } }
    private func run(_ id: String, operation: @escaping (ManagementTarget) async throws -> Void) {
        guard !actionBusy else { return }
        do {
            let target = try store.managementTarget(kind: .channel, entityID: id)
            actionBusy = true
            Task { defer { actionBusy = false }; do { try await operation(target) } catch { message = error.localizedDescription } }
        } catch { message = error.localizedDescription }
    }
}
