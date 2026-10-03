import SwiftUI

/// Use server catalogs for scopes and entity choices; never ask for opaque IDs.
struct NativeEntityInputFields: View {
    @ObservedObject var session: AdminSession
    let fields: [AdminField]
    @Binding var value: JSON
    @State private var profileExpanded = false
    var body: some View {
        ForEach(fields) { field in
            if field.name == "profile" && session.schema.base(field.type) == "APIKeyProfileInput" {
                DisclosureGroup("策略配置", isExpanded: Binding(get: { profileExpanded }, set: { expanded in
                    if expanded && value[field.name].isNull { set(field.name, .object(["name": .string("Default")])) }
                    profileExpanded = expanded
                })) {
                    NativeProfileEditor(session: session, profile: binding(field.name), isKey: true, embedded: true)
                }
            } else if ["scopes", "appendScopes"].contains(field.name) {
                DisclosureGroup(NativeAdminLabels.field(field.name)) {
                    NativeCatalogSelectionView(session: session, kind: "scopes", selected: binding(field.name), multiple: true, embedded: true)
                }
            } else if let kind = catalogKind(field.name) {
                DisclosureGroup {
                    NativeCatalogSelectionView(session: session, kind: kind, selected: binding(field.name), multiple: field.type.hasPrefix("["), embedded: true)
                } label: {
                    HStack { Text(NativeAdminLabels.field(field.name)); Spacer(); Text(value[field.name].isNull ? obsText("未选择") : obsText("已选择")).font(.caption).foregroundStyle(.secondary) }
                }
            } else if field.name == "allowedIps" {
                NativeStringListField(title: "IP / CIDR 白名单", values: Binding(get: { value[field.name].array.map(\.string) }, set: { set(field.name, .array($0.map(JSON.string))) }))
            } else {
                AdminSchemaForm(schema: session.schema, fields: [field], value: $value)
            }
        }
    }
    private func catalogKind(_ key: String) -> String? {
        if ["userId", "userID", "userIDs", "addUserIDs", "removeUserIDs"].contains(key) { return "users" }
        if ["roleIDs", "addRoleIDs", "removeRoleIDs"].contains(key) { return "roles" }
        if ["projectID", "projectId", "projectIDs", "addProjectIDs", "removeProjectIDs"].contains(key) { return "projects" }
        return nil
    }
    private func binding(_ key: String) -> Binding<JSON> { Binding(get: { value[key] }, set: { set(key, $0) }) }
    private func set(_ key: String, _ new: JSON) { var fields = value.object; fields[key] = new; value = .object(fields) }
}

struct NativeCatalogSelectionView: View {
    @ObservedObject var session: AdminSession
    let kind: String
    @Binding var selected: JSON
    let multiple: Bool
    var embedded = false
    @State private var rows: [JSON] = []
    @State private var search = ""
    @State private var failure: String?
    @State private var loading = false
    @State private var cursor: String?
    private var filtered: [JSON] { rows.filter { search.isEmpty || AdminOperationView.label($0).localizedCaseInsensitiveContains(search) || $0["scope"].string.localizedCaseInsensitiveContains(search) } }
    var body: some View {
        Group {
            if embedded {
                TextField("搜索名称", text: $search).textInputAutocapitalization(.never).autocorrectionDisabled()
                if loading && rows.isEmpty { ProgressView("正在读取服务器数据") }
                if let failure = failure { ObservabilityErrorView(message: failure) }
                if !filtered.isEmpty {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) { selectionRows }
                    }.frame(height: min(CGFloat(filtered.count) * 60, 260))
                }
                selectionActions
            } else {
                List {
                    if loading && rows.isEmpty { ProgressView("正在读取服务器数据") }
                    if let failure = failure { ObservabilityErrorView(message: failure) }
                    selectionRows
                    selectionActions
                }
                .navigationTitle(kind == "scopes" ? NativeAdminLabels.field("scopes") : kind == "users" ? NativeAdminLabels.field("userIDs") : kind == "roles" ? NativeAdminLabels.field("roleIDs") : NativeAdminLabels.field("projectIDs"))
                .searchable(text: $search, prompt: obsText("搜索名称"))
            }
        }
        .task { if rows.isEmpty { await load(append: false) } }
    }
    private var selectionRows: some View {
        Group {
            ForEach(filtered, id: \.self) { row in
                let id = kind == "scopes" ? row["scope"] : row["id"]
                Button {
                    if multiple {
                        var values = selected.array
                        if values.contains(id) { values.removeAll { $0 == id } } else { values.append(id) }
                        selected = .array(values)
                    } else { selected = id }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(kind == "scopes" ? NativeAdminLabels.value(row["scope"].string) : AdminOperationView.label(row)).foregroundStyle(.primary)
                            if kind == "scopes" { Text(row["levels"].array.map { NativeAdminLabels.value($0.string) }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        Image(systemName: (multiple ? selected.array.contains(id) : selected == id) ? "checkmark.circle.fill" : "circle")
                    }.frame(minHeight: 44)
                }.buttonStyle(.plain)
            }
        }
    }
    private var selectionActions: some View {
        HStack {
            if cursor != nil { Button("加载更多") { Task { await load(append: true) } }.disabled(loading) }
            if multiple { Button("取消全选") { selected = .array([]) } }
        }.buttonStyle(.borderless)
    }
    @MainActor private func load(append: Bool) async {
        guard !loading else { return }; loading = true; defer { loading = false }
        do {
            if kind == "scopes" {
                let level = session.connection.projectID == nil ? "system" : "project"
                rows = try await session.read("allScopes", variables: .object(["level": .string(level)]), cached: true).array
            } else {
                var vars: [String: JSON] = ["first": .number(100)]
                if kind == "roles" {
                    var filter: [String: JSON] = ["level": .string(session.connection.projectID == nil ? "system" : "project")]
                    if let project = session.connection.projectID { filter["projectID"] = .string(project) }
                    vars["where"] = .object(filter)
                }
                if append, let cursor = cursor { vars["after"] = .string(cursor) }
                let page = try await session.read(kind, variables: .object(vars), cached: true)
                let next = page["edges"].array.map { $0["node"] }
                session.store.entityNames.register(next)
                rows = append ? rows + next : next
                cursor = page["pageInfo"]["hasNextPage"].bool ? page["pageInfo"]["endCursor"].string : nil
            }
            failure = nil
        } catch { failure = error.localizedDescription }
    }
}

struct NativeProjectMemberDetail: View {
    @ObservedObject var session: AdminSession
    let member: JSON
    let projectID: String
    var body: some View {
        List {
            Section { NativeEntityRow(value: member["user"], module: .users) }
            ForEach(["updateProjectUser", "removeUserFromProject"], id: \.self) { key in
                if let operation = try? session.schema.operation(key) {
                    NavigationLink(NativeAdminLabels.operation(key)) {
                        NativeEntityEditor(session: session, operation: operation, seed: .object(["input": .object(["projectId": .string(projectID), "userId": member["userID"], "isOwner": member["isOwner"], "scopes": member["scopes"]].filter { !$0.value.isNull })]))
                    }
                }
            }
        }.navigationTitle("项目成员")
    }
}
