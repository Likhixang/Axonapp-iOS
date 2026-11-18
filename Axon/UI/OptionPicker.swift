import SwiftUI

/// Searchable single-choice list, the native counterpart of the web console's AutoComplete selects.
/// When `allowsCustom` is on, the typed text can be used as a value that is not in the list,
/// as the web console allows for model ids and icons.
struct OptionPickerView: View {
    let title: String
    let options: [String]
    var label: (String) -> String = { $0 }
    var detail: ((String) -> String?)? = nil
    var allowsCustom = true
    var allowsClear = false
    var emptyMessage = "没有可选项"
    var isLoading = false
    let selection: String
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [String] {
        let q = query.trimmed.lowercased()
        guard !q.isEmpty else { return OptionSearch.filter(options, query: "") }
        // Match on the value and on its label (for example a developer's Chinese name).
        let byValue = OptionSearch.filter(options, query: q)
        let byLabel = options.filter { label($0).lowercased().contains(q) }
        return OptionSearch.merge(byValue, byLabel)
    }

    var body: some View {
        List {
            if allowsCustom, OptionSearch.canAddCustom(query, to: options) {
                Section {
                    Button {
                        choose(query.trimmed)
                    } label: {
                        Label("使用“\(query.trimmed)”", systemImage: "plus.circle")
                    }
                } footer: {
                    Text("列表里没有时，可以直接用输入的值。")
                }
            }
            if allowsClear, !selection.isEmpty {
                Section {
                    Button("清除", role: .destructive) { choose("") }
                }
            }
            Section {
                if isLoading && options.isEmpty {
                    HStack { ProgressView(); Text("正在加载…").foregroundStyle(.secondary) }
                } else if filtered.isEmpty {
                    Text(options.isEmpty ? emptyMessage : "没有匹配的选项").foregroundStyle(.secondary)
                }
                ForEach(filtered, id: \.self) { option in
                    Button {
                        choose(option)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(label(option)).foregroundStyle(.primary)
                                if let sub = detail?(option) ?? (label(option) == option ? nil : option) {
                                    Text(sub).font(.caption.monospaced()).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if option == selection {
                                Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                            }
                        }
                    }
                }
            } header: {
                if !options.isEmpty { Text("\(filtered.count) / \(options.count)") }
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: allowsCustom ? "搜索或输入" : "搜索")
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .onSubmit(of: .search) {
            let q = query.trimmed
            guard !q.isEmpty else { return }
            if let first = filtered.first, first.lowercased() == q.lowercased() || !allowsCustom {
                choose(first)
            } else if allowsCustom {
                choose(q)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func choose(_ value: String) {
        onSelect(value)
        dismiss()
    }
}

/// A form row that opens an `OptionPickerView` and shows the current value.
struct OptionPickerRow: View {
    let title: String
    let value: String
    var placeholder = "请选择"
    var monospaced = false
    var display: (String) -> String = { $0 }
    let options: [String]
    var label: (String) -> String = { $0 }
    var detail: ((String) -> String?)? = nil
    var allowsCustom = true
    var allowsClear = false
    var emptyMessage = "没有可选项"
    var isLoading = false
    let onSelect: (String) -> Void

    var body: some View {
        NavigationLink {
            OptionPickerView(title: title, options: options, label: label, detail: detail, allowsCustom: allowsCustom,
                             allowsClear: allowsClear, emptyMessage: emptyMessage, isLoading: isLoading,
                             selection: value, onSelect: onSelect)
        } label: {
            LabeledContent(title) {
                Text(value.isEmpty ? placeholder : display(value))
                    .font(monospaced && !value.isEmpty ? .callout.monospaced() : .body)
                    .foregroundStyle(value.isEmpty ? HierarchicalShapeStyle.tertiary : HierarchicalShapeStyle.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }
}

/// Searchable channel select (the web console's channel AutoComplete), showing name and type.
struct ChannelPickerRow: View {
    var title = "渠道"
    let channels: [ChannelOption]
    let selection: Int?
    var allowsClear = false
    let onSelect: (Int) -> Void

    private var byID: [String: ChannelOption] {
        Dictionary(channels.compactMap { c in c.numericID.map { (String($0), c) } }, uniquingKeysWith: { a, _ in a })
    }

    var body: some View {
        let map = byID
        OptionPickerRow(
            title: title,
            value: selection.map(String.init) ?? "",
            display: { map[$0]?.name ?? "#\($0)" },
            options: channels.compactMap { $0.numericID.map(String.init) },
            label: { map[$0]?.name ?? "#\($0)" },
            detail: { id in map[id].map { "#\(id) · \($0.type)\($0.status == "enabled" ? "" : " · \($0.status)")" } },
            allowsCustom: false,
            allowsClear: allowsClear,
            emptyMessage: "没有渠道"
        ) { onSelect(Int($0) ?? 0) }
    }
}
