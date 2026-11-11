import SwiftUI

/// Lets the user choose which pages sit in the tab bar and in what order.
struct TabBarEditorView: View {
    @Environment(SessionStore.self) private var session
    @AppStorage(TabLayout.storageKey) private var storedPinned = ""
    @State private var pinned: [AppDestination] = []
    @State private var loaded = false

    private var available: [AppDestination] {
        AppDestination.available(isAdmin: session.canManageSystem, isOwner: session.isOwner)
    }

    private var others: [AppDestination] { TabLayout.unpinned(pinned, available: available) }
    private var isFull: Bool { pinned.count >= TabLayout.maxPinned }

    var body: some View {
        List {
            Section {
                TabBarPreview(items: pinned)
                    .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                    .listRowBackground(Color.clear)
            }

            Section {
                ForEach(pinned) { item in
                    HStack(spacing: 12) {
                        Button {
                            withAnimation { remove(item) }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, pinned.count > 1 ? Theme.danger : Color.gray)
                                .font(.title3)
                        }
                        .buttonStyle(.plain)
                        .disabled(pinned.count <= 1)
                        .accessibilityLabel("从底栏移除\(item.title)")
                        Label(item.title, systemImage: item.systemImage)
                    }
                }
                .onMove { from, to in
                    pinned.move(fromOffsets: from, toOffset: to)
                    save()
                }
            } header: {
                Text("底栏（\(pinned.count)/\(TabLayout.maxPinned)）")
            } footer: {
                Text("按住右侧的把手拖动可以排序。“更多”始终在最后一格，没放到底栏的页面都在里面。")
            }

            if !others.isEmpty {
                Section {
                    ForEach(others) { item in
                        HStack(spacing: 12) {
                            Button {
                                withAnimation { add(item) }
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, isFull ? Color.gray : Theme.success)
                                    .font(.title3)
                            }
                            .buttonStyle(.plain)
                            .disabled(isFull)
                            .accessibilityLabel("把\(item.title)放到底栏")
                            Label(item.title, systemImage: item.systemImage)
                        }
                    }
                } header: {
                    Text("放在“更多”里")
                } footer: {
                    if isFull { Text("底栏已满，先移除一项再添加。") }
                }
            }

            Section {
                Button("恢复默认") {
                    withAnimation {
                        pinned = TabLayout.defaults(available: available)
                        storedPinned = ""
                    }
                }
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("自定义底栏")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            pinned = TabLayout.resolve(stored: storedPinned, available: available)
        }
    }

    private func add(_ item: AppDestination) {
        guard !isFull, !pinned.contains(item) else { return }
        pinned.append(item)
        save()
    }

    private func remove(_ item: AppDestination) {
        guard pinned.count > 1 else { return }
        pinned.removeAll { $0 == item }
        save()
    }

    private func save() { storedPinned = TabLayout.encode(pinned) }
}

/// Small mock of the tab bar so the user sees the result while editing.
private struct TabBarPreview: View {
    let items: [AppDestination]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                cell(title: item.tabTitle, image: item.systemImage, highlighted: item == items.first)
            }
            cell(title: "更多", image: "ellipsis.circle", highlighted: false)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .adaptiveGlass(in: Capsule())
        .animation(.snappy, value: items)
    }

    private func cell(title: String, image: String, highlighted: Bool) -> some View {
        VStack(spacing: 3) {
            Image(systemName: image).font(.system(size: 17, weight: .medium))
            Text(title).font(.system(size: 10, weight: .medium)).lineLimit(1)
        }
        .foregroundStyle(highlighted ? Theme.accent : .secondary)
        .frame(maxWidth: .infinity)
    }
}
