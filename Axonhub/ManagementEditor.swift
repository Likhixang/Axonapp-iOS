import SwiftUI

struct ManagementEditor: View {
    @ObservedObject var store: AxonStore
    let target: ManagementTarget
    var duplicateID: String? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var channel = ChannelDraft()
    @State private var model = ModelDraft()
    @State private var loaded = false
    @State private var loading = false
    @State private var saving = false
    @State private var writeStarted = false
    @State private var uncertainWrite = false
    @State private var failure: String?
    @State private var routes: JSON = .array([])
    @State private var fetched: [String] = []
    @State private var channelPage = 0
    @State private var selectingModels = false
    @State private var manualModel = ""
    @State private var advancedModels = false

    private var creating: Bool { target.entityID == nil }
    private var title: String {
        switch target.kind {
        case .channel: return NSLocalizedString(creating ? "新增渠道" : "编辑渠道", comment: "")
        case .model: return NSLocalizedString(creating ? "新增模型" : "编辑模型", comment: "")
        }
    }
    var body: some View {
        NavigationStack {
            Form {
                Section(NSLocalizedString("目标实例", comment: "")) {
                    Text(target.instance.name)
                    Text(target.instance.address).font(.caption).foregroundStyle(.secondary)
                }
                if loading { ProgressView() }
                if let failure = failure {
                    Section {
                        Text(failure).foregroundStyle(.red)
                        if !loaded && !loading { Button(NSLocalizedString("重新加载", comment: "")) { Task { await load() } } }
                        if uncertainWrite { Text(NSLocalizedString("写入可能已经完成。请关闭编辑器并刷新核对，勿重复提交。", comment: "")) }
                    }
                }
                if loaded {
                    switch target.kind {
                    case .channel: channelFields
                    case .model: modelFields
                    }
                }
            }
            .disabled(saving || loading)
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("取消", comment: "")) { clearSecrets(); dismiss() }.disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("保存", comment: "")) { Task { await save() } }
                        .disabled(!loaded || loading || saving || store.managementBusy || uncertainWrite || target.kind == .channel && creating && !channel.authorizeReadback)
                }
            }
            .interactiveDismissDisabled(saving)
            .task { await load() }
        }
        .onDisappear { clearSecrets() }
    }
    private var channelFields: some View {
        Group {
            Section {
                Picker("配置页面", selection: $channelPage) {
                    Text("连接").tag(0); Text("模型").tag(1); Text("高级").tag(2)
                }.pickerStyle(.segmented)
            }
            if channelPage == 0 {
                Section("基本信息") {
                    LabeledEditorField("名称", text: $channel.name)
                    Picker("渠道类型", selection: Binding(get: { channel.type }, set: { channel.migrate(to: $0); fetched = [] })) {
                        ForEach(ChannelType.allCases) { Text(NativeAdminLabels.value($0.rawValue)).tag($0.rawValue) }
                    }
                    LabeledEditorField("Base URL（留空使用默认地址）", text: $channel.baseURL)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .disabled(!creating && channel.type == "xai_subscription")
                    Button("使用服务商默认地址") { channel.baseURL = ChannelDefaults.urls[channel.type] ?? "" }
                    if !creating && channel.type != channel.original?["type"].string {
                        Toggle("确认迁移渠道类型", isOn: $channel.migrationConfirmed)
                        Text("类型迁移会重置协议与端点，请核对认证和模型配置。").font(.caption).foregroundStyle(.orange)
                    }
                    LabeledEditorField("备注", text: $channel.remark)
                    NativeStringListField(title: "标签", values: Binding(get: { channel.tags.lines }, set: { channel.tags = $0.joined(separator: "\n") }))
                }
                Section("认证") {
                    if (!creating || duplicateID != nil) && !channel.secretsLoaded {
                        Button("读取现有认证与高级配置") { Task { await loadSecrets() } }
                        Text("凭据只读入当前编辑器，不保存到本地；未修改的配置保持原样。").font(.caption).foregroundStyle(.secondary)
                        Text("不修改凭据时保持原样，无需重复输入。").font(.caption).foregroundStyle(.secondary)
                    } else {
                        if channel.type == "anthropic_gcp" || channel.type == "gemini_vertex" {
                            ChannelSchemaFields(value: $channel.credentials, type: "ChannelCredentialsInput", path: "credentials", secure: true)
                        } else if ["codex", "claudecode", "antigravity", "github_copilot", "xai_subscription"].contains(channel.type) {
                            NavigationLink("OAuth 授权或导入") { ChannelOAuthView(store: store, target: target, type: channel.type, credential: credentialKey, proxy: channel.settings["proxy"]) }
                            LabeledEditorField("OAuth JSON / Token", text: credentialKey, secure: true)
                            if channel.secretsLoaded {
                                NavigationLink("多个密钥及管理凭据") { Form { ChannelSchemaFields(value: $channel.credentials, type: "ChannelCredentialsInput", path: "credentials", secure: true) }.navigationTitle("认证") }
                            }
                        } else {
                            if channel.secretsLoaded && !channel.credentials["apiKeys"].array.isEmpty {
                                ForEach(Array(channel.credentials["apiKeys"].array.indices), id: \.self) { index in
                                    LabeledEditorField(NativeAdminLabels.field("apiKeys") + " \(index + 1)", text: credentialItem(index), secure: true)
                                }
                            } else if channel.type != "anthropic_aws" {
                                LabeledEditorField("API Key", text: credentialKey, secure: true)
                            }
                            NavigationLink("多个密钥及管理凭据") { Form { ChannelSchemaFields(value: $channel.credentials, type: "ChannelCredentialsInput", path: "credentials", secure: true) }.navigationTitle("认证") }
                        }
                    }
                }
                Section {
                    Button("获取上游模型并继续") { Task { await fetchModels(); if failure == nil { channelPage = 1; selectingModels = true } } }
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
            } else if channelPage == 1 {
                Section("上游模型") {
                    Button { Task { await fetchModels(); if failure == nil { selectingModels = true } } } label: { Label("获取上游模型", systemImage: "arrow.down.circle") }
                    Button { selectingModels = true } label: {
                        HStack { Text("选择支持的模型"); Spacer(); Text(String(channel.supportedModels.lines.count)).foregroundStyle(.secondary) }
                    }
                    if !fetched.isEmpty {
                        Button("选择全部上游模型") { setModels(Array(Set(channel.supportedModels.lines + fetched)).sorted()) }
                    }
                    Picker("默认测试模型", selection: $channel.defaultTestModel) {
                        Text("选择模型").tag("")
                        ForEach(channel.supportedModels.lines, id: \.self) { Text($0).tag($0) }
                    }
                    DisclosureGroup("手动添加") {
                        TextField("模型 ID", text: $manualModel).textInputAutocapitalization(.never).autocorrectionDisabled()
                        Button("添加") { setModels(Array(Set(channel.supportedModels.lines + manualModel.lines)).sorted()); manualModel = "" }.disabled(manualModel.trimmed.isEmpty)
                    }
                }
                Section("自动同步") {
                    Toggle("自动同步支持模型", isOn: $channel.autoSync)
                    if channel.autoSync {
                        TextField("同步正则（留空为全部）", text: $channel.syncPattern).textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                    if !creating { Button("立即同步模型") { Task { await syncModels() } } }
                    DisclosureGroup("保留的手动模型") {
                        NativeStringListField(title: "模型 ID", values: Binding(get: { channel.manualModels.lines }, set: { channel.manualModels = $0.joined(separator: "\n") }))
                    }
                }
            } else {
                Section("路由与协议") {
                    LabeledEditorField("排序权重", text: $channel.orderingWeight).keyboardType(.numbersAndPunctuation)
                    NavigationLink("策略与密钥自动禁用") { Form { ChannelSchemaFields(value: $channel.policies, type: "ChannelPoliciesInput", path: "policies") }.navigationTitle("策略与密钥自动禁用") }
                    NavigationLink("自定义端点与协议") { Form { ChannelSchemaFields(value: $channel.endpoints, type: "[ChannelEndpointInput!]", path: "endpoints") }.navigationTitle("自定义端点与协议") }
                }
                if (creating && duplicateID == nil) || channel.secretsLoaded {
                    Section("高级配置") {
                        ForEach(["modelMappings", "proxy", "transformOptions", "headerOverrideOperations", "bodyOverrideOperations", "rateLimit", "modelProtocols", "providerQuota"], id: \.self) { key in
                            if let type = ChannelInputSchema.fields["ChannelSettingsInput"]?[key] {
                                NavigationLink(NativeAdminLabels.field(key)) {
                                    Form {
                                        if channel.settings[key].isNull {
                                            Button("启用配置") { var s = channel.settings.object; s[key] = ChannelInputSchema.seed(type); channel.settings = .object(s) }
                                        } else {
                                            ChannelSchemaFields(value: setting(key), type: type, path: key)
                                        }
                                    }.navigationTitle(NativeAdminLabels.field(key))
                                }
                            }
                        }
                        NavigationLink("其他高级选项") { Form { ChannelSchemaFields(value: $channel.settings, type: "ChannelSettingsInput", path: "settings") }.navigationTitle("其他高级选项") }
                    }
                } else {
                    Section {
                        Button("读取现有认证与高级配置") { Task { await loadSecrets() } }
                        Text("凭据只读入当前编辑器，不保存到本地；未修改的配置保持原样。").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .sheet(isPresented: $selectingModels) {
            NavigationStack {
                NativeModelSelectionView(available: fetched, selected: Binding(get: { channel.supportedModels.lines }, set: { setModels($0) }))
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { selectingModels = false } } }
            }
        }
    }
    private func setting(_ key: String) -> Binding<JSON> { Binding(get: { channel.settings[key] }, set: { var s = channel.settings.object; s[key] = $0; channel.settings = .object(s) }) }
    private var credentialKey: Binding<String> {
        Binding(get: { channel.secretsLoaded ? channel.credentials["apiKey"].string : channel.apiKey }, set: { text in
            if channel.secretsLoaded { var fields = channel.credentials.object; fields["apiKey"] = .string(text); channel.credentials = .object(fields) }
            else { channel.apiKey = text }
        })
    }
    private func credentialItem(_ index: Int) -> Binding<String> {
        Binding(get: {
            let keys = channel.credentials["apiKeys"].array
            return keys.indices.contains(index) ? keys[index].string : ""
        }, set: { text in
            var keys = channel.credentials["apiKeys"].array
            guard keys.indices.contains(index) else { return }
            keys[index] = .string(text)
            var fields = channel.credentials.object; fields["apiKeys"] = .array(keys); channel.credentials = .object(fields)
        })
    }
    private func setModels(_ models: [String]) {
        channel.supportedModels = Array(Set(models)).sorted().joined(separator: "\n")
        channel.manualModels = channel.manualModels.lines.filter { models.contains($0) }.joined(separator: "\n")
        if !models.contains(channel.defaultTestModel) { channel.defaultTestModel = models.first ?? "" }
    }
    private var modelFields: some View {
        Group {
            Section(NSLocalizedString("基本信息", comment: "")) {
                LabeledEditorField("名称", text: $model.name)
                LabeledEditorField("模型 ID", text: $model.modelID)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                LabeledEditorField("开发者", text: $model.developer)
                Picker(NSLocalizedString("模型类型", comment: ""), selection: $model.type) {
                    ForEach(ModelType.allCases) { Text(NativeAdminLabels.value($0.rawValue)).tag($0.rawValue) }
                }
                LabeledEditorField("分组", text: $model.group)
                LabeledEditorField("图标（Lobe Icons 名称）", text: $model.icon)
                LabeledEditorField("备注", text: $model.remark)
            }
            Section(NSLocalizedString("路由关联", comment: "")) {
                if creating { LabeledEditorField("上游模型 ID", text: $model.routeModelID) }
                Toggle("不继承供应商设置", isOn: $model.disableInheritance)
                Picker("负载均衡", selection: $model.loadBalancer) {
                    ForEach(["default", "adaptive", "failover", "circuit-breaker", "round-robin"], id: \.self) { Text(NativeAdminLabels.value($0)).tag($0) }
                }
                Picker("追踪粘性", selection: $model.sticky) {
                    ForEach(["default", "disabled", "prefer_previous_channel"], id: \.self) { Text(NativeAdminLabels.value($0)).tag($0) }
                }
                NavigationLink("路由条件") {
                    Form { ChannelSchemaFields(value: associationsBinding, type: "[ModelAssociationInput!]", path: "associations") }
                }
                DisclosureGroup(obsText("高级 JSON 编辑")) {
                    TextEditor(text: $model.associationsJSON).font(.system(.caption, design: .monospaced)).frame(minHeight: 200).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Text("上游模型留空时使用 JSON 关联。").font(.caption)
                Button("预览路由") { Task { await previewRoutes() } }
                ForEach(Array(routes.array.enumerated()), id: \.offset) { _, row in
                    Text("\(row["channel"]["name"].string) · \(NativeAdminLabels.value(row["channel"]["status"].string)) · \(row["models"].array.map { $0["actualModel"].string }.joined(separator: ", "))").font(.caption)
                }
            }
            Section(NSLocalizedString("ModelCard 高级 JSON", comment: "")) {
                NavigationLink("模型信息") { Form { ChannelSchemaFields(value: cardBinding, type: "ModelCardInput", path: "modelCard") } }
                DisclosureGroup(obsText("高级 JSON 编辑")) {
                    TextEditor(text: $model.modelCard).font(.system(.caption, design: .monospaced)).frame(minHeight: 180)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Text(NSLocalizedString("新增可使用 {}。编辑时只有修改此 JSON 才会更新 ModelCard，其余配置原样保留。", comment: ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    @MainActor private func load() async {
        guard !loaded, !loading else { return }
        loading = true; failure = nil
        defer { loading = false }
        do {
            try store.validateTarget(target)
            if !creating || duplicateID != nil {
                var readTarget = target
                if let duplicateID = duplicateID { readTarget = ManagementTarget(instance: target.instance, connectionRevision: target.connectionRevision, entityID: duplicateID, kind: target.kind) }
                let detail = try await store.managementDetail(readTarget)
                switch target.kind {
                case .channel: channel = ChannelDraft(detail: detail)
                case .model: model = ModelDraft(detail: detail)
                }
                if let source = duplicateID {
                    if target.kind == .channel {
                        channel.duplicateSourceID = source
                        channel.original = nil; channel.name += " (copy)"; channel.replaceCredentials = true
                    } else { model.original = nil; model.modelID += "-copy"; model.name += " (copy)" }
                }
            }
            if creating { channel.authorizeReadback = true }
            loaded = true
        } catch { failure = error.localizedDescription }
    }
    @MainActor private func save() async {
        guard !saving, !uncertainWrite else { return }
        saving = true; failure = nil; writeStarted = false
        defer { saving = false }
        do {
            switch target.kind {
            case .channel: try await store.saveChannel(channel, target: target) { writeStarted = true }
            case .model: try await store.saveModel(model, target: target) { writeStarted = true }
            }
            clearSecrets(); dismiss()
        } catch {
            failure = error.localizedDescription
            // Network errors may follow a committed mutation; no blind retry.
            uncertainWrite = writeStarted
        }
    }

    private var associationsBinding: Binding<JSON> { Binding(get: { JSON.from(model.associationsJSON) ?? .array([]) }, set: { model.associationsJSON = $0.prettyJSON; model.routeModelID = "" }) }
    private var cardBinding: Binding<JSON> { Binding(get: { JSON.from(model.modelCard) ?? .object([:]) }, set: { model.modelCard = $0.prettyJSON }) }
    private func clearSecrets() { channel.apiKey = ""; channel.credentials = .object([:]); channel.originalCredentials = nil; channel.settings = .object([:]); channel.originalSettings = nil; channel.secretsLoaded = false }
    @MainActor private func loadSecrets() async {
        guard !loading, !saving else { return }
        loading = true; failure = nil; defer { loading = false }
        do {
            var readTarget = target
            if let source = duplicateID { readTarget = ManagementTarget(instance: target.instance, connectionRevision: target.connectionRevision, entityID: source, kind: .channel) }
            let secret = try await store.authorizedChannelSecrets(readTarget)
            if let original = channel.original { guard original["updatedAt"] == secret["updatedAt"] else { throw ManagementError.changedTarget } }
            channel.loadSecrets(secret)
        } catch { failure = error.localizedDescription }
    }
    @MainActor private func fetchModels() async {
        loading = true; failure = nil; defer { loading = false }
        do { fetched = try await store.managedFetchModels(channel, target: target) } catch { failure = error.localizedDescription }
    }
    @MainActor private func syncModels() async {
        guard let id = target.entityID else { return }
        saving = true; defer { saving = false }
        do {
            _ = try await store.managedBatch(target, ids: [id], action: .sync)
            channel = ChannelDraft(detail: try await store.managementDetail(target))
        } catch { failure = error.localizedDescription; uncertainWrite = true }
    }
    @MainActor private func previewRoutes() async {
        loading = true; defer { loading = false }
        do { routes = try await store.managedRoutePreview(model, target: target) } catch { failure = error.localizedDescription }
    }
}

/// A placeholder is not a field label: keep the label visible for populated values.
struct LabeledEditorField: View {
    let title: String
    @Binding var text: String
    var secure = false
    init(_ title: String, text: Binding<String>, secure: Bool = false) {
        self.title = obsText(title); _text = text; self.secure = secure
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            if secure { SecureField(title, text: $text).accessibilityLabel(title) }
            else { TextField(title, text: $text, axis: .vertical).accessibilityLabel(title) }
        }.textInputAutocapitalization(.never).autocorrectionDisabled().padding(.vertical, 3)
    }
}
