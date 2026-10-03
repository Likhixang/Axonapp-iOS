import SwiftUI
import Charts

struct NativeProfilesView: View {
    @ObservedObject var session: AdminSession
    let entity: String
    let id: String
    var embedded = false
    var inline = false
    var onUncertainChange: (Bool) -> Void = { _ in }
    var coordinatedSave = false
    var onDraftChange: (JSON, JSON) -> Void = { _, _ in }
    var onReadyChange: (Bool) -> Void = { _ in }
    @State private var baseline: JSON = .null
    @State private var profiles: JSON = .object([:])
    @State private var loaded = false
    @State private var loading = false
    @State private var loadError: String?
    @State private var selectedProfileIndex: Int?
    @State private var uncertain = false
    @State private var selectedTemplate: String = ""
    @State private var templates: [JSON] = []
    @State private var confirmRemoval: Int?
    @State private var showRemoval = false
    private var isKey: Bool { entity == "APIKey" }
    var body: some View {
        Group {
            if inline { fields }
            else { Form { fields } }
        }
        .modifier(NativeProfilesTitle(embedded: embedded || inline))
        .disabled(session.busy || session.invalidated || uncertain)
        .toolbar { if !embedded && !inline { Button("保存策略") { save() }.disabled(!loaded || loading || uncertain) } }
        .task { if !loaded { await load() } }
        .onChange(of: uncertain) { onUncertainChange($0) }
        .onChange(of: profiles) { onDraftChange($0, baseline) }
        .onChange(of: loaded) { onReadyChange($0); if $0 { onDraftChange(profiles, baseline) } }
        .onChange(of: session.invalidated) { invalid in
            if invalid {
                baseline = .null; profiles = .object([:]); templates = []; loaded = false
                selectedProfileIndex = nil; selectedTemplate = ""; confirmRemoval = nil
                loading = false; loadError = nil; showRemoval = false
            }
        }
        .alert("移除 Profile", isPresented: $showRemoval) {
            Button("取消", role: .cancel) { confirmRemoval = nil }
            Button("移除", role: .destructive) {
                guard let index = confirmRemoval, profiles["profiles"].array.indices.contains(index) else { return }
                var list = profiles["profiles"].array
                list.remove(at: index)
                if let selected = selectedProfileIndex {
                    if selected > index { selectedProfileIndex = selected - 1 }
                    else if selected == index { selectedProfileIndex = list.isEmpty ? nil : min(index, list.count - 1) }
                }
                replaceList(list)
                confirmRemoval = nil
            }
        } message: {
            Text((confirmRemoval.flatMap { profiles["profiles"].array.indices.contains($0) ? profiles["profiles"].array[$0]["name"].string : nil } ?? "") + "\n\n" + obsText("移除后该 Profile 的模型、渠道与额度配置将不再保留；保存后生效。"))
        }
    }
    @ViewBuilder private var fields: some View {
        if !loaded {
            if loading { ProgressView("正在读取服务器数据") }
            else {
                if let loadError { ObservabilityErrorView(message: loadError) }
                Button("重试读取策略") { Task { await load() } }.frame(minHeight: 44)
            }
        } else {
            NativeProfileFieldGroup(title: "当前策略", embedded: inline) {
                HStack {
                    if profiles["profiles"].array.count > 1 {
                        Picker("Profile", selection: profileSelection) {
                            ForEach(Array(profiles["profiles"].array.enumerated()), id: \.offset) { index, profile in
                                Text(profile["name"].string).tag(index)
                            }
                        }.pickerStyle(.menu)
                    } else { Text("Profile") }
                    Spacer()
                    Menu {
                        Button("新增 Profile") { addProfile() }
                        if let index = validSelectedIndex {
                            Button("设为启用策略") { var p = profiles.object; p["activeProfile"] = profiles["profiles"].array[index]["name"]; profiles = .object(p) }
                            if profiles["profiles"].array.count > 1 {
                                Button("移除 Profile", role: .destructive) { confirmRemoval = index; showRemoval = true }
                            }
                        }
                    } label: { Label("操作", systemImage: "ellipsis") }
                }.frame(minHeight: 44).buttonStyle(.borderless)
                if let index = validSelectedIndex {
                    if profiles["profiles"].array[index]["name"].string == profiles["activeProfile"].string {
                        Label("当前启用", systemImage: "checkmark").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Button("设为启用策略") { var p = profiles.object; p["activeProfile"] = profiles["profiles"].array[index]["name"]; profiles = .object(p) }
                    }
                }
            }
            if let index = validSelectedIndex {
                NativeProfileEditor(session: session, profile: profileBinding(index), isKey: isKey, embedded: true)
                    .id(index)
            }
            if (embedded || inline) && !coordinatedSave {
                Button("保存策略") { save() }.frame(minHeight: 44).disabled(loading || uncertain)
            }
            if isKey {
                DisclosureGroup("策略模板") {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("模板", selection: $selectedTemplate) {
                            Text("选择模板").tag("")
                            ForEach(templates, id: \.self) { Text($0["name"].string).tag($0["id"].string) }
                        }.pickerStyle(.menu).frame(minHeight: 44)
                        Button("载入模板") { loadTemplate() }.frame(minHeight: 44).disabled(selectedTemplate.isEmpty)
                        Text("载入模板会立即更新服务端策略，请先保存当前修改。").font(.caption).foregroundStyle(.orange)
                    }
                }.frame(minHeight: 44)
            }
        }
        if !inline {
            if loaded, let error = session.error { ObservabilityErrorView(message: error) }
            if uncertain { Text("写入可能已经完成。请关闭编辑器并刷新核对，勿重复提交。").foregroundStyle(.orange) }
        }
    }
    private var validSelectedIndex: Int? {
        let list = profiles["profiles"].array
        if let index = selectedProfileIndex, list.indices.contains(index) { return index }
        return list.firstIndex { $0["name"].string == profiles["activeProfile"].string } ?? list.indices.first
    }
    private var profileSelection: Binding<Int> {
        Binding(get: { validSelectedIndex ?? 0 }, set: { index in
            guard profiles["profiles"].array.indices.contains(index) else { return }
            selectedProfileIndex = index
        })
    }
    private func addProfile() {
        var list = profiles["profiles"].array
        var index = list.count + 1
        while list.contains(where: { $0["name"].string == "Profile \(index)" }) { index += 1 }
        list.append(.object(["name": .string("Profile \(index)"), "channelIDs": .array([]), "channelTags": .array([]), "channelTagsMatchMode": .string("any"), "modelMappings": .array([]), "modelIDs": .array([]), "loadBalanceStrategy": .string("default"), "traceStickyMode": .string("default")]))
        replaceList(list)
        selectedProfileIndex = list.count - 1
    }
    private func string(_ key: String) -> Binding<String> { Binding(get: { profiles[key].string }, set: { var p = profiles.object; p[key] = .string($0); profiles = .object(p) }) }
    private func profileBinding(_ index: Int) -> Binding<JSON> {
        Binding(get: { profiles["profiles"].array.indices.contains(index) ? profiles["profiles"].array[index] : .null }, set: { next in
            var list = profiles["profiles"].array
            guard list.indices.contains(index) else { return }
            let wasActive = list[index]["name"].string == profiles["activeProfile"].string
            list[index] = next
            var p = profiles.object
            p["profiles"] = .array(list)
            if wasActive { p["activeProfile"] = next["name"] }
            profiles = .object(p)
        })
    }
    private func replaceList(_ list: [JSON]) {
        var p = profiles.object
        p["profiles"] = .array(list)
        if !list.contains(where: { $0["name"].string == p["activeProfile"]?.string }) { p["activeProfile"] = list.first?["name"] ?? .string("") }
        profiles = .object(p)
        selectedProfileIndex = validSelectedIndex
    }
    @MainActor private func load(resetSelection: Bool = false) async {
        guard !loading, !session.invalidated else { return }
        loading = true; loadError = nil; loaded = false
        defer { loading = false }
        do {
            let next = try await session.detail(entity, id: id)
            guard !next.isNull else { throw AdminError.notFound }
            var nextTemplates: [JSON] = []
            if isKey {
                let value = try await session.read("apiKeyProfileTemplates", variables: .object(["first": .number(100), "where": .object(["projectID": next["projectID"]])]))
                nextTemplates = value["edges"].array.map { $0["node"] }
            }
            try session.validate()
            baseline = next
            profiles = session.schema.project(next["profiles"], type: isKey ? "UpdateAPIKeyProfilesInput" : "UpdateProjectProfilesInput")
            templates = nextTemplates; loaded = true
            if resetSelection { selectedProfileIndex = nil }
            selectedProfileIndex = validSelectedIndex
        } catch {
            guard !session.invalidated else { return }
            loadError = error.localizedDescription
        }
    }
    private func save() {
        guard loaded, !loading, !uncertain else { return }
        session.start {
            try NativeProfileValidation.validate(profiles, isKey: isKey)
            let operation = try session.schema.operation(isKey ? "updateAPIKeyProfiles" : "updateProjectProfiles")
            uncertain = true
            _ = try await session.execute(operation, variables: .object(["id": .string(id), "input": profiles]), baseline: baseline)
            uncertain = false
            await load()
        }
    }
    private func loadTemplate() {
        guard loaded, !loading, !uncertain, !selectedTemplate.isEmpty else { return }
        session.start {
            let operation = try session.schema.operation("loadApiKeyProfileTemplate")
            uncertain = true
            _ = try await session.execute(operation, variables: .object(["input": .object(["apiKeyID": .string(id), "templateID": .string(selectedTemplate)])]), baseline: baseline)
            uncertain = false
            await load(resetSelection: true)
        }
    }
}

/// Form/List sections at the root, plain stacks for inline content.
private struct NativeProfileFieldGroup<Content: View>: View {
    let title: LocalizedStringKey
    let embedded: Bool
    @ViewBuilder var content: () -> Content
    var body: some View {
        if embedded {
            VStack(alignment: .leading, spacing: 12) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                content()
            }.padding(.vertical, 6)
        } else {
            Section { content() } header: { Text(title) }
        }
    }
}

private struct NativeProfilesTitle: ViewModifier {
    let embedded: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if embedded { content }
        else { content.navigationTitle("配置 Profiles") }
    }
}

struct NativeProfileEditor: View {
    @ObservedObject var session: AdminSession
    @Binding var profile: JSON
    let isKey: Bool
    var embedded = false
    var renamed: (String, String) -> Void = { _, _ in }
    @State private var channels: [ChannelItem] = []
    @State private var models: [String] = []
    @State private var channelSearch = ""
    private var filteredChannels: [ChannelItem] { channels.filter { channelSearch.isEmpty || $0.name.localizedCaseInsensitiveContains(channelSearch) } }
    var body: some View {
        Group {
            if embedded { fields }
            else { Form { fields }.navigationTitle("策略配置") }
        }
        .disabled(session.busy || session.invalidated)
        .task {
            guard channels.isEmpty && models.isEmpty else { return }
            do {
                try session.validate()
                channels = session.store.snapshot.channels
                models = Array(Set(session.store.snapshot.models.map(\.modelID) + channels.flatMap(\.supportedModels))).sorted()
            } catch { session.error = error.localizedDescription }
        }
    }
    private var fields: some View {
        Group {
            LabeledContent("Profile 名称") {
                TextField("Profile 名称", text: Binding(get: { profile["name"].string }, set: { new in
                    let old = profile["name"].string
                    set("name", .string(new))
                    renamed(old, new)
                })).multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .frame(minHeight: 44)
            }
            if !profile["templateName"].string.isEmpty {
                LabeledContent("关联模板", value: profile["templateName"].string)
                Button("解除模板关联") { remove("templateID"); remove("templateName") }.frame(minHeight: 44)
            }
            if isKey {
                NativeMappingsField(value: json("modelMappings"), models: models)
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 12) {
                        NativeModelSelectionView(available: models, selected: list("modelIDs"), embedded: true)
                    }
                } label: { selectionSummary("允许的模型", count: profile["modelIDs"].array.count) }
            }
            DisclosureGroup {
                channelSelection
            } label: { selectionSummary("允许的渠道", count: profile["channelIDs"].array.count) }
            DisclosureGroup("渠道标签与匹配") {
                VStack(alignment: .leading, spacing: 12) {
                    NativeStringListField(title: "渠道标签", values: list("channelTags"))
                    Picker("标签匹配方式", selection: string("channelTagsMatchMode", fallback: "any")) {
                        Text("任一标签").tag("any"); Text("全部标签").tag("all"); Text("排除标签").tag("none")
                    }.pickerStyle(.menu).frame(minHeight: 44)
                }
            }.frame(minHeight: 44)
            if isKey {
                NativeProfileFieldGroup(title: "路由策略", embedded: embedded) {
                        Picker("负载均衡", selection: string("loadBalanceStrategy", fallback: "default")) {
                            ForEach(["default", "adaptive", "failover", "circuit-breaker", "round-robin"], id: \.self) { Text(NativeAdminLabels.value($0)).tag($0) }
                        }.pickerStyle(.menu).frame(minHeight: 44)
                        Picker("追踪粘性", selection: string("traceStickyMode", fallback: "default")) {
                            ForEach(["default", "disabled", "prefer_previous_channel"], id: \.self) { Text(NativeAdminLabels.value($0)).tag($0) }
                        }.pickerStyle(.menu).frame(minHeight: 44)
                }
                NativeProfileFieldGroup(title: "额度限制", embedded: embedded) {
                        Toggle("启用额度限制", isOn: Binding(get: { !profile["quota"].isNull }, set: { enabled in
                            if enabled { set("quota", .object(["period": .object(["type": .string("all_time")])])) }
                            else { remove("quota") }
                        })).frame(minHeight: 44)
                        if !profile["quota"].isNull { NativeQuotaFields(quota: json("quota")) }
                }
            }
            if !embedded, let error = session.error { ObservabilityErrorView(message: error) }
        }
    }
    private var channelSelection: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("搜索渠道") {
                TextField("搜索名称", text: $channelSearch).textInputAutocapitalization(.never).autocorrectionDisabled().frame(minHeight: 44)
            }
            if !filteredChannels.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(filteredChannels) { channel in
                            if let numeric = ChannelModelToolsView.channelNumericID(channel.id) {
                                Toggle(channel.name, isOn: membership(.number(Double(numeric)), key: "channelIDs"))
                                    .frame(minHeight: 44)
                            }
                        }
                    }
                }.frame(height: min(CGFloat(filteredChannels.count) * 52, 260))
            }
        }
    }
    private func selectionSummary(_ title: LocalizedStringKey, count: Int) -> some View { HStack { Text(title); Spacer(); Text(count == 0 ? obsText("不限制") : String(count)).foregroundStyle(.secondary) }.frame(minHeight: 44) }
    private func set(_ key: String, _ value: JSON) { var p = profile.object; p[key] = value; profile = .object(p) }
    private func remove(_ key: String) { var p = profile.object; p.removeValue(forKey: key); profile = .object(p) }
    private func json(_ key: String) -> Binding<JSON> { Binding(get: { profile[key] }, set: { set(key, $0) }) }
    private func string(_ key: String, fallback: String = "") -> Binding<String> { Binding(get: { profile[key].string.isEmpty ? fallback : profile[key].string }, set: { set(key, .string($0)) }) }
    private func list(_ key: String) -> Binding<[String]> { Binding(get: { profile[key].array.map(\.string) }, set: { set(key, .array($0.map(JSON.string))) }) }
    private func membership(_ value: JSON, key: String) -> Binding<Bool> { Binding(get: { profile[key].array.contains(value) }, set: { selected in var values = profile[key].array.filter { $0 != value }; if selected { values.append(value) }; set(key, .array(values)) }) }
}

struct NativeQuotaFields: View {
    @Binding var quota: JSON
    var body: some View {
        number("requests", title: "请求数上限", integer: true)
        number("totalTokens", title: "Token 上限", integer: true)
        number("cost", title: "费用上限（USD）", integer: false)
        Picker("额度周期", selection: Binding(get: { quota["period"]["type"].string }, set: { type in
            var period: [String: JSON] = ["type": .string(type)]
            if type == "past_duration" { period["pastDuration"] = .object(["value": .number(1), "unit": .string("day")]) }
            if type == "calendar_duration" { period["calendarDuration"] = .object(["unit": .string("month")]) }
            set("period", .object(period))
        })) {
            Text("累计").tag("all_time"); Text("滚动时间窗口").tag("past_duration"); Text("日历周期").tag("calendar_duration")
        }.pickerStyle(.menu)
        if quota["period"]["type"].string == "past_duration" {
            LabeledContent("窗口长度") {
                TextField("窗口长度", text: Binding(get: { quota["period"]["pastDuration"]["value"].string.isEmpty ? String(quota["period"]["pastDuration"]["value"].int) : quota["period"]["pastDuration"]["value"].string }, set: { setPeriod("pastDuration", "value", Int($0).map { .number(Double($0)) } ?? .string($0)) }))
                    .keyboardType(.numberPad).multilineTextAlignment(.trailing)
            }
            Picker("单位", selection: periodString("pastDuration", "unit")) {
                Text("分钟").tag("minute"); Text("小时").tag("hour"); Text("天").tag("day")
            }.pickerStyle(.menu)
        }
        if quota["period"]["type"].string == "calendar_duration" {
            Picker("单位", selection: periodString("calendarDuration", "unit")) { Text("天").tag("day"); Text("月").tag("month") }.pickerStyle(.menu)
        }
    }
    private func number(_ key: String, title: LocalizedStringKey, integer: Bool) -> some View {
        LabeledContent(title) {
            TextField(title, text: Binding(get: {
                if quota[key].isNull { return "" }
                if !quota[key].string.isEmpty { return quota[key].string }
                return integer ? String(quota[key].int) : String(quota[key].number)
            }, set: { text in
                if text.isEmpty { var q = quota.object; q.removeValue(forKey: key); quota = .object(q) }
                else if integer { set(key, Int(text).map { .number(Double($0)) } ?? .string(text)) }
                else { set(key, .string(text)) }
            })).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
        }
    }
    private func set(_ key: String, _ value: JSON) { var q = quota.object; q[key] = value; quota = .object(q) }
    private func setPeriod(_ kind: String, _ key: String, _ value: JSON) { var q = quota.object; var p = quota["period"].object; var d = quota["period"][kind].object; d[key] = value; p[kind] = .object(d); q["period"] = .object(p); quota = .object(q) }
    private func periodString(_ kind: String, _ key: String) -> Binding<String> { Binding(get: { quota["period"][kind][key].string }, set: { setPeriod(kind, key, .string($0)) }) }
}

struct NativeModelSelectionView: View {
    let available: [String]
    @Binding var selected: [String]
    var embedded = false
    @State private var search = ""
    @State private var manual = ""
    private var candidates: [String] { Array(Set(available + selected)).sorted().filter { search.isEmpty || $0.localizedCaseInsensitiveContains(search) } }
    var body: some View {
        Group {
            if embedded {
                LabeledContent("搜索模型") {
                    TextField("模型 ID", text: $search).textInputAutocapitalization(.never).autocorrectionDisabled().frame(minHeight: 44)
                }
                selectionActions
                if !candidates.isEmpty {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) { candidateRows }
                    }.frame(height: min(CGFloat(candidates.count) * 48, 260))
                }
                manualFields
            } else {
                List {
                    Section { selectionActions }
                    Section { candidateRows }
                    Section("手动添加") { manualFields }
                }.searchable(text: $search, prompt: obsText("搜索模型"))
                    .navigationTitle("选择模型")
            }
        }
    }
    private var selectionActions: some View {
        HStack {
            Text(String(format: obsText("已选择 %lld 个模型"), Int64(selected.count))).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("全选") { selected = Array(Set(selected + candidates)).sorted() }.frame(minHeight: 44)
            Button("取消全选") { selected = selected.filter { !candidates.contains($0) } }.frame(minHeight: 44)
        }.buttonStyle(.borderless)
    }
    private var candidateRows: some View {
        ForEach(candidates, id: \.self) { model in
            Button {
                if selected.contains(model) { selected.removeAll { $0 == model } }
                else { selected.append(model) }
            } label: {
                HStack {
                    Text(model).foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: selected.contains(model) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected.contains(model) ? Color.accentColor : .secondary)
                }.frame(minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(.plain)
        }
    }
    private var manualFields: some View {
        LabeledContent("手动添加") {
            TextField("模型 ID", text: $manual).textInputAutocapitalization(.never).autocorrectionDisabled().frame(minHeight: 44)
            Button("添加") { selected = Array(Set(selected + manual.lines)).sorted(); manual = "" }
                .frame(minWidth: 44, minHeight: 44).disabled(manual.trimmed.isEmpty).buttonStyle(.borderless)
        }
    }
}

struct NativeMappingsField: View {
    @Binding var value: JSON
    let models: [String]
    var body: some View {
        Text("模型映射").font(.subheadline.weight(.medium))
        if !value.array.isEmpty {
            HStack {
                Text("请求模型").frame(maxWidth: .infinity, alignment: .leading)
                Text("实际模型").frame(maxWidth: .infinity, alignment: .leading)
            }.font(.caption).foregroundStyle(.secondary)
        }
        ForEach(Array(value.array.indices), id: \.self) { index in
            HStack {
                TextField("请求模型", text: field(index, "from")).frame(minHeight: 44)
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                TextField("实际模型", text: field(index, "to")).frame(minHeight: 44)
                Button(role: .destructive) {
                    var items = value.array
                    guard items.indices.contains(index) else { return }
                    items.remove(at: index); value = .array(items)
                } label: {
                    Image(systemName: "minus.circle").frame(minWidth: 44, minHeight: 44)
                }.buttonStyle(.borderless).accessibilityLabel("移除模型映射")
            }.textInputAutocapitalization(.never).autocorrectionDisabled()
        }
        Button("添加模型映射") { value = .array(value.array + [.object(["from": .string(""), "to": .string("")])]) }.frame(minHeight: 44)
    }
    private func field(_ index: Int, _ key: String) -> Binding<String> { Binding(get: { value.array.indices.contains(index) ? value.array[index][key].string : "" }, set: { text in var items = value.array; guard items.indices.contains(index) else { return }; var p = items[index].object; p[key] = .string(text); items[index] = .object(p); value = .array(items) }) }
}

struct NativeStringListField: View {
    let title: LocalizedStringKey
    @Binding var values: [String]
    @State private var text = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.medium))
            TextField(title, text: $text, axis: .vertical)
                .frame(minHeight: 44)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .onAppear { text = values.joined(separator: "\n") }
                .onChange(of: text) { values = $0.lines }
                .onChange(of: values) { next in
                    if text.lines != next { text = next.joined(separator: "\n") }
                }
        }
    }
}

enum NativeProfileValidation {
    static func validate(_ value: JSON, isKey: Bool) throws {
        let list = value["profiles"].array
        let names = list.map { $0["name"].string.trimmed.lowercased() }
        guard !list.isEmpty, names.allSatisfy({ !$0.isEmpty }), Set(names).count == names.count,
              list.contains(where: { $0["name"].string == value["activeProfile"].string }) else { throw AdminError.invalidInput }
        guard isKey else { return }
        for profile in list {
            for mapping in profile["modelMappings"].array { guard !mapping["from"].string.trimmed.isEmpty, !mapping["to"].string.trimmed.isEmpty else { throw AdminError.invalidInput } }
            if !profile["quota"].isNull {
                let quota = profile["quota"]
                guard ["requests", "totalTokens", "cost"].contains(where: { !quota[$0].isNull }) else { throw AdminError.invalidInput }
                for key in ["requests", "totalTokens"] where !quota[key].isNull {
                    guard case .number(let number) = quota[key], number > 0, number.rounded() == number else { throw AdminError.invalidInput }
                }
                if !quota["cost"].isNull { guard let amount = Decimal(string: quota["cost"].string, locale: Locale(identifier: "en_US_POSIX")), amount >= 0 else { throw AdminError.invalidInput } }
                if quota["period"]["type"].string == "past_duration" { guard quota["period"]["pastDuration"]["value"].number > 0 else { throw AdminError.invalidInput } }
            }
        }
    }
}

private struct NativeUsageTitle: ViewModifier {
    let embedded: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if embedded { content }
        else { content.navigationTitle("Token 与额度用量") }
    }
}

struct NativeAPIKeyUsageView: View {
    @ObservedObject var session: AdminSession
    let id: String
    var active = true
    var embedded = false
    var inline = false
    @State private var stats: JSON = .null
    @State private var quotas: [JSON] = []
    @State private var loading = false
    @State private var loadError: String?
    var body: some View {
        Group {
            if inline { fields }
            else { List { fields } }
        }
        .modifier(NativeUsageTitle(embedded: embedded || inline))
        .task(id: active) { if active && stats.isNull { await loadUsage() } }
        .refreshable { if active { await loadUsage() } }
        .onChange(of: session.invalidated) { invalid in
            if invalid { stats = .null; quotas = []; loading = false; loadError = nil }
        }
    }
    @ViewBuilder private var fields: some View {
        NativeProfileFieldGroup(title: "Token 用量", embedded: inline) {
            if loading { ProgressView("正在读取服务器数据") }
            if !stats.isNull {
                Chart(["inputTokens", "outputTokens", "cachedTokens", "reasoningTokens"], id: \.self) { key in
                    BarMark(x: .value("Type", NativeAdminLabels.field(key)), y: .value("Tokens", stats[key].number)).foregroundStyle(by: .value("Type", NativeAdminLabels.field(key)))
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine(); AxisTick()
                        AxisValueLabel { if let number = value.as(Double.self) { Text(DisplayFormat.compact(number)) } }
                    }
                }.frame(height: 220)
                ForEach(["inputTokens", "outputTokens", "cachedTokens", "reasoningTokens"], id: \.self) { key in
                    LabeledContent(NativeAdminLabels.field(key), value: ManagementFormat.number(stats[key])).monospacedDigit()
                }
            }
            if let loadError { ObservabilityErrorView(message: loadError) }
            if loadError != nil || (stats.isNull && !loading && active) {
                Button("重试读取用量") { Task { await loadUsage() } }
                    .frame(minHeight: 44).disabled(loading || !active || session.busy || session.invalidated)
            }
        }
        ForEach(Array(quotas.enumerated()), id: \.offset) { _, quota in
            NativeProfileFieldGroup(title: LocalizedStringKey(quota["profileName"].string), embedded: inline) {
                ForEach(["requests", "totalTokens", "cost"], id: \.self) { key in
                    if !quota["quota"][key].isNull {
                        let usageKey = key == "requests" ? "requestCount" : key == "cost" ? "totalCost" : "totalTokens"
                        let limit = Double(quota["quota"][key].string) ?? quota["quota"][key].number
                        let used = Double(quota["usage"][usageKey].string) ?? quota["usage"][usageKey].number
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(NativeAdminLabels.field(key)); Spacer()
                                Text(key == "totalTokens" ? DisplayFormat.compact(used) + " / " + DisplayFormat.compact(limit) : key == "cost" ? ManagementFormat.cost(quota["usage"][usageKey]) + " / " + ManagementFormat.cost(quota["quota"][key]) : DisplayFormat.number(used) + " / " + DisplayFormat.number(limit)).monospacedDigit()
                            }
                            if limit > 0 { ProgressView(value: min(used, limit), total: limit).tint(used >= limit ? .orange : .accentColor) }
                        }.padding(.vertical, 5)
                    }
                }
                DisclosureGroup("详细信息") { NativeDetailFieldsView(store: session.store, value: quota) }
            }
        }
        if !inline, let error = session.error, error != loadError { ObservabilityErrorView(message: error) }
    }
    @MainActor private func loadUsage() async {
        guard active, !loading, !session.invalidated else { return }
        loading = true; loadError = nil
        defer { loading = false }
        do {
            let response = try await session.read("apiKeyTokenUsageStats", variables: .object(["input": .object(["apiKeyIds": .array([.string(id)])])]))
            let nextQuotas = try await session.read("apiKeyQuotaUsages", variables: .object(["apiKeyId": .string(id)])).array
            try session.validate()
            stats = response.array.first ?? response; quotas = nextQuotas
        } catch is CancellationError { }
        catch {
            guard !session.invalidated else { return }
            loadError = error.localizedDescription
        }
    }
}
