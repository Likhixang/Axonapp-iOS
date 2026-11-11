import SwiftUI

struct APIKeysView: View {
    @Environment(SessionStore.self) private var session
    @State private var loader = PagedLoader<APIKey>()
    @State private var query = ""
    @State private var search = ""
    @State private var includeArchived = false
    @State private var showCreate = false
    @State private var revealed: Set<String> = []
    @State private var toast: Toast?
    @State private var pendingRotate: APIKey?
    @State private var renaming: APIKey?
    @State private var renameText = ""
    @State private var editingProfiles: APIKey?
    @State private var editingKey: APIKey?

    var body: some View {
        List {
            ForEach(loader.items) { key in
                NavigationLink {
                    APIKeyDetailView(apiKey: key) { loader.replace($0) }
                } label: {
                    APIKeyRow(apiKey: key, isRevealed: revealed.contains(key.id)) {
                        if revealed.contains(key.id) { revealed.remove(key.id) } else { revealed.insert(key.id) }
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if key.keyStatus != .archived {
                        Button("归档", systemImage: "archivebox", role: .destructive) { Task { await setStatus(key, .archived) } }
                    }
                    Button(key.keyStatus == .enabled ? "停用" : "启用",
                           systemImage: key.keyStatus == .enabled ? "pause.circle" : "play.circle") {
                        Task { await setStatus(key, key.keyStatus == .enabled ? .disabled : .enabled) }
                    }
                    .tint(key.keyStatus == .enabled ? .orange : .green)
                }
                .swipeActions(edge: .leading) {
                    Button("拷贝", systemImage: "doc.on.doc") { copy(key) }.tint(.blue)
                }
                .contextMenu {
                    Button("拷贝密钥", systemImage: "doc.on.doc") { copy(key) }
                    Button("编辑配置文件", systemImage: "slider.horizontal.3") { editingProfiles = key }
                    Button("编辑密钥", systemImage: "pencil") { editingKey = key }
                    Button("重命名", systemImage: "character.cursor.ibeam") { renameText = key.name; renaming = key }
                    Button("轮换密钥", systemImage: "arrow.triangle.2.circlepath") { pendingRotate = key }
                    Divider()
                    Button(key.keyStatus == .enabled ? "停用" : "启用",
                           systemImage: key.keyStatus == .enabled ? "pause.circle" : "play.circle") {
                        Task { await setStatus(key, key.keyStatus == .enabled ? .disabled : .enabled) }
                    }
                    if key.keyStatus != .archived {
                        Button("归档", systemImage: "archivebox", role: .destructive) { Task { await setStatus(key, .archived) } }
                    }
                }
                .task { await loader.loadMoreIfNeeded(current: key) }
            }
            LoadMoreFooter(isLoading: loader.isLoadingMore)
        }
        .listStyle(.insetGrouped)
        .overlay {
            ListStateOverlay(loader: loader, emptyTitle: "还没有 API 密钥", emptyImage: "key",
                             emptyMessage: "创建密钥后即可用 OpenAI / Anthropic / Gemini 兼容接口访问网关")
        }
        .navigationTitle("API 密钥")
        .searchable(text: $query, prompt: "搜索密钥名称")
        .onSubmit(of: .search) { search = query }
        .onChange(of: query) { _, value in if value.isEmpty { search = "" } }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { ProjectPicker() }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Toggle("显示已归档", isOn: $includeArchived)
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
                Button { showCreate = true } label: { Image(systemName: "plus") }
                    .disabled(session.selectedProjectID == nil)
            }
        }
        .sheet(isPresented: $showCreate) {
            APIKeyFormSheet(existing: nil) { created in
                loader.prepend(created)
                revealed.insert(created.id)
            }
        }
        .sheet(item: $editingKey) { key in
            APIKeyFormSheet(existing: key) { loader.replace($0) }
        }
        .sheet(item: $editingProfiles) { key in
            APIKeyProfilesEditorView(apiKey: key) { saved in
                loader.replace(saved)
                toast = Toast(message: "配置文件已保存")
            }
        }
        .confirmationDialog("轮换密钥？", isPresented: Binding(get: { pendingRotate != nil }, set: { if !$0 { pendingRotate = nil } }),
                            titleVisibility: .visible, presenting: pendingRotate) { key in
            Button("轮换 \(key.name)", role: .destructive) { Task { await rotate(key) } }
        } message: { _ in
            Text("旧密钥会立即失效，使用它的客户端需要更新。")
        }
        .alert("重命名", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("名称", text: $renameText)
            Button("取消", role: .cancel) {}
            Button("保存") { if let key = renaming { Task { await rename(key) } } }
        }
        .toast($toast)
        .refreshable { await loader.reload() }
        .task(id: ReloadKey(search: search, archived: includeArchived, project: session.selectedProjectID)) {
            guard let service = session.service else { return }
            let search = search, archived = includeArchived
            loader.fetch = { cursor in try await service.apiKeys(after: cursor, search: search, includeArchived: archived) }
            await loader.reload()
        }
    }

    private struct ReloadKey: Hashable { let search: String; let archived: Bool; let project: String? }

    private func copy(_ key: APIKey) {
        Clipboard.copy(key.key)
        toast = Toast(message: "已拷贝 \(key.name)")
    }

    private func setStatus(_ key: APIKey, _ status: ResourceStatus) async {
        guard let service = session.service else { return }
        do {
            let updated = try await service.setAPIKeyStatus(id: key.id, status: status)
            if status == .archived && !includeArchived {
                withAnimation { loader.remove(id: key.id) }
            } else {
                loader.replace(updated)
            }
        } catch {
            toast = Toast(message: error.localizedDescription, isError: true)
        }
    }

    private func rotate(_ key: APIKey) async {
        guard let service = session.service else { return }
        do {
            let updated = try await service.rotateAPIKey(id: key.id)
            loader.replace(updated)
            revealed.insert(updated.id)
            toast = Toast(message: "已生成新密钥")
        } catch {
            toast = Toast(message: error.localizedDescription, isError: true)
        }
    }

    private func rename(_ key: APIKey) async {
        guard let service = session.service, let name = renameText.nilIfBlank else { return }
        do {
            loader.replace(try await service.renameAPIKey(id: key.id, name: name))
        } catch {
            toast = Toast(message: error.localizedDescription, isError: true)
        }
    }
}

struct APIKeyRow: View {
    let apiKey: APIKey
    let isRevealed: Bool
    var toggleReveal: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(apiKey.name).font(.body.weight(.medium)).lineLimit(1)
                Spacer()
                StatusBadge(apiKey.keyStatus)
            }
            HStack(spacing: 8) {
                Text(isRevealed ? apiKey.key : Fmt.mask(apiKey.key))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(isRevealed ? 3 : 1)
                    .textSelection(.enabled)
                Spacer(minLength: 4)
                Button(action: toggleReveal) {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Tag(text: apiKey.typeLabel)
                if let profile = apiKey.profiles?.activeProfile.nilIfBlank {
                    Label(profile, systemImage: "slider.horizontal.3")
                }
                if let project = apiKey.project {
                    Label(project.name, systemImage: "folder")
                }
                Spacer()
                Text(Fmt.relative(apiKey.createdAt))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .labelStyle(CompactLabelStyle())
            .lineLimit(1)
        }
        .padding(.vertical, 2)
    }
}
