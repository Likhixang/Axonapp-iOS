import SwiftUI

extension AxonClient {
    func channelTemplates(after: String? = nil) async throws -> JSON {
        let query = """
        query ChannelTemplates($after: Cursor) { channelOverrideTemplates(first: 100, after: $after) { edges { node { id name description headerOverrideOperations { op path from to value condition match { path eq } index splat } bodyOverrideOperations { op path from to value condition match { path eq } index splat } } } pageInfo { hasNextPage endCursor } } }
        """
        var vars: [String: Any] = [:]; if let after = after { vars["after"] = after }
        return try await graphql(query: query, variables: vars)["channelOverrideTemplates"]
    }
    func createChannelTemplate(_ input: JSON) async throws -> String {
        let mutation = """
        mutation ChannelTemplateCreate($input: CreateChannelOverrideTemplateInput!) { createChannelOverrideTemplate(input: $input) { id } }
        """
        let result = try await graphql(query: mutation, variables: ["input": input.foundationObject()])["createChannelOverrideTemplate"]["id"].string
        guard !result.isEmpty else { throw ManagementError.verification }; return result
    }
    func editChannelTemplate(id: String, input: JSON) async throws {
        let mutation = """
        mutation ChannelTemplateEdit($id: ID!, $input: UpdateChannelOverrideTemplateInput!) { updateChannelOverrideTemplate(id: $id, input: $input) { id } }
        """
        let result = try await graphql(query: mutation, variables: ["id": id, "input": input.foundationObject()])
        guard result["updateChannelOverrideTemplate"]["id"].string == id else { throw ManagementError.verification }
    }
    func deleteChannelTemplate(id: String) async throws {
        let mutation = """
        mutation ChannelTemplateDelete($id: ID!) { deleteChannelOverrideTemplate(id: $id) }
        """
        guard try await graphql(query: mutation, variables: ["id": id])["deleteChannelOverrideTemplate"].bool else { throw ManagementError.verification }
    }
    func applyChannelTemplate(id: String, ids: [String], mode: String) async throws -> JSON {
        let mutation = """
        mutation ChannelTemplateApply($input: ApplyChannelOverrideTemplateInput!) { applyChannelOverrideTemplate(input: $input) { success updated channels { id } } }
        """
        return try await graphql(query: mutation, variables: ["input": ["templateID": id, "channelIDs": ids, "mode": mode]])["applyChannelOverrideTemplate"]
    }
    func clearChannelTemplates(ids: [String]) async throws -> JSON {
        let mutation = """
        mutation ChannelTemplateClear($input: ClearChannelOverrideTemplatesInput!) { clearChannelOverrideTemplates(input: $input) { success updated channels { id } } }
        """
        return try await graphql(query: mutation, variables: ["input": ["channelIDs": ids]])["clearChannelOverrideTemplates"]
    }
    func allChannelTemplates() async throws -> [JSON] {
        var after: String?, cursors = Set<String>(), records: [JSON] = []
        repeat {
            let page = try await channelTemplates(after: after)
            guard case .array = page["edges"], case .bool = page["pageInfo"]["hasNextPage"] else { throw AxonAPIError.invalidResponse }
            records += page["edges"].array.map { $0["node"] }
            if !page["pageInfo"]["hasNextPage"].bool { return records }
            let next = page["pageInfo"]["endCursor"].string
            guard !next.isEmpty, cursors.insert(next).inserted else { throw AxonAPIError.invalidResponse }; after = next
        } while true
    }
}

/// Secrets may occur in arbitrary override values. No unprotected JSON presentation.
struct ChannelTemplatesView: View {
    @ObservedObject var store: AxonStore
    let target: ManagementTarget
    @State private var records: [JSON] = []
    @State private var selection = Set<String>()
    @State private var input: JSON = .object(["name": .string("")])
    @State private var selectedID = ""
    @State private var mode = "MERGE"
    @State private var authorized = false
    @State private var busy = false
    @State private var confirmation = false
    @State private var uncertain = false
    @State private var pending = "read"
    @State private var message: String?
    var body: some View {
        Form {
            Text(target.instance.name)
            if !authorized {
                Text("模板可能包含凭据，读取后仅在受保护字段中显示。").font(.caption)
                Button("读取模板") { pending = "read"; confirmation = true }
            } else {
                Section("模板") {
                    Picker("模板", selection: $selectedID) {
                        Text("新增模板").tag("")
                        ForEach(records, id: \.idString) { Text($0["name"].string).tag($0["id"].string) }
                    }.pickerStyle(.menu).onChange(of: selectedID) { id in
                        guard let row = records.first(where: { $0["id"].string == id }) else { input = .object(["name": .string("")]); return }
                        input = .object(row.object.filter { ChannelInputSchema.fields["CreateChannelOverrideTemplateInput"]?[$0.key] != nil })
                    }
                    NavigationLink("编辑模板") { Form { ChannelSchemaFields(value: $input, type: "CreateChannelOverrideTemplateInput", path: "template", secure: true) } }
                    Button(selectedID.isEmpty ? "创建模板" : "保存模板") { pending = "save"; confirmation = true }.disabled(uncertain)
                    Button("删除模板", role: .destructive) { pending = "delete"; confirmation = true }.disabled(selectedID.isEmpty || uncertain)
                }
                Section("应用到渠道") {
                    ForEach(store.snapshot.channels) { row in
                        Toggle(row.name, isOn: Binding(get: { selection.contains(row.id) }, set: { if $0 { selection.insert(row.id) } else { selection.remove(row.id) } }))
                    }
                    Picker("模式", selection: $mode) { Text("合并").tag("MERGE"); Text("替换").tag("REPLACE") }.pickerStyle(.menu)
                    Text("替换会清除现有覆盖项；合并保留不冲突的项。").font(.caption)
                    Button("应用模板") { pending = "apply"; confirmation = true }.disabled(selectedID.isEmpty || selection.isEmpty || uncertain)
                    Button("清空覆盖项", role: .destructive) { pending = "clear"; confirmation = true }.disabled(selection.isEmpty || uncertain)
                }
            }
            if let message = message { Text(message).font(.caption) }
        }.navigationTitle("渠道覆盖模板").disabled(busy || store.managementBusy)
        .alert("确认敏感操作", isPresented: $confirmation) {
            Button("授权并执行", role: pending == "delete" || pending == "clear" ? .destructive : nil) { execute() }
            Button("取消", role: .cancel) { }
        } message: { Text("\(target.instance.name) · \(target.instance.address)\n\(pendingTitle)") }
        .onDisappear { input = .object([:]); records = [] }
    }
    private var pendingTitle: String {
        switch pending {
        case "read": return obsText("读取模板")
        case "save": return obsText("保存模板")
        case "delete": return obsText("删除模板")
        case "apply": return obsText("应用模板")
        case "clear": return obsText("清空覆盖项")
        default: return obsText("操作")
        }
    }
    private func execute() {
        busy = true
        Task { defer { busy = false }
            var started = false
            do {
                let cli = try store.beginManagement(target); defer { store.endManagement() }
                if pending == "read" { records = try await cli.allChannelTemplates(); try store.validateTarget(target); authorized = true; return }
                if pending == "save" {
                    let submitted = input
                    try ChannelInputSchema.validate(submitted, type: "CreateChannelOverrideTemplateInput!")
                    guard !input["name"].string.trimmed.isEmpty else { throw ManagementError.invalidFields }
                    if !selectedID.isEmpty {
                        let fresh = try await cli.allChannelTemplates()
                        guard fresh.first(where: { $0["id"].string == selectedID }) == records.first(where: { $0["id"].string == selectedID }) else { throw ManagementError.changedTarget }
                    }
                    try store.validateTarget(target); started = true
                    let savedID: String
                    if selectedID.isEmpty { savedID = try await cli.createChannelTemplate(submitted) }
                    else { try await cli.editChannelTemplate(id: selectedID, input: submitted); savedID = selectedID }
                    records = try await cli.allChannelTemplates()
                    guard let saved = records.first(where: { $0["id"].string == savedID }), AxonStore.matches(saved, expected: submitted) else { throw ManagementError.verification }
                    selectedID = savedID; input = submitted
                } else if pending == "delete" {
                    started = true; try await cli.deleteChannelTemplate(id: selectedID)
                    records = try await cli.allChannelTemplates()
                    guard !records.contains(where: { $0["id"].string == selectedID }) else { throw ManagementError.verification }
                    selectedID = ""; input = .object(["name": .string("")])
                } else {
                    let ids = selection.sorted()
                    var expected: [String: JSON] = [:]
                    let template = records.first(where: { $0["id"].string == selectedID }) ?? .object([:])
                    for id in ids {
                        try store.validateTarget(target)
                        let saved = try await cli.channelSecrets(id: id)
                        var s = saved["settings"].object
                        for key in ["headerOverrideOperations", "bodyOverrideOperations"] {
                            if pending == "clear" { s[key] = .array([]) }
                            else if mode == "REPLACE" { s[key] = .array(template[key].array) }
                            else { s[key] = .array(Self.merge(s[key]?.array ?? [], template: template[key].array, header: key.hasPrefix("header"))) }
                        }
                        expected[id] = .object(s)
                    }
                    try store.validateTarget(target); started = true
                    let result = pending == "clear" ? try await cli.clearChannelTemplates(ids: ids) : try await cli.applyChannelTemplate(id: selectedID, ids: ids, mode: mode)
                    guard result["success"].bool, result["updated"].int == ids.count else { throw ManagementError.verification }
                    for id in ids {
                        let saved = try await cli.channelSecrets(id: id)
                        guard let expected = expected[id], AxonStore.matches(saved["settings"], expected: expected) else { throw ManagementError.verification }
                        try store.validateTarget(target)
                    }
                }
                try store.validateTarget(target); message = obsText("已保存")
            } catch { uncertain = started; message = error.localizedDescription }
        }
    }
    /// Matches official Go MergeOverrideOperations and MergeOverrideHeaders ordering.
    static func merge(_ existing: [JSON], template: [JSON], header: Bool) -> [JSON] {
        func replacing(_ o: JSON) -> Bool { header ? o["op"].string == "set" : ["set", "set_if_absent", "delete"].contains(o["op"].string) }
        func path(_ o: JSON) -> String { header ? o["path"].string.lowercased() : o["path"].string }
        let groups = Dictionary(grouping: template.filter(replacing), by: path)
        if header {
            var result = existing
            for op in template {
                if ["rename", "copy"].contains(op["op"].string) { result.append(op); continue }
                if let index = result.firstIndex(where: { ["set", "delete"].contains($0["op"].string) && path($0) == path(op) }) { result[index] = op }
                else { result.append(op) }
            }
            return result
        }
        var result: [JSON] = [], emitted = Set<String>()
        for op in existing {
            if replacing(op), let replacements = groups[path(op)] {
                if emitted.insert(path(op)).inserted { result += replacements }
            } else { result.append(op) }
        }
        result += template.filter { !replacing($0) || !emitted.contains(path($0)) }
        return result
    }
}
private extension JSON { var idString: String { self["id"].string } }
