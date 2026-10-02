import SwiftUI

/// Presentation-only naming. Never decode a GID and mistake its number for a name.
@MainActor final class EntityNameDirectory: ObservableObject {
    @Published private(set) var names: [String: String] = [:]
    private var pending = Set<String>()
    private var generation = UUID()
    func reset() { generation = UUID(); pending = []; names = [:] }
    func register(_ rows: [JSON]) {
        for row in rows {
            let label = NativeDisplay.name(row)
            if !row["id"].string.isEmpty && label != "—" { names[row["id"].string] = label }
        }
    }
    func label(_ id: JSON, field: String, store: AxonStore) -> String? {
        let text = id.string.isEmpty && !id.isNull ? String(id.int) : id.string
        if field.lowercased().contains("model") {
            if let model = store.snapshot.models.first(where: { $0.id == text || $0.modelID == text }) { return model.name }
            // A model identifier such as gpt-... is meaningful, unlike a node GID.
            return NativeDisplay.isOpaque(text) ? nil : text
        }
        if field.lowercased().contains("channel"), let channel = store.snapshot.channels.first(where: { $0.id == text || ChannelModelToolsView.channelNumericID($0.id).map(String.init) == text }) { return channel.name }
        return names[text]
    }
    func resolve(_ value: JSON, store: AxonStore) async {
        var targets: [String: String] = [:]
        func collect(_ value: JSON) {
            switch value {
            case .object(let fields):
                for (key, item) in fields {
                    if let entity = NativeDisplay.entity(for: key) {
                        for id in item.array.isEmpty ? [item] : item.array where !id.string.isEmpty { targets[id.string] = entity }
                    }
                    collect(item)
                }
            case .array(let values): values.forEach(collect)
            default: break
            }
        }
        collect(value)
        let revision = generation
        guard let instance = store.selectedInstance else { return }
        do {
            let session = try AdminSession(store: store, schema: AdminSchema.loaded.get())
            for (id, entity) in targets where names[id] == nil && !pending.contains(id) {
                pending.insert(id)
                do {
                    let node = try await session.detail(entity, id: id)
                    guard generation == revision, instance == store.selectedInstance else { return }
                    register([node])
                } catch { /* Unreadable/deleted relations are not replaced with fabricated labels. */ }
                pending.remove(id)
            }
        } catch { }
    }
}

enum NativeDisplay {
    static func entity(for key: String) -> String? {
        switch key.lowercased() {
        case "projectid", "projectids": return "Project"
        case "userid", "userids": return "User"
        case "roleid", "roleids": return "Role"
        case "apikeyid", "apikeyids": return "APIKey"
        case "templateid": return "APIKeyProfileTemplate"
        case "datastorageid": return "DataStorage"
        default: return nil
        }
    }
    static func identifier(_ key: String) -> Bool {
        let key = key.lowercased()
        return key == "id" || key == "gid" || key == "__typename" || key == "cursor" || key == "externalid" || key.hasSuffix("id") && !key.contains("model") || key.hasSuffix("ids") && !key.contains("model")
    }
    static func isOpaque(_ text: String) -> Bool {
        if UUID(uuidString: text) != nil { return true }
        if let data = Data(base64Encoded: text), let raw = String(data: data, encoding: .utf8), raw.contains(":") { return true }
        return false
    }
    static func name(_ value: JSON) -> String {
        for key in ["name", "displayName", "email", "firstName", "modelName", "modelID", "channelName", "apiKeyName", "title"] where !value[key].string.isEmpty { return value[key].string }
        return "—"
    }
    static func date(_ text: String) -> String {
        DisplayFormat.date(text)
    }
}

struct NativeDetailFieldsView: View {
    @ObservedObject var store: AxonStore
    let value: JSON
    @ObservedObject private var directory: EntityNameDirectory
    init(store: AxonStore, value: JSON) { self.store = store; self.value = value; directory = store.entityNames }
    var body: some View {
        ForEach(value.object.keys.sorted(), id: \.self) { key in
            let item = value[key]
            if NativeDisplay.identifier(key) {
                if NativeDisplay.entity(for: key) != nil || key.lowercased().contains("channel") {
                    let labels = (item.array.isEmpty ? [item] : item.array).compactMap { directory.label($0, field: key, store: store) }
                    if !labels.isEmpty { detailRow(NativeAdminLabels.field(key), labels.joined(separator: ", ")) }
                }
            } else if (!AdminSchema.sensitive(key) || key == "apiKeyName"), !item.isNull {
                if !item.object.isEmpty {
                    DisclosureGroup(NativeAdminLabels.field(key)) { AnyView(NativeDetailFieldsView(store: store, value: item)) }
                } else if case .array(let rows) = item {
                    if !rows.isEmpty {
                        DisclosureGroup(NativeAdminLabels.field(key)) {
                            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                                if case .object = row { AnyView(NativeDetailFieldsView(store: store, value: row)) }
                                else { Text(NativeAdminLabels.scalar(row, key: key)).font(.subheadline).foregroundStyle(.secondary) }
                            }
                        }
                    }
                } else {
                    detailRow(NativeAdminLabels.field(key), formatted(item, key: key))
                }
            }
        }
        .task(id: value) { await directory.resolve(value, store: store) }
    }
    private func formatted(_ item: JSON, key: String) -> String {
        if case .bool(let flag) = item { return obsText(flag ? "是" : "否") }
        if key.hasSuffix("At") { return NativeDisplay.date(item.string) }
        if key.lowercased().contains("model"), let label = directory.label(item, field: key, store: store) { return label }
        if case .string(let text) = item { return NativeDisplay.isOpaque(text) ? "—" : NativeAdminLabels.scalar(item, key: key) }
        return NativeAdminLabels.scalar(item, key: key)
    }
    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 20) {
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value).multilineTextAlignment(.trailing).textSelection(.enabled)
        }.font(.subheadline).padding(.vertical, 5)
    }
}

struct ManagementMenuRow: View {
    let title: String
    let symbol: String
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).symbolVariant(.fill)
                .font(.system(size: 24, weight: .semibold)).foregroundStyle(Color.accentColor)
                .frame(width: 32, height: 36).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
            }
        }.padding(.vertical, 5).frame(minHeight: 54)
    }
}
