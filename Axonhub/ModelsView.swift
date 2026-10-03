import SwiftUI

struct ModelRowView<Actions: View>: View {
    let model: ModelItem
    let canManage: Bool
    let onToggle: (Bool) -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onMore: () -> Void
    @ViewBuilder var moreActions: () -> Actions

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onEdit) {
                HStack(alignment: .top, spacing: 12) {
                    BrandMark(asset: BrandIdentity.asset(icon: model.icon), name: model.name)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(model.name).font(.headline).lineLimit(2)
                            Spacer(minLength: 8)
                            Text(NativeAdminLabels.value(model.status))
                                .font(.caption).foregroundStyle(model.isEnabled ? Color.green : .secondary)
                        }
                        HStack(spacing: 8) {
                            if model.modelID != model.name { Text(model.modelID).font(.caption.monospaced()).lineLimit(1) }
                            Text(model.developer + " · " + NativeAdminLabels.value(model.type)).lineLimit(1)
                        }.font(.caption).foregroundStyle(.secondary)
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
                Button { onToggle(!model.isEnabled) } label: {
                    Label(model.isEnabled ? obsText("禁用") : obsText("启用"), systemImage: "power")
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
        Button { onToggle(!model.isEnabled) } label: { Label(model.isEnabled ? obsText("禁用") : obsText("启用"), systemImage: "power") }
        moreActions()
        Button(role: .destructive) { onDelete() } label: { Label("永久删除", systemImage: "trash") }
    }
}

struct ModelsListView: View {
    @ObservedObject var store: AxonStore
    var embedded = false
    var gatewayTab: Binding<GatewaySubTab>? = nil
    var gatewaySearch: Binding<String>? = nil
    @State private var filterText = ""
    private var query: String { gatewaySearch?.wrappedValue ?? filterText }
    @State private var statusFilter = "all"
    @State private var message: String?
    @State private var editor: ManagementTarget?
    @State private var tools: ManagementTarget?
    @State private var keyTarget: ManagementTarget?
    @State private var duplicateID: String?
    @State private var deletion: ManagementTarget?
    @State private var showDeletion = false
    @State private var archiveTarget: ManagementTarget?
    @State private var showArchive = false
    @State private var actionBusy = false

    var filteredModels: [ModelItem] {
        store.snapshot.models.filter { (statusFilter == "all" || (statusFilter == "enabled" ? $0.isEnabled : !$0.isEnabled)) && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) ||
            $0.modelID.localizedCaseInsensitiveContains(query) || $0.developer.localizedCaseInsensitiveContains(query) ) }
    }
    var body: some View {
        List {
            if let error = store.error { Text(error).font(.caption).foregroundStyle(.orange) }
            if store.loading && store.snapshot.models.isEmpty { ProgressView("正在读取服务器数据") }
            if filteredModels.isEmpty && !store.loading && store.error == nil {
                Text("没有符合条件的记录").foregroundStyle(.secondary)
            }
            entityRows
        }
        .listStyle(.plain)
        .safeAreaInset(edge: .top, spacing: 0) { listFilters }
        .modifier(GatewaySearchPresentation(enabled: gatewaySearch == nil, text: $filterText, prompt: obsText("搜索模型名称、ID 或厂商")))
        .refreshable { await store.refresh() }
        .navigationTitle(embedded ? obsText("网关") : obsText("模型列表"))
        .toolbar { if store.canManage {
            Button { open(nil) } label: { Label(NSLocalizedString("新增模型", comment: ""), systemImage: "plus") }.disabled(actionBusy || store.managementBusy)
            Button { do { tools = try store.managementTarget(kind: .model) } catch { message = error.localizedDescription } } label: {
                Label(NSLocalizedString("批量与工具", comment: ""), systemImage: "ellipsis.circle")
            }
        } }
        .sheet(item: $editor) { ManagementEditor(store: store, target: $0, duplicateID: duplicateID) }
        .sheet(item: $tools) { target in NavigationStack { ChannelModelToolsView(store: store, target: target)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { tools = nil } } }
        } }
        .alert(NSLocalizedString("删除模型", comment: ""), isPresented: $showDeletion) {
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
        GatewayListFilters(tab: gatewayTab, status: $statusFilter, count: filteredModels.count)
    }
    private var deleteConfirmationMessage: String {
        obsText("这将从打开操作时的目标实例永久删除服务端模型，客户端将无法继续使用该模型。无法撤销。") + "\n" + (deletion.map { target in target.instance.name + " · " + (store.snapshot.models.first { $0.id == target.entityID }?.name ?? "—") } ?? "")
    }
    private var archiveConfirmationMessage: String {
        (archiveTarget.map { target in target.instance.name + " · " + (store.snapshot.models.first { $0.id == target.entityID }?.name ?? "—") } ?? "") + "\n" + obsText("确认操作")
    }
    private var entityRows: some View {
        ForEach(filteredModels) { model in
            entityRow(model)
        }
    }
    private func entityRow(_ model: ModelItem) -> some View {
                ModelRowView(model: model, canManage: store.canManage,
                    onToggle: { enabled in toggle(model.id, enabled: enabled) },
                    onEdit: { open(model.id) }, onDelete: { confirmDelete(model.id) },
                    onMore: { do { tools = try store.managementTarget(kind: .model, entityID: model.id) } catch { message = error.localizedDescription } }) {
                        Button { do { duplicateID = model.id; editor = try store.managementTarget(kind: .model) } catch { message = error.localizedDescription } } label: { Label("复制模型", systemImage: "doc.on.doc") }
                        Button { do { archiveTarget = try store.managementTarget(kind: .model, entityID: model.id); showArchive = true } catch { message = error.localizedDescription } } label: { Label("归档", systemImage: "archivebox") }

                    }
                    .disabled(actionBusy || store.managementBusy)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 8))
    }
    private func open(_ id: String?) { do { duplicateID = nil; editor = try store.managementTarget(kind: .model, entityID: id) } catch { message = error.localizedDescription } }
    private func confirmDelete(_ id: String) { do { deletion = try store.managementTarget(kind: .model, entityID: id); showDeletion = true } catch { message = error.localizedDescription } }
    private func toggle(_ id: String, enabled: Bool) {
        guard !actionBusy else { return }
        do {
            let target = try store.managementTarget(kind: .model, entityID: id)
            actionBusy = true
            Task { defer { actionBusy = false }; do { try await store.toggleModel(id: id, enabled: enabled, target: target) } catch { message = error.localizedDescription } }
        } catch { message = error.localizedDescription }
    }
}
