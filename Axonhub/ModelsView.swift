import SwiftUI

struct ModelRowView<Actions: View>: View {
    let model: ModelItem
    let canManage: Bool
    let onToggle: (Bool) -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    @ViewBuilder var moreActions: () -> Actions
    @State private var showingMore = false
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 12) {
                    BrandMark(asset: BrandIdentity.asset(icon: model.icon), name: model.name)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(model.name).font(.headline).lineLimit(2)
                        Text(model.developer + " · " + NativeAdminLabels.value(model.type)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer(minLength: 0)

                }
                    Text(model.modelID).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                    Label(NativeAdminLabels.value(model.status), systemImage: model.isEnabled ? "checkmark.circle" : "pause.circle").font(.caption).foregroundStyle(.secondary)
            }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
        }.clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous)).neutralCard()
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if canManage {
                Button(action: onEdit) { Label("编辑", systemImage: "pencil") }.tint(Color(.darkGray))

                Button { onToggle(!model.isEnabled) } label: {
                    Label(model.isEnabled ? obsText("禁用") : obsText("启用"), systemImage: model.isEnabled ? "pause.circle" : "play.circle")
                }.tint(model.isEnabled ? Color(.systemGray) : .green)
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

                Button { onToggle(!model.isEnabled) } label: { Label(model.isEnabled ? obsText("禁用") : obsText("启用"), systemImage: "power") }
                moreActions()
                Button("永久删除", role: .destructive, action: onDelete)
            }
        }
        .confirmationDialog("更多操作", isPresented: $showingMore, titleVisibility: .visible) { moreActions() }
        .accessibilityAction(named: Text("编辑")) { if canManage { onEdit() } }
    }
}

struct ModelsListView: View {
    @ObservedObject var store: AxonStore
    @State private var filterText = ""
    @State private var statusFilter = "all"
    @State private var message: String?
    @State private var editor: ManagementTarget?
    @State private var tools: ManagementTarget?
    @State private var keyTarget: ManagementTarget?
    @State private var duplicateID: String?
    @State private var deletion: ManagementTarget?
    @State private var showDeletion = false
    @State private var actionBusy = false

    var filteredModels: [ModelItem] {
        store.snapshot.models.filter { (statusFilter == "all" || (statusFilter == "enabled" ? $0.isEnabled : !$0.isEnabled)) && (filterText.isEmpty || $0.name.localizedCaseInsensitiveContains(filterText) ||
            $0.modelID.localizedCaseInsensitiveContains(filterText) || $0.developer.localizedCaseInsensitiveContains(filterText) ) }
    }
    var body: some View {
        List {
            Section {
                Picker("状态筛选", selection: $statusFilter) {
                    Text("全部").tag("all"); Text("启用中").tag("enabled"); Text("已禁用").tag("disabled")
                }.pickerStyle(.segmented)
            }

            if let error = store.error { Text(error).font(.caption).foregroundStyle(.orange) }
            if store.loading && store.snapshot.models.isEmpty { ProgressView("正在读取服务器数据") }
            if store.snapshot.models.isEmpty && !store.loading { Text(NSLocalizedString("暂无模型列表", comment: "")).foregroundStyle(.secondary) }
            ForEach(filteredModels) { model in
                ModelRowView(model: model, canManage: store.canManage,
                    onToggle: { enabled in toggle(model.id, enabled: enabled) },
                    onEdit: { open(model.id) }, onDelete: { confirmDelete(model.id) }) {
                        Button(NSLocalizedString("复制模型", comment: "")) { do { duplicateID = model.id; editor = try store.managementTarget(kind: .model) } catch { message = error.localizedDescription } }
                        Button(NSLocalizedString("归档", comment: "")) { do { let t = try store.managementTarget(kind: .model, entityID: model.id); tools = t } catch { message = error.localizedDescription } }

                    }
                    .disabled(actionBusy || store.managementBusy)
                    .listRowInsets(EdgeInsets(top: 7, leading: 0, bottom: 7, trailing: 0))
                    .listRowSeparator(.hidden).listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $filterText, prompt: NSLocalizedString("搜索模型名称、ID 或厂商", comment: ""))
        .refreshable { await store.refresh() }
        .navigationTitle(NSLocalizedString("模型列表", comment: ""))
        .toolbar { if store.canManage {
            Button { open(nil) } label: { Label(NSLocalizedString("新增模型", comment: ""), systemImage: "plus") }.disabled(actionBusy || store.managementBusy)
            Button { do { tools = try store.managementTarget(kind: .model) } catch { message = error.localizedDescription } } label: {
                Label(NSLocalizedString("批量与工具", comment: ""), systemImage: "ellipsis.circle")
            }
        } }
        .sheet(item: $editor) { ManagementEditor(store: store, target: $0, duplicateID: duplicateID) }
        .sheet(item: $tools) { target in NavigationStack { ChannelModelToolsView(store: store, target: target) } }
        .confirmationDialog(NSLocalizedString("删除模型", comment: ""), isPresented: $showDeletion, titleVisibility: .visible) {
            Button(NSLocalizedString("永久删除", comment: ""), role: .destructive) {
                guard let target = deletion else { return }
                actionBusy = true
                Task { defer { actionBusy = false; deletion = nil }; do { try await store.deleteManagedEntity(target) } catch { message = error.localizedDescription } }
            }
            Button(NSLocalizedString("取消", comment: ""), role: .cancel) { deletion = nil }
        } message: {
            Text(NSLocalizedString("这将从打开操作时的目标实例永久删除服务端模型，客户端将无法继续使用该模型。无法撤销。", comment: ""))
            if let target = deletion { Text(target.instance.name + " · " + (store.snapshot.models.first { $0.id == target.entityID }?.name ?? "—")) }
        }
        .alert(NSLocalizedString("操作结果", comment: ""), isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button(NSLocalizedString("确定", comment: ""), role: .cancel) {}
        } message: { Text(message ?? "") }
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
