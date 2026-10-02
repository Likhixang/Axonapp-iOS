import SwiftUI

/// Transport keeps server IDs; the operator selects names. Existing string bindings
/// remain compatible with each endpoint's GID/numeric-ID contract.
struct NativeNamedFilter: View {
    @ObservedObject var store: AxonStore
    let kind: String
    let title: String
    @Binding var identifiers: String
    var numeric = false
    @ObservedObject private var names: EntityNameDirectory
    init(store: AxonStore, kind: String, title: String, identifiers: Binding<String>, numeric: Bool = false) {
        self.store = store; self.kind = kind; self.title = title; self._identifiers = identifiers
        self.numeric = numeric; self.names = store.entityNames
    }
    private var selected: [String] { ObservabilityFilters().identifiers(identifiers) }
    private var summary: String {
        let labels = selected.compactMap { names.label(.string($0), field: kind == "channels" ? "channelID" : kind == "models" ? "modelID" : "id", store: store) }
        return selected.isEmpty ? obsText("全部") : labels.isEmpty ? obsText("已选择") : labels.joined(separator: ", ")
    }
    var body: some View {
        NavigationLink {
            NativeNamedFilterSelection(store: store, kind: kind, title: title, identifiers: $identifiers, numeric: numeric)
        } label: {
            HStack { Text(title); Spacer(); Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
        }
    }
}

struct NativeNamedFilterSelection: View {
    @ObservedObject var store: AxonStore
    let kind: String
    let title: String
    @Binding var identifiers: String
    let numeric: Bool
    @State private var rows: [JSON] = []
    @State private var after: String?
    @State private var loading = false
    @State private var error: String?
    @State private var search = ""
    private func id(_ row: JSON) -> String {
        if numeric { return ChannelModelToolsView.channelNumericID(row["id"].string).map(String.init) ?? "" }
        return row["id"].string
    }
    private var selected: [String] { ObservabilityFilters().identifiers(identifiers) }
    var body: some View {
        List {
            Button("重置筛选") { identifiers = "" }
            if loading { ProgressView() }
            if let error = error { ObservabilityErrorView(message: error) }
            ForEach(rows.filter { search.isEmpty || NativeDisplay.name($0).localizedCaseInsensitiveContains(search) }, id: \.self) { row in
                let key = id(row)
                if !key.isEmpty {
                    Button {
                        var values = selected
                        if values.contains(key) { values.removeAll { $0 == key } } else { values.append(key) }
                        identifiers = values.joined(separator: ",")
                    } label: {
                        HStack { Text(NativeDisplay.name(row)).foregroundStyle(.primary); Spacer(); Image(systemName: selected.contains(key) ? "checkmark.circle.fill" : "circle") }.frame(minHeight: 44)
                    }.buttonStyle(.plain)
                }
            }
            if after != nil { Button("加载更多") { Task { await load(append: true) } }.disabled(loading) }
        }.navigationTitle(title).searchable(text: $search, prompt: obsText("搜索名称"))
            .task { if rows.isEmpty { await load(append: false) } }
    }
    @MainActor private func load(append: Bool) async {
        guard !loading else { return }; loading = true; defer { loading = false }
        do {
            let session = try AdminSession(store: store, schema: AdminSchema.loaded.get())
            if kind == "channels" {
                rows = store.snapshot.channels.map { .object(["id": .string($0.id), "name": .string($0.name)]) }
            } else if kind == "models" {
                rows = store.snapshot.models.map { .object(["id": .string($0.modelID), "name": .string($0.name)]) }
            } else if kind == "projects" {
                rows = try await session.read("myProjects", cached: true).array
            } else {
                var vars: [String: JSON] = ["first": .number(100)]
                if append, let after = after { vars["after"] = .string(after) }
                let data = try await session.read(kind, variables: .object(vars), cached: true)
                let page = data["edges"].array.map { $0["node"] }
                rows = append ? rows + page : page
                after = data["pageInfo"]["hasNextPage"].bool ? data["pageInfo"]["endCursor"].string : nil
            }
            store.entityNames.register(rows)
            if numeric {
                store.entityNames.register(rows.map { row in var fields = row.object; fields["id"] = .string(id(row)); return .object(fields) })
            }
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}
