import SwiftUI
import Charts

struct NativeProfilesView: View {
    @ObservedObject var session: AdminSession
    let entity: String
    let id: String
    @State private var baseline: JSON = .null
    @State private var profiles: JSON = .object([:])
    @State private var loaded = false
    @State private var uncertain = false
    @State private var selectedTemplate: String = ""
    @State private var templates: [JSON] = []
    @State private var confirmRemoval: Int?
    @State private var showRemoval = false
    private var isKey: Bool { entity == "APIKey" }
    var body: some View {
        Form {
            if !loaded { ProgressView("正在读取服务器数据") }
            else {
                Section("当前策略") {
                    Picker("启用的 Profile", selection: string("activeProfile")) {
                        ForEach(Array(profiles["profiles"].array.enumerated()), id: \.offset) { _, profile in Text(profile["name"].string).tag(profile["name"].string) }
                    }
                    Button("新增 Profile") {
                        var list = profiles["profiles"].array
                        var index = list.count + 1
                        while list.contains(where: { $0["name"].string == "Profile \(index)" }) { index += 1 }
                        list.append(.object(["name": .string("Profile \(index)"), "channelIDs": .array([]), "channelTags": .array([]), "channelTagsMatchMode": .string("any"), "modelMappings": .array([]), "modelIDs": .array([]), "loadBalanceStrategy": .string("default"), "traceStickyMode": .string("default")]))
                        replaceList(list)
                    }
                }
                ForEach(Array(profiles["profiles"].array.indices), id: \.self) { index in
                    Section {
                        NavigationLink {
                            NativeProfileEditor(session: session, profile: profileBinding(index), isKey: isKey, renamed: { old, new in
                                if profiles["activeProfile"].string == old { var p = profiles.object; p["activeProfile"] = .string(new); profiles = .object(p) }
                            })
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(profiles["profiles"].array[index]["name"].string).font(.headline)
                                    if profiles["activeProfile"].string == profiles["profiles"].array[index]["name"].string { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                                }
                                Text(profiles["profiles"].array[index]["quota"].isNull ? obsText("不限额度") : obsText("已设置额度限制")).font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 5)
                        }
                        if profiles["profiles"].array.count > 1 {
                            Button("移除 Profile", role: .destructive) { confirmRemoval = index; showRemoval = true }
                        }
                    }
                }
                if isKey {
                    Section("策略模板") {
                        Picker("模板", selection: $selectedTemplate) {
                            Text("选择模板").tag("")
                            ForEach(templates, id: \.self) { Text($0["name"].string).tag($0["id"].string) }
                        }
                        Button("载入模板") { loadTemplate() }.disabled(selectedTemplate.isEmpty)
                        Text("载入模板会立即更新服务端策略，请先保存当前修改。").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if let error = session.error { ObservabilityErrorView(message: error) }
            if uncertain { Text("写入可能已经完成。请关闭编辑器并刷新核对，勿重复提交。").foregroundStyle(.orange) }
        }
        .navigationTitle("配置 Profiles")
        .disabled(session.busy || session.invalidated || uncertain)
        .toolbar { Button("保存") { save() }.disabled(!loaded || uncertain) }
        .task { if !loaded { await load() } }
        .confirmationDialog("移除 Profile", isPresented: $showRemoval, titleVisibility: .visible) {
            Button("移除", role: .destructive) {
                guard let index = confirmRemoval, profiles["profiles"].array.indices.contains(index) else { return }
                var list = profiles["profiles"].array; list.remove(at: index); replaceList(list)
            }
        }
    }
    private func string(_ key: String) -> Binding<String> { Binding(get: { profiles[key].string }, set: { var p = profiles.object; p[key] = .string($0); profiles = .object(p) }) }
    private func profileBinding(_ index: Int) -> Binding<JSON> { Binding(get: { profiles["profiles"].array.indices.contains(index) ? profiles["profiles"].array[index] : .null }, set: { var list = profiles["profiles"].array; guard list.indices.contains(index) else { return }; list[index] = $0; replaceList(list) }) }
    private func replaceList(_ list: [JSON]) {
        var p = profiles.object
        p["profiles"] = .array(list)
        if !list.contains(where: { $0["name"].string == p["activeProfile"]?.string }) { p["activeProfile"] = list.first?["name"] ?? .string("") }
        profiles = .object(p)
    }
    @MainActor private func load() async {
        do {
            baseline = try await session.detail(entity, id: id)
            guard !baseline.isNull else { throw AdminError.notFound }
            profiles = session.schema.project(baseline["profiles"], type: isKey ? "UpdateAPIKeyProfilesInput" : "UpdateProjectProfilesInput")
            loaded = true
            if isKey {
                let value = try await session.read("apiKeyProfileTemplates", variables: .object(["first": .number(100), "where": .object(["projectID": baseline["projectID"]])]))
                templates = value["edges"].array.map { $0["node"] }
            }
        } catch { session.error = error.localizedDescription }
    }
    private func save() {
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
        session.start {
            let operation = try session.schema.operation("loadApiKeyProfileTemplate")
            _ = try await session.execute(operation, variables: .object(["input": .object(["apiKeyID": .string(id), "templateID": .string(selectedTemplate)])]), baseline: baseline)
            await load()
        }
    }
}

struct NativeProfileEditor: View {
    @ObservedObject var session: AdminSession
    @Binding var profile: JSON
    let isKey: Bool
    var renamed: (String, String) -> Void = { _, _ in }
    @State private var channels: [ChannelItem] = []
    @State private var models: [String] = []
    var body: some View {
        Form {
            Section("基本信息") {
                TextField("Profile 名称", text: Binding(get: { profile["name"].string }, set: { new in let old = profile["name"].string; set("name", .string(new)); renamed(old, new) }))
                if !profile["templateName"].string.isEmpty {
                    LabeledContent("关联模板", value: profile["templateName"].string)
                    Button("解除模板关联") { remove("templateID"); remove("templateName") }
                }
            }
            Section("渠道限制") {
                NavigationLink {
                    List {
                        ForEach(channels) { channel in
                            if let numeric = ChannelModelToolsView.channelNumericID(channel.id) {
                                Toggle(channel.name, isOn: membership(.number(Double(numeric)), key: "channelIDs"))
                            }
                        }
                    }.navigationTitle("选择渠道")
                } label: { selectionSummary("允许的渠道", count: profile["channelIDs"].array.count) }
                NativeStringListField(title: "渠道标签", values: list("channelTags"))
                Picker("标签匹配方式", selection: string("channelTagsMatchMode", fallback: "any")) {
                    Text("任一标签").tag("any"); Text("全部标签").tag("all"); Text("排除标签").tag("none")
                }
                Text("未选择渠道或标签表示不增加对应限制。").font(.caption).foregroundStyle(.secondary)
            }
            if isKey {
                Section("模型权限与映射") {
                    NavigationLink {
                        NativeModelSelectionView(available: models, selected: Binding(get: { profile["modelIDs"].array.map(\.string) }, set: { set("modelIDs", .array($0.map(JSON.string))) }))
                    } label: { selectionSummary("允许的模型", count: profile["modelIDs"].array.count) }
                    NativeMappingsField(value: json("modelMappings"), models: models)
                }
                Section("路由策略") {
                    Picker("负载均衡", selection: string("loadBalanceStrategy", fallback: "default")) {
                        ForEach(["default", "adaptive", "failover", "circuit-breaker", "round-robin"], id: \.self) { Text(NativeAdminLabels.value($0)).tag($0) }
                    }
                    Picker("追踪粘性", selection: string("traceStickyMode", fallback: "default")) {
                        ForEach(["default", "disabled", "prefer_previous_channel"], id: \.self) { Text(NativeAdminLabels.value($0)).tag($0) }
                    }
                }
                Section("额度限制") {
                    Toggle("启用额度限制", isOn: Binding(get: { !profile["quota"].isNull }, set: { enabled in
                        if enabled { set("quota", .object(["period": .object(["type": .string("all_time")])])) }
                        else { remove("quota") }
                    }))
                    if !profile["quota"].isNull { NativeQuotaFields(quota: json("quota")) }
                }
            }
            if let error = session.error { ObservabilityErrorView(message: error) }
        }.navigationTitle("策略配置")
        .task {
            guard channels.isEmpty && models.isEmpty else { return }
            do {
                try session.validate()
                channels = session.store.snapshot.channels
                models = Array(Set(session.store.snapshot.models.map(\.modelID) + channels.flatMap(\.supportedModels))).sorted()
            } catch { session.error = error.localizedDescription }
        }
    }
    private func selectionSummary(_ title: LocalizedStringKey, count: Int) -> some View { HStack { Text(title); Spacer(); Text(count == 0 ? obsText("不限制") : String(count)).foregroundStyle(.secondary) } }
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
        }
        if quota["period"]["type"].string == "past_duration" {
            TextField("窗口长度", text: Binding(get: { String(quota["period"]["pastDuration"]["value"].int) }, set: { setPeriod("pastDuration", "value", Int($0).map { .number(Double($0)) } ?? .string($0)) })).keyboardType(.numberPad)
            Picker("单位", selection: periodString("pastDuration", "unit")) {
                Text("分钟").tag("minute"); Text("小时").tag("hour"); Text("天").tag("day")
            }
        }
        if quota["period"]["type"].string == "calendar_duration" {
            Picker("单位", selection: periodString("calendarDuration", "unit")) { Text("天").tag("day"); Text("月").tag("month") }
        }
    }
    private func number(_ key: String, title: LocalizedStringKey, integer: Bool) -> some View {
        TextField(title, text: Binding(get: {
            if quota[key].isNull { return "" }; if !quota[key].string.isEmpty { return quota[key].string }; return integer ? String(quota[key].int) : String(quota[key].number)
        }, set: { text in
            if text.isEmpty { var q = quota.object; q.removeValue(forKey: key); quota = .object(q) }
            else if integer { set(key, Int(text).map { .number(Double($0)) } ?? .string(text)) }
            else { set(key, .string(text)) }
        })).keyboardType(.decimalPad)
    }
    private func set(_ key: String, _ value: JSON) { var q = quota.object; q[key] = value; quota = .object(q) }
    private func setPeriod(_ kind: String, _ key: String, _ value: JSON) { var q = quota.object; var p = quota["period"].object; var d = quota["period"][kind].object; d[key] = value; p[kind] = .object(d); q["period"] = .object(p); quota = .object(q) }
    private func periodString(_ kind: String, _ key: String) -> Binding<String> { Binding(get: { quota["period"][kind][key].string }, set: { setPeriod(kind, key, .string($0)) }) }
}

struct NativeModelSelectionView: View {
    let available: [String]
    @Binding var selected: [String]
    @State private var search = ""
    @State private var manual = ""
    private var candidates: [String] { Array(Set(available + selected)).sorted().filter { search.isEmpty || $0.localizedCaseInsensitiveContains(search) } }
    var body: some View {
        List {
            Section {
                HStack {
                    Button("全选") { selected = Array(Set(selected + candidates)).sorted() }
                    Spacer()
                    Button("取消全选") { selected = selected.filter { !candidates.contains($0) } }
                }
                Text(String(format: obsText("已选择 %lld 个模型"), Int64(selected.count))).font(.caption).foregroundStyle(.secondary)
            }
            Section {
                ForEach(candidates, id: \.self) { model in
                    Button {
                        if selected.contains(model) { selected.removeAll { $0 == model } }
                        else { selected.append(model) }
                    } label: {
                        HStack { Text(model).foregroundStyle(.primary); Spacer(); Image(systemName: selected.contains(model) ? "checkmark.circle.fill" : "circle").foregroundStyle(selected.contains(model) ? Color.accentColor : .secondary) }.frame(minHeight: 44)
                    }.buttonStyle(.plain)
                }
            }
            Section("手动添加") {
                TextField("模型 ID", text: $manual).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("添加") { selected = Array(Set(selected + manual.lines)).sorted(); manual = "" }.disabled(manual.trimmed.isEmpty)
            }
        }.searchable(text: $search, prompt: obsText("搜索模型"))
            .navigationTitle("选择模型")
    }
}

struct NativeMappingsField: View {
    @Binding var value: JSON
    let models: [String]
    var body: some View {
        ForEach(Array(value.array.indices), id: \.self) { index in
            HStack {
                TextField("请求模型", text: field(index, "from"))
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                TextField("实际模型", text: field(index, "to"))
                Button(role: .destructive) { var items = value.array; items.remove(at: index); value = .array(items) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
            }.textInputAutocapitalization(.never).autocorrectionDisabled()
        }
        Button("添加模型映射") { value = .array(value.array + [.object(["from": .string(""), "to": .string("")])]) }
    }
    private func field(_ index: Int, _ key: String) -> Binding<String> { Binding(get: { value.array.indices.contains(index) ? value.array[index][key].string : "" }, set: { text in var items = value.array; guard items.indices.contains(index) else { return }; var p = items[index].object; p[key] = .string(text); items[index] = .object(p); value = .array(items) }) }
}

struct NativeStringListField: View {
    let title: LocalizedStringKey
    @Binding var values: [String]
    @State private var text = ""
    var body: some View {
        TextField(title, text: $text, axis: .vertical)
            .textInputAutocapitalization(.never).autocorrectionDisabled()
            .onAppear { text = values.joined(separator: "\n") }
            .onChange(of: text) { values = $0.lines }
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

struct NativeAPIKeyUsageView: View {
    @ObservedObject var session: AdminSession
    let id: String
    @State private var stats: JSON = .null
    @State private var quotas: [JSON] = []
    var body: some View {
        List {
            Section("Token 用量") {
                if stats.isNull { ProgressView() }
                else {
                    Chart(["inputTokens", "outputTokens", "cachedTokens", "reasoningTokens"], id: \.self) { key in
                        BarMark(x: .value("Type", NativeAdminLabels.field(key)), y: .value("Tokens", stats[key].number)).foregroundStyle(by: .value("Type", NativeAdminLabels.field(key)))
                    }
                    .chartYAxis {
                        AxisMarks { value in
                            AxisGridLine(); AxisTick()
                            AxisValueLabel { if let number = value.as(Double.self) { Text(DisplayFormat.compact(number)) } }
                        }
                    }.frame(height: 220)
                    ForEach(["inputTokens", "outputTokens", "cachedTokens", "reasoningTokens"], id: \.self) { key in LabeledContent(NativeAdminLabels.field(key), value: ManagementFormat.number(stats[key])) }
                }
            }
            ForEach(Array(quotas.enumerated()), id: \.offset) { _, quota in
                Section(quota["profileName"].string) {
                    ForEach(["requests", "totalTokens", "cost"], id: \.self) { key in
                        if !quota["quota"][key].isNull {
                            let usageKey = key == "requests" ? "requestCount" : key == "cost" ? "totalCost" : "totalTokens"
                            let limit = Double(quota["quota"][key].string) ?? quota["quota"][key].number
                            let used = Double(quota["usage"][usageKey].string) ?? quota["usage"][usageKey].number
                            VStack(alignment: .leading, spacing: 8) {
                                HStack { Text(NativeAdminLabels.field(key)); Spacer(); Text(key == "totalTokens" ? DisplayFormat.compact(used) + " / " + DisplayFormat.compact(limit) : DisplayFormat.number(used) + " / " + DisplayFormat.number(limit)).monospacedDigit() }
                                if limit > 0 { ProgressView(value: min(used, limit), total: limit).tint(used >= limit ? .orange : .accentColor) }
                            }.padding(.vertical, 5)
                        }
                    }
                    DisclosureGroup("详细信息") { NativeDetailFieldsView(store: session.store, value: quota) }
                }
            }
            if let error = session.error { ObservabilityErrorView(message: error) }
        }.navigationTitle("Token 与额度用量")
        .task { session.start {
            let response = try await session.read("apiKeyTokenUsageStats", variables: .object(["input": .object(["apiKeyIds": .array([.string(id)])])]))
            stats = response.array.first ?? response
            quotas = try await session.read("apiKeyQuotaUsages", variables: .object(["apiKeyId": .string(id)])).array
        } }
    }
}
