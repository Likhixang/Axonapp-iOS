import SwiftUI

/// Multi-select tag editor: picks from tags already in use (`allChannelTags`) and accepts new ones,
/// like the web console's tags autocomplete.
struct TagPickerView: View {
    var title = "标签"
    let suggestions: [String]
    var isLoading = false
    @Binding var tags: [String]
    @State private var query = ""

    private var available: [String] {
        ChannelChoices.tagSuggestions(all: suggestions, selected: tags, query: query)
    }

    private var typed: [String] { ChannelChoices.parseTags(query).filter { !tags.contains($0) } }

    var body: some View {
        List {
            if !tags.isEmpty {
                Section("已选 (\(tags.count))") {
                    ForEach(tags, id: \.self) { tag in
                        Button {
                            tags.removeAll { $0 == tag }
                        } label: {
                            HStack {
                                Text(tag).foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                            }
                        }
                    }
                }
            }
            if !typed.isEmpty, !suggestions.contains(where: { typed == [$0] }) {
                Section {
                    Button {
                        tags = ChannelChoices.addTags(query, to: tags)
                        query = ""
                    } label: {
                        Label("添加“\(typed.joined(separator: "”“"))”", systemImage: "plus.circle")
                    }
                }
            }
            Section {
                if isLoading && suggestions.isEmpty {
                    HStack { ProgressView(); Text("正在加载标签").foregroundStyle(.secondary) }
                } else if available.isEmpty {
                    Text(query.isEmpty ? "没有其他标签，可以在搜索框里输入新标签" : "没有匹配的标签")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(available, id: \.self) { tag in
                        Button {
                            tags.append(tag)
                        } label: {
                            HStack {
                                Text(tag).foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "circle").foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                Text("可选标签")
            } footer: {
                Text("输入后按回车添加新标签，多个标签用逗号或空格分隔。")
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索或新建标签")
        .onSubmit(of: .search) {
            tags = ChannelChoices.addTags(query, to: tags)
            query = ""
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A form row that shows the chosen tags and opens `TagPickerView`.
struct TagPickerRow: View {
    var title = "标签"
    let suggestions: [String]
    var isLoading = false
    @Binding var tags: [String]

    var body: some View {
        NavigationLink {
            TagPickerView(title: title, suggestions: suggestions, isLoading: isLoading, tags: $tags)
        } label: {
            LabeledContent(title) {
                Text(tags.isEmpty ? "未设置" : tags.joined(separator: "、"))
                    .lineLimit(1)
                    .foregroundStyle(tags.isEmpty ? .tertiary : .secondary)
            }
        }
    }
}

/// A fixed select written with `Choice`s, with the chosen option's explanation under it.
struct ChoicePicker: View {
    let title: String
    let choices: [Choice]
    @Binding var selection: String
    var label: (Choice) -> String = { $0.label }

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(choices) { choice in
                VStack(alignment: .leading) {
                    Text(label(choice))
                    if let detail = choice.detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
                }
                .tag(choice.value)
            }
        }
        .pickerStyle(.navigationLink)
    }
}
