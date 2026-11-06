import SwiftUI

struct MoreView: View {
    @Environment(SessionStore.self) private var session
    @State private var confirmSignOut = false

    var body: some View {
        List {
            if let user = session.user {
                Section {
                    NavigationLink { AccountView() } label: {
                        HStack(spacing: 14) {
                            Text(user.initials)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(width: 48, height: 48)
                                .background(Theme.accent.gradient, in: Circle())
                            VStack(alignment: .leading, spacing: 3) {
                                Text(user.displayName).font(.headline)
                                Text(user.email).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if user.isOwner { StatusBadge("所有者", color: Theme.accent) }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            Section("网关") {
                if session.canManageSystem {
                    NavigationLink { ModelsView() } label: { Label("模型", systemImage: "cpu") }
                    NavigationLink { APIKeysView() } label: { Label("API 密钥", systemImage: "key") }
                } else {
                    NavigationLink { ModelsView() } label: { Label("模型", systemImage: "cpu") }
                }
                NavigationLink { ConnectGuideView() } label: { Label("接入指南", systemImage: "link") }
            }

            if session.isOwner {
                Section("管理") {
                    NavigationLink { UsersView() } label: { Label("用户", systemImage: "person.2") }
                    NavigationLink { ProjectsView() } label: { Label("项目", systemImage: "folder") }
                }
            }

            Section("服务器") {
                NavigationLink { ServerInfoView() } label: {
                    LabeledContent {
                        Text(session.serverURL?.host ?? "—").lineLimit(1)
                    } label: {
                        Label("服务器信息", systemImage: "server.rack")
                    }
                }
                if session.projects.count > 1 {
                    Picker(selection: Binding(
                        get: { session.selectedProjectID ?? "" },
                        set: { session.selectProject($0.isEmpty ? nil : $0) }
                    )) {
                        ForEach(session.projects) { Text($0.name).tag($0.id) }
                    } label: {
                        Label("当前项目", systemImage: "folder.badge.gearshape")
                    }
                }
            }

            Section {
                Button("退出登录", role: .destructive) { confirmSignOut = true }
            } footer: {
                Text("AxonHub iOS \(Bundle.main.shortVersion)")
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("更多")
        .confirmationDialog("退出登录？", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("退出", role: .destructive) { session.signOut() }
        }
        .refreshable { await session.refreshProfile() }
    }
}

extension Bundle {
    var shortVersion: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? ""
        return build.isEmpty ? version : "\(version) (\(build))"
    }
}

// MARK: - Account

struct AccountView: View {
    @Environment(SessionStore.self) private var session
    @State private var oldPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isSaving = false
    @State private var toast: Toast?

    private var passwordValid: Bool {
        newPassword.count >= 6 && newPassword == confirmPassword && !isSaving
    }

    var body: some View {
        Form {
            if let user = session.user {
                Section("资料") {
                    KeyValueRow(key: "邮箱", value: user.email)
                    KeyValueRow(key: "姓名", value: user.displayName)
                    KeyValueRow(key: "身份", value: user.isOwner ? "所有者" : (user.roles?.map(\.name).joined(separator: ", ").nilIfBlank ?? "成员"))
                }
                if let scopes = user.scopes, !scopes.isEmpty {
                    Section("权限范围") {
                        FlowTags(items: scopes.sorted())
                    }
                }
            }
            Section {
                if session.user?.hasPassword != false {
                    SecureField("当前密码", text: $oldPassword).textContentType(.password)
                }
                SecureField("新密码（至少 6 位）", text: $newPassword).textContentType(.newPassword)
                SecureField("确认新密码", text: $confirmPassword).textContentType(.newPassword)
                Button {
                    Task { await save() }
                } label: {
                    HStack { Text("修改密码"); Spacer(); if isSaving { ProgressView() } }
                }
                .disabled(!passwordValid)
            } header: {
                Text("密码")
            } footer: {
                if !confirmPassword.isEmpty && newPassword != confirmPassword {
                    Text("两次输入的密码不一致").foregroundStyle(Theme.danger)
                }
            }
        }
        .navigationTitle("账号")
        .navigationBarTitleDisplayMode(.inline)
        .toast($toast)
    }

    private func save() async {
        guard let service = session.service else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await service.updatePassword(old: oldPassword, new: newPassword)
            oldPassword = ""; newPassword = ""; confirmPassword = ""
            toast = Toast(message: "密码已更新")
        } catch {
            toast = Toast(message: error.localizedDescription, isError: true)
        }
    }
}

struct FlowTags: View {
    let items: [String]
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 6, alignment: .leading)], alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { Tag(text: $0) }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Server

struct ServerInfoView: View {
    @Environment(SessionStore.self) private var session
    @State private var health: HealthInfo?
    @State private var version: SystemVersion?
    @State private var error: String?
    @State private var latency: Double?

    var body: some View {
        List {
            Section("连接") {
                KeyValueRow(key: "地址", value: session.serverURL?.absoluteString ?? "—", monospaced: true)
                HStack {
                    Text("状态").foregroundStyle(.secondary)
                    Spacer()
                    if let health {
                        StatusBadge(health.status == "healthy" ? "健康" : health.status, color: health.status == "healthy" ? Theme.success : Theme.warning)
                    } else if error != nil {
                        StatusBadge("不可达", color: Theme.danger)
                    } else {
                        ProgressView()
                    }
                }
                KeyValueRow(key: "响应时间", value: Fmt.latency(latency))
                if let error { Text(error).font(.caption).foregroundStyle(Theme.danger) }
            }
            Section("版本") {
                KeyValueRow(key: "版本", value: version?.version ?? health?.version ?? "—", monospaced: true)
                KeyValueRow(key: "提交", value: String((version?.commit ?? health?.build?.commit ?? "—").prefix(12)), monospaced: true)
                KeyValueRow(key: "构建时间", value: version?.buildTime ?? health?.build?.buildTime ?? "—")
                KeyValueRow(key: "Go", value: version?.goVersion ?? health?.build?.goVersion ?? "—")
                KeyValueRow(key: "平台", value: version?.platform ?? health?.build?.platform ?? "—")
                KeyValueRow(key: "运行时长", value: version?.uptime ?? health?.uptime ?? "—")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("服务器")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        guard let url = session.serverURL else { return }
        let start = Date()
        do {
            health = try await APIClient.health(baseURL: url)
            latency = Date().timeIntervalSince(start) * 1000
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        if let service = session.service { version = try? await service.systemVersion() }
    }
}

struct ConnectGuideView: View {
    @Environment(SessionStore.self) private var session

    private var base: String { session.serverURL?.absoluteString ?? "https://your-axonhub" }

    var body: some View {
        List {
            Section {
                Text("AxonHub 对外兼容多种主流 SDK。在客户端里填下面的 Base URL，并使用在「API 密钥」里创建的密钥即可。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            endpoint("OpenAI 兼容", url: base + "/v1", note: "Chat Completions、Responses、Embeddings、Images 等")
            endpoint("Anthropic 兼容", url: base + "/anthropic", note: "也可使用 \(base)/v1/messages；Claude Code 设置 ANTHROPIC_BASE_URL")
            endpoint("Gemini 兼容", url: base + "/gemini", note: "密钥通过 x-goog-api-key 或 key 参数传入")
            Section("curl 示例") {
                let sample = """
                curl \(base)/v1/chat/completions \\
                  -H "Authorization: Bearer $AXONHUB_API_KEY" \\
                  -H "Content-Type: application/json" \\
                  -d '{"model":"gpt-4o-mini","messages":[{"role":"user","content":"Hello"}]}'
                """
                Text(sample)
                    .font(.caption2.monospaced())
                    .textSelection(.enabled)
                    .contextMenu { Button("拷贝", systemImage: "doc.on.doc") { Clipboard.copy(sample) } }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("接入指南")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func endpoint(_ title: String, url: String, note: String) -> some View {
        Section(title) {
            HStack {
                Text(url).font(.callout.monospaced()).textSelection(.enabled)
                Spacer()
                Button { Clipboard.copy(url) } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.borderless)
            }
            Text(note).font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Users & projects

struct UsersView: View {
    @Environment(SessionStore.self) private var session
    @State private var loader = PagedLoader<AxonUser>()
    @State private var query = ""
    @State private var search = ""
    @State private var toast: Toast?

    var body: some View {
        List {
            ForEach(loader.items) { user in
                HStack(spacing: 12) {
                    Text(String(user.displayName.prefix(1)).uppercased())
                        .font(.headline)
                        .frame(width: 36, height: 36)
                        .background(Color(.tertiarySystemFill), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(user.displayName).font(.body.weight(.medium)).lineLimit(1)
                            if user.isOwner { StatusBadge("所有者", color: Theme.accent) }
                        }
                        Text(user.email).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    if !user.isActive { StatusBadge("已停用", color: Theme.warning) }
                }
                .swipeActions {
                    if !user.isOwner {
                        Button(user.isActive ? "停用" : "启用") { Task { await toggle(user) } }
                            .tint(user.isActive ? .orange : .green)
                    }
                }
                .task { await loader.loadMoreIfNeeded(current: user) }
            }
            LoadMoreFooter(isLoading: loader.isLoadingMore)
        }
        .overlay { ListStateOverlay(loader: loader, emptyTitle: "没有用户", emptyImage: "person.2") }
        .navigationTitle("用户")
        .searchable(text: $query, prompt: "搜索邮箱或姓名")
        .onSubmit(of: .search) { search = query }
        .onChange(of: query) { _, value in if value.isEmpty { search = "" } }
        .toast($toast)
        .refreshable { await loader.reload() }
        .task(id: search) {
            guard let service = session.service else { return }
            let search = search
            loader.fetch = { cursor in try await service.users(after: cursor, search: search) }
            await loader.reload()
        }
    }

    private func toggle(_ user: AxonUser) async {
        guard let service = session.service else { return }
        do {
            try await service.setUserStatus(id: user.id, active: !user.isActive)
            await loader.reload()
        } catch {
            toast = Toast(message: error.localizedDescription, isError: true)
        }
    }
}

struct ProjectsView: View {
    @Environment(SessionStore.self) private var session
    @State private var loader = PagedLoader<Project>()
    @State private var showCreate = false
    @State private var newName = ""
    @State private var newDescription = ""
    @State private var toast: Toast?

    var body: some View {
        List {
            ForEach(loader.items) { project in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(project.name).font(.body.weight(.medium))
                        if project.id == session.selectedProjectID {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent).font(.caption)
                        }
                        Spacer()
                        if !project.isActive { StatusBadge("已归档", color: .secondary) }
                    }
                    if let description = project.description?.nilIfBlank {
                        Text(description).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Text("创建于 \(Fmt.dateTime(project.createdAt))").font(.caption2).foregroundStyle(.tertiary)
                }
                .swipeActions {
                    Button(project.isActive ? "归档" : "恢复") { Task { await toggle(project) } }
                        .tint(project.isActive ? .gray : .green)
                }
                .task { await loader.loadMoreIfNeeded(current: project) }
            }
            LoadMoreFooter(isLoading: loader.isLoadingMore)
        }
        .overlay { ListStateOverlay(loader: loader, emptyTitle: "没有项目", emptyImage: "folder") }
        .navigationTitle("项目")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showCreate = true } label: { Image(systemName: "plus") }
            }
        }
        .alert("新建项目", isPresented: $showCreate) {
            TextField("名称", text: $newName)
            TextField("描述（可选）", text: $newDescription)
            Button("取消", role: .cancel) { newName = ""; newDescription = "" }
            Button("创建") { Task { await create() } }
        }
        .toast($toast)
        .refreshable { await loader.reload() }
        .task {
            guard let service = session.service else { return }
            loader.fetch = { cursor in try await service.projects(after: cursor) }
            await loader.reload()
        }
    }

    private func create() async {
        guard let service = session.service, let name = newName.nilIfBlank else { return }
        do {
            let project = try await service.createProject(name: name, description: newDescription.trimmed)
            loader.prepend(project)
            newName = ""; newDescription = ""
            await session.refreshProfile()
        } catch {
            toast = Toast(message: error.localizedDescription, isError: true)
        }
    }

    private func toggle(_ project: Project) async {
        guard let service = session.service else { return }
        do {
            try await service.setProjectStatus(id: project.id, active: !project.isActive)
            await loader.reload()
            await session.refreshProfile()
        } catch {
            toast = Toast(message: error.localizedDescription, isError: true)
        }
    }
}
