import SwiftUI

/// Project-scoped API keys, with primary actions visible rather than schema-driven navigation.
struct KeysWorkspaceView: View {
    @ObservedObject var store: AxonStore
    var initialProjectID: String? = nil
    @State private var projects: [JSON] = []
    @State private var projectID = ""
    @State private var status = "all"
    @State private var loadedProject = ""
    @State private var search = ""
    @State private var rows: [JSON] = []
    @State private var total: Int?
    @State private var cursor: String?
    @State private var session: AdminSession?
    @State private var loading = false
    @State private var failure: String?
    @State private var creating = false
    @State private var editingKey: KeyEditorContext?
    @State private var archiveKey: JSON?
    @State private var confirmingArchive = false
    @State private var revision = UUID()
    @State private var ticket = UUID()
    @State private var selection = Set<String>()
    @State private var selecting = false
    @State private var appliedSearch = ""
    @State private var bulkAction: String?
    @State private var confirming = false
    @State private var writeUncertain = false
    private var queryKey: String { projectID + "|" + status + "|" + appliedSearch + "|" + revision.uuidString }

    var body: some View {
        List {
            if let session = session { AdminSessionFailure(session: session) }
            if writeUncertain {
                Section {
                    Text("写入可能已经完成。请关闭编辑器并刷新核对，勿重复提交。").font(.caption).foregroundStyle(.orange)
                    Button("刷新") { revision = UUID() }.disabled(session?.busy == true)
                }
            }
            if let failure = failure { Section { ObservabilityErrorView(message: failure); Button("重试") { revision = UUID() } } }
            if loading && rows.isEmpty { ProgressView("正在读取服务器数据") }
            if !loading && rows.isEmpty && failure == nil {
                Section {
                    ManagementEmptyView(symbol: "key", title: projectID.isEmpty ? "选择项目" : "没有符合条件的密钥")
                }
            }
            if let session = session, !rows.isEmpty {
                Section {
                    ForEach(rows.map(KeyWorkspaceItem.init)) { item in
                        let row = item.value
                        Button {
                            if selecting { select(row) } else { openKey(row, session: session) }
                        } label: {
                            HStack(spacing: 8) {
                                if selecting {
                                    Image(systemName: selection.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                        .frame(width: 44, height: 44)
                                }
                                KeySummaryRow(value: row).frame(maxWidth: .infinity, alignment: .leading)
                            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        .disabled(loading || writeUncertain || session.busy || session.invalidated)
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            if !selecting && !loading && !writeUncertain && !session.busy && !session.invalidated {
                                Button { openKey(row, session: session) } label: { Label("编辑", systemImage: "pencil") }.tint(Color(.darkGray))
                                if row["status"].string != "archived" {
                                    Button { toggleKey(row, session: session) } label: {
                                        Label(row["status"].string == "enabled" ? obsText("禁用") : obsText("启用"), systemImage: "power")
                                    }.tint(Color(.systemGray))
                                }
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if !selecting && !loading && !writeUncertain && !session.busy && !session.invalidated {
                                if row["status"].string != "archived" {
                                    Button { archiveKey = row; confirmingArchive = true } label: { Label("归档", systemImage: "archivebox") }.tint(.orange)
                                }
                                Button { selecting = true; select(row) } label: { Label("选择", systemImage: "checkmark.circle") }.tint(Color(.systemGray))
                            }
                        }
                        .contextMenu {
                            if !selecting {
                                Button { openKey(row, session: session) } label: { Label("编辑", systemImage: "pencil") }
                                    .disabled(loading || writeUncertain || session.busy || session.invalidated)
                            }
                            Button { selecting = true; select(row) } label: { Label("选择", systemImage: "checkmark.circle") }
                                .disabled(loading || writeUncertain || session.busy || session.invalidated)
                        }
                        .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                    }
                    if cursor != nil { Button("加载更多") { Task { await loadMore() } }.disabled(loading || session.busy) }
                } header: {
                    if let total = total { Text(String(format: obsText("共 %lld 条"), Int64(total))) }
                }
            }
        }
        .listStyle(.plain)
        .safeAreaInset(edge: .top, spacing: 0) { listFilters }
        .navigationTitle("密钥")
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: obsText("搜索密钥名称"))
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if selecting {
                    Button("完成") { selecting = false; selection = [] }.disabled(loading || session?.busy == true)
                }
                if !selection.isEmpty {
                    Menu {
                        Button { confirmBulk("bulkEnableAPIKeys") } label: { Label("启用", systemImage: "power") }
                        Button { confirmBulk("bulkDisableAPIKeys") } label: { Label("禁用", systemImage: "pause.circle") }
                        Button(role: .destructive) { confirmBulk("bulkArchiveAPIKeys") } label: { Label("归档", systemImage: "archivebox") }
                        Button { selection = []; selecting = false } label: { Label("取消选择", systemImage: "xmark.circle") }
                    } label: { Image(systemName: "checkmark.circle") }.disabled(writeUncertain || session?.busy == true)
                }
                Button { creating = true } label: { Label("新增密钥", systemImage: "plus") }
                    .disabled(projectID.isEmpty || session == nil || loading || writeUncertain || session?.busy == true)
                Menu {
                    Button { selecting.toggle(); selection = [] } label: { Label("选择", systemImage: "checkmark.circle") }
                        .disabled(loading || session?.busy == true)
                    NavigationLink { NativeAdminModuleView(store: store, module: .templates, initialProjectID: projectID.isEmpty ? nil : projectID) } label: {
                        Label("密钥策略模板", systemImage: "slider.horizontal.3")
                    }
                } label: { Image(systemName: "ellipsis.circle") }
                    .accessibilityLabel("操作")
                    .disabled(session?.busy == true || editingKey != nil || creating)
            }
        }
        .sheet(isPresented: $creating, onDismiss: { revision = UUID() }) {
            if let session = session, let operation = try? session.schema.operation("createAPIKey") {
                NavigationStack { NativeEntityEditor(session: session, operation: operation) }
            }
        }
        .sheet(item: $editingKey, onDismiss: { revision = UUID() }) { context in
            NavigationStack { KeyEditorSheet(context: context, session: context.session) }
        }
        .alert("确认操作", isPresented: $confirmingArchive) {
            Button("取消", role: .cancel) { archiveKey = nil }
            Button("归档", role: .destructive) {
                guard !writeUncertain, let session = session, let row = archiveKey, let op = try? session.schema.operation("bulkArchiveAPIKeys") else { return }
                session.start {
                    writeUncertain = true
                    _ = try await session.execute(op, variables: .object(["ids": .array([row["id"]])]))
                    writeUncertain = false; archiveKey = nil; revision = UUID()
                }
            }
        } message: {
            Text((archiveKey.map(NativeDisplay.name) ?? "") + "\n\n" + obsText("归档后密钥将停止访问，无法重新启用。"))
        }
        .alert("确认批量操作", isPresented: $confirming) {
            Button("取消", role: .cancel) { bulkAction = nil }
            if let action = bulkAction {
                Button(NativeAdminLabels.operation(action), role: action == "bulkArchiveAPIKeys" ? .destructive : nil) { executeBulk() }
            }
        } message: {
            Text(rows.filter { selection.contains($0["id"].string) }.map(NativeDisplay.name).joined(separator: "\n") + "\n\n" + (bulkAction == "bulkArchiveAPIKeys" ? obsText("归档后密钥将停止访问，无法重新启用。") : bulkAction == "bulkDisableAPIKeys" ? obsText("禁用立即停止此密钥的访问，策略和额度配置仍保留。") : obsText("启用后所选密钥将恢复访问。")))
        }
        .task(id: store.selectedInstance) {
            do {
                let system = try AdminSession(store: store, schema: AdminSchema.loaded.get())
                projects = try await system.read("myProjects", cached: true).array
                store.entityNames.register(projects)
                if projectID.isEmpty { projectID = initialProjectID ?? projects.first?["id"].string ?? "" }
                else { await loadFirst() }
            } catch { failure = error.localizedDescription }
        }
        .task(id: queryKey) { await loadFirst() }
        .task(id: search) {
            do { try await Task.sleep(nanoseconds: 300_000_000); try Task.checkCancellation(); appliedSearch = search }
            catch { }
        }
        .refreshable { store.pageCache.invalidate(); await loadFirst() }

        .onChange(of: projectID) { _ in
            if session?.connection.projectID != projectID {
                ticket = UUID(); session?.invalidate(); session = nil
                rows = []; total = nil; cursor = nil; loading = false
            }
            selection = []; selecting = false
            clearPresentations()
        }
        .onChange(of: store.selectedInstance) { _ in
            ticket = UUID(); session?.invalidate(); session = nil
            rows = []; total = nil; cursor = nil; loading = false
            projects = []; projectID = ""; loadedProject = ""; selection = []; selecting = false
            clearPresentations()
        }
    }
    private var listFilters: some View {
        HStack(spacing: 12) {
            Picker("项目", selection: $projectID) {
                Text("选择项目").tag("")
                ForEach(projects.map(KeyWorkspaceItem.init)) { item in Text(item.value["name"].string).tag(item.id) }
            }.pickerStyle(.menu).labelsHidden().accessibilityLabel("项目")
            Spacer(minLength: 0)
            Picker("状态筛选", selection: $status) {
                Text("全部").tag("all"); Text("启用中").tag("enabled")
                Text("已禁用").tag("disabled"); Text("已归档").tag("archived")
            }.pickerStyle(.menu).labelsHidden().accessibilityLabel("状态筛选")
        }
        .disabled(session?.busy == true)
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.regularMaterial)
    }
    @MainActor private func loadFirst() async {
        guard !projectID.isEmpty else { return }
        while session?.busy == true || editingKey != nil || creating {
            do { try await Task.sleep(nanoseconds: 100_000_000); try Task.checkCancellation() } catch { return }
        }
        guard !Task.isCancelled else { return }
        let generation = UUID(); ticket = generation
        let selectedProject = projectID
        if loadedProject != selectedProject { rows = []; total = nil; loadedProject = selectedProject }
        session?.invalidate(); selection = []; loading = true; failure = nil; cursor = nil
        defer { if ticket == generation { loading = false } }
        do {
            let next = try AdminSession(store: store, schema: AdminSchema.loaded.get(), projectID: selectedProject)
            session = next
            let result = try await next.read("apiKeys", variables: variables(after: nil), cached: true)
            try Task.checkCancellation()
            guard ticket == generation, projectID == selectedProject else { return }
            rows = result["edges"].array.map { $0["node"] }; store.entityNames.register(rows)
            total = result["totalCount"].isNull ? nil : result["totalCount"].int
            cursor = result["pageInfo"]["hasNextPage"].bool ? result["pageInfo"]["endCursor"].string : nil
            writeUncertain = false
        } catch {
            if ticket == generation && !(error is CancellationError) { rows = []; total = nil; failure = error.localizedDescription }
        }
    }
    private func variables(after: String?) -> JSON {
        var filter: [String: JSON] = ["projectID": .string(projectID)]
        if status != "all" { filter["status"] = .string(status) }
        if !appliedSearch.trimmed.isEmpty { filter["nameContainsFold"] = .string(appliedSearch.trimmed) }
        var vars: [String: JSON] = ["first": .number(25), "where": .object(filter)]
        if let after = after { vars["after"] = .string(after) }
        return .object(vars)
    }
    @MainActor private func loadMore() async {
        guard !loading, let session = session, let cursor = cursor else { return }
        let generation = ticket; loading = true
        defer { if ticket == generation { loading = false } }
        do {
            let result = try await session.read("apiKeys", variables: variables(after: cursor), cached: true)
            guard ticket == generation else { return }
            let page = result["edges"].array.map { $0["node"] }
            let existingIDs = Set(rows.map { $0["id"].string })
            rows += page.filter { !existingIDs.contains($0["id"].string) }; store.entityNames.register(page)
            self.cursor = result["pageInfo"]["hasNextPage"].bool ? result["pageInfo"]["endCursor"].string : nil
        } catch { if ticket == generation { failure = error.localizedDescription } }
    }
    private func clearPresentations() {
        editingKey = nil; creating = false; archiveKey = nil; confirmingArchive = false
        bulkAction = nil; confirming = false
    }
    @MainActor private func openKey(_ row: JSON, session: AdminSession) {
        guard !selecting, !loading, !writeUncertain, !session.busy, !session.invalidated,
              editingKey == nil, !creating, self.session === session,
              session.connection.projectID == projectID, !row["id"].string.isEmpty,
              row["projectID"].isNull || row["projectID"].string == projectID else { return }
        do {
            try session.validate()
            editingKey = KeyEditorContext(session: session, entityID: row["id"].string, projectID: projectID, title: NativeDisplay.name(row))
        } catch { failure = error.localizedDescription }
    }
    private func toggleKey(_ row: JSON, session: AdminSession) {
        guard !writeUncertain, !loading, let op = try? session.schema.operation("updateAPIKeyStatus") else { return }
        session.start {
            writeUncertain = true
            _ = try await session.execute(op, variables: .object(["id": row["id"], "status": .string(row["status"].string == "enabled" ? "disabled" : "enabled")]), baseline: row)
            writeUncertain = false; revision = UUID()
        }
    }
    private func select(_ row: JSON) { let id = row["id"].string; if selection.contains(id) { selection.remove(id) } else { selection.insert(id) } }
    private func confirmBulk(_ action: String) {
        guard !writeUncertain, !loading, session?.busy == false, !selection.isEmpty else { return }
        bulkAction = action; confirming = true
    }
    private func executeBulk() {
        guard !writeUncertain, !loading, let session = session, let action = bulkAction, let operation = try? session.schema.operation(action) else { return }
        let ids = selection.sorted()
        guard !ids.isEmpty else { return }
        session.start {
            writeUncertain = true
            _ = try await session.execute(operation, variables: .object(["ids": .array(ids.map(JSON.string))]))
            writeUncertain = false; selection = []; selecting = false; revision = UUID()
        }
    }
}

/// Capture the target before presenting; loading never gates sheet presentation.
private struct KeyEditorContext: Identifiable {
    let id = UUID()
    let session: AdminSession
    let entityID: String
    let projectID: String
    let title: String
}

private struct KeyEditorSheet: View {
    let context: KeyEditorContext
    @ObservedObject var session: AdminSession
    @State private var baseline: JSON = .null
    @State private var operation: AdminOperation?
    @State private var seed: JSON = .object([:])
    @State private var loading = false
    @State private var failure: String?
    @State private var revision = UUID()
    @State private var ticket = UUID()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            if let operation = operation, !baseline.isNull {
                NativeEntityEditor(session: session, operation: operation, seed: seed, baseline: baseline)
            } else {
                List {
                    if loading || failure == nil { ProgressView("正在读取服务器数据") }
                    if let failure = failure {
                        ObservabilityErrorView(message: failure)
                        Button("重试") { revision = UUID() }
                            .disabled(loading || session.busy || session.invalidated)
                    }
                }
                .navigationTitle(context.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                }
            }
        }
        .task(id: revision) { await load() }
        .interactiveDismissDisabled(session.busy)
        .onDisappear { ticket = UUID() }
        .onChange(of: session.invalidated) { invalid in if invalid { dismiss() } }
        .onChange(of: session.store.selectedInstance) { _ in dismiss() }
    }

    @MainActor private func load() async {
        guard baseline.isNull else { return }
        let generation = UUID(); ticket = generation
        loading = true; failure = nil
        defer { if ticket == generation { loading = false } }
        do {
            try session.validate()
            guard !session.busy else { throw AdminError.busy }
            guard session.connection.projectID == context.projectID else { throw AdminError.changedTarget }
            let nextOperation = try session.schema.operation("updateAPIKey")
            let value = try await session.detail("APIKey", id: context.entityID)
            try Task.checkCancellation()
            try session.validate()
            guard ticket == generation else { return }
            guard !value.isNull else { throw AdminError.notFound }
            guard value["id"].string == context.entityID,
                  value["projectID"].isNull || value["projectID"].string == context.projectID else { throw AdminError.changedTarget }
            var variables: [String: JSON] = ["id": .string(context.entityID)]
            if let input = nextOperation.variables.first(where: { $0.name == "input" }) {
                variables["input"] = session.schema.project(value, type: input.type)
            }
            seed = .object(variables); baseline = value; operation = nextOperation
        } catch is CancellationError { }
        catch {
            guard ticket == generation, !Task.isCancelled else { return }
            if session.invalidated { dismiss() }
            else { failure = error.localizedDescription }
        }
    }
}

private struct KeyWorkspaceItem: Identifiable {
    let value: JSON
    var id: String { value["id"].string }
    init(_ value: JSON) { self.value = value }
}

struct KeySummaryRow: View {
    let value: JSON
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(NativeDisplay.name(value)).font(.body.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 0)
                Text(NativeAdminLabels.value(value["status"].string)).font(.caption)
                    .foregroundStyle(value["status"].string == "enabled" ? Color.green : .secondary)
            }
            HStack(spacing: 8) {
                Text(value["type"].string == "user" ? obsText("项目密钥") : NativeAdminLabels.value(value["type"].string))
                if !value["profiles"]["activeProfile"].string.isEmpty { Text(value["profiles"]["activeProfile"].string).lineLimit(1).foregroundStyle(Color.accentColor) }
                if !value["allowedIps"].array.isEmpty {
                    Label(String(format: obsText("%lld 条 IP 限制"), Int64(value["allowedIps"].array.count)), systemImage: "shield.lefthalf.filled")
                }
            }.font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 2).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }
}


private struct AdminSessionFailure: View {
    @ObservedObject var session: AdminSession
    var body: some View {
        if let error = session.error, !session.invalidated { ObservabilityErrorView(message: error) }
    }
}
