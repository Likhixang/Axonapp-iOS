import SwiftUI

/// A native operation center; selection and target are captured before confirmation.
struct ChannelModelToolsView: View {
    @ObservedObject var store: AxonStore
    let target: ManagementTarget
    @State private var selection = Set<String>()
    @State private var action = ManagedBatchAction.enable
    @State private var confirmation = false
    @State private var busy = false
    @State private var uncertain = false
    @State private var capturedIDs: [String] = []
    @State private var message: String?
    @State private var importMode = "models"
    @State private var input: JSON = .array([])
    @State private var catalog: JSON = .object([:])
    @State private var unassociated: JSON = .array([])
    private var channel: Bool { target.kind == .channel }
    var body: some View {
        Form {
            Section("目标") { Text(target.instance.name); Text(target.instance.address).font(.caption) }
            Section("批量选择") {
                if channel {
                    ForEach(store.snapshot.channels) { c in selectionRow(c.id, name: c.name + " · " + NativeAdminLabels.value(c.status)) }
                } else {
                    ForEach(store.snapshot.models) { m in selectionRow(m.id, name: m.name + " · " + NativeAdminLabels.value(m.status)) }
                }
                Button("全选") { selection = Set(channel ? store.snapshot.channels.map(\.id) : store.snapshot.models.map(\.id)) }
                Button("清空选择") { selection.removeAll() }
                Picker("操作", selection: $action) {
                    ForEach(ManagedBatchAction.allCases.filter { channel || ![.recover, .sync, .test].contains($0) }) { Text(NativeAdminLabels.value($0.rawValue)).tag($0) }
                }.pickerStyle(.menu)
                Button("确认批量操作", role: action == .delete ? .destructive : nil) { capturedIDs = selection.sorted(); confirmation = true }.disabled(selection.isEmpty || uncertain)
            }
            if channel {
                Section("导入与排序") {
                    NavigationLink("渠道覆盖模板") { ChannelTemplatesView(store: store, target: target) }
                    Picker("操作", selection: $importMode) {
                        Text("导入渠道").tag("import"); Text("按密钥创建渠道").tag("create"); Text("排序权重").tag("ordering")
                    }.pickerStyle(.menu).onChange(of: importMode) { mode in
                        input = ChannelInputSchema.seed(mode == "create" ? "BulkCreateChannelsInput" : mode == "ordering" ? "BulkUpdateChannelOrderingInput" : "BulkImportChannelsInput")
                    }
                    NavigationLink("编辑批量配置") { Form { ChannelSchemaFields(value: $input, type: importType, path: "input", secure: importMode != "ordering") } }
                    Button("提交") { capturedIDs = []; confirmation = true }.disabled(uncertain)
                }
            } else {
                Section("模型目录") {
                    Button("载入模型目录") { readCatalog(refresh: false) }
                    Button("刷新模型目录") { readCatalog(refresh: true) }
                    if !catalog.isNull {
                        ForEach(catalog["data"]["providers"].object.keys.sorted(), id: \.self) { developer in
                            NavigationLink(developer) {
                                List {
                                    ForEach(Array(catalog["data"]["providers"][developer]["models"].array.enumerated()), id: \.offset) { _, model in
                                        Button(model["id"].string) {
                                            input = .array(input.array + [Self.catalogInput(model, developer: developer)])
                                        }
                                    }
                                }.navigationTitle(developer)
                            }
                        }
                    }
                    Button("查找未关联模型") {
                        read { cli in unassociated = try await cli.unassociatedChannels() }
                    }
                    ForEach(Array(unassociated.array.enumerated()), id: \.offset) { _, row in
                        NavigationLink(row["channel"]["name"].string) {
                            List { ForEach(row["models"].array.map(\.string), id: \.self) { model in
                                Button(model) {
                                    var draft = ModelDraft(); draft.modelID = model; draft.name = model; draft.developer = "custom"; draft.group = "custom"; draft.icon = "OpenAI"
                                    draft.associationsJSON = JSON.array([.object(["type": .string("channel_model"), "channelModel": .object(["channelId": .number(Double(Self.channelNumericID(row["channel"]["id"].string) ?? 0)), "modelId": .string(model)])])]).prettyJSON
                                    do { input = .array(input.array + [.object(try draft.payload())]) } catch { message = error.localizedDescription }
                                }
                            } }
                        }
                    }
                    NavigationLink("编辑模型配置") { Form { ChannelSchemaFields(value: $input, type: "[CreateModelInput!]", path: "models") } }
                    Text(String(format: obsText("已选择 %lld 个模型"), Int64(input.array.count))).font(.caption)
                    Button("导入模型") { capturedIDs = []; confirmation = true }.disabled(input.array.isEmpty || uncertain)
                }
            }
            if uncertain { Text("写入可能已完成，请刷新后再试。").foregroundStyle(.orange) }
            if let message = message { Text(message).font(.caption) }
        }.disabled(busy || store.managementBusy).navigationTitle(channel ? "渠道操作" : "模型操作")
        .onAppear {
            if let id = target.entityID { selection = [id]; action = .archive }
            if channel { importMode = "import"; input = ChannelInputSchema.seed("BulkImportChannelsInput") }
        }
        .alert("确认执行操作", isPresented: $confirmation) {
            Button("执行", role: action == .delete && !capturedIDs.isEmpty ? .destructive : nil) { execute() }
            Button("取消", role: .cancel) { }
        } message: { Text("\(target.instance.name) · \(target.instance.address)\n\(capturedIDs.isEmpty ? obsText("批量输入") : NativeAdminLabels.value(action.rawValue) + ": " + capturedNames.joined(separator: ", "))") }
    }
    private var capturedNames: [String] {
        capturedIDs.map { id in
            if channel { return store.snapshot.channels.first { $0.id == id }?.name ?? obsText("已选渠道") }
            return store.snapshot.models.first { $0.id == id }?.name ?? obsText("已选模型")
        }
    }
    private var importType: String { importMode == "create" ? "BulkCreateChannelsInput" : importMode == "ordering" ? "BulkUpdateChannelOrderingInput" : "BulkImportChannelsInput" }
    private func selectionRow(_ id: String, name: String) -> some View {
        Toggle(name, isOn: Binding(get: { selection.contains(id) }, set: { if $0 { selection.insert(id) } else { selection.remove(id) } }))
    }
    private func read(_ operation: @escaping (AxonClient) async throws -> Void) {
        busy = true; Task { defer { busy = false }; do { try await operation(store.managementClient(target)); try store.validateTarget(target) } catch { message = error.localizedDescription } }
    }
    private func readCatalog(refresh: Bool) {
        read { cli in
            if refresh {
                _ = try await cli.refreshProvidersCatalog()
                try store.validateTarget(target)
            }
            catalog = try await cli.providersCatalog() // always exact target readback
        }
    }
    private func execute() {
        busy = true
        Task { defer { busy = false }
            var started = false
            do {
                if !capturedIDs.isEmpty {
                    started = true
                    message = try await store.managedBatch(target, ids: capturedIDs, action: action)
                } else {
                    try ChannelInputSchema.validate(input, type: channel ? importType + "!" : "[CreateModelInput!]!")
                    let cli = try store.beginManagement(target); defer { store.endManagement() }
                    try store.validateTarget(target)
                    started = true
                    if channel {
                        let result: JSON
                        switch importMode {
                        case "create": result = try await cli.bulkCreateChannels(input: input)
                        case "ordering": result = try await cli.bulkUpdateChannelOrdering(input: input)
                        default: result = try await cli.bulkImportChannels(input: input)
                        }
                        let records = importMode == "create" ? result.array : result["channels"].array
                        for record in records {
                            try store.validateTarget(target)
                            guard let saved = try await cli.channelDetail(id: record["id"].string) else { throw ManagementError.verification }
                            if importMode == "ordering" { guard saved["orderingWeight"] == record["orderingWeight"] else { throw ManagementError.verification } }
                        }
                        if importMode == "ordering" { guard result["updated"].int == input["channels"].array.count else { throw ManagementError.verification } }
                        if importMode == "create" { guard records.count == input["apiKeys"].array.count else { throw ManagementError.verification } }
                        message = String(format: obsText("已处理：%lld · 失败：%lld"), Int64(records.count), Int64(result["failed"].int))
                    } else {
                        for model in input.array { try ChannelSemantics.modelSettings(model["settings"]); guard ModelDraft.validCard(model["modelCard"]) else { throw ManagementError.invalidFields } }
                        let submitted = JSON.array(input.array.map { model in var fields = model.object; fields["modelCard"] = ModelDraft.normalizedCard(model["modelCard"]); return .object(fields) })
                        let ids = try await cli.bulkCreateModels(inputs: submitted)
                        for (id, expected) in zip(ids, submitted.array) {
                            try store.validateTarget(target)
                            guard let saved = try await cli.modelDetail(id: id) else { throw ManagementError.verification }
                            try store.verify(saved, input: expected.object)
                        }
                        message = String(format: obsText("已保存 %lld 项"), Int64(ids.count))
                    }
                    try store.validateTarget(target); await store.refresh(); try store.validateTarget(target)
                }
            } catch { uncertain = started; message = error.localizedDescription }
        }
    }
    static func channelNumericID(_ id: String) -> Int? {
        if let number = Int(id) { return number }
        guard let decoded = Data(base64Encoded: id), let text = String(data: decoded, encoding: .utf8) else { return nil }
        return Int(text.split(separator: ":").last.map(String.init) ?? "")
    }
    static func catalogInput(_ model: JSON, developer: String) -> JSON {
        var d = ModelDraft()
        d.modelID = model["id"].string; d.name = model["display_name"].string.isEmpty ? model["name"].string : model["display_name"].string
        if d.name.isEmpty { d.name = d.modelID }
        d.developer = developer; d.icon = developer; d.group = model["family"].string.isEmpty ? developer : model["family"].string
        let type = model["type"].string.replacingOccurrences(of: "-", with: "_")
        d.type = ModelType(rawValue: type)?.rawValue ?? "chat"
        let card: JSON = .object([
            "reasoning": .object(["supported": .bool(model["reasoning"]["supported"].bool), "default": .bool(model["reasoning"]["default"].bool)]),
            "toolCall": .bool(model["tool_call"].bool), "temperature": .bool(model["temperature"].bool),
            "vision": .bool(model["vision"].isNull ? model["modalities"]["input"].array.contains(.string("image")) : model["vision"].bool),
            "modalities": .object(["input": .array(model["modalities"]["input"].array), "output": .array(model["modalities"]["output"].array)]),
            "cost": .object(["input": .number(model["cost"]["input"].number), "output": .number(model["cost"]["output"].number), "cacheRead": .number(model["cost"]["cache_read"].number), "cacheWrite": .number(model["cost"]["cache_write"].number)]),
            "limit": .object(["context": .number(model["limit"]["context"].number), "output": .number(model["limit"]["output"].number)]),
            "knowledge": .string(model["knowledge"].string), "releaseDate": .string(model["release_date"].string), "lastUpdated": .string(model["last_updated"].string)])
        d.modelCard = card.prettyJSON
        return .object(["name": .string(d.name), "modelID": .string(d.modelID), "developer": .string(d.developer), "group": .string(d.group), "icon": .string(d.icon), "type": .string(d.type), "modelCard": card, "settings": d.settings])
    }
}
