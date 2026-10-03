import SwiftUI

/// Entity-oriented navigation. Operation names, GraphQL IDs and input envelopes
/// never form the primary information architecture.
enum NativeAdminModule: String, CaseIterable, Identifiable {
    case apiKeys, templates, projects, users, roles, projectUsers, projectRoles, prompts, protection, storage
    var id: String { rawValue }
    var title: String {
        switch self {
        case .apiKeys: return obsText("API 密钥")
        case .templates: return obsText("密钥策略模板")
        case .projects: return obsText("项目空间")
        case .users: return obsText("用户管理")
        case .roles: return obsText("系统角色")
        case .projectUsers: return obsText("项目成员")
        case .projectRoles: return obsText("项目角色")
        case .prompts: return obsText("提示词")
        case .protection: return obsText("提示词防护")
        case .storage: return obsText("数据存储")
        }
    }
    var symbol: String {
        switch self {
        case .apiKeys, .templates: return "key"
        case .projects: return "folder"
        case .users, .projectUsers: return "person.2"
        case .roles, .projectRoles, .protection: return "shield"
        case .prompts: return "text.bubble"
        case .storage: return "externaldrive"
        }
    }
    var listOperation: String {
        switch self {
        case .apiKeys: return "apiKeys"
        case .templates: return "apiKeyProfileTemplates"
        case .projects: return "projects"
        case .users: return "users"
        case .projectUsers: return "projectUsers"
        case .roles, .projectRoles: return "roles"
        case .prompts: return "prompts"
        case .protection: return "promptProtectionRules"
        case .storage: return "dataStorages"
        }
    }
    var entity: String {
        switch self {
        case .apiKeys: return "APIKey"
        case .templates: return "APIKeyProfileTemplate"
        case .projects: return "Project"
        case .users, .projectUsers: return "User"
        case .roles, .projectRoles: return "Role"
        case .prompts: return "Prompt"
        case .protection: return "PromptProtectionRule"
        case .storage: return "DataStorage"
        }
    }
    var createOperation: String {
        switch self {
        case .apiKeys: return "createAPIKey"
        case .templates: return "createApiKeyProfileTemplate"
        case .projects: return "createProject"
        case .users: return "createUser"
        case .projectUsers: return "addUserToProject"
        case .roles, .projectRoles: return "createRole"
        case .prompts: return "createPrompt"
        case .protection: return "createPromptProtectionRule"
        case .storage: return "createDataStorage"
        }
    }
    var needsProject: Bool { [.apiKeys, .templates, .projectUsers, .projectRoles, .prompts].contains(self) }
}

struct ManagementWorkspaceView: View {
    @ObservedObject var store: AxonStore
    var body: some View {
        List {
            Section {
                ManagementInstanceControls(store: store)
                    .listRowInsets(EdgeInsets(top: 7, leading: 0, bottom: 7, trailing: 0))
                    .listRowSeparator(.hidden).listRowBackground(Color.clear)
            }
            Section("工作空间") {
                moduleLink(.projects)
                moduleLink(.prompts)
            }
            Section("审计与历史") {
                ForEach(ObservabilityKind.allCases) { kind in
                    NavigationLink { ObservabilityListView(store: store, kind: kind) } label: {
                        ManagementMenuRow(title: kind.title, symbol: kind == .requests ? "arrow.up.arrow.down" : kind == .traces ? "point.3.filled.connected.trianglepath.dotted" : kind == .threads ? "bubble.left.and.bubble.right" : "chart.bar.doc.horizontal")
                    }
                }
            }
            Section("分析") {
                NavigationLink { ObservabilityListView(store: store, kind: .threads, chatHistory: true) } label: { ManagementMenuRow(title: obsText("聊天历史"), symbol: "text.bubble") }
                NavigationLink { ObservabilityDashboardView(store: store) } label: { ManagementMenuRow(title: obsText("渠道成功率与性能"), symbol: "waveform.path.ecg") }
            }
            Section("访问与安全") {
                moduleLink(.users); moduleLink(.roles); moduleLink(.templates); moduleLink(.protection)
            }
            Section("系统与运维") {
                moduleLink(.storage)
                NavigationLink { NativeSystemSettingsView(store: store) } label: { ManagementMenuRow(title: obsText("系统设置"), symbol: "gearshape.2") }
                NavigationLink { NativeAccountView(store: store) } label: { ManagementMenuRow(title: obsText("个人账号"), symbol: "person.crop.circle") }
            }
            Section("应用") {
                NavigationLink { SettingsView(store: store) } label: { ManagementMenuRow(title: obsText("实例与应用设置"), symbol: "network") }
            }
        }.symbolVariant(.fill).listStyle(.insetGrouped).navigationTitle("管理中心")
    }
    private func moduleLink(_ module: NativeAdminModule) -> some View {
        NavigationLink { NativeAdminModuleView(store: store, module: module) } label: {
            ManagementMenuRow(title: module.title, symbol: module.symbol)
        }
    }
}

struct NativeAdminModuleView: View {
    @ObservedObject var store: AxonStore
    let module: NativeAdminModule
    var initialProjectID: String? = nil
    @State private var cacheRevision: UUID?
    @State private var projectID = ""
    @State private var projects: [JSON] = []
    @State private var session: AdminSession?
    @State private var rows: [JSON] = []
    @State private var total: Int?
    @State private var cursor: String?
    @State private var search = ""
    @State private var status = "all"
    @State private var failure: String?
    @State private var busy = false
    @State private var creating = false
    @State private var selection = Set<String>()
    @State private var batchAction: String?
    @State private var showBatchConfirmation = false

    var body: some View {
        if module == .apiKeys { KeysWorkspaceView(store: store, initialProjectID: initialProjectID) }
        else { moduleBody }
    }
    private var moduleBody: some View {
        List {
            if module.needsProject {
                Section {
                    Picker("项目作用域", selection: $projectID) {
                        Text("选择项目").tag("")
                        ForEach(projects, id: \.self) { Text($0["name"].string).tag($0["id"].string) }
                    }
                }
            }
            if module != .projectUsers && module != .templates && module != .roles && module != .projectRoles {
                Section {
                    Picker("状态筛选", selection: $status) {
                        Text("全部").tag("all")
                        if module == .users { Text("启用中").tag("activated"); Text("已禁用").tag("deactivated") }
                        else if module == .projects { Text("启用中").tag("active"); Text("已归档").tag("archived") }
                        else { Text("启用中").tag("enabled"); Text("已禁用").tag("disabled"); if module == .apiKeys || module == .protection { Text("已归档").tag("archived") } }
                    }.pickerStyle(.segmented)
                }
            }
            if let failure = failure { Section { ObservabilityErrorView(message: failure); Button("重试") { Task { await reload() } } } }
            if busy && rows.isEmpty { Section { ProgressView("正在读取服务器数据") } }
            if let total = total { Section { Text(String(format: obsText("共 %lld 条"), Int64(total))).font(.caption).foregroundStyle(.secondary) } }
            if !busy && rows.isEmpty && failure == nil {
                ManagementEmptyView(symbol: module.symbol, title: module.needsProject && projectID.isEmpty ? "选择项目" : "没有符合条件的记录")
            }
            if let session = session {
                ForEach(rows, id: \.self) { row in
                    HStack(spacing: 12) {
                        if !selection.isEmpty {
                            Button { toggleSelection(row["id"].string) } label: {
                                Image(systemName: selection.contains(row["id"].string) ? "checkmark.circle.fill" : "circle")
                            }.buttonStyle(.plain).frame(minWidth: 44, minHeight: 44)
                        }
                        NavigationLink {
                            if module == .projectUsers {
                                NativeProjectMemberDetail(session: session, member: row["membership"], projectID: projectID)
                            } else {
                                NativeEntityDetailView(session: session, module: module, id: row["id"].string)
                            }
                        } label: { NativeEntityRow(value: row, module: module) }
                    }
                    .contextMenu {
                        Button { toggleSelection(row["id"].string) } label: { Label("选择", systemImage: "checkmark.circle") }
                    }
                }
                if cursor != nil { Button("加载更多") { Task { await loadPage(append: true) } }.disabled(busy) }
            }
        }
        .navigationTitle(module.title)
        .searchable(text: $search, prompt: obsText("搜索名称"))
        .onSubmit(of: .search) { Task { await reload() } }
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if !selection.isEmpty {
                    Menu {
                        Button { confirmBatch("Enable") } label: { Label("启用", systemImage: "power") }
                        Button { confirmBatch("Disable") } label: { Label("禁用", systemImage: "pause.circle") }
                        if module == .apiKeys {
                            Button(role: .destructive) { confirmBatch("Archive") } label: { Label("归档", systemImage: "archivebox") }
                        }
                        Button { selection = [] } label: { Label("取消选择", systemImage: "xmark.circle") }
                    } label: { Image(systemName: "checkmark.circle") }
                }
                Button { creating = true } label: { Image(systemName: "plus") }
                    .disabled(session == nil || busy || module.needsProject && projectID.isEmpty)
                    .accessibilityLabel("新增")
            }
        }
        .sheet(isPresented: $creating, onDismiss: { Task { await reload() } }) {
            if let session = session, let operation = try? session.schema.operation(module.createOperation) {
                NavigationStack { NativeEntityEditor(session: session, operation: operation, seed: creationSeed) }
            }
        }
        .alert("确认批量操作", isPresented: $showBatchConfirmation) {
            Button("取消", role: .cancel) { batchAction = nil }
            Button("执行", role: batchAction?.contains("Archive") == true ? .destructive : nil) { executeBatch() }
        } message: {
            Text(rows.filter { selection.contains($0["id"].string) }.map(NativeDisplay.name).joined(separator: "\n") + "\n\n" + (batchAction?.contains("Archive") == true ? obsText("归档后密钥将停止访问，无法重新启用。") : NativeAdminLabels.operation(batchAction ?? "")))
        }
        .task {
            guard session == nil || cacheRevision != store.pageCache.revision else { return }
            do {
                let schema = try AdminSchema.loaded.get()
                let system = try AdminSession(store: store, schema: schema)
                projects = try await system.read("myProjects", cached: true).array
                store.entityNames.register(projects)
                if module.needsProject && projectID.isEmpty { projectID = initialProjectID ?? projects.first?["id"].string ?? "" }
                await reload()
            } catch { failure = error.localizedDescription }
        }
        .onChange(of: projectID) { _ in rows = []; total = nil; Task { await reload() } }
        .onChange(of: status) { _ in Task { await reload() } }
        .refreshable { store.pageCache.invalidate(); await reload() }
        .onChange(of: store.selectedInstance) { _ in session?.invalidate(); session = nil; rows = []; projects = [] }
    }
    private var creationSeed: JSON {
        if module == .projectUsers { return .object(["input": .object(["projectId": .string(projectID)])]) }
        if module == .projectRoles { return .object(["input": .object(["level": .string("project"), "projectID": .string(projectID)])]) }
        if module == .roles { return .object(["input": .object(["level": .string("system")])]) }
        return .object([:])
    }
    @MainActor private func reload() async {
        guard !busy else { return }
        session?.invalidate(); cursor = nil; selection = []
        if module.needsProject && projectID.isEmpty { session = nil; return }
        do { session = try AdminSession(store: store, schema: AdminSchema.loaded.get(), projectID: module.needsProject ? projectID : nil) }
        catch { failure = error.localizedDescription; return }
        await loadPage(append: false)
    }
    @MainActor private func loadPage(append: Bool) async {
        guard !busy, let session = session else { return }
        busy = true; failure = nil; defer { busy = false }
        do {
            var vars: [String: JSON] = ["first": .number(25)]
            var whereInput: [String: JSON] = [:]
            if module.needsProject { whereInput["projectID"] = .string(projectID) }
            if module == .roles { whereInput["level"] = .string("system") }
            if module == .projectRoles { whereInput["level"] = .string("project") }
            if !search.trimmed.isEmpty { whereInput[module == .users ? "emailContainsFold" : "nameContainsFold"] = .string(search.trimmed) }
            if status != "all" { whereInput["status"] = .string(status) }
            if !whereInput.isEmpty { vars["where"] = .object(whereInput) }
            if append, let cursor = cursor { vars["after"] = .string(cursor) }
            if module == .projectUsers { vars = ["projectId": .string(projectID)] }
            let value = try await session.read(module.listOperation, variables: .object(vars), cached: true)
            cacheRevision = store.pageCache.revision
            if module == .projectUsers {
                rows = value["projectUsers"].array.map { member in
                    var user = member["user"].object
                    if user["id"] == nil { user["id"] = member["userID"] }
                    user["membership"] = member
                    return .object(user)
                }; total = rows.count; cursor = nil
            } else {
                let page = value["edges"].array.map { $0["node"] }
                session.store.entityNames.register(page)
                rows = append ? rows + page : page
                total = value["totalCount"].isNull ? nil : value["totalCount"].int
                cursor = value["pageInfo"]["hasNextPage"].bool ? value["pageInfo"]["endCursor"].string : nil
            }
        } catch { failure = error.localizedDescription }
    }
    private func toggleSelection(_ id: String) { if selection.contains(id) { selection.remove(id) } else { selection.insert(id) } }
    private func confirmBatch(_ suffix: String) {
        let entity = module == .apiKeys ? "APIKeys" : module == .prompts ? "Prompts" : module == .protection ? "PromptProtectionRules" : ""
        guard !entity.isEmpty else { failure = obsText("此模块不支持批量操作"); return }
        batchAction = "bulk" + suffix + entity; showBatchConfirmation = true
    }
    private func executeBatch() {
        guard let session = session, let id = batchAction, let operation = try? session.schema.operation(id) else { return }
        let ids = selection.sorted()
        session.start {
            _ = try await session.execute(operation, variables: .object(["ids": .array(ids.map(JSON.string))]))
            await reload()
        }
    }
}

struct NativeEntityRow: View {
    let value: JSON
    let module: NativeAdminModule
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(AdminOperationView.label(value)).font(.headline).lineLimit(2)
            HStack(spacing: 8) {
                if !value["status"].string.isEmpty {
                    Circle().fill(["enabled", "activated", "active"].contains(value["status"].string) ? Color.green : Color.orange).frame(width: 6, height: 6)
                    Text(NativeAdminLabels.value(value["status"].string)).font(.caption).foregroundStyle(.secondary)
                }
                if !value["type"].string.isEmpty { Text(value["type"].string == "user" ? obsText("项目密钥") : NativeAdminLabels.value(value["type"].string)).font(.caption).foregroundStyle(.secondary) }
                if !value["profiles"]["activeProfile"].string.isEmpty { Text(value["profiles"]["activeProfile"].string).font(.caption).foregroundStyle(Color.accentColor) }
            }
            if !value["description"].string.isEmpty { Text(value["description"].string).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
            if module == .users && !value["firstName"].string.isEmpty { Text(value["firstName"].string + " " + value["lastName"].string).font(.caption).foregroundStyle(.secondary) }
        }.padding(.vertical, 8)
    }
}

struct NativeEntityDetailView: View {
    @ObservedObject var session: AdminSession
    let module: NativeAdminModule
    let id: String
    @State private var value: JSON = .null
    @State private var editing: AdminOperation?
    @State private var confirmation: AdminOperation?
    @State private var confirming = false
    @State private var failure: String?
    private var actions: [AdminOperation] {
        session.schema.operations.filter { $0.entity == module.entity && $0.mutation && !$0.root.hasPrefix("create") && !$0.root.hasPrefix("bulk") && $0.root != "updateAPIKeyProfiles" && $0.root != "updateProjectProfiles" && $0.root != "loadApiKeyProfileTemplate" && !duplicateStatusAction($0) }
    }
    private func duplicateStatusAction(_ op: AdminOperation) -> Bool {
        guard op.id.hasSuffix("Status") else { return false }
        guard let edit = session.schema.operations.first(where: { $0.entity == module.entity && $0.id == "update" + module.entity }), let input = edit.variables.first(where: { $0.name == "input" }) else { return false }
        return session.schema.types[session.schema.base(input.type)]?.fields.contains(where: { $0.name == "status" }) == true
    }
    var body: some View {
        List {
            if value.isNull { ProgressView("正在读取服务器数据") }
            else {
                Section { if module == .apiKeys { KeySummaryRow(value: value) } else { NativeEntityRow(value: value, module: module) } }
                if module == .apiKeys || module == .projects {
                    Section("策略与额度") {
                        NavigationLink { NativeProfilesView(session: session, entity: module.entity, id: id) } label: { Label("配置 Profiles", systemImage: "slider.horizontal.3") }
                        if module == .apiKeys {
                            NavigationLink { NativeAPIKeyUsageView(session: session, id: id) } label: { Label("Token 与额度用量", systemImage: "chart.bar") }
                        }
                        if module == .projects {
                            NavigationLink { NativeProjectMembersView(session: session, projectID: id) } label: { Label("项目成员", systemImage: "person.2") }
                            NavigationLink { NativeAdminModuleView(store: session.store, module: .projectRoles, initialProjectID: id) } label: { Label("项目角色", systemImage: "shield") }
                        }
                    }
                }
                if module == .apiKeys {
                    Section("访问控制") {
                        Toggle("启用密钥", isOn: Binding(get: { value["status"].string == "enabled" }, set: { enabled in
                            guard let operation = try? session.schema.operation("updateAPIKeyStatus") else { return }
                            session.start {
                                _ = try await session.execute(operation, variables: .object(["id": .string(id), "status": .string(enabled ? "enabled" : "disabled")]), baseline: value)
                                await load()
                            }
                        })).disabled(value["status"].string == "archived")
                    }
                    Section("API 密钥") {
                        APIKeyValueRow(read: revealSecret).id(session.invalidated)
                    }
                }
                Section("操作") {
                    ForEach(actions.filter { module != .apiKeys || ["updateAPIKey", "deleteAPIKey", "rotateAPIKey", "archiveAPIKey"].contains($0.id) }) { operation in
                        Button(NativeAdminLabels.operation(operation.id), role: operation.destructive ? .destructive : nil) {
                            if operation.variables.contains(where: { $0.name == "input" || $0.name == "status" || $0.name == "profile" }) { editing = operation }
                            else { confirmation = operation; confirming = true }
                        }
                    }
                }
                DisclosureGroup("详细信息") { NativeDetailFieldsView(store: session.store, value: value) }
            }
            if let failure = failure ?? session.error { ObservabilityErrorView(message: failure) }
        }
        .navigationTitle(value.isNull ? module.title : AdminOperationView.label(value))
        .navigationBarTitleDisplayMode(.inline)
        .disabled(session.busy || session.invalidated)
        .sheet(item: $editing, onDismiss: { Task { await load() } }) { operation in
            NavigationStack { NativeEntityEditor(session: session, operation: operation, seed: seed(operation), baseline: value) }
        }
        .alert("确认操作", isPresented: $confirming) {
            Button("取消", role: .cancel) { confirmation = nil }
            if let operation = confirmation {
                Button(NativeAdminLabels.operation(operation.id), role: operation.destructive ? .destructive : nil) {
                    session.start { _ = try await session.execute(operation, variables: seed(operation), baseline: value); await load() }
                }
            }
        } message: {
            Text(AdminOperationView.label(value) + "\n\n" + (confirmation?.destructive == true ? obsText("撤销、删除、重生成或清空可能不可恢复，旧凭据可能立即失效。") : NativeAdminLabels.operation(confirmation?.id ?? "")))
        }
        .task { if value.isNull { await load() } }
        .refreshable { await load() }
        .onChange(of: session.invalidated) { invalid in if invalid { value = .null } }
    }
    @MainActor private func revealSecret() async throws -> String {
        let revealed = try await session.read("revealAPIKey", variables: .object(["id": .string(id)]))
        guard revealed["id"].string == id, !revealed["key"].string.isEmpty else { throw AdminError.notFound }
        return revealed["key"].string
    }
    private func seed(_ op: AdminOperation) -> JSON {
        var seed: [String: JSON] = ["id": .string(id)]
        if let field = op.variables.first(where: { $0.name == "input" }) { seed["input"] = session.schema.project(value, type: field.type) }
        if op.variables.contains(where: { $0.name == "status" }) { seed["status"] = value["status"] }
        if op.variables.contains(where: { $0.name == "profile" }) { seed["profile"] = session.schema.project(value["profile"], type: "APIKeyProfileInput") }
        return .object(seed.filter { k, _ in op.variables.contains(where: { $0.name == k }) })
    }
    @MainActor private func load() async {
        do { value = try await session.detail(module.entity, id: id); guard !value.isNull else { throw AdminError.notFound }; failure = nil }
        catch { failure = error.localizedDescription }
    }
}

struct NativeEntityEditor: View {
    @ObservedObject var session: AdminSession
    let operation: AdminOperation
    let baseline: JSON
    @State private var variables: JSON
    @State private var failure: String?
    @State private var uncertain = false
    @State private var completed = false
    @State private var createdSecret = ""
    @State private var confirmDestructive = false
    @State private var usageExpanded = false
    @State private var usageVisited = false
    @State private var managedValue: JSON
    @State private var editorBaseline: JSON
    @State private var keyConfirmation: String?
    @State private var confirmingKeyAction = false
    @State private var secretRevision = UUID()
    @State private var profileRevision = UUID()
    @State private var profileDraft: JSON = .null
    @State private var profileBaseline: JSON = .null
    @State private var profileReady = false
    private var isKeyWorkspace: Bool { operation.id == "updateAPIKey" && !baseline["id"].string.isEmpty }
    private var supportsKeyStatus: Bool { isKeyWorkspace && (try? session.schema.operation("updateAPIKeyStatus")) != nil }
    @Environment(\.dismiss) private var dismiss
    init(session: AdminSession, operation: AdminOperation, seed: JSON = .object([:]), baseline: JSON = .null) {
        self.session = session; self.operation = operation; self.baseline = baseline
        _managedValue = State(initialValue: baseline)
        _editorBaseline = State(initialValue: baseline)
        var vars = seed.object
        for field in operation.variables where vars[field.name] == nil && field.required {
            vars[field.name] = session.schema.defaultValue(field.type)
        }
        if let input = operation.variables.first(where: { $0.name == "input" }), let info = session.schema.types[session.schema.base(input.type)] {
            var values = session.schema.project(vars["input"] ?? .object([:]), type: input.type).object
            if let projectID = session.connection.projectID {
                for key in ["projectID", "projectId"] where info.fields.contains(where: { $0.name == key }) { values[key] = .string(projectID) }
            }
            if operation.id == "createAPIKey" { values["type"] = .string("user"); values["allowedIps"] = .array([]) }
            if operation.id == "createPrompt" { values["role"] = .string("system") }
            if operation.id == "updateAPIKey" && baseline["type"].string != "service_account" { values.removeValue(forKey: "scopes") }
            if operation.id == "updateAPIKey", !baseline["id"].string.isEmpty, (try? session.schema.operation("updateAPIKeyStatus")) != nil { values.removeValue(forKey: "status") }
            vars["input"] = .object(values)
        }
        _variables = State(initialValue: .object(vars))
    }
    var body: some View {
        generalForm
        .disabled(session.busy || session.invalidated || uncertain)
        .navigationTitle(isKeyWorkspace ? NativeDisplay.name(managedValue) : NativeAdminLabels.operation(operation.id))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(completed ? "完成" : "取消") { dismiss() }.disabled(session.busy) }
            if !completed {
                ToolbarItem(placement: .confirmationAction) {
                    Button(operation.destructive ? NativeAdminLabels.operation(operation.id) : obsText("保存")) {
                        if operation.destructive { confirmDestructive = true } else { save() }
                    }.disabled(uncertain || session.busy || session.invalidated || (isKeyWorkspace && !profileReady))
                }
            }
            if isKeyWorkspace {
                ToolbarItem(placement: .navigationBarTrailing) {
                    keyActions.disabled(uncertain || session.busy || session.invalidated)
                }
            }
        }
        .alert("确认操作", isPresented: $confirmDestructive) {
            Button("取消", role: .cancel) {}
            Button(NativeAdminLabels.operation(operation.id), role: .destructive) { save() }
        } message: {
            Text(AdminOperationView.label(baseline) + "\n\n" + obsText("撤销、删除、重生成或清空可能不可恢复，旧凭据可能立即失效。"))
        }
        .alert("确认操作", isPresented: $confirmingKeyAction) {
            Button("取消", role: .cancel) { keyConfirmation = nil }
            if let action = keyConfirmation {
                Button(NativeAdminLabels.operation(action), role: .destructive) { performKeyAction(action) }
            }
        } message: {
            Text(NativeDisplay.name(managedValue) + "\n\n" + keyActionWarning)
        }
        .interactiveDismissDisabled(session.busy)
        .onDisappear { createdSecret = ""; secretRevision = UUID() }
        .onChange(of: usageExpanded) { expanded in
            if expanded { usageVisited = true }
        }
        .onChange(of: session.invalidated) { invalid in
            if invalid { variables = .null; managedValue = .null; editorBaseline = .null; createdSecret = ""; secretRevision = UUID(); dismiss() }
        }
    }
    private var generalForm: some View {
        Form {
            if !session.status.isEmpty { Section { Label(session.status, systemImage: "checkmark.circle").foregroundStyle(.green) } }
            if let failure = failure ?? session.error { Section { ObservabilityErrorView(message: failure) } }
            if uncertain {
                Section {
                    Text("写入可能已经完成。请关闭编辑器并刷新核对，勿重复提交。")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            if completed {
                Section { Label("已保存", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                if !createdSecret.isEmpty {
                    Section("API 密钥") {
                        APIKeyValueRow(initialValue: createdSecret, initiallyVisible: true) { createdSecret }
                    }
                }
            } else if ["createAPIKey", "updateAPIKey"].contains(operation.id), let input = operation.variables.first(where: { $0.name == "input" }), let info = session.schema.types[session.schema.base(input.type)] {
                Section("基本信息") {
                    keyBasicFields(info.fields)
                    if supportsKeyStatus {
                        Toggle("启用密钥", isOn: Binding(get: { managedValue["status"].string == "enabled" }, set: { enabled in
                            setKeyStatus(enabled ? "enabled" : "disabled")
                        })).disabled(managedValue["status"].string == "archived")
                    }
                }
                Section("访问限制") {
                    if info.fields.contains(where: { $0.name == "allowedIps" }) {
                        NativeStringListField(title: "允许 IP 列表（每行一个，留空表示不限制）", values: Binding(get: { variables["input"]["allowedIps"].array.map(\.string) }, set: { updateKeyInput("allowedIps", .array($0.map(JSON.string))) }))
                    }
                    if baseline["type"].string == "service_account" || variables["input"]["type"].string == "service_account" {
                        if info.fields.contains(where: { $0.name == "scopes" }) {
                            DisclosureGroup(NativeAdminLabels.field("scopes")) {
                                NativeCatalogSelectionView(session: session, kind: "scopes", selected: Binding(get: { variables["input"]["scopes"] }, set: { updateKeyInput("scopes", $0) }), multiple: true, embedded: true)
                            }
                        }
                    }
                }
                let profileFields = keyFields(info.fields, names: ["profile"])
                if !profileFields.isEmpty {
                    Section("模型与额度策略") {
                        NativeEntityInputFields(session: session, fields: profileFields, value: binding("input"))
                    }
                }
                let remaining = keyFields(info.fields, excluding: ["name", "type", "status", "allowedIps", "scopes", "profile"])
                if !remaining.isEmpty {
                    Section { DisclosureGroup("高级配置") { NativeEntityInputFields(session: session, fields: remaining, value: binding("input")) } }
                }
            } else {
                ForEach(operation.variables.filter { !["id", "ids"].contains($0.name) }) { field in
                    Section(field.name == "input" ? obsText("配置") : NativeAdminLabels.field(field.name)) {
                        if let info = session.schema.types[session.schema.base(field.type)], info.kind == "object", !field.type.hasPrefix("[") {
                            NativeEntityInputFields(session: session, fields: info.fields.filter {
                                (!["projectID", "projectId"].contains($0.name) || variables[field.name][$0.name].isNull) && (operation.allowedInputFields.isEmpty || operation.allowedInputFields.contains($0.name)) && (!operation.id.contains("APIKey") || variables["input"]["type"].string == "service_account" || baseline["type"].string == "service_account" || !$0.name.lowercased().contains("scopes"))
                            }, value: binding(field.name))
                        } else {
                            AdminSchemaForm(schema: session.schema, fields: [field], value: $variables)
                        }
                    }
                }
            }
            if isKeyWorkspace { keyManagementSections }
        }
    }
    @ViewBuilder private var keyManagementSections: some View {
        Section("API 密钥") {
            APIKeyValueRow(read: revealWorkspaceSecret).id(secretRevision)
        }
        Section("策略") {
            NativeProfilesView(session: session, entity: "APIKey", id: baseline["id"].string, embedded: true, inline: true,
                onUncertainChange: { uncertain = $0 }, coordinatedSave: true,
                onDraftChange: { draft, original in profileDraft = draft; profileBaseline = original },
                onReadyChange: { profileReady = $0 })
                .id(profileRevision)
        }
        Section {
            DisclosureGroup("Token 与额度用量", isExpanded: $usageExpanded) {
                if usageVisited {
                    NativeAPIKeyUsageView(session: session, id: baseline["id"].string, active: usageExpanded, embedded: true, inline: true)
                }
            }
        }
        Section { DisclosureGroup("详细信息") { NativeDetailFieldsView(store: session.store, value: managedValue) } }
    }
    private var keyActions: some View {
        Menu {
            if (try? session.schema.operation("rotateAPIKey")) != nil {
                Button { keyConfirmation = "rotateAPIKey"; confirmingKeyAction = true } label: {
                    Label(NativeAdminLabels.operation("rotateAPIKey"), systemImage: "arrow.triangle.2.circlepath")
                }.disabled(managedValue["status"].string == "archived")
            }
            if (try? session.schema.operation("bulkArchiveAPIKeys")) != nil {
                Button(role: .destructive) { keyConfirmation = "bulkArchiveAPIKeys"; confirmingKeyAction = true } label: {
                    Label("归档", systemImage: "archivebox")
                }.disabled(managedValue["status"].string == "archived")
            }
            if let delete = try? session.schema.operation("deleteAPIKey") {
                Button(role: .destructive) { keyConfirmation = delete.id; confirmingKeyAction = true } label: {
                    Label("删除", systemImage: "trash")
                }
            }
        } label: { Label("操作", systemImage: "ellipsis.circle") }
    }
    private var keyActionWarning: String {
        switch keyConfirmation {
        case "rotateAPIKey": return obsText("轮换后原密钥将立即失效，所有使用旧密钥的应用需更新。确定继续吗？")
        case "bulkArchiveAPIKeys": return obsText("归档后密钥将停止访问，无法重新启用。")
        default: return obsText("撤销、删除、重生成或清空可能不可恢复，旧凭据可能立即失效。")
        }
    }
    @MainActor private func revealWorkspaceSecret() async throws -> String {
        guard !session.busy, !uncertain else { throw AdminError.changedTarget }
        let id = baseline["id"].string
        let revealed = try await session.read("revealAPIKey", variables: .object(["id": .string(id)]))
        guard revealed["id"].string == id, !revealed["key"].string.isEmpty else { throw AdminError.notFound }
        return revealed["key"].string
    }
    private func setKeyStatus(_ status: String) {
        guard !uncertain, !session.busy, !session.invalidated else { return }
        session.start {
            let op = try session.schema.operation("updateAPIKeyStatus")
            session.status = ""
            uncertain = true
            _ = try await session.execute(op, variables: .object(["id": baseline["id"], "status": .string(status)]), baseline: managedValue)
            let actual = try await session.detail("APIKey", id: baseline["id"].string)
            guard !actual.isNull else { throw AdminError.notFound }
            managedValue = actual; uncertain = false
        }
    }
    private func performKeyAction(_ action: String) {
        guard !uncertain, !session.busy, !session.invalidated else { return }
        session.start {
            let op = try session.schema.operation(action)
            let vars: JSON = action == "bulkArchiveAPIKeys" ? .object(["ids": .array([baseline["id"]])]) : .object(["id": baseline["id"]])
            session.status = ""; secretRevision = UUID()
            uncertain = true
            _ = try await session.execute(op, variables: vars, baseline: managedValue)
            secretRevision = UUID(); keyConfirmation = nil
            if action == "deleteAPIKey" { dismiss() }
            else {
                let actual = try await session.detail("APIKey", id: baseline["id"].string)
                guard !actual.isNull else { throw AdminError.notFound }
                managedValue = actual
            }
            uncertain = false
        }
    }
    @ViewBuilder private func keyBasicFields(_ fields: [AdminField]) -> some View {
        if keyFields(fields, names: ["name"]).isEmpty == false {
            LabeledContent(NativeAdminLabels.field("name")) {
                TextField(NativeAdminLabels.field("name"), text: Binding(get: { variables["input"]["name"].string }, set: { updateKeyInput("name", .string($0)) }))
                    .multilineTextAlignment(.trailing).textInputAutocapitalization(.never).autocorrectionDisabled()
            }
        }
        if operation.id == "createAPIKey", let type = fields.first(where: { $0.name == "type" }),
           let options = session.schema.types[session.schema.base(type.type)]?.values {
            Picker(NativeAdminLabels.field("type"), selection: Binding(get: { variables["input"]["type"].string }, set: { updateKeyInput("type", .string($0)) })) {
                ForEach(options, id: \.self) { value in Text(value == "user" ? obsText("项目密钥") : NativeAdminLabels.value(value)).tag(value) }
            }.pickerStyle(.menu)
        } else if !baseline["type"].string.isEmpty {
            LabeledContent(NativeAdminLabels.field("type"), value: baseline["type"].string == "user" ? obsText("项目密钥") : NativeAdminLabels.value(baseline["type"].string))
        }
        if !supportsKeyStatus {
            NativeEntityInputFields(session: session, fields: keyFields(fields, names: ["status"]), value: binding("input"))
        }
    }
    private func updateKeyInput(_ key: String, _ value: JSON) {
        var input = variables["input"].object
        input[key] = value
        var vars = variables.object
        vars["input"] = .object(input)
        variables = .object(vars)
    }
    private func keyFields(_ fields: [AdminField], names: Set<String>? = nil, excluding: Set<String> = []) -> [AdminField] {
        fields.filter { field in
            (names == nil || names!.contains(field.name)) && !excluding.contains(field.name) &&
            (!["projectID", "projectId"].contains(field.name) || variables["input"][field.name].isNull) &&
            (operation.allowedInputFields.isEmpty || operation.allowedInputFields.contains(field.name)) &&
            (variables["input"]["type"].string == "service_account" || baseline["type"].string == "service_account" || !field.name.lowercased().contains("scopes"))
        }
    }
    private func binding(_ key: String) -> Binding<JSON> { Binding(get: { variables[key] }, set: { var v = variables.object; v[key] = $0; variables = .object(v) }) }
    private func save() {
        guard !uncertain, !session.busy, !session.invalidated else { return }
        session.start {
            var submitted = variables
            if !editorBaseline.isNull, let input = operation.variables.first(where: { $0.name == "input" }), !operation.replacement {
                let original = session.schema.project(editorBaseline, type: input.type)
                var vars = submitted.object
                vars["input"] = .object(submitted["input"].object.filter { original[$0.key] != $0.value })
                submitted = .object(vars)
            }
            try session.schema.validate(submitted, fields: operation.variables, mutation: true)
            var profileOperation: AdminOperation?
            if isKeyWorkspace {
                guard profileReady else { throw AdminError.invalidInput }
                try NativeProfileValidation.validate(profileDraft, isKey: true)
                let original = session.schema.project(profileBaseline["profiles"], type: "UpdateAPIKeyProfilesInput")
                if original != profileDraft {
                    let op = try session.schema.operation("updateAPIKeyProfiles")
                    try session.schema.validate(.object(["id": baseline["id"], "input": profileDraft]), fields: op.variables, mutation: true)
                    profileOperation = op
                }
            }
            session.status = ""
            uncertain = true
            let response = try await session.execute(operation, variables: submitted, baseline: editorBaseline)
            if let profileOperation {
                do {
                    _ = try await session.execute(profileOperation, variables: .object(["id": baseline["id"], "input": profileDraft]), baseline: profileBaseline)
                } catch {
                    failure = obsText("基本信息已保存，策略保存未确认。请刷新核对后再编辑。") + "\n" + error.localizedDescription
                    throw error
                }
            }
            if isKeyWorkspace {
                let actual = try await session.detail("APIKey", id: baseline["id"].string)
                guard !actual.isNull else { throw AdminError.notFound }
                managedValue = actual
                editorBaseline = managedValue
                profileReady = false
                profileRevision = UUID()
                if let input = operation.variables.first(where: { $0.name == "input" }) {
                    var values = session.schema.project(managedValue, type: input.type).object
                    if managedValue["type"].string != "service_account" { values.removeValue(forKey: "scopes") }
                    if supportsKeyStatus { values.removeValue(forKey: "status") }
                    variables = .object(["id": baseline["id"], "input": .object(values)])
                }
            } else {
                completed = true
                if operation.id == "createAPIKey" { createdSecret = response["key"].string }
                else { dismiss() }
            }
            uncertain = false
        }
    }
}

import UIKit

enum NativeSecretClipboard {
    static func copy(_ value: String) {
        UIPasteboard.general.setItems([[UIPasteboard.typeAutomatic: value]], options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(60)])
    }
}
