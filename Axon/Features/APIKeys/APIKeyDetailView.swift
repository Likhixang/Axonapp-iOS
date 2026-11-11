import SwiftUI

/// One API key: the key itself, its settings, its profiles (with the active one), quota usage and templates.
struct APIKeyDetailView: View {
    @Environment(SessionStore.self) private var session
    @State private var apiKey: APIKey
    @State private var usages: [APIKeyQuotaUsageInfo] = []
    @State private var revealed = false
    @State private var showSettings = false
    @State private var showProfiles = false
    @State private var toast: Toast?
    var onChange: ((APIKey) -> Void)?

    init(apiKey: APIKey, onChange: ((APIKey) -> Void)? = nil) {
        _apiKey = State(initialValue: apiKey)
        self.onChange = onChange
    }

    private var profiles: [APIKeyProfile] { apiKey.profiles?.profiles ?? [] }
    private var active: String { apiKey.profiles?.activeProfile ?? "" }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(revealed ? apiKey.key : Fmt.mask(apiKey.key))
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                    HStack {
                        Button(revealed ? "隐藏" : "显示", systemImage: revealed ? "eye.slash" : "eye") { revealed.toggle() }
                        Button("拷贝", systemImage: "doc.on.doc") {
                            Clipboard.copy(apiKey.key)
                            toast = Toast(message: "已拷贝")
                        }
                    }
                    .adaptiveButtonStyle()
                    .controlSize(.small)
                }
                .padding(.vertical, 2)
                KeyValueRow(key: "状态", value: apiKey.keyStatus.label)
                KeyValueRow(key: "类型", value: apiKey.typeLabel)
                if let project = apiKey.project { KeyValueRow(key: "项目", value: project.name) }
                if let ips = apiKey.allowedIps, !ips.isEmpty {
                    KeyValueRow(key: "IP 白名单", value: ips.joined(separator: "\n"), monospaced: true)
                }
                if apiKey.type == "service_account", let scopes = apiKey.scopes, !scopes.isEmpty {
                    KeyValueRow(key: "权限", value: scopes.joined(separator: "\n"), monospaced: true)
                }
                KeyValueRow(key: "创建时间", value: Fmt.dateTime(apiKey.createdAt))
            } header: {
                Text("密钥")
            }

            Section {
                if profiles.isEmpty {
                    Text("还没有配置文件，这个密钥可以访问所有模型和渠道。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(profiles) { profile in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(profile.name).font(.subheadline.weight(.medium))
                            if profile.name == active { Tag(text: "生效中", color: Theme.success) }
                            if let template = profile.templateName ?? profile.templateID.map({ "#\($0)" }) {
                                Tag(text: "模板 \(template)", color: Theme.accent)
                            }
                        }
                        Text(profile.summary).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Button {
                    showProfiles = true
                } label: {
                    Label("编辑配置文件", systemImage: "slider.horizontal.3")
                }
            } header: {
                Text("配置文件 (\(profiles.count))")
            } footer: {
                Text("配置文件决定这个密钥能用哪些模型、走哪些渠道、模型如何映射以及配额。同一时间只有一个生效。")
            }

            if !usages.isEmpty {
                Section("配额用量") {
                    ForEach(Array(usages.enumerated()), id: \.offset) { _, usage in
                        QuotaUsageRow(usage: usage)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(apiKey.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("编辑密钥", systemImage: "pencil") { showSettings = true }
                    Button("编辑配置文件", systemImage: "slider.horizontal.3") { showProfiles = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            APIKeyFormSheet(existing: apiKey) { saved in update(saved) }
        }
        .sheet(isPresented: $showProfiles) {
            APIKeyProfilesEditorView(apiKey: apiKey) { saved in
                update(saved)
                toast = Toast(message: "配置文件已保存")
            }
        }
        .toast($toast)
        .refreshable { await refresh() }
        .task { await loadUsages() }
    }

    private func update(_ key: APIKey) {
        apiKey = key
        onChange?(key)
        Task { await loadUsages() }
    }

    private func refresh() async {
        guard let service = session.service else { return }
        if let fresh = try? await service.apiKey(id: apiKey.id) {
            apiKey = fresh
            onChange?(fresh)
        }
        await loadUsages()
    }

    private func loadUsages() async {
        guard let service = session.service else { return }
        usages = (try? await service.apiKeyQuotaUsages(id: apiKey.id)) ?? []
    }
}

private struct QuotaUsageRow: View {
    let usage: APIKeyQuotaUsageInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(usage.profileName).font(.subheadline.weight(.medium))
                Spacer()
                Text(usage.quota.period.label).font(.caption).foregroundStyle(.secondary)
            }
            if let limit = usage.quota.requests {
                meter("请求", used: Double(usage.usage.requestCount), limit: Double(limit), text: "\(usage.usage.requestCount) / \(limit)")
            }
            if let limit = usage.quota.totalTokens {
                meter("Token", used: Double(usage.usage.totalTokens), limit: Double(limit),
                      text: "\(Fmt.compact(usage.usage.totalTokens)) / \(Fmt.compact(limit))")
            }
            if let limit = usage.quota.cost {
                meter("费用", used: usage.usage.totalCost, limit: limit, text: "\(Fmt.cost(usage.usage.totalCost)) / \(Fmt.cost(limit))")
            }
        }
        .padding(.vertical, 2)
    }

    private func meter(_ title: String, used: Double, limit: Double, text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.caption)
                Spacer()
                Text(text).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            ProgressView(value: min(used, limit), total: max(limit, 0.000_001))
                .tint(used >= limit ? Theme.danger : Theme.accent)
        }
    }
}

// MARK: - Key settings (create / edit)

struct APIKeyFormSheet: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    let existing: APIKey?
    var onSaved: (APIKey) -> Void

    @State private var name = ""
    @State private var type = "user"
    @State private var projectID = ""
    @State private var scopes: [String] = []
    @State private var ips: [String] = []
    @State private var newIP = ""
    @State private var availableScopes: [ScopeInfo] = []
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var created: APIKey?

    var body: some View {
        NavigationStack {
            Form {
                if let created {
                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("密钥已创建", systemImage: "checkmark.seal.fill").foregroundStyle(Theme.success)
                            Text(created.key).font(.callout.monospaced()).textSelection(.enabled)
                            Button("拷贝密钥", systemImage: "doc.on.doc") { Clipboard.copy(created.key) }
                                .adaptiveButtonStyle(prominent: true)
                        }
                        .padding(.vertical, 4)
                    } footer: {
                        Text("在客户端里把 Base URL 设为 \(session.serverURL?.absoluteString ?? "服务器地址")/v1，并使用这个密钥。配置文件可以在密钥详情里编辑。")
                    }
                } else {
                    Section {
                        TextField("名称，例如 Cursor、开发环境", text: $name)
                        if existing == nil {
                            Picker("类型", selection: $type) {
                                Text("用户").tag("user")
                                Text("服务账号").tag("service_account")
                            }
                            if session.projects.count > 1 {
                                Picker("项目", selection: $projectID) {
                                    ForEach(session.projects) { Text($0.name).tag($0.id) }
                                }
                            }
                        }
                    } footer: {
                        if type == "service_account" {
                            Text("服务账号密钥可以调用管理接口，权限由下面的范围决定。")
                        }
                    }

                    if type == "service_account" {
                        Section("权限范围") {
                            if availableScopes.isEmpty {
                                ProgressView()
                            }
                            ForEach(availableScopes) { scope in
                                Button {
                                    if let i = scopes.firstIndex(of: scope.scope) { scopes.remove(at: i) } else { scopes.append(scope.scope) }
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(scope.scope).font(.callout.monospaced()).foregroundStyle(.primary)
                                            if !scope.description.isEmpty {
                                                Text(scope.description).font(.caption).foregroundStyle(.secondary)
                                            }
                                        }
                                        Spacer()
                                        if scopes.contains(scope.scope) { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
                                    }
                                }
                            }
                        }
                    }

                    Section {
                        ForEach(ips, id: \.self) { ip in Text(ip).font(.callout.monospaced()) }
                            .onDelete { ips.remove(atOffsets: $0) }
                        HStack {
                            TextField("IP 或 CIDR，如 10.0.0.0/8", text: $newIP)
                                .keyboardType(.numbersAndPunctuation)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .onSubmit(addIP)
                            Button("添加", action: addIP).disabled(newIP.trimmed.isEmpty)
                        }
                    } header: {
                        Text("IP 白名单")
                    } footer: {
                        Text("留空表示不限制来源 IP。")
                    }

                    if let errorMessage {
                        Section { Text(errorMessage).font(.footnote).foregroundStyle(Theme.danger) }
                    }
                }
            }
            .navigationTitle(existing == nil ? "新建 API 密钥" : "编辑密钥")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(created == nil ? "取消" : "完成") { dismiss() }
                }
                if created == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        if isSaving { ProgressView() } else {
                            Button(existing == nil ? "创建" : "保存") { Task { await save() } }
                                .disabled(name.trimmed.isEmpty || (existing == nil && projectID.isEmpty))
                        }
                    }
                }
            }
            .task { await setUp() }
            .onChange(of: type) { _, _ in Task { await loadScopes() } }
        }
    }

    private func addIP() {
        let ip = newIP.trimmed
        guard !ip.isEmpty else { return }
        if !ips.contains(ip) { ips.append(ip) }
        newIP = ""
    }

    private func setUp() async {
        if let existing, name.isEmpty {
            name = existing.name
            type = existing.type
            scopes = existing.scopes ?? []
            ips = existing.allowedIps ?? []
        }
        if projectID.isEmpty { projectID = session.selectedProjectID ?? session.projects.first?.id ?? "" }
        await loadScopes()
    }

    private func loadScopes() async {
        guard type == "service_account", availableScopes.isEmpty, let service = session.service else { return }
        availableScopes = (try? await service.projectScopes()) ?? []
    }

    private func save() async {
        guard let service = session.service else { return }
        if type == "service_account" && scopes.isEmpty {
            errorMessage = "服务账号至少需要一个权限"
            return
        }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            if let existing {
                let saved = try await service.updateAPIKey(
                    id: existing.id,
                    input: APIKeyEditor.updateInput(name: name, type: existing.type, scopes: scopes, allowedIps: ips))
                onSaved(saved)
                dismiss()
            } else {
                let key = try await service.createAPIKey(
                    input: APIKeyEditor.createInput(name: name, type: type, scopes: scopes, allowedIps: ips),
                    projectID: projectID)
                created = key
                onSaved(key)
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Profiles

/// Edits `profiles` of a key as a whole, like the console's profiles dialog, and saves with `updateAPIKeyProfiles`.
struct APIKeyProfilesEditorView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    let apiKey: APIKey
    var onSaved: (APIKey) -> Void

    @State private var profiles: [APIKeyProfile] = []
    @State private var active = ""
    @State private var channels: [ChannelOption] = []
    @State private var modelIDs: [String] = []
    @State private var templates: [APIKeyProfileTemplate] = []
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var didLoad = false
    @State private var savingTemplateFor: APIKeyProfile?
    @State private var templateName = ""
    @State private var toast: Toast?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("生效配置", selection: $active) {
                        if profiles.isEmpty { Text("无").tag("") }
                        ForEach(profiles) { Text($0.name.trimmed.isEmpty ? "（未命名）" : $0.name).tag($0.name) }
                    }
                }

                Section {
                    ForEach($profiles) { $profile in
                        NavigationLink {
                            ProfileEditorView(profile: $profile, channels: channels, modelIDs: modelIDs) { old, new in
                                if active == old { active = new }
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(profile.name.trimmed.isEmpty ? "（未命名）" : profile.name)
                                        .font(.subheadline.weight(.medium))
                                    if profile.name == active { Tag(text: "生效中", color: Theme.success) }
                                    if let template = profile.templateName ?? profile.templateID.map({ "#\($0)" }) {
                                        Tag(text: "模板 \(template)", color: Theme.accent)
                                    }
                                }
                                Text(profile.summary).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .contextMenu {
                            Button("设为生效", systemImage: "checkmark.circle") { active = profile.name }
                            Button("复制", systemImage: "plus.square.on.square") { duplicate(profile) }
                            Button("存为模板", systemImage: "square.and.arrow.down") {
                                templateName = profile.name
                                savingTemplateFor = profile
                            }
                        }
                    }
                    .onDelete { offsets in
                        let removed = offsets.map { profiles[$0].name }
                        profiles.remove(atOffsets: offsets)
                        if removed.contains(active) { active = profiles.first?.name ?? "" }
                    }
                    .onMove { profiles.move(fromOffsets: $0, toOffset: $1) }

                    Button {
                        let name = uniqueName("配置 \(profiles.count + 1)")
                        profiles.append(APIKeyProfile(name: name))
                        if active.isEmpty { active = name }
                    } label: {
                        Label("新建配置", systemImage: "plus.circle")
                    }
                } header: {
                    Text("配置 (\(profiles.count))")
                } footer: {
                    Text("长按可以设为生效、复制或存为模板，左滑删除。改动点“保存”后才会生效。")
                }

                if !templates.isEmpty {
                    Section {
                        ForEach(templates) { template in
                            Button {
                                Task { await load(template) }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(template.name).foregroundStyle(.primary)
                                    Text([template.description?.nilIfBlank, template.profile?.summary,
                                          template.linkedProfilesCount.map { "\($0) 个配置在用" }]
                                        .compactMap { $0 }.joined(separator: " · "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .swipeActions {
                                Button("删除", systemImage: "trash", role: .destructive) { Task { await deleteTemplate(template) } }
                            }
                        }
                    } header: {
                        Text("从模板加载")
                    } footer: {
                        Text("加载会在服务器上直接把模板加到这个密钥的配置里；未保存的改动会被服务器上的结果替换。")
                    }
                }

                if let errorMessage {
                    Section { Text(errorMessage).font(.footnote).foregroundStyle(Theme.danger) }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("配置文件")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving { ProgressView() } else { Button("保存") { Task { await save() } } }
                }
                ToolbarItem(placement: .topBarLeading) { EditButton() }
            }
            .alert("存为模板", isPresented: Binding(get: { savingTemplateFor != nil }, set: { if !$0 { savingTemplateFor = nil } })) {
                TextField("模板名称", text: $templateName)
                Button("取消", role: .cancel) {}
                Button("保存") { if let p = savingTemplateFor { Task { await saveTemplate(p) } } }
            } message: {
                Text("其他密钥以后可以直接加载这套配置。")
            }
            .toast($toast)
            .task { await loadOnce() }
        }
    }

    private func uniqueName(_ base: String) -> String {
        var name = base
        var n = 2
        let existing = Set(profiles.map { $0.name.trimmed.lowercased() })
        while existing.contains(name.lowercased()) {
            name = "\(base) (\(n))"
            n += 1
        }
        return name
    }

    private func duplicate(_ profile: APIKeyProfile) {
        var copy = profile
        copy.localID = UUID()
        copy.name = uniqueName(profile.name + " 副本")
        copy.templateID = nil
        copy.templateName = nil
        profiles.append(copy)
    }

    private func loadOnce() async {
        guard !didLoad, let service = session.service else { return }
        didLoad = true
        profiles = apiKey.profiles?.profiles ?? []
        active = apiKey.profiles?.activeProfile ?? profiles.first?.name ?? ""
        async let c = try? service.channelOptions()
        async let m = try? service.modelIDSuggestions()
        async let t = try? service.apiKeyProfileTemplates()
        channels = await c ?? []
        modelIDs = await m ?? []
        templates = await t ?? []
    }

    private func save() async {
        if let error = ProfilesEditor.validationError(active: active, profiles: profiles) {
            errorMessage = error
            return
        }
        guard let service = session.service else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let saved = try await service.updateAPIKeyProfiles(id: apiKey.id, input: ProfilesEditor.input(active: active, profiles: profiles))
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onSaved(saved)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func load(_ template: APIKeyProfileTemplate) async {
        guard let service = session.service else { return }
        do {
            let updated = try await service.loadAPIKeyProfileTemplate(templateID: template.id, apiKeyID: apiKey.id)
            profiles = updated.profiles?.profiles ?? []
            active = updated.profiles?.activeProfile ?? active
            onSaved(updated)
            toast = Toast(message: "已加载模板 \(template.name)")
        } catch {
            toast = Toast(message: error.localizedDescription, isError: true)
        }
    }

    private func saveTemplate(_ profile: APIKeyProfile) async {
        guard let service = session.service, let name = templateName.nilIfBlank else { return }
        guard let projectID = apiKey.project?.id ?? session.selectedProjectID else {
            toast = Toast(message: "不知道这个密钥属于哪个项目", isError: true)
            return
        }
        do {
            let template = try await service.createAPIKeyProfileTemplate(name: name, description: "", projectID: projectID, profile: profile)
            templates.append(template)
            toast = Toast(message: "已存为模板")
        } catch {
            toast = Toast(message: error.localizedDescription, isError: true)
        }
    }

    private func deleteTemplate(_ template: APIKeyProfileTemplate) async {
        guard let service = session.service else { return }
        do {
            try await service.deleteAPIKeyProfileTemplate(id: template.id)
            templates.removeAll { $0.id == template.id }
        } catch {
            toast = Toast(message: error.localizedDescription, isError: true)
        }
    }
}

struct ProfileEditorView: View {
    @Binding var profile: APIKeyProfile
    let channels: [ChannelOption]
    let modelIDs: [String]
    var onRename: (String, String) -> Void

    @State private var nameText = ""

    private var allTags: [String] { ChannelOption.allTags(channels) }

    var body: some View {
        Form {
            Section("名称") {
                TextField("配置名称", text: $nameText)
                    .onSubmit(commitName)
                if let template = profile.templateName ?? profile.templateID.map({ "#\($0)" }) {
                    HStack {
                        Label("跟随模板 \(template)", systemImage: "link").font(.callout)
                        Spacer()
                        Button("解除") {
                            profile.templateID = nil
                            profile.templateName = nil
                        }
                        .font(.callout)
                    }
                }
            }

            Section {
                ForEach(Array((profile.modelMappings ?? []).enumerated()), id: \.offset) { index, _ in
                    HStack {
                        TextField("请求模型", text: mappingBinding(index, \.from))
                        Image(systemName: "arrow.right").foregroundStyle(.secondary).font(.caption)
                        TextField("实际模型", text: mappingBinding(index, \.to))
                    }
                    .font(.callout.monospaced())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                }
                .onDelete { offsets in
                    var list = profile.modelMappings ?? []
                    list.remove(atOffsets: offsets)
                    profile.modelMappings = list
                }
                Button {
                    profile.modelMappings = (profile.modelMappings ?? []) + [ModelMapping(from: "", to: "")]
                } label: {
                    Label("添加映射", systemImage: "plus.circle")
                }
            } header: {
                Text("模型映射")
            } footer: {
                Text("请求模型支持正则，例如 gpt-4.* → gpt-4o。")
            }

            Section {
                NavigationLink {
                    StringListPicker(title: "允许的模型", known: modelIDs, selection: Binding(
                        get: { profile.modelIDs ?? [] }, set: { profile.modelIDs = $0 }))
                } label: {
                    LabeledContent("允许的模型", value: countText(profile.modelIDs, empty: "全部"))
                }
                NavigationLink {
                    ChannelMultiPicker(channels: channels, selection: Binding(
                        get: { profile.channelIDs ?? [] }, set: { profile.channelIDs = $0 }))
                } label: {
                    LabeledContent("允许的渠道", value: countText(profile.channelIDs, empty: "全部"))
                }
                NavigationLink {
                    TagPickerView(title: "渠道标签", known: allTags, selection: Binding(
                        get: { profile.channelTags ?? [] }, set: { profile.channelTags = $0 }))
                } label: {
                    LabeledContent("渠道标签", value: countText(profile.channelTags, empty: "不限"))
                }
                if !(profile.channelTags ?? []).isEmpty {
                    Picker("标签匹配", selection: Binding(
                        get: { profile.channelTagsMatchMode ?? .any }, set: { profile.channelTagsMatchMode = $0 })) {
                        ForEach(ChannelTagsMatchMode.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                }
            } header: {
                Text("范围")
            } footer: {
                Text("不选就是不限制。")
            }

            Section("路由") {
                Picker("负载均衡", selection: Binding(
                    get: { LoadBalancerStrategy.normalized(profile.loadBalanceStrategy) },
                    set: { profile.loadBalanceStrategy = $0 })) {
                    ForEach(LoadBalancerStrategy.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Picker("会话粘滞", selection: Binding(
                    get: { TraceStickyMode.normalized(profile.traceStickyMode) },
                    set: { profile.traceStickyMode = $0 })) {
                    ForEach(TraceStickyMode.allCases) { Text($0.label).tag($0.rawValue) }
                }
            }

            QuotaSection(quota: $profile.quota)
        }
        .navigationTitle(profile.name.trimmed.isEmpty ? "配置" : profile.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { nameText = profile.name }
        .onDisappear(perform: commitName)
    }

    private func commitName() {
        let old = profile.name
        guard nameText != old else { return }
        profile.name = nameText
        onRename(old, nameText)
    }

    private func countText(_ list: [some Any]?, empty: String) -> String {
        guard let list, !list.isEmpty else { return empty }
        return "\(list.count) 个"
    }

    private func mappingBinding(_ index: Int, _ keyPath: WritableKeyPath<ModelMapping, String>) -> Binding<String> {
        Binding(
            get: { (profile.modelMappings ?? [])[safe: index]?[keyPath: keyPath] ?? "" },
            set: { value in
                var list = profile.modelMappings ?? []
                guard list.indices.contains(index) else { return }
                list[index][keyPath: keyPath] = value
                profile.modelMappings = list
            })
    }
}

private struct QuotaSection: View {
    @Binding var quota: APIKeyQuota?

    private var enabled: Binding<Bool> {
        Binding(get: { quota != nil }, set: { quota = $0 ? APIKeyQuota(period: .allTime) : nil })
    }

    var body: some View {
        Section {
            Toggle("限制用量", isOn: enabled)
            if quota != nil {
                Picker("周期", selection: periodType) {
                    Text("总量").tag("all_time")
                    Text("过去一段时间").tag("past_duration")
                    Text("自然周期").tag("calendar_duration")
                }
                if quota?.period.type == "past_duration" {
                    Stepper(value: Binding(
                        get: { quota?.period.pastDuration?.value ?? 1 },
                        set: { quota?.period.pastDuration?.value = $0 }), in: 1...10_000) {
                        LabeledContent("时长", value: String(quota?.period.pastDuration?.value ?? 1))
                    }
                    Picker("单位", selection: Binding(
                        get: { quota?.period.pastDuration?.unit ?? "day" },
                        set: { quota?.period.pastDuration?.unit = $0 })) {
                        ForEach(["minute", "hour", "day"], id: \.self) { Text(APIKeyQuotaPeriod.unitLabel($0)).tag($0) }
                    }
                }
                if quota?.period.type == "calendar_duration" {
                    Picker("单位", selection: Binding(
                        get: { quota?.period.calendarDuration?.unit ?? "day" },
                        set: { quota?.period.calendarDuration?.unit = $0 })) {
                        Text("每自然日").tag("day")
                        Text("每自然月").tag("month")
                    }
                }
                NumberField("请求数", text: intBinding(\.requests), placeholder: "不限")
                NumberField("Token 数", text: intBinding(\.totalTokens), placeholder: "不限")
                NumberField("费用 (USD)", text: costBinding, placeholder: "不限")
            }
        } header: {
            Text("配额")
        } footer: {
            if quota != nil { Text("至少填一项上限，全部留空保存时会当作不限制。") }
        }
    }

    private var periodType: Binding<String> {
        Binding(
            get: { quota?.period.type ?? "all_time" },
            set: { type in
                switch type {
                case "past_duration": quota?.period = APIKeyQuotaPeriod(type: type, pastDuration: .init(value: 1, unit: "day"))
                case "calendar_duration": quota?.period = APIKeyQuotaPeriod(type: type, calendarDuration: .init(unit: "day"))
                default: quota?.period = .allTime
                }
            })
    }

    private func intBinding(_ keyPath: WritableKeyPath<APIKeyQuota, Int?>) -> Binding<String> {
        Binding(
            get: { quota?[keyPath: keyPath].map(String.init) ?? "" },
            set: { quota?[keyPath: keyPath] = Int($0.trimmed) })
    }

    private var costBinding: Binding<String> {
        Binding(
            get: { quota?.cost.map { Fmt.trim($0) } ?? "" },
            set: { quota?.cost = Double($0.trimmed) })
    }
}

struct ChannelMultiPicker: View {
    let channels: [ChannelOption]
    @Binding var selection: [Int]
    @State private var query = ""

    var body: some View {
        List {
            ForEach(channels.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }) { channel in
                if let id = channel.numericID {
                    Button {
                        if let i = selection.firstIndex(of: id) { selection.remove(at: i) } else { selection.append(id) }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(channel.name).foregroundStyle(.primary)
                                if let tags = channel.tags, !tags.isEmpty {
                                    Text(tags.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if selection.contains(id) { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
                        }
                    }
                }
            }
        }
        .searchable(text: $query)
        .navigationTitle("渠道")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !selection.isEmpty { Button("清空") { selection = [] } }
        }
    }
}

/// Select strings from a known list, or add free text.
struct StringListPicker: View {
    let title: String
    let known: [String]
    @Binding var selection: [String]
    @State private var query = ""

    var body: some View {
        List {
            if !query.trimmed.isEmpty, !known.contains(query.trimmed), !selection.contains(query.trimmed) {
                Button {
                    selection.append(query.trimmed)
                    query = ""
                } label: {
                    Label("添加 “\(query.trimmed)”", systemImage: "plus.circle")
                }
            }
            let extra = selection.filter { !known.contains($0) }
            ForEach(Array(Set(extra + known)).sorted().filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) }, id: \.self) { item in
                Button {
                    if let i = selection.firstIndex(of: item) { selection.remove(at: i) } else { selection.append(item) }
                } label: {
                    HStack {
                        Text(item).font(.callout.monospaced()).foregroundStyle(.primary)
                        Spacer()
                        if selection.contains(item) { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "搜索或输入")
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !selection.isEmpty { Button("清空") { selection = [] } }
        }
    }
}
