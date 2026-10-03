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
    @State private var secretsLoading = false
    @State private var writeStarted = false
    @State private var uncertainWrite = false
    @State private var failure: String?
    @State private var routes: JSON = .array([])
    @State private var fetched: [String] = []

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
                Section {
                    LabeledContent(obsText("目标实例"), value: target.instance.name)
                        .accessibilityValue(target.instance.name + " · " + target.instance.address)
                }
                if loading || secretsLoading { ProgressView() }
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
            .disabled(saving || loading || secretsLoading)
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("取消", comment: "")) { clearSecrets(); dismiss() }.disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("保存", comment: "")) { Task { await save() } }
                        .disabled(!loaded || loading || saving || secretsLoading || store.managementBusy || uncertainWrite || target.kind == .channel && creating && !channel.authorizeReadback)
                }
            }
            .interactiveDismissDisabled(saving)
            .task { await load() }
        }
        .onDisappear { clearSecrets() }
    }
    private var channelFields: some View {
        Group {
            channelBasicFields
            channelConnectionFields
            channelModelFields
            channelSyncFields
            channelRoutingFields
            channelRequestFields
        }
    }
    private var channelBasicFields: some View {
        Section("基本信息") {
            LabeledEditorField("名称", text: $channel.name)
            Picker("渠道类型", selection: Binding(get: { channel.type }, set: { channel.migrate(to: $0); fetched = [] })) {
                ForEach(ChannelType.allCases) { Text(NativeAdminLabels.value($0.rawValue)).tag($0.rawValue) }
            }.pickerStyle(.menu)
            if !creating && channel.type != channel.original?["type"].string {
                Toggle("确认迁移渠道类型", isOn: $channel.migrationConfirmed)
                Text("类型迁移会重置协议与端点，请核对认证和模型配置。").font(.caption).foregroundStyle(.orange)
            }
            LabeledEditorField("备注", text: $channel.remark)
            NativeStringListField(title: "标签", values: Binding(get: { channel.tags.lines }, set: { channel.tags = $0.joined(separator: "\n") }))
            LabeledEditorField("排序权重", text: $channel.orderingWeight).keyboardType(.numbersAndPunctuation)
        }
    }
    private var channelConnectionFields: some View {
        Section("连接与凭证") {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Base URL").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("恢复默认") { channel.baseURL = ChannelDefaults.urls[channel.type] ?? "" }
                        .frame(minHeight: 44).buttonStyle(.borderless)
                        .disabled(baseURLLocked)
                }
                TextField(ChannelDefaults.urls[channel.type] ?? obsText("留空使用默认地址"), text: $channel.baseURL, axis: .vertical)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityLabel("Base URL").disabled(baseURLLocked)
            }
            channelCredentialFields
        }
    }
    private var baseURLLocked: Bool { !creating && channel.type == "xai_subscription" }
    private var canEditChannelSecrets: Bool { (creating && duplicateID == nil) || channel.secretsLoaded }
    @ViewBuilder private var channelCredentialFields: some View {
        if !canEditChannelSecrets {
            Button("重新读取连接凭证") { Task { await loadSecrets() } }
        } else if channel.type == "anthropic_gcp" || channel.type == "gemini_vertex" {
            LabeledEditorField("项目 ID", text: gcpField("projectID"))
            LabeledEditorField("区域", text: gcpField("region"))
            KeyEditorField(title: obsText("服务账号 JSON"), text: gcpField("jsonData"))
            if channel.type == "gemini_vertex" { KeyEditorField(title: "API Key", text: credentialKey) }
        } else if ["codex", "claudecode", "antigravity", "github_copilot", "xai_subscription"].contains(channel.type) {
            NavigationLink {
                ChannelOAuthView(store: store, target: target, type: channel.type, credential: credentialKey, proxy: channel.settings["proxy"])
            } label: {
                Label("OAuth 授权或导入", systemImage: "person.badge.key")
            }
            KeyEditorField(title: "Token / JSON", text: credentialKey)
            if !channel.credentials["oauth"].isNull {
                KeyEditorField(title: "Access Token", text: oauthField("accessToken"))
                KeyEditorField(title: "Refresh Token", text: oauthField("refreshToken"))
                LabeledEditorField("Client ID", text: oauthField("clientID"))
            }
        } else if channel.type == "anthropic_aws" {
            KeyEditorField(title: "API Key", text: credentialKey)
        } else {
            channelAPIKeyFields
        }
    }
    private var channelAPIKeyFields: some View {
        Group {
            ForEach(Array(channel.editableKeys.indices), id: \.self) { index in
                KeyEditorField(title: "API Key \(index + 1)", text: credentialItem(index),
                    onRemove: channel.editableKeys.count > 1 ? { channel.removeKey(at: index) } : nil)
            }
            Button { channel.appendKey() } label: { Label("添加 API Key", systemImage: "plus") }
            if channel.type.hasPrefix("zenmux") || !channel.credentials["managementApiKey"].string.isEmpty {
                KeyEditorField(title: obsText("管理 API Key"), text: credentialField("managementApiKey"))
            }
        }
    }
    private var channelModelFields: some View {
        Section("支持的模型") {
            Button { Task { await fetchModels() } } label: {
                Label(fetched.isEmpty ? "获取上游模型并选择" : "刷新上游模型", systemImage: "arrow.triangle.2.circlepath")
            }
            NativeModelSelectionView(available: fetched,
                selected: Binding(get: { channel.supportedModels.lines }, set: { updateSupportedModels($0) }),
                embedded: true)
            Picker("默认测试模型", selection: $channel.defaultTestModel) {
                Text("选择模型").tag("")
                ForEach(channel.supportedModels.lines, id: \.self) { Text($0).tag($0) }
            }.pickerStyle(.menu)
        }
    }
    private var channelSyncFields: some View {
        Section("模型同步") {
            Toggle("自动同步支持模型", isOn: $channel.autoSync)
            if channel.autoSync {
                LabeledEditorField("同步正则（留空为全部）", text: $channel.syncPattern)
            }
            if !creating { Button("立即同步模型") { Task { await syncModels() } } }
            DisclosureGroup("同步时保留的手动模型") {
                NativeModelSelectionView(available: channel.supportedModels.lines,
                    selected: Binding(get: { channel.manualModels.lines }, set: { setManualModels($0) }),
                    embedded: true)
            }
        }
    }
    private var channelRoutingFields: some View {
        Section("模型与路由规则") {
            Picker("流式请求", selection: streamPolicy) {
                Text("默认（不限）").tag("")
                ForEach(["unlimited", "require", "forbid"], id: \.self) { Text(NativeAdminLabels.value($0)).tag($0) }
            }.pickerStyle(.menu)
            DisclosureGroup("密钥自动禁用规则") {
                ManagementSchemaContent(value: $channel.policies, type: "ChannelPoliciesInput", path: "policies", excludingFields: ["stream"])
            }
            DisclosureGroup("自定义端点与协议") {
                ManagementSchemaContent(value: $channel.endpoints, type: "[ChannelEndpointInput!]", path: "endpoints")
                if canEditChannelSecrets { settingFields(["modelProtocols"]) }
            }
            if canEditChannelSecrets {
                DisclosureGroup("模型映射与命名") {
                    settingFields(["modelMappings", "extraModelPrefix", "autoTrimedModelPrefixes", "lowercaseModelId", "hideOriginalModels", "hideMappedModels"])
                }
            }
        }
    }
    private var channelRequestFields: some View {
        Section("请求设置") {
            if canEditChannelSecrets {
                DisclosureGroup("网络代理") { settingFields(["proxy"]) }
                DisclosureGroup("请求转换与透传") { settingFields(["transformOptions", "passThroughUserAgent", "passThroughBody"]) }
                DisclosureGroup("请求头与请求体覆盖") { settingFields(["headerOverrideOperations", "bodyOverrideOperations"]) }
                DisclosureGroup("限流与重试") { settingFields(["rateLimit", "retryableStatusCodes", "retryableErrorPatterns"]) }
                DisclosureGroup("供应商额度凭证") { settingFields(["providerQuota"]) }
                if !remainingChannelSettings.isEmpty {
                    DisclosureGroup("其他请求设置") { settingFields(remainingChannelSettings) }
                }
            } else {
                Button("重新读取请求设置") { Task { await loadSecrets() } }
            }
        }
    }
    private var streamPolicy: Binding<String> {
        Binding(get: { channel.policies["stream"].string }, set: { next in
            var policies = channel.policies.object
            if next.isEmpty { policies.removeValue(forKey: "stream") }
            else { policies["stream"] = .string(next) }
            channel.policies = .object(policies)
        })
    }
    private var remainingChannelSettings: [String] {
        let grouped: Set<String> = ["modelProtocols", "modelMappings", "extraModelPrefix", "autoTrimedModelPrefixes", "lowercaseModelId", "hideOriginalModels", "hideMappedModels", "proxy", "transformOptions", "passThroughUserAgent", "passThroughBody", "headerOverrideOperations", "bodyOverrideOperations", "rateLimit", "retryableStatusCodes", "retryableErrorPatterns", "providerQuota"]
        return (ChannelInputSchema.fields["ChannelSettingsInput"] ?? [:]).keys.filter { !grouped.contains($0) }.sorted()
    }
    private func settingFields(_ keys: [String]) -> some View {
        ForEach(keys, id: \.self) { key in
            if let type = ChannelInputSchema.fields["ChannelSettingsInput"]?[key] {
                ManagementOptionalField(value: setting(key), type: type, path: "settings." + key)
            }
        }
    }
    private func setting(_ key: String) -> Binding<JSON> {
        Binding(get: { channel.settings[key] }, set: { next in
            var settings = channel.settings.object
            if next.isNull { settings.removeValue(forKey: key) } else { settings[key] = next }
            channel.settings = .object(settings)
        })
    }
    private var credentialKey: Binding<String> {
        Binding(get: { channel.secretsLoaded ? channel.credentials["apiKey"].string : channel.apiKey }, set: { text in
            if channel.secretsLoaded { var fields = channel.credentials.object; fields["apiKey"] = .string(text); channel.credentials = .object(fields) }
            else { channel.apiKey = text }
        })
    }
    private func credentialField(_ key: String) -> Binding<String> {
        Binding(get: { channel.credentials[key].string }, set: { text in
            var fields = channel.credentials.object; fields[key] = .string(text); channel.credentials = .object(fields)
        })
    }
    private func nestedCredential(_ group: String, _ key: String) -> Binding<String> {
        Binding(get: { channel.credentials[group][key].string }, set: { text in
            var nested = channel.credentials[group].object; nested[key] = .string(text)
            var fields = channel.credentials.object; fields[group] = .object(nested); channel.credentials = .object(fields)
        })
    }
    private func gcpField(_ key: String) -> Binding<String> { nestedCredential("gcp", key) }
    private func oauthField(_ key: String) -> Binding<String> { nestedCredential("oauth", key) }
    private func credentialItem(_ index: Int) -> Binding<String> {
        Binding(get: { channel.editableKeys.indices.contains(index) ? channel.editableKeys[index] : "" },
                set: { channel.setKey($0, at: index) })
    }
    private func setModels(_ models: [String]) {
        channel.supportedModels = Array(Set(models)).sorted().joined(separator: "\n")
        channel.manualModels = channel.manualModels.lines.filter { models.contains($0) }.joined(separator: "\n")
        if !models.contains(channel.defaultTestModel) { channel.defaultTestModel = models.first ?? "" }
    }
    private func updateSupportedModels(_ models: [String]) {
        let addedManually = models.filter { !channel.supportedModels.lines.contains($0) && !fetched.contains($0) }
        let preserved = channel.manualModels.lines + addedManually
        setModels(models)
        channel.manualModels = Array(Set(preserved.filter { models.contains($0) })).sorted().joined(separator: "\n")
    }
    private func setManualModels(_ models: [String]) {
        setModels(Array(Set(channel.supportedModels.lines + models)).sorted())
        channel.manualModels = Array(Set(models)).sorted().joined(separator: "\n")
    }
    private var modelFields: some View {
        Group {
            modelBasicFields
            modelRouteFields
            modelBehaviorFields
            modelCardFields
            modelJSONFields
        }
    }
    private var modelBasicFields: some View {
        Section("基本信息") {
            LabeledEditorField("名称", text: $model.name)
            LabeledEditorField("模型 ID", text: $model.modelID)
            LabeledEditorField("开发者", text: $model.developer)
            Picker("模型类型", selection: $model.type) {
                ForEach(ModelType.allCases) { Text(NativeAdminLabels.value($0.rawValue)).tag($0.rawValue) }
            }.pickerStyle(.menu)
            LabeledEditorField("分组", text: $model.group)
            LabeledEditorField("图标（Lobe Icons 名称）", text: $model.icon)
            LabeledEditorField("备注", text: $model.remark)
        }
    }
    private var modelRouteFields: some View {
        Section("路由关联") {
            if creating { LabeledEditorField("上游模型 ID", text: $model.routeModelID) }
            DisclosureGroup("渠道匹配与路由条件") {
                ManagementSchemaContent(value: associationsBinding, type: "[ModelAssociationInput!]", path: "associations")
            }
            Button("预览路由") { Task { await previewRoutes() } }
            ForEach(Array(routes.array.enumerated()), id: \.offset) { _, row in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(row["channel"]["name"].string)
                        Spacer()
                        Text(NativeAdminLabels.value(row["channel"]["status"].string)).foregroundStyle(.secondary)
                    }
                    Text(row["models"].array.map { $0["actualModel"].string }.joined(separator: ", "))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
    private var modelBehaviorFields: some View {
        Section("调度策略") {
            Toggle("不继承供应商设置", isOn: $model.disableInheritance)
            Picker("负载均衡", selection: $model.loadBalancer) {
                ForEach(["default", "adaptive", "failover", "circuit-breaker", "round-robin"], id: \.self) { Text(NativeAdminLabels.value($0)).tag($0) }
            }.pickerStyle(.menu)
            Picker("追踪粘性", selection: $model.sticky) {
                ForEach(["default", "disabled", "prefer_previous_channel"], id: \.self) { Text(NativeAdminLabels.value($0)).tag($0) }
            }.pickerStyle(.menu)
        }
    }
    private var modelCardFields: some View {
        Section("模型信息") {
            DisclosureGroup("能力与输入输出") {
                modelCardFieldGroup(["reasoning", "toolCall", "temperature", "vision", "modalities"])
            }
            DisclosureGroup("上下文与输出上限") { modelCardFieldGroup(["limit"]) }
            DisclosureGroup("Token 价格") { modelCardFieldGroup(["cost"]) }
            DisclosureGroup("知识与发布日期") { modelCardFieldGroup(["knowledge", "releaseDate", "lastUpdated"]) }
        }
    }
    private func modelCardFieldGroup(_ keys: [String]) -> some View {
        ForEach(keys, id: \.self) { key in
            if let type = ChannelInputSchema.fields["ModelCardInput"]?[key] {
                ManagementOptionalField(value: modelCardField(key), type: type, path: "modelCard." + key)
            }
        }
    }
    private func modelCardField(_ key: String) -> Binding<JSON> {
        Binding(get: { cardBinding.wrappedValue[key] }, set: { next in
            var card = cardBinding.wrappedValue.object
            if next.isNull { card.removeValue(forKey: key) } else { card[key] = next }
            cardBinding.wrappedValue = .object(card)
        })
    }
    private var modelJSONFields: some View {
        Section("JSON 编辑") {
            DisclosureGroup("路由条件 JSON") { jsonEditor($model.associationsJSON) }
            DisclosureGroup("模型信息 JSON") { jsonEditor($model.modelCard) }
        }
    }
    private func jsonEditor(_ text: Binding<String>) -> some View {
        TextEditor(text: text).font(.system(.caption, design: .monospaced)).frame(minHeight: 180)
            .textInputAutocapitalization(.never).autocorrectionDisabled()
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
            if target.kind == .channel { await loadSecrets() }
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
        guard !secretsLoading, !saving, !creating || duplicateID != nil else { return }
        secretsLoading = true; failure = nil; defer { secretsLoading = false }
        do {
            var readTarget = target
            if let source = duplicateID { readTarget = ManagementTarget(instance: target.instance, connectionRevision: target.connectionRevision, entityID: source, kind: .channel) }
            let secret = try await store.authorizedChannelSecrets(readTarget)
            if let original = channel.original { guard original["updatedAt"] == secret["updatedAt"] else { throw ManagementError.changedTarget } }
            try Task.checkCancellation()
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
            saving = false
            await loadSecrets()
        } catch { failure = error.localizedDescription; uncertainWrite = true }
    }
    @MainActor private func previewRoutes() async {
        loading = true; defer { loading = false }
        do { routes = try await store.managedRoutePreview(model, target: target) } catch { failure = error.localizedDescription }
    }
}

/// This editor has one disclosure per task; schema objects and array items stay
/// visible inside it. AnyView breaks the recursive SwiftUI type, not the data model.
private struct ManagementSchemaContent: View {
    @Binding var value: JSON
    let type: String
    var path = ""
    var secure = false
    var excludingFields: Set<String> = []
    private var clean: String { type.trimmingCharacters(in: CharacterSet(charactersIn: "!")) }
    private var sensitive: Bool {
        secure || path.split(separator: ".").contains {
            ["credentials", "proxy", "providerQuota", "headerOverrideOperations", "bodyOverrideOperations"].contains(String($0))
        }
    }
    var body: some View {
        Group {
            if clean.hasPrefix("[") {
                arrayFields
            } else if let fields = ChannelInputSchema.fields[clean] {
                ForEach(fields.keys.filter { !excludingFields.contains($0) }.sorted(), id: \.self) { key in
                    ManagementOptionalField(value: field(key), type: fields[key] ?? "String", path: path + "." + key, secure: sensitive)
                }
            } else {
                ChannelSchemaFields(value: $value, type: type, path: path, secure: sensitive)
            }
        }
    }
    private var fieldLabel: String { NativeAdminLabels.field(path.split(separator: ".").last.map(String.init) ?? "item") }
    private var arrayFields: some View {
        Group {
            ForEach(Array(value.array.indices), id: \.self) { index in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("\(fieldLabel) · \(index + 1)").font(.subheadline.weight(.medium))
                        Spacer()
                        Button(role: .destructive) { removeItem(index) } label: {
                            Image(systemName: "minus.circle").frame(width: 44, height: 44)
                        }.buttonStyle(.borderless)
                            .accessibilityLabel(obsText("移除") + " " + String(index + 1))
                    }
                    arrayItem(index)
                }
            }
            Button { value = .array(value.array + [ChannelInputSchema.seed(elementType)]) } label: {
                Label(obsText("添加") + " " + fieldLabel, systemImage: "plus")
            }.frame(minHeight: 44)
        }
    }
    private var elementType: String { String(clean.dropFirst().dropLast()) }
    private func arrayItem(_ index: Int) -> AnyView {
        AnyView(ManagementSchemaContent(value: item(index), type: elementType, path: path, secure: sensitive))
    }
    private func field(_ key: String) -> Binding<JSON> {
        Binding(get: { value[key] }, set: { next in
            var object = value.object
            if next.isNull { object.removeValue(forKey: key) } else { object[key] = next }
            value = .object(object)
        })
    }
    private func item(_ index: Int) -> Binding<JSON> {
        Binding(get: { value.array.indices.contains(index) ? value.array[index] : .null }, set: { next in
            var items = value.array
            guard items.indices.contains(index) else { return }
            items[index] = next; value = .array(items)
        })
    }
    private func removeItem(_ index: Int) {
        var items = value.array
        guard items.indices.contains(index) else { return }
        items.remove(at: index); value = .array(items)
    }
}

private struct ManagementOptionalField: View {
    @Binding var value: JSON
    let type: String
    let path: String
    var secure = false
    private var label: String { NativeAdminLabels.field(path.split(separator: ".").last.map(String.init) ?? path) }
    private var composite: Bool {
        let clean = type.trimmingCharacters(in: CharacterSet(charactersIn: "!"))
        return clean.hasPrefix("[") || ChannelInputSchema.fields[clean] != nil
    }
    var body: some View {
        Group {
            if value.isNull {
                Button(obsText("配置") + " " + label) { value = ChannelInputSchema.seed(type) }
                    .frame(minHeight: 44)
            } else {
                if composite {
                    HStack {
                        Text(label).font(.subheadline.weight(.medium))
                        Spacer()
                        clearButton
                    }.padding(.top, 4)
                    content
                } else {
                    HStack(alignment: .center, spacing: 8) {
                        content
                        clearButton
                    }
                }
            }
        }
    }
    @ViewBuilder private var clearButton: some View {
        if !type.hasSuffix("!") {
            Button(role: .destructive) { value = .null } label: {
                Image(systemName: "xmark.circle").frame(width: 44, height: 44)
            }.buttonStyle(.borderless).accessibilityLabel(obsText("清除") + " " + label)
        }
    }
    private var content: AnyView {
        AnyView(ManagementSchemaContent(value: $value, type: type, path: path, secure: secure))
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
            if !secure { Text(title).font(.caption).foregroundStyle(.secondary) }
            if secure { KeyEditorField(title: title, text: $text) }
            else { TextField(title, text: $text, axis: .vertical).accessibilityLabel(title) }
        }.textInputAutocapitalization(.never).autocorrectionDisabled().padding(.vertical, 3)
    }
}
