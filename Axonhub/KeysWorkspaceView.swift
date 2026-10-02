import SwiftUI

/// Project-scoped API keys, with primary actions visible rather than schema-driven navigation.
struct KeysWorkspaceView: View {
    @ObservedObject var store: AxonStore
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
    @State private var editingKey: JSON?
    @State private var archiveKey: JSON?
    @State private var confirmingArchive = false
    @State private var revision = UUID()
    @State private var ticket = UUID()
    @State private var selection = Set<String>()
    @State private var selecting = false
    @State private var appliedSearch = ""
    @State private var bulkAction: String?
    @State private var confirming = false
    private var queryKey: String { projectID + "|" + status + "|" + appliedSearch + "|" + revision.uuidString }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("项目访问密钥").font(.headline)
                    Text("选择项目，管理应用接入、策略与额度。").font(.subheadline).foregroundStyle(.secondary)
                }.padding(.vertical, 6)
                Picker("项目", selection: $projectID) {
                    Text("选择项目").tag("")
                    ForEach(projects, id: \.self) { Text($0["name"].string).tag($0["id"].string) }
                }.disabled(session?.busy == true)
                Picker("状态筛选", selection: $status) {
                    Text("全部").tag("all"); Text("启用中").tag("enabled")
                    Text("已禁用").tag("disabled"); Text("已归档").tag("archived")
                }.pickerStyle(.segmented).disabled(session?.busy == true)
            }
            if let session = session { AdminSessionFailure(session: session) }
            if let failure = failure { Section { ObservabilityErrorView(message: failure); Button("重试") { revision = UUID() } } }
            if loading && rows.isEmpty { ProgressView("正在读取服务器数据") }
            if !loading && rows.isEmpty && failure == nil {
                Section {
                    ManagementEmptyView(symbol: "key", title: projectID.isEmpty ? "选择项目" : "没有符合条件的密钥")
                    if !projectID.isEmpty { Button("创建第一把密钥") { creating = true }.disabled(session == nil) }
                }
            }
            if let session = session, !rows.isEmpty {
                Section {
                    ForEach(rows, id: \.self) { row in
                        HStack(spacing: 12) {
                            if selecting {
                                Button { select(row) } label: { Image(systemName: selection.contains(row["id"].string) ? "checkmark.circle.fill" : "circle") }
                                    .buttonStyle(.plain).frame(width: 44, height: 44)
                            }
                            NavigationLink { NativeEntityDetailView(session: session, module: .apiKeys, id: row["id"].string) } label: { KeySummaryRow(value: row) }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            if !selecting && !session.busy {
                                Button { editKey(row, session: session) } label: { Label("编辑", systemImage: "pencil") }.tint(Color(.darkGray))
                                if row["status"].string != "archived" {
                                    Button { toggleKey(row, session: session) } label: {
                                        Label(row["status"].string == "enabled" ? obsText("禁用") : obsText("启用"), systemImage: "power")
                                    }.tint(Color(.systemGray))
                                }
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if !selecting && !session.busy {
                                if row["status"].string != "archived" {
                                    Button { archiveKey = row; confirmingArchive = true } label: { Label("归档", systemImage: "archivebox") }.tint(.orange)
                                }
                                Button { selecting = true; select(row) } label: { Label("选择", systemImage: "checkmark.circle") }.tint(Color(.systemGray))
                            }
                        }
                        .contextMenu {
                            Button { editKey(row, session: session) } label: { Label("编辑", systemImage: "pencil") }
                            Button("选择") { selecting = true; select(row) }
                        }
                        .listRowInsets(EdgeInsets(top: 7, leading: 0, bottom: 7, trailing: 0))
                        .listRowSeparator(.hidden).listRowBackground(Color.clear)
                    }
                    if cursor != nil { Button("加载更多") { Task { await loadMore() } }.disabled(loading || session.busy) }
                } header: {
                    Text(total.map { String(format: obsText("共 %lld 条"), Int64($0)) } ?? obsText("API 密钥"))
                }
            }
            Section("策略") {
                NavigationLink { NativeAdminModuleView(store: store, module: .templates, initialProjectID: projectID.isEmpty ? nil : projectID) } label: {
                    Label("密钥策略模板", systemImage: "slider.horizontal.3")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("密钥")
        .searchable(text: $search, prompt: obsText("搜索密钥名称"))
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button(selecting ? "完成" : "选择") { selecting.toggle(); selection = [] }.disabled(loading || session?.busy == true)
                if !selection.isEmpty {
                    Menu {
                        Button("启用") { confirmBulk("bulkEnableAPIKeys") }
                        Button("禁用") { confirmBulk("bulkDisableAPIKeys") }
                        Button("归档", role: .destructive) { confirmBulk("bulkArchiveAPIKeys") }
                        Button("取消选择") { selection = []; selecting = false }
                    } label: { Image(systemName: "checkmark.circle") }.disabled(session?.busy == true)
                }
                Button { creating = true } label: { Label("新增密钥", systemImage: "plus") }
                    .disabled(projectID.isEmpty || session == nil || loading || session?.busy == true)
            }
        }
        .sheet(isPresented: $creating, onDismiss: { revision = UUID() }) {
            if let session = session, let operation = try? session.schema.operation("createAPIKey") {
                NavigationStack { NativeEntityEditor(session: session, operation: operation) }
            }
        }
        .sheet(isPresented: Binding(get: { editingKey != nil }, set: { if !$0 { editingKey = nil } }), onDismiss: { revision = UUID() }) {
            if let session = session, let baseline = editingKey, let operation = try? session.schema.operation("updateAPIKey"), let input = operation.variables.first(where: { $0.name == "input" }) {
                NavigationStack {
                    NativeEntityEditor(session: session, operation: operation, seed: .object(["id": baseline["id"], "input": session.schema.project(baseline, type: input.type)]), baseline: baseline)
                }
            }
        }
        .confirmationDialog("确认操作", isPresented: $confirmingArchive, titleVisibility: .visible) {
            Button("归档", role: .destructive) {
                guard let session = session, let row = archiveKey, let op = try? session.schema.operation("bulkArchiveAPIKeys") else { return }
                session.start {
                    _ = try await session.execute(op, variables: .object(["ids": .array([row["id"]])]))
                    archiveKey = nil; revision = UUID()
                }
            }
        } message: { Text(archiveKey.map(NativeDisplay.name) ?? "") }
        .confirmationDialog("确认批量操作", isPresented: $confirming, titleVisibility: .visible) {
            if let action = bulkAction {
                Button(NativeAdminLabels.operation(action), role: action == "bulkArchiveAPIKeys" ? .destructive : nil) { executeBulk() }
            }
        } message: { Text(rows.filter { selection.contains($0["id"].string) }.map(NativeDisplay.name).joined(separator: "\n")) }
        .task {
            do {
                let system = try AdminSession(store: store, schema: AdminSchema.loaded.get())
                projects = try await system.read("myProjects", cached: true).array
                store.entityNames.register(projects)
                if projectID.isEmpty { projectID = projects.first?["id"].string ?? "" }
                else { await loadFirst() }
            } catch { failure = error.localizedDescription }
        }
        .task(id: queryKey) { await loadFirst() }
        .task(id: search) {
            do { try await Task.sleep(nanoseconds: 300_000_000); try Task.checkCancellation(); appliedSearch = search }
            catch { }
        }
        .refreshable { store.pageCache.invalidate(); await loadFirst() }

        .onChange(of: projectID) { _ in rows = []; total = nil; selection = [] }
        .onChange(of: store.selectedInstance) { _ in
            ticket = UUID(); session?.invalidate(); session = nil; rows = []; projects = []; projectID = ""; selection = []
        }
    }
    @MainActor private func loadFirst() async {
        guard !projectID.isEmpty else { return }
        while session?.busy == true {
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
            rows += page; store.entityNames.register(page)
            self.cursor = result["pageInfo"]["hasNextPage"].bool ? result["pageInfo"]["endCursor"].string : nil
        } catch { if ticket == generation { failure = error.localizedDescription } }
    }
    private func editKey(_ row: JSON, session: AdminSession) {
        session.start { editingKey = try await session.detail("APIKey", id: row["id"].string) }
    }
    private func toggleKey(_ row: JSON, session: AdminSession) {
        guard let op = try? session.schema.operation("updateAPIKeyStatus") else { return }
        session.start {
            _ = try await session.execute(op, variables: .object(["id": row["id"], "status": .string(row["status"].string == "enabled" ? "disabled" : "enabled")]), baseline: row)
            revision = UUID()
        }
    }
    private func select(_ row: JSON) { let id = row["id"].string; if selection.contains(id) { selection.remove(id) } else { selection.insert(id) } }
    private func confirmBulk(_ action: String) { bulkAction = action; confirming = true }
    private func executeBulk() {
        guard let session = session, let action = bulkAction, let operation = try? session.schema.operation(action) else { return }
        let ids = selection.sorted()
        session.start {
            _ = try await session.execute(operation, variables: .object(["ids": .array(ids.map(JSON.string))]))
            selection = []; selecting = false; revision = UUID()
        }
    }
}

struct KeySummaryRow: View {
    let value: JSON
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                Image(systemName: "key.fill").foregroundStyle(Color.accentColor)
                Text(NativeDisplay.name(value)).font(.headline).lineLimit(2)
                Spacer(minLength: 0)
                Text(NativeAdminLabels.value(value["status"].string)).font(.caption)
                    .foregroundStyle(value["status"].string == "enabled" ? Color.green : .secondary)
            }
            HStack(spacing: 8) {
                Text(value["type"].string == "user" ? obsText("项目密钥") : NativeAdminLabels.value(value["type"].string))
                if !value["profiles"]["activeProfile"].string.isEmpty { Text("·"); Text(value["profiles"]["activeProfile"].string) }
            }.font(.caption).foregroundStyle(.secondary)
            Label(value["allowedIps"].array.isEmpty ? obsText("未限制来源 IP") : String(format: obsText("%lld 条 IP 限制"), Int64(value["allowedIps"].array.count)), systemImage: "shield.lefthalf.filled")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading).neutralCard()
    }
}


private struct AdminSessionFailure: View {
    @ObservedObject var session: AdminSession
    var body: some View {
        if let error = session.error, !session.invalidated { ObservabilityErrorView(message: error) }
    }
}
