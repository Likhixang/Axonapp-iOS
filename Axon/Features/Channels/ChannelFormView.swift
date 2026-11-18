import SwiftUI

/// Create / edit form for API-key based channels.
struct ChannelFormView: View {
    enum Mode {
        case create
        case edit(Channel)

        var channel: Channel? {
            if case .edit(let channel) = self { return channel }
            return nil
        }
    }

    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    let mode: Mode
    var onSaved: (Channel) -> Void

    @State private var type = "openai"
    @State private var name = ""
    @State private var baseURL = ""
    @State private var apiKeys = ""
    @State private var models: [String] = []
    @State private var newModel = ""
    @State private var defaultTestModel = ""
    @State private var tags: [String] = []
    @State private var weight = 0
    @State private var remark = ""
    @State private var autoSync = false
    @State private var apiKeyStrategy = ChannelChoices.defaultAPIKeyStrategy
    @State private var switchAfter = 1
    @State private var quotaRoutingMode = "INHERIT"
    @State private var streamPolicy = "unlimited"
    @State private var proxyType = "disabled"
    @State private var proxyURL = ""
    @State private var proxyUsername = ""
    @State private var proxyPassword = ""
    @State private var proxyNoReuse = false

    @State private var tagSuggestions: [String] = []
    @State private var proxyPresets: [ProxyPreset] = []
    @State private var quotaDefaultMode: String?
    @State private var isLoadingOptions = false
    @State private var showQuickAdd = false

    @State private var isSaving = false
    @State private var isFetching = false
    @State private var errorMessage: String?
    @State private var fetchedModels: [String] = []
    @State private var showModelPicker = false
    @State private var didPrefill = false

    private var isEditing: Bool { mode.channel != nil }
    private var provider: ChannelProvider { .of(type) }

    private var canSave: Bool {
        !name.trimmed.isEmpty && !models.isEmpty && (isEditing || !apiKeys.listItems.isEmpty) && !isSaving
            && (proxyType != "url" || !proxyURL.trimmed.isEmpty)
    }

    private var quickAddModels: [String] { ChannelChoices.quickAddModels(type: type, existing: []) }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    if isEditing {
                        LabeledContent("类型", value: provider.name)
                    } else {
                        Picker("类型", selection: $type) {
                            ForEach(ChannelProvider.creatable) { item in
                                Text(item.name).tag(item.type)
                            }
                        }
                        .pickerStyle(.navigationLink)
                    }
                    TextField("名称", text: $name)
                    TextField(provider.defaultBaseURL ?? "Base URL", text: $baseURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.callout.monospaced())
                }

                Section {
                    TextField(isEditing ? "留空则保持原密钥不变" : "sk-...", text: $apiKeys, axis: .vertical)
                        .lineLimit(1...5)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.callout.monospaced())
                } header: {
                    Text("API 密钥")
                } footer: {
                    Text("多个密钥用换行或逗号分隔，网关会轮流使用。")
                }

                Section {
                    ForEach(models, id: \.self) { model in
                        HStack {
                            Text(model).font(.callout.monospaced())
                            Spacer()
                            if model == defaultTestModel {
                                Text("测试").font(.caption2).foregroundStyle(Theme.accent)
                            }
                        }
                        .swipeActions {
                            Button("移除", role: .destructive) { remove(model) }
                            Button("设为测试") { defaultTestModel = model }.tint(.blue)
                        }
                    }
                    HStack {
                        TextField("添加模型 ID", text: $newModel)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.callout.monospaced())
                            .onSubmit(addModel)
                        Button("添加", action: addModel).disabled(newModel.trimmed.isEmpty)
                    }
                    Button {
                        Task { await fetchModels() }
                    } label: {
                        HStack {
                            Label("从上游拉取模型列表", systemImage: "icloud.and.arrow.down")
                            Spacer()
                            if isFetching { ProgressView() }
                        }
                    }
                    .disabled(isFetching)
                    if !quickAddModels.isEmpty {
                        Button {
                            showQuickAdd = true
                        } label: {
                            Label("从推荐模型中选择", systemImage: "sparkles")
                        }
                    }
                } header: {
                    Text("模型 (\(models.count))")
                } footer: {
                    Text("左滑可移除或设为默认测试模型。推荐模型和网页端“快速添加”的列表一样。")
                }

                Section {
                    OptionPickerRow(
                        title: "默认测试模型",
                        value: ChannelTestModel.resolve(defaultTestModel, models: models),
                        monospaced: true,
                        options: models,
                        allowsCustom: false,
                        emptyMessage: "先添加模型"
                    ) { defaultTestModel = $0 }
                    TagPickerRow(suggestions: tagSuggestions, isLoading: isLoadingOptions, tags: $tags)
                } footer: {
                    Text("默认测试模型用于测试连接。标签可以从已有渠道的标签里选，也可以新建。")
                }

                Section {
                    ChoicePicker(title: "Key 策略", choices: ChannelChoices.apiKeyStrategies, selection: $apiKeyStrategy)
                    if ChannelChoices.isRoundRobin(apiKeyStrategy) {
                        Stepper("每个 Key 用 \(switchAfter) 次后切换", value: $switchAfter, in: 1...10000)
                    }
                    ChoicePicker(title: "限额调度模式", choices: ChannelChoices.quotaRoutingModes, selection: $quotaRoutingMode) {
                        ChannelChoices.quotaRoutingLabel($0.value, systemDefault: quotaDefaultMode)
                    }
                    ChoicePicker(title: "流式策略", choices: ChannelChoices.streamPolicies, selection: $streamPolicy)
                } header: {
                    Text("调度")
                } footer: {
                    Text(ChannelChoices.quotaRoutingModes.first { $0.value == quotaRoutingMode }?.detail ?? "")
                }

                Section {
                    ChoicePicker(title: "代理类型", choices: ChannelChoices.proxyTypes, selection: $proxyType)
                    if proxyType == "url" {
                        if !proxyPresets.isEmpty {
                            OptionPickerRow(
                                title: "已保存的代理",
                                value: proxyPresets.first { $0.url == proxyURL }?.url ?? "",
                                placeholder: "选择已保存的代理",
                                display: { url in proxyPresets.first { $0.url == url }?.title ?? url },
                                options: proxyPresets.map(\.url),
                                label: { url in proxyPresets.first { $0.url == url }?.title ?? url },
                                detail: { url in
                                    let preset = proxyPresets.first { $0.url == url }
                                    return preset?.name?.nilIfBlank == nil ? nil : url
                                },
                                allowsCustom: false
                            ) { applyPreset($0) }
                        }
                        TextField("http://proxy.example.com:8080", text: $proxyURL)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.callout.monospaced())
                        TextField("用户名（可选）", text: $proxyUsername)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        SecureField("密码（可选）", text: $proxyPassword)
                        Toggle("每次请求使用新的代理连接", isOn: $proxyNoReuse)
                    }
                } header: {
                    Text("代理")
                } footer: {
                    Text(ChannelChoices.proxyTypes.first { $0.value == proxyType }?.detail ?? "")
                }

                Section("高级") {
                    Toggle("自动同步模型列表", isOn: $autoSync)
                    Stepper("排序权重：\(weight)", value: $weight, in: -1000...1000)
                    TextField("备注", text: $remark, axis: .vertical)
                        .lineLimit(1...4)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).font(.footnote).foregroundStyle(Theme.danger)
                    }
                }
            }
            .navigationTitle(isEditing ? "编辑渠道" : "新建渠道")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("保存") { Task { await save() } }.disabled(!canSave)
                    }
                }
            }
            .sheet(isPresented: $showModelPicker) {
                ModelMultiPicker(available: fetchedModels, selected: $models)
            }
            .sheet(isPresented: $showQuickAdd) {
                ModelMultiPicker(available: quickAddModels, selected: $models)
            }
            .onAppear(perform: prefill)
            .task { await loadOptions() }
            .onChange(of: models) { _, newValue in
                defaultTestModel = ChannelTestModel.resolve(defaultTestModel, models: newValue)
            }
            .onChange(of: type) { _, _ in
                if name.isEmpty || ChannelProvider.catalog.contains(where: { $0.name == name }) {
                    name = provider.name
                }
            }
            .interactiveDismissDisabled(isSaving)
        }
    }

    private func prefill() {
        guard !didPrefill else { return }
        didPrefill = true
        guard let channel = mode.channel else {
            name = provider.name
            return
        }
        type = channel.type
        name = channel.name
        baseURL = channel.baseURL ?? ""
        models = channel.supportedModels
        defaultTestModel = channel.defaultTestModel ?? ""
        tags = channel.tags ?? []
        apiKeyStrategy = channel.settings?.apiKeyStrategy?.nilIfBlank ?? ChannelChoices.defaultAPIKeyStrategy
        switchAfter = max(1, channel.settings?.apiKeyRoundRobinSwitchAfter ?? 1)
        quotaRoutingMode = ChannelChoices.quotaRoutingMode(from: channel.settings)
        streamPolicy = ChannelChoices.streamPolicy(from: channel.policies)
        let proxy = channel.settings?.proxy
        proxyType = ChannelChoices.proxyType(proxy?.type)
        proxyURL = proxy?.url ?? ""
        proxyUsername = proxy?.username ?? ""
        proxyPassword = proxy?.password ?? ""
        proxyNoReuse = proxy?.disableConnectionReuse ?? false
        weight = channel.orderingWeight ?? 0
        remark = channel.remark ?? ""
        autoSync = channel.autoSyncSupportedModels ?? false
    }

    /// Loads the select options the web console loads for this dialog. Each one is optional:
    /// a failure (for example a key without the settings scope) leaves that select empty.
    private func loadOptions() async {
        guard let service = session.service else { return }
        isLoadingOptions = true
        defer { isLoadingOptions = false }
        async let tagsResult = try? service.allChannelTags()
        async let presetsResult = try? service.proxyPresets()
        async let quotaResult = try? service.quotaRoutingDefaultMode()
        tagSuggestions = await tagsResult ?? []
        proxyPresets = await presetsResult ?? []
        quotaDefaultMode = await quotaResult
    }

    private func applyPreset(_ url: String) {
        guard let preset = proxyPresets.first(where: { $0.url == url }) else { return }
        proxyURL = preset.url
        proxyUsername = preset.username ?? ""
        proxyPassword = preset.password ?? ""
    }

    private func addModel() {
        for item in newModel.listItems where !models.contains(item) {
            models.append(item)
        }
        if defaultTestModel.isEmpty { defaultTestModel = models.first ?? "" }
        newModel = ""
    }

    private func remove(_ model: String) {
        models.removeAll { $0 == model }
        if defaultTestModel == model { defaultTestModel = models.first ?? "" }
    }

    private func fetchModels() async {
        guard let service = session.service else { return }
        let url = baseURL.nilIfBlank ?? provider.defaultBaseURL ?? ""
        guard !url.isEmpty else {
            errorMessage = "请先填写 Base URL"
            return
        }
        isFetching = true
        errorMessage = nil
        defer { isFetching = false }
        do {
            let list = try await service.fetchUpstreamModels(type: type, baseURL: url, apiKey: apiKeys.listItems.first,
                                                             channelID: mode.channel?.id)
            guard !list.isEmpty else {
                errorMessage = "上游没有返回模型"
                return
            }
            fetchedModels = list.sorted()
            showModelPicker = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() async {
        guard let service = session.service else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let testModel = ChannelTestModel.resolve(defaultTestModel, models: models)
        let proxy = ChannelChoices.proxyInput(type: proxyType, url: proxyURL, username: proxyUsername,
                                              password: proxyPassword, disableConnectionReuse: proxyNoReuse)
        let settingsFields = ChannelChoices.settingsFields(apiKeyStrategy: apiKeyStrategy, switchAfter: switchAfter,
                                                           quotaRoutingMode: quotaRoutingMode, proxy: proxy)
        var input: [String: JSONValue] = [
            "name": .string(name.trimmed),
            "supportedModels": .strings(models),
            "defaultTestModel": .string(testModel),
            "tags": .strings(tags),
            "orderingWeight": .int(weight),
            "autoSyncSupportedModels": .bool(autoSync),
            "remark": .string(remark.trimmed),
        ]
        let keys = apiKeys.listItems
        if !keys.isEmpty {
            let credentials: JSONValue = keys.count == 1 ? .object(["apiKey": .string(keys[0])]) : .object(["apiKeys": .strings(keys)])
            input["credentials"] = credentials
        }

        do {
            let saved: Channel
            if let channel = mode.channel {
                if let url = baseURL.nilIfBlank {
                    input["baseURL"] = .string(url)
                } else if channel.baseURL?.nilIfBlank != nil {
                    input["clearBaseURL"] = true
                }
                if ChannelChoices.streamPolicy(from: channel.policies) != streamPolicy {
                    input["policies"] = ChannelChoices.policiesInput(existing: channel.policies, stream: streamPolicy)
                }
                _ = try await service.updateChannel(id: channel.id, input)
                saved = try await service.updateChannelSettings(id: channel.id, settingsFields)
            } else {
                input["type"] = .string(type)
                input["settings"] = .object(settingsFields)
                input["policies"] = .object(["stream": .string(streamPolicy)])
                input["baseURL"] = .string(baseURL.nilIfBlank ?? provider.defaultBaseURL ?? "")
                saved = try await service.createChannel(input)
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onSaved(saved)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Searchable multi-select list used after fetching upstream models.
struct ModelMultiPicker: View {
    let available: [String]
    @Binding var selected: [String]
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var picked: Set<String> = []

    private var filtered: [String] {
        query.isEmpty ? available : available.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            List(filtered, id: \.self) { model in
                Button {
                    if picked.contains(model) { picked.remove(model) } else { picked.insert(model) }
                } label: {
                    HStack {
                        Text(model).font(.callout.monospaced()).foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: picked.contains(model) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(picked.contains(model) ? Theme.accent : .secondary)
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
            .navigationTitle("选择模型 (\(picked.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        selected = available.filter { picked.contains($0) } + selected.filter { !available.contains($0) }
                        dismiss()
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    HStack {
                        Button("全选") { picked.formUnion(filtered) }
                        Spacer()
                        Button("清空") { picked.subtract(filtered) }
                    }
                }
            }
            .onAppear { picked = Set(selected).intersection(available) }
        }
    }
}
