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
                    .contextMenu { Button("选择") { toggleSelection(row["id"].string) } }
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
                        Button("启用") { confirmBatch("Enable") }
                        Button("禁用") { confirmBatch("Disable") }
                        if module == .apiKeys { Button("归档", role: .destructive) { confirmBatch("Archive") } }
                        Button("取消选择") { selection = [] }
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
        .confirmationDialog("确认批量操作", isPresented: $showBatchConfirmation, titleVisibility: .visible) {
            Button("执行", role: batchAction?.contains("Archive") == true ? .destructive : nil) { executeBatch() }
        } message: { Text(rows.filter { selection.contains($0["id"].string) }.map(NativeDisplay.name).joined(separator: "\n")) }
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
                        Text("禁用立即停止此密钥的访问，策略和额度配置仍保留。").font(.caption).foregroundStyle(.secondary)
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
        .confirmationDialog("确认操作", isPresented: $confirming, titleVisibility: .visible) {
            if let operation = confirmation {
                Button(NativeAdminLabels.operation(operation.id), role: operation.destructive ? .destructive : nil) {
                    session.start { _ = try await session.execute(operation, variables: seed(operation), baseline: value); await load() }
                }
            }
        } message: { Text(AdminOperationView.label(value)) }
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
    @Environment(\.dismiss) private var dismiss
    init(session: AdminSession, operation: AdminOperation, seed: JSON = .object([:]), baseline: JSON = .null) {
        self.session = session; self.operation = operation; self.baseline = baseline
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
            vars["input"] = .object(values)
        }
        _variables = State(initialValue: .object(vars))
    }
    var body: some View {
        Form {
            if completed {
                Section { Label("已保存", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                if !createdSecret.isEmpty {
                    Section("API 密钥") {
                        APIKeyValueRow(initialValue: createdSecret, initiallyVisible: true) { createdSecret }
                    }
                }
            } else if ["createAPIKey", "updateAPIKey"].contains(operation.id), let input = operation.variables.first(where: { $0.name == "input" }), let info = session.schema.types[session.schema.base(input.type)] {
                Section("基本信息") {
                    NativeEntityInputFields(session: session, fields: keyFields(info.fields, names: ["name", "type", "status"]), value: binding("input"))
                }
                Section("访问限制") {
                    NativeEntityInputFields(session: session, fields: keyFields(info.fields, names: ["allowedIps", "scopes", "appendScopes", "clearScopes"]), value: binding("input"))
                    Text("普通项目密钥使用项目权限；服务账号可单独配置权限。").font(.caption).foregroundStyle(.secondary)
                }
                Section("模型与额度策略") {
                    NativeEntityInputFields(session: session, fields: keyFields(info.fields, names: ["profile"]), value: binding("input"))
                }
                let remaining = keyFields(info.fields, excluding: ["name", "type", "status", "allowedIps", "scopes", "appendScopes", "clearScopes", "profile"])
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
            if let failure = failure ?? session.error { Section { ObservabilityErrorView(message: failure) } }
            if uncertain { Text("写入可能已经完成。请关闭编辑器并刷新核对，勿重复提交。").foregroundStyle(.orange) }
        }
        .navigationTitle(NativeAdminLabels.operation(operation.id))
        .navigationBarTitleDisplayMode(.inline)
        .disabled(session.busy || session.invalidated)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(completed ? "完成" : "取消") { dismiss() } }
            if !completed { ToolbarItem(placement: .confirmationAction) { Button(operation.destructive ? NativeAdminLabels.operation(operation.id) : obsText("保存")) {
                if operation.destructive { confirmDestructive = true } else { save() }
            }.disabled(uncertain) } }
        }
        .confirmationDialog("确认操作", isPresented: $confirmDestructive, titleVisibility: .visible) {
            Button(NativeAdminLabels.operation(operation.id), role: .destructive) { save() }
        } message: { Text(AdminOperationView.label(baseline)) }
        .interactiveDismissDisabled(session.busy)
        .onDisappear { createdSecret = "" }
        .onChange(of: session.invalidated) { invalid in if invalid { variables = .null; createdSecret = "" } }
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
        session.start {
            var submitted = variables
            if !baseline.isNull, let input = operation.variables.first(where: { $0.name == "input" }), !operation.replacement {
                let original = session.schema.project(baseline, type: input.type)
                var vars = submitted.object
                vars["input"] = .object(submitted["input"].object.filter { original[$0.key] != $0.value })
                submitted = .object(vars)
            }
            try session.schema.validate(submitted, fields: operation.variables, mutation: true)
            uncertain = true
            let response = try await session.execute(operation, variables: submitted, baseline: baseline)
            uncertain = false; completed = true
            if operation.id == "createAPIKey" { createdSecret = response["key"].string }
            else { dismiss() }
        }
    }
}

import UIKit

enum NativeSecretClipboard {
    static func copy(_ value: String) {
        UIPasteboard.general.setItems([[UIPasteboard.typeAutomatic: value]], options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(60)])
    }
}
