import SwiftUI

// MARK: - Scope / role multi-select

/// A checklist page for scopes, like the web console's scope checkboxes.
struct ScopeChecklist: View {
    let scopes: [ScopeInfo]
    @Binding var selection: [String]
    @State private var query = ""

    private var filtered: [ScopeInfo] {
        let q = query.trimmed.lowercased()
        guard !q.isEmpty else { return scopes }
        return scopes.filter { $0.scope.lowercased().contains(q) || $0.description.lowercased().contains(q) }
    }

    var body: some View {
        List {
            Section {
                ForEach(filtered) { scope in
                    Button {
                        selection = MultiSelect.toggle(scope.scope, in: selection)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(scope.scope).font(.callout.monospaced()).foregroundStyle(.primary)
                                if !scope.description.isEmpty {
                                    Text(scope.description).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: selection.contains(scope.scope) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selection.contains(scope.scope) ? Theme.accent : .secondary)
                        }
                    }
                }
            } footer: {
                if scopes.isEmpty { Text("没有拿到权限列表。") }
            }
        }
        .searchable(text: $query, prompt: "搜索权限")
        .navigationTitle("权限 (\(selection.count))")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ScopesRow: View {
    let scopes: [ScopeInfo]
    @Binding var selection: [String]

    var body: some View {
        NavigationLink {
            ScopeChecklist(scopes: scopes, selection: $selection)
        } label: {
            LabeledContent("权限") {
                Text(selection.isEmpty ? "未选" : "已选 \(selection.count) 项").foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Users

struct UserFormView: View {
    /// nil creates a user.
    let userID: String?
    var onSaved: () -> Void

    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirm = ""
    @State private var isOwner = false
    @State private var scopes: [String] = []
    @State private var roleIDs: [String] = []
    @State private var currentRoleIDs: [String] = []

    @State private var roles: [RoleItem] = []
    @State private var allScopes: [ScopeInfo] = []
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var errorText: String?

    private var isEditing: Bool { userID != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("名", text: $firstName)
                    TextField("姓", text: $lastName)
                    TextField("邮箱", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !isEditing {
                        SecureField("密码（至少 6 位）", text: $password)
                        SecureField("确认密码", text: $confirm)
                    }
                }
                Section {
                    Toggle("所有者", isOn: $isOwner)
                } footer: {
                    Text("所有者拥有全部权限。")
                }
                Section {
                    if isLoading && roles.isEmpty {
                        HStack { ProgressView(); Text("正在加载角色").foregroundStyle(.secondary) }
                    } else if roles.isEmpty {
                        Text("还没有系统角色").foregroundStyle(.secondary)
                    }
                    ForEach(roles) { role in
                        Button {
                            roleIDs = MultiSelect.toggle(role.id, in: roleIDs)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(role.name).foregroundStyle(.primary)
                                    Text("\(role.scopes?.count ?? 0) 项权限").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: roleIDs.contains(role.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(roleIDs.contains(role.id) ? Theme.accent : .secondary)
                            }
                        }
                    }
                } header: {
                    Text("角色")
                }
                if !isOwner {
                    Section {
                        ScopesRow(scopes: allScopes, selection: $scopes)
                    } footer: {
                        Text("角色之外单独给这个用户的权限。")
                    }
                }
                if let errorText {
                    Section { Text(errorText).foregroundStyle(Theme.danger) }
                }
            }
            .navigationTitle(isEditing ? "编辑用户" : "新建用户")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving { ProgressView() } else { Button("保存") { Task { await save() } } }
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        guard let service = session.service else { return }
        isLoading = true
        defer { isLoading = false }
        async let rolesResult = try? service.systemRoles()
        async let scopesResult = try? service.systemScopes()
        if let userID {
            do {
                let user = try await service.userDetail(id: userID)
                firstName = user.firstName ?? ""
                lastName = user.lastName ?? ""
                email = user.email
                isOwner = user.isOwner
                scopes = user.scopes ?? []
                roleIDs = user.roleIDs
                currentRoleIDs = user.roleIDs
            } catch {
                errorText = error.localizedDescription
            }
        }
        roles = await rolesResult ?? []
        allScopes = await scopesResult ?? []
    }

    private func save() async {
        if let message = UserEditor.validationError(isEditing: isEditing, email: email, password: password, confirm: confirm) {
            errorText = message
            return
        }
        guard let service = session.service else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            if let userID {
                try await service.updateUser(id: userID, UserEditor.updateInput(
                    firstName: firstName, lastName: lastName, email: email, isOwner: isOwner,
                    scopes: scopes, roleIDs: roleIDs, currentRoleIDs: currentRoleIDs))
            } else {
                try await service.createUser(UserEditor.createInput(
                    firstName: firstName, lastName: lastName, email: email, password: password,
                    isOwner: isOwner, scopes: scopes, roleIDs: roleIDs))
            }
            onSaved()
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}

// MARK: - Roles

struct RolesView: View {
    @Environment(SessionStore.self) private var session
    @State private var roles: [RoleItem] = []
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var editing: RoleItem?
    @State private var showCreate = false
    @State private var toast: Toast?

    var body: some View {
        List {
            ForEach(roles) { role in
                Button { editing = role } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(role.name).font(.body.weight(.medium)).foregroundStyle(.primary)
                        Text((role.scopes ?? []).prefix(4).joined(separator: "、") + ((role.scopes?.count ?? 0) > 4 ? " 等 \(role.scopes!.count) 项" : ""))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                .swipeActions {
                    Button("删除", role: .destructive) { Task { await delete(role) } }
                }
            }
        }
        .overlay {
            if isLoading && roles.isEmpty {
                ProgressView()
            } else if let errorText, roles.isEmpty {
                ContentUnavailableView("加载失败", systemImage: "exclamationmark.triangle", description: Text(errorText))
            } else if roles.isEmpty {
                ContentUnavailableView("没有角色", systemImage: "person.badge.shield.checkmark")
            }
        }
        .navigationTitle("角色")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showCreate = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showCreate) { RoleFormView(role: nil) { Task { await load() } } }
        .sheet(item: $editing) { role in RoleFormView(role: role) { Task { await load() } } }
        .toast($toast)
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        guard let service = session.service else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            roles = try await service.systemRoles()
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func delete(_ role: RoleItem) async {
        guard let service = session.service else { return }
        do {
            try await service.deleteRole(id: role.id)
            roles.removeAll { $0.id == role.id }
        } catch {
            toast = Toast(message: error.localizedDescription, isError: true)
        }
    }
}

struct RoleFormView: View {
    let role: RoleItem?
    var onSaved: () -> Void

    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var scopes: [String] = []
    @State private var allScopes: [ScopeInfo] = []
    @State private var isSaving = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("名称") {
                    TextField("角色名称", text: $name)
                }
                Section {
                    ScopesRow(scopes: allScopes, selection: $scopes)
                } footer: {
                    Text("和网页端一样，只列系统级权限。")
                }
                if let errorText {
                    Section { Text(errorText).foregroundStyle(Theme.danger) }
                }
            }
            .navigationTitle(role == nil ? "新建角色" : "编辑角色")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving { ProgressView() } else {
                        Button("保存") { Task { await save() } }
                            .disabled(name.trimmed.isEmpty || scopes.isEmpty)
                    }
                }
            }
            .onAppear {
                name = role?.name ?? ""
                scopes = role?.scopes ?? []
            }
            .task {
                allScopes = (try? await session.service?.systemScopes()) ?? []
            }
        }
    }

    private func save() async {
        guard let service = session.service else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            if let role {
                _ = try await service.updateRole(id: role.id, RoleEditor.updateInput(name: name, scopes: scopes))
            } else {
                _ = try await service.createRole(RoleEditor.createInput(name: name, scopes: scopes))
            }
            onSaved()
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}

// MARK: - Project profiles

struct ProjectProfilesView: View {
    let project: Project
    var onSaved: (Project) -> Void

    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ProfilesDraft()
    @State private var channels: [ChannelOption] = []
    @State private var tags: [String] = []
    @State private var isSaving = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("当前激活配置", selection: $draft.activeProfile) {
                        Text("不限制").tag("")
                        ForEach(draft.profiles) { Text($0.name).tag($0.name) }
                    }
                } footer: {
                    Text("选“不限制”时项目可以用全部渠道。")
                }
                ForEach(draft.profiles) { profile in
                    let binding = profileBinding(profile.id)
                    Section {
                        TextField("配置名称", text: Binding(
                            get: { profile.name },
                            set: { draft.rename(id: profile.id, to: $0) }
                        ))
                        NavigationLink {
                            ChannelChecklist(channels: channels, selection: binding.channelIDs)
                        } label: {
                            LabeledContent("渠道") {
                                Text(profile.channelIDs.isEmpty ? "未选" : "已选 \(profile.channelIDs.count) 个").foregroundStyle(.secondary)
                            }
                        }
                        TagPickerRow(title: "渠道标签", suggestions: tags, tags: binding.channelTags)
                        if !profile.channelTags.isEmpty {
                            ChoicePicker(title: "标签匹配方式", choices: ProfilesDraft.matchModes, selection: binding.matchMode)
                        }
                        Button("删除这个配置", role: .destructive) { draft.removeProfile(id: profile.id) }
                    } header: {
                        Text(profile.name == draft.activeProfile ? "\(profile.name)（已激活）" : profile.name)
                    }
                }
                Section {
                    Button { draft.addProfile() } label: { Label("添加配置", systemImage: "plus.circle") }
                }
                if let errorText {
                    Section { Text(errorText).foregroundStyle(Theme.danger) }
                }
            }
            .navigationTitle("渠道访问配置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving { ProgressView() } else { Button("保存") { Task { await save() } } }
                }
            }
            .onAppear { draft = ProfilesDraft(project.profiles) }
            .task {
                guard let service = session.service else { return }
                async let channelResult = try? service.channelOptions()
                async let tagResult = try? service.allChannelTags()
                channels = await channelResult ?? []
                tags = await tagResult ?? []
            }
        }
    }

    /// A binding by id, so removing a profile while its section is on screen cannot index past the end.
    private func profileBinding(_ id: UUID) -> Binding<ProfilesDraft.Profile> {
        Binding(
            get: { draft.profiles.first { $0.id == id } ?? ProfilesDraft.Profile(id: id, name: "") },
            set: { newValue in
                if let index = draft.profiles.firstIndex(where: { $0.id == id }) { draft.profiles[index] = newValue }
            }
        )
    }

    private func save() async {
        if let message = draft.validationError {
            errorText = message
            return
        }
        guard let service = session.service else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let saved = try await service.updateProjectProfiles(id: project.id, draft)
            onSaved(saved)
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}

/// Multi-select of channels by numeric id.
struct ChannelChecklist: View {
    let channels: [ChannelOption]
    @Binding var selection: [Int]
    @State private var query = ""

    private var filtered: [ChannelOption] {
        let q = query.trimmed.lowercased()
        guard !q.isEmpty else { return channels }
        return channels.filter { $0.name.lowercased().contains(q) || $0.type.lowercased().contains(q) }
    }

    var body: some View {
        List {
            if channels.isEmpty {
                Text("没有拿到渠道列表").foregroundStyle(.secondary)
            }
            ForEach(filtered) { channel in
                if let numeric = channel.numericID {
                    Button {
                        selection = selection.contains(numeric) ? selection.filter { $0 != numeric } : selection + [numeric]
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(channel.name).foregroundStyle(.primary)
                                Text("\(channel.type) · \(channel.status)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: selection.contains(numeric) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selection.contains(numeric) ? Theme.accent : .secondary)
                        }
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "搜索渠道")
        .navigationTitle("渠道 (\(selection.count))")
        .navigationBarTitleDisplayMode(.inline)
    }
}
