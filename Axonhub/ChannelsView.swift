import SwiftUI

struct ChannelRowView<Actions: View>: View {
    let channel: ChannelItem
    let canManage: Bool
    let onToggle: (Bool) -> Void
    let onTest: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onMore: () -> Void
    @ViewBuilder var moreActions: () -> Actions

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onEdit) {
                HStack(alignment: .top, spacing: 12) {
                    BrandMark(asset: BrandIdentity.channel(channel.type), name: channel.name)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(channel.name).font(.headline).lineLimit(2)
                            Spacer(minLength: 8)
                            Text(NativeAdminLabels.value(channel.status))
                                .font(.caption).foregroundStyle(channel.isEnabled ? Color.green : .secondary)
                        }
                        HStack(spacing: 8) {
                            Text(NativeAdminLabels.value(channel.type)).lineLimit(1)
                            if !channel.tags.isEmpty { Text(channel.tags.joined(separator: " · ")).lineLimit(1) }
                        }.font(.caption).foregroundStyle(.secondary)
                        if channel.errorMessage != nil { Label("渠道存在服务端错误", systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange) }
                    }
                }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(!canManage)
            if canManage {
                Menu { rowActions } label: {
                    Label("更多操作", systemImage: "ellipsis.circle").labelStyle(.iconOnly).frame(width: 44, height: 44)
                }.buttonStyle(.borderless)
            }
        }.padding(.vertical, 4)
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if canManage {
                Button(action: onEdit) { Label("编辑", systemImage: "pencil") }.tint(Color(.darkGray))
                Button { onToggle(!channel.isEnabled) } label: {
                    Label(channel.isEnabled ? obsText("禁用") : obsText("启用"), systemImage: "power")
                }.tint(Color(.systemGray))
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if canManage {
                Button(action: onDelete) { Label("删除", systemImage: "trash") }.tint(.red)
                Button(action: onMore) { Label("批量与工具", systemImage: "ellipsis") }.tint(Color(.systemGray))
            }
        }
        .contextMenu { if canManage { rowActions } }
        .accessibilityAction(named: Text("编辑")) { if canManage { onEdit() } }
    }
    @ViewBuilder private var rowActions: some View {
        Button { onEdit() } label: { Label("编辑", systemImage: "pencil") }
        Button { onTest() } label: { Label("测试连通性", systemImage: "bolt") }
        Button { onToggle(!channel.isEnabled) } label: { Label(channel.isEnabled ? obsText("禁用") : obsText("启用"), systemImage: "power") }
        moreActions()
        Button(role: .destructive) { onDelete() } label: { Label("永久删除", systemImage: "trash") }
    }
}

struct ChannelsListView: View {
    @ObservedObject var store: AxonStore
    var embedded = false
    var gatewayTab: Binding<GatewaySubTab>? = nil
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
    @State private var archiveTarget: ManagementTarget?
    @State private var showArchive = false
    @State private var actionBusy = false

    var filteredChannels: [ChannelItem] {
        store.snapshot.channels.filter { (statusFilter == "all" || (statusFilter == "enabled" ? $0.isEnabled : !$0.isEnabled)) && (filterText.isEmpty || $0.name.localizedCaseInsensitiveContains(filterText) ||
            $0.type.localizedCaseInsensitiveContains(filterText) || $0.tags.contains { $0.localizedCaseInsensitiveContains(filterText) } ) }
    }
    var body: some View {
        List {
            if let error = store.error { Text(error).font(.caption).foregroundStyle(.orange) }
            if store.loading && store.snapshot.channels.isEmpty { ProgressView("正在读取服务器数据") }
            if filteredChannels.isEmpty && !store.loading && store.error == nil {
                Text("没有符合条件的记录").foregroundStyle(.secondary)
            }
            entityRows
        }
        .listStyle(.plain)
        .safeAreaInset(edge: .top, spacing: 0) { listFilters }
        .searchable(text: $filterText, prompt: NSLocalizedString("搜索渠道名称、类型或标签", comment: ""))
        .refreshable { await store.refresh() }
        .navigationTitle(embedded ? obsText("网关") : obsText("渠道管理"))
        .toolbar { if store.canManage {
            Button { open(nil) } label: { Label(NSLocalizedString("新增渠道", comment: ""), systemImage: "plus") }.disabled(actionBusy || store.managementBusy)
            Button { do { tools = try store.managementTarget(kind: .channel) } catch { message = error.localizedDescription } } label: {
                Label(NSLocalizedString("批量与工具", comment: ""), systemImage: "ellipsis.circle")
            }
        } }
        .sheet(item: $editor) { ManagementEditor(store: store, target: $0, duplicateID: duplicateID) }
        .sheet(item: $tools) { target in NavigationStack { ChannelModelToolsView(store: store, target: target)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { tools = nil } } }
        } }
        .sheet(item: $keyTarget) { target in NavigationStack { ChannelKeysView(store: store, target: target)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { keyTarget = nil } } }
        } }
        .sheet(item: $detailTools) { target in NavigationStack { ChannelDetailToolsView(store: store, target: target)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { detailTools = nil } } }
        } }
        .alert(NSLocalizedString("删除渠道", comment: ""), isPresented: $showDeletion) {
            Button(NSLocalizedString("永久删除", comment: ""), role: .destructive) {
                guard let target = deletion else { return }
                actionBusy = true
                Task { defer { actionBusy = false; deletion = nil }; do { try await store.deleteManagedEntity(target) } catch { message = error.localizedDescription } }
            }
            Button(NSLocalizedString("取消", comment: ""), role: .cancel) { deletion = nil }
        } message: {
            Text(deleteConfirmationMessage)
        }
        .alert("归档", isPresented: $showArchive) {
            Button("归档", role: .destructive) {
                guard let target = archiveTarget, let id = target.entityID else { return }
                actionBusy = true
                Task {
                    defer { actionBusy = false; archiveTarget = nil }
                    do { _ = try await store.managedBatch(target, ids: [id], action: .archive) }
                    catch { message = error.localizedDescription }
                }
            }
            Button("取消", role: .cancel) { archiveTarget = nil }
        } message: {
            Text(archiveConfirmationMessage)
        }
        .alert(NSLocalizedString("操作结果", comment: ""), isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button(NSLocalizedString("确定", comment: ""), role: .cancel) {}
        } message: { Text(message ?? "") }
    }
    private var listFilters: some View {
        GatewayListFilters(tab: gatewayTab, status: $statusFilter, count: filteredChannels.count)
    }
    private var deleteConfirmationMessage: String {
        obsText("这将从打开操作时的目标实例永久删除服务端渠道，可能中断模型路由。无法撤销。") + "\n" + (deletion.map { target in target.instance.name + " · " + (store.snapshot.channels.first { $0.id == target.entityID }?.name ?? "—") } ?? "")
    }
    private var archiveConfirmationMessage: String {
        (archiveTarget.map { target in target.instance.name + " · " + (store.snapshot.channels.first { $0.id == target.entityID }?.name ?? "—") } ?? "") + "\n" + obsText("确认操作")
    }
    private var entityRows: some View {
        ForEach(filteredChannels) { channel in
            entityRow(channel)
        }
    }
    private func entityRow(_ channel: ChannelItem) -> some View {
                ChannelRowView(channel: channel, canManage: store.canManage,
                    onToggle: { enabled in run(channel.id) { target in try await store.toggleChannel(id: channel.id, enabled: enabled, target: target) } },
                    onTest: { run(channel.id) { target in
                        let (ok, ms, error) = try await store.testChannel(id: channel.id, target: target)
                        message = ok ? String(format: NSLocalizedString("测试成功！延迟：%lld ms", comment: ""), Int64(ms)) : error
                    } },
                    onEdit: { open(channel.id) }, onDelete: { confirmDelete(channel.id) },
                    onMore: { do { tools = try store.managementTarget(kind: .channel, entityID: channel.id) } catch { message = error.localizedDescription } }) {
                        Button { do { duplicateID = channel.id; editor = try store.managementTarget(kind: .channel) } catch { message = error.localizedDescription } } label: { Label("复制渠道", systemImage: "doc.on.doc") }
                        Button { do { archiveTarget = try store.managementTarget(kind: .channel, entityID: channel.id); showArchive = true } catch { message = error.localizedDescription } } label: { Label("归档", systemImage: "archivebox") }
                        Button { do { detailTools = try store.managementTarget(kind: .channel, entityID: channel.id) } catch { message = error.localizedDescription } } label: { Label("测试模型与价格", systemImage: "bolt") }
                        Button { do { keyTarget = try store.managementTarget(kind: .channel, entityID: channel.id) } catch { message = error.localizedDescription } } label: { Label("渠道密钥与禁用凭据", systemImage: "key") }

                    }
                    .disabled(actionBusy || store.managementBusy)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 8))
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
