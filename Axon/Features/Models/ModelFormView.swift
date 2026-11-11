import SwiftUI

/// Create or edit a model: identity, model card, routing settings and channel associations,
/// following the web console's model dialog and model settings dialog.
struct ModelFormView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    let existing: AIModel?
    var onSaved: (AIModel) -> Void

    @State private var draft = ModelDraft()
    @State private var channels: [ChannelOption] = []
    @State private var modelSuggestions: [String] = []
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var didLoad = false

    init(model: AIModel? = nil, onSaved: @escaping (AIModel) -> Void) {
        existing = model
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            Form {
                identitySection
                capabilitySection
                modalitySection
                priceSection
                limitSection
                datesSection
                routingSection
                associationsSection
                if let errorMessage {
                    Section { Text(errorMessage).font(.footnote).foregroundStyle(Theme.danger) }
                }
            }
            .navigationTitle(existing == nil ? "新建模型" : "编辑模型")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving { ProgressView() } else {
                        Button(existing == nil ? "创建" : "保存") { Task { await save() } }
                            .disabled(draft.modelID.trimmed.isEmpty || draft.developer.trimmed.isEmpty)
                    }
                }
            }
            .task { await loadOnce() }
        }
    }

    // MARK: Sections

    private var identitySection: some View {
        Section {
            LabeledField("厂商") {
                TextField("openai、anthropic…", text: $draft.developer)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            LabeledField("模型 ID") {
                TextField("gpt-4o", text: $draft.modelID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
            }
            LabeledField("显示名称") { TextField("不填则用模型 ID", text: $draft.name) }
            Picker("类型", selection: $draft.type) {
                ForEach(ModelType.allCases) { Text($0.label).tag($0.rawValue) }
            }
            LabeledField("分组") {
                TextField("不填则用厂商", text: $draft.group)
                    .textInputAutocapitalization(.never)
            }
            LabeledField("图标") {
                TextField("图标名，如 OpenAI", text: $draft.icon)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            LabeledField("备注") { TextField("可选", text: $draft.remark, axis: .vertical) }
        } header: {
            Text("基本信息")
        }
    }

    private var capabilitySection: some View {
        Section("能力") {
            Toggle("工具调用", isOn: $draft.toolCall)
            Toggle("视觉", isOn: $draft.vision)
            Toggle("支持温度参数", isOn: $draft.temperature)
            Toggle("支持推理", isOn: $draft.reasoningSupported)
            if draft.reasoningSupported {
                Toggle("默认开启推理", isOn: $draft.reasoningDefault)
                NavigationLink {
                    MultiSelectView(title: "推理强度", options: ReasoningEffort.allCases.map { ($0.rawValue, $0.rawValue) },
                                    selection: $draft.reasoningEfforts)
                } label: {
                    LabeledContent("推理强度", value: draft.reasoningEfforts.isEmpty ? "未设置" : draft.reasoningEfforts.joined(separator: ", "))
                }
            }
        }
    }

    private var modalitySection: some View {
        Section("模态") {
            NavigationLink {
                MultiSelectView(title: "输入模态", options: Modality.allCases.map { ($0.rawValue, $0.label) },
                                selection: $draft.inputModalities)
            } label: {
                LabeledContent("输入", value: modalityText(draft.inputModalities))
            }
            NavigationLink {
                MultiSelectView(title: "输出模态", options: Modality.allCases.map { ($0.rawValue, $0.label) },
                                selection: $draft.outputModalities)
            } label: {
                LabeledContent("输出", value: modalityText(draft.outputModalities))
            }
        }
    }

    private var priceSection: some View {
        Section {
            NumberField("输入", text: $draft.costInput)
            NumberField("输出", text: $draft.costOutput)
            NumberField("缓存读取", text: $draft.costCacheRead)
            NumberField("缓存写入", text: $draft.costCacheWrite)
        } header: {
            Text("价格")
        } footer: {
            Text("单位：美元 / 百万 Token。只用于展示，计费以渠道价格为准。")
        }
    }

    private var limitSection: some View {
        Section {
            NumberField("上下文窗口", text: $draft.contextLimit, placeholder: "128000 或 128k")
            NumberField("最大输出", text: $draft.outputLimit, placeholder: "16384 或 16k")
        } header: {
            Text("上下文")
        }
    }

    private var datesSection: some View {
        Section("日期") {
            LabeledField("知识截止") { TextField("2024-10", text: $draft.knowledge) }
            LabeledField("发布日期") { TextField("2025-01-01", text: $draft.releaseDate) }
            LabeledField("最后更新") { TextField("2025-01-01", text: $draft.lastUpdated) }
        }
    }

    private var routingSection: some View {
        Section {
            Picker("负载均衡", selection: $draft.loadBalancerStrategy) {
                ForEach(LoadBalancerStrategy.allCases) { Text($0.label).tag($0.rawValue) }
            }
            Picker("会话粘滞", selection: $draft.traceStickyMode) {
                ForEach(TraceStickyMode.allCases) { Text($0.label).tag($0.rawValue) }
            }
            Toggle("不继承厂商设置", isOn: Binding(
                get: { draft.settings.disableDeveloperSettingsInheritance ?? false },
                set: { draft.settings.disableDeveloperSettingsInheritance = $0 }))
        } header: {
            Text("路由")
        } footer: {
            Text("“默认”会继承厂商或系统的设置。")
        }
    }

    private var associationsSection: some View {
        Section {
            ForEach($draft.settings.associations) { $association in
                NavigationLink {
                    AssociationEditorView(association: $association, channels: channels, modelSuggestions: modelSuggestions)
                } label: {
                    AssociationRow(association: association, channelName: channelName)
                }
            }
            .onDelete { draft.settings.associations.remove(atOffsets: $0) }
            .onMove { draft.settings.associations.move(fromOffsets: $0, toOffset: $1) }
            Menu {
                ForEach(AssociationKind.allCases) { kind in
                    Button(kind.label) {
                        var association = ModelAssociation(kind: kind, priority: draft.settings.associations.count)
                        if kind == .model { association.update(model: draft.modelID.trimmed) }
                        draft.settings.associations.append(association)
                    }
                }
            } label: {
                Label("添加关联", systemImage: "plus.circle")
            }
            if !draft.settings.associations.isEmpty {
                NavigationLink {
                    ConnectionPreviewView(associations: draft.settings.associations)
                } label: {
                    Label("预览会命中的渠道", systemImage: "point.3.connected.trianglepath.dotted")
                }
            }
        } header: {
            Text("渠道关联 (\(draft.settings.associations.count))")
        } footer: {
            Text("决定这个模型的请求会走哪些渠道、用哪个上游模型。左滑删除，优先级数字越小越先匹配。")
        }
    }

    // MARK: Helpers

    private func modalityText(_ values: [String]) -> String {
        values.isEmpty ? "未设置" : values.map { Modality(rawValue: $0)?.label ?? $0 }.joined(separator: "、")
    }

    private func channelName(_ id: Int) -> String? {
        channels.first { $0.numericID == id }?.name
    }

    private func loadOnce() async {
        guard !didLoad, let service = session.service else { return }
        didLoad = true
        if let existing {
            draft = ModelDraft(model: existing)
            if let fresh = try? await service.model(id: existing.id) { draft = ModelDraft(model: fresh) }
        }
        async let channelList = try? service.channelOptions()
        async let suggestions = try? service.modelIDSuggestions()
        channels = await channelList ?? []
        var ids = await suggestions ?? []
        for channel in channels { ids.append(contentsOf: channel.supportedModels ?? []) }
        var seen = Set<String>()
        modelSuggestions = ids.filter { seen.insert($0).inserted }.sorted()
    }

    private func save() async {
        if let error = draft.validationError {
            errorMessage = error
            return
        }
        if let bad = draft.settings.associations.first(where: { $0.validationError != nil }) {
            errorMessage = "关联“\(bad.kind?.label ?? bad.type)”：\(bad.validationError ?? "")"
            return
        }
        guard let service = session.service else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let saved: AIModel
            if let existing {
                saved = try await service.updateModel(id: existing.id, draft.updateInput)
            } else {
                saved = try await service.createModel(draft.createInput)
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onSaved(saved)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Associations

struct AssociationRow: View {
    let association: ModelAssociation
    let channelName: (Int) -> String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(association.kind?.label ?? association.type).font(.subheadline.weight(.medium))
                if !association.isEnabled { Tag(text: "已停用", color: Color.secondary) }
                if association.hasCondition { Tag(text: "有条件", color: Color.orange) }
                Spacer()
                Text("优先级 \(association.priority ?? 0)").font(.caption).foregroundStyle(.secondary)
            }
            Text(association.summary(channelName: channelName))
                .font(.caption.monospaced())
                .foregroundStyle(association.validationError == nil ? Color.secondary : Theme.danger)
                .lineLimit(2)
        }
        .opacity(association.isEnabled ? 1 : 0.6)
    }
}

struct AssociationEditorView: View {
    @Binding var association: ModelAssociation
    let channels: [ChannelOption]
    let modelSuggestions: [String]

    private var allTags: [String] { ChannelOption.allTags(channels) }

    var body: some View {
        Form {
            Section {
                Picker("类型", selection: Binding(
                    get: { association.kind ?? .model },
                    set: { association.setKind($0) })) {
                    ForEach(AssociationKind.allCases) { Text($0.label).tag($0) }
                }
                Stepper(value: Binding(get: { association.priority ?? 0 }, set: { association.priority = $0 }), in: 0...999) {
                    LabeledContent("优先级", value: String(association.priority ?? 0))
                }
                Toggle("启用", isOn: Binding(get: { association.isEnabled }, set: { association.disabled = !$0 }))
            }

            if let kind = association.kind {
                Section {
                    if kind.usesChannel {
                        Picker("渠道", selection: Binding(
                            get: { association.channelID ?? 0 },
                            set: { association.update(channel: $0) })) {
                            Text("请选择").tag(0)
                            ForEach(channels) { channel in
                                if let id = channel.numericID { Text(channel.name).tag(id) }
                            }
                        }
                    }
                    if kind.usesTags {
                        NavigationLink {
                            TagPickerView(title: "渠道标签", known: allTags, selection: Binding(
                                get: { association.tagsValue },
                                set: { association.update(tags: $0) }))
                        } label: {
                            LabeledContent("渠道标签", value: association.tagsValue.isEmpty ? "未选" : association.tagsValue.joined(separator: ", "))
                        }
                    }
                    if kind.usesPattern {
                        LabeledField("正则") {
                            TextField("^gpt-4o.*", text: Binding(get: { association.patternValue }, set: { association.update(pattern: $0) }))
                                .font(.body.monospaced())
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                    } else {
                        LabeledField("上游模型") {
                            TextField("模型 ID", text: Binding(get: { association.modelValue }, set: { association.update(model: $0) }))
                                .font(.body.monospaced())
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                        let matches = suggestions(for: association.modelValue)
                        if !matches.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack {
                                    ForEach(matches, id: \.self) { id in
                                        Button(id) { association.update(model: id) }
                                            .font(.caption.monospaced())
                                            .adaptiveButtonStyle()
                                            .controlSize(.small)
                                    }
                                }
                            }
                        }
                    }
                } header: {
                    Text("匹配")
                } footer: {
                    if let error = association.validationError {
                        Text(error).foregroundStyle(Theme.danger)
                    }
                }

                if kind.supportsExclude {
                    Section {
                        ForEach(Array((association.excludeValue ?? []).enumerated()), id: \.offset) { index, rule in
                            NavigationLink {
                                ExcludeEditorView(rule: Binding(
                                    get: { (association.excludeValue ?? [])[safe: index] ?? ExcludeAssociation() },
                                    set: { value in
                                        var list = association.excludeValue ?? []
                                        if list.indices.contains(index) { list[index] = value }
                                        association.excludeValue = list
                                    }), channels: channels, allTags: allTags)
                            } label: {
                                Text(excludeSummary(rule)).font(.callout).lineLimit(2)
                            }
                        }
                        .onDelete { offsets in
                            var list = association.excludeValue ?? []
                            list.remove(atOffsets: offsets)
                            association.excludeValue = list
                        }
                        Button {
                            var list = association.excludeValue ?? []
                            list.append(ExcludeAssociation(channelNamePattern: ""))
                            // keep the placeholder until the user fills it in
                            switch association.kind {
                            case .regex?: association.regex?.exclude = list
                            case .model?: association.modelId?.exclude = list
                            default: break
                            }
                        } label: {
                            Label("添加排除规则", systemImage: "minus.circle")
                        }
                    } header: {
                        Text("排除渠道")
                    } footer: {
                        Text("命中任一排除规则的渠道不会被这条关联选中。")
                    }
                }

                if association.hasCondition {
                    Section {
                        Text(association.when?.prettyPrinted ?? "")
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                        Button("清除条件", role: .destructive) { association.when = nil }
                    } header: {
                        Text("生效条件")
                    } footer: {
                        Text("条件在网页端编辑，这里会原样保留。")
                    }
                }
            }
        }
        .navigationTitle("关联")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func suggestions(for text: String) -> [String] {
        let q = text.trimmed.lowercased()
        guard !q.isEmpty else { return Array(modelSuggestions.prefix(12)) }
        return Array(modelSuggestions.filter { $0.lowercased().contains(q) && $0.lowercased() != q }.prefix(12))
    }

    private func excludeSummary(_ rule: ExcludeAssociation) -> String {
        var parts: [String] = []
        if let p = rule.channelNamePattern?.nilIfBlank { parts.append("名称 ~ \(p)") }
        if let ids = rule.channelIds, !ids.isEmpty {
            parts.append("渠道 " + ids.map { id in channels.first { $0.numericID == id }?.name ?? "#\(id)" }.joined(separator: ", "))
        }
        if let tags = rule.channelTags, !tags.isEmpty { parts.append("标签 " + tags.joined(separator: ", ")) }
        return parts.isEmpty ? "（空规则，点击填写）" : parts.joined(separator: "；")
    }
}

struct ExcludeEditorView: View {
    @Binding var rule: ExcludeAssociation
    let channels: [ChannelOption]
    let allTags: [String]

    var body: some View {
        Form {
            Section("渠道名称正则") {
                TextField("例如 ^backup-", text: Binding(get: { rule.channelNamePattern ?? "" }, set: { rule.channelNamePattern = $0 }))
                    .font(.body.monospaced())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            Section("渠道") {
                ForEach(channels) { channel in
                    if let id = channel.numericID {
                        let selected = rule.channelIds?.contains(id) ?? false
                        Button {
                            var ids = rule.channelIds ?? []
                            if selected { ids.removeAll { $0 == id } } else { ids.append(id) }
                            rule.channelIds = ids.isEmpty ? nil : ids
                        } label: {
                            HStack {
                                Text(channel.name).foregroundStyle(.primary)
                                Spacer()
                                if selected { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
                            }
                        }
                    }
                }
            }
            NavigationLink {
                TagPickerView(title: "渠道标签", known: allTags, selection: Binding(
                    get: { rule.channelTags ?? [] },
                    set: { rule.channelTags = $0.isEmpty ? nil : $0 }))
            } label: {
                LabeledContent("渠道标签", value: (rule.channelTags ?? []).isEmpty ? "未选" : (rule.channelTags ?? []).joined(separator: ", "))
            }
        }
        .navigationTitle("排除规则")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Which channels and upstream models the current associations resolve to (`queryModelChannelConnections`).
struct ConnectionPreviewView: View {
    @Environment(SessionStore.self) private var session
    let associations: [ModelAssociation]
    @State private var state: Loadable<[ModelChannelConnection]> = .idle

    var body: some View {
        Group {
            switch state {
            case .idle, .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ErrorStateView(message: message) { await load() }
            case .loaded(let connections):
                if connections.isEmpty {
                    ContentUnavailableView("没有命中的渠道", systemImage: "point.3.connected.trianglepath.dotted",
                                           description: Text("检查关联里的模型 ID、正则或标签是否和渠道支持的模型对得上。"))
                } else {
                    List {
                        ForEach(Array(connections.enumerated()), id: \.offset) { _, connection in
                            Section {
                                ForEach(connection.models, id: \.self) { entry in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.requestModel).font(.callout.monospaced())
                                        if entry.actualModel != entry.requestModel {
                                            Text("→ " + entry.actualModel).font(.caption.monospaced()).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            } header: {
                                HStack {
                                    Text(connection.channel.name)
                                    Spacer()
                                    Text("优先级 \(connection.priority)")
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
        }
        .navigationTitle("命中的渠道")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        guard let service = session.service else { return }
        state = .loading
        do {
            let valid = associations.filter { $0.validationError == nil }
            state = .loaded(try await service.modelChannelConnections(valid))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

// MARK: - Small form helpers

struct LabeledField<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        LabeledContent(title) {
            content.multilineTextAlignment(.trailing)
        }
    }
}

struct NumberField: View {
    let title: String
    @Binding var text: String
    var placeholder = "0"

    init(_ title: String, text: Binding<String>, placeholder: String = "0") {
        self.title = title
        _text = text
        self.placeholder = placeholder
    }

    var body: some View {
        LabeledField(title) {
            TextField(placeholder, text: $text)
                .keyboardType(.numbersAndPunctuation)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
    }
}

struct MultiSelectView: View {
    let title: String
    let options: [(value: String, label: String)]
    @Binding var selection: [String]

    var body: some View {
        List {
            ForEach(options, id: \.value) { option in
                Button {
                    if let index = selection.firstIndex(of: option.value) {
                        selection.remove(at: index)
                    } else {
                        let order = options.map(\.value)
                        selection = (selection + [option.value]).sorted {
                            (order.firstIndex(of: $0) ?? .max) < (order.firstIndex(of: $1) ?? .max)
                        }
                    }
                } label: {
                    HStack {
                        Text(option.label).foregroundStyle(.primary)
                        Spacer()
                        if selection.contains(option.value) { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Pick from known tags or type new ones.
struct TagPickerView: View {
    let title: String
    let known: [String]
    @Binding var selection: [String]
    @State private var newTag = ""

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("新标签", text: $newTag)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit(add)
                    Button("添加", action: add).disabled(newTag.trimmed.isEmpty)
                }
            }
            Section {
                ForEach(Array(Set(known + selection)).sorted(), id: \.self) { tag in
                    Button {
                        if let i = selection.firstIndex(of: tag) { selection.remove(at: i) } else { selection.append(tag) }
                    } label: {
                        HStack {
                            Text(tag).foregroundStyle(.primary)
                            Spacer()
                            if selection.contains(tag) { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
                        }
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func add() {
        let tag = newTag.trimmed
        guard !tag.isEmpty else { return }
        if !selection.contains(tag) { selection.append(tag) }
        newTag = ""
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
