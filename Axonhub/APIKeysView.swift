import SwiftUI
import UIKit

/// Native API Key representation parsed from official GraphQL schema.
struct AdminAPIKeyItem: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let keyMasked: String
    let type: String
    let status: String
    let scopes: [String]
    let allowedIps: [String]
    let activeProfile: String?
    let templateName: String?
    let projectID: String?
    let createdAt: String
    let updatedAt: String

    var isEnabled: Bool { status.lowercased() == "enabled" }
    var isArchived: Bool { status.lowercased() == "archived" }
    var isServiceAccount: Bool { type == "service_account" }

    static func from(json: JSON) -> AdminAPIKeyItem {
        let profiles = json["profiles"]
        let activeProf = profiles["activeProfile"].string
        var template: String? = nil
        if case .array(let list) = profiles["profiles"] {
            for p in list where p["name"].string == activeProf {
                let tName = p["templateName"].string
                if !tName.isEmpty { template = tName }
            }
        }
        let rawKey = json["key"].string
        let masked: String
        if rawKey.isEmpty {
            masked = "••••••••"
        } else if rawKey.count > 8 {
            masked = "••••" + String(rawKey.suffix(4))
        } else {
            masked = rawKey
        }

        return AdminAPIKeyItem(
            id: json["id"].string,
            name: json["name"].string.isEmpty ? NSLocalizedString("未命名密钥", comment: "") : json["name"].string,
            keyMasked: masked,
            type: json["type"].string.isEmpty ? "user" : json["type"].string,
            status: json["status"].string.isEmpty ? "enabled" : json["status"].string,
            scopes: json["scopes"].array.map { $0.string },
            allowedIps: json["allowedIps"].array.map { $0.string },
            activeProfile: activeProf.isEmpty ? nil : activeProf,
            templateName: template,
            projectID: json["projectID"].isNull ? nil : json["projectID"].string,
            createdAt: json["createdAt"].string,
            updatedAt: json["updatedAt"].string
        )
    }
}

/// Primary native view for managing AxonHub API Keys.
struct APIKeysListView: View {
    @ObservedObject var store: AxonStore
    var initialProjectID: String? = nil

    @State private var items: [AdminAPIKeyItem] = []
    @State private var loading = false
    @State private var errorMessage: String? = nil
    @State private var search = ""
    @State private var statusFilter = "all"
    @State private var projectID = ""
    @State private var projectOptions: [JSON] = []

    @State private var showingCreate = false
    @State private var editingItem: AdminAPIKeyItem? = nil
    @State private var rotatingItem: AdminAPIKeyItem? = nil
    @State private var showRotateConfirm = false
    @State private var newlyCreatedKey: String? = nil
    @State private var newlyCreatedTitle = ""
    @State private var showNewKeyAlert = false
    @State private var alertNotice: String? = nil

    private var filteredItems: [AdminAPIKeyItem] {
        items.filter { item in
            let matchesSearch = search.isEmpty ||
                item.name.localizedCaseInsensitiveContains(search) ||
                item.id.localizedCaseInsensitiveContains(search)
            let matchesStatus: Bool
            switch statusFilter {
            case "enabled": matchesStatus = item.isEnabled
            case "disabled": matchesStatus = (!item.isEnabled && !item.isArchived)
            case "archived": matchesStatus = item.isArchived
            default: matchesStatus = true
            }
            return matchesSearch && matchesStatus
        }
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 8) {
                    Picker(NSLocalizedString("状态筛选", comment: ""), selection: $statusFilter) {
                        Text(NSLocalizedString("全部", comment: "")).tag("all")
                        Text(NSLocalizedString("启用中", comment: "")).tag("enabled")
                        Text(NSLocalizedString("已禁用", comment: "")).tag("disabled")
                        Text(NSLocalizedString("已归档", comment: "")).tag("archived")
                    }
                    .pickerStyle(.segmented)

                    if !projectOptions.isEmpty {
                        Picker(NSLocalizedString("项目作用域", comment: ""), selection: $projectID) {
                            Text(NSLocalizedString("系统全局", comment: "")).tag("")
                            ForEach(projectOptions, id: \.self) { proj in
                                Text(proj["name"].string).tag(proj["id"].string)
                            }
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }

            if loading && items.isEmpty {
                Section {
                    HStack {
                        Spacer()
                        ProgressView(NSLocalizedString("正在读取密钥列表...", comment: ""))
                        Spacer()
                    }
                    .padding(.vertical, 20)
                }
            } else if let error = errorMessage {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Button(NSLocalizedString("重试", comment: "")) {
                        Task { await loadData() }
                    }
                }
            } else if filteredItems.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "key.slash").symbolVariant(.fill)
                            .font(.system(size: 36))
                            .foregroundStyle(Color.accentColor)
                        Text(NSLocalizedString("暂无符合条件的 API 密钥", comment: ""))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                }
            } else {
                ForEach(filteredItems) { item in
                    APIKeyRowCard(
                        item: item,
                        canManage: store.canManage,
                        onToggle: { enabled in toggleStatus(item: item, enabled: enabled) },
                        onRotate: {
                            rotatingItem = item
                            showRotateConfirm = true
                        },
                        onEdit: { editingItem = item },
                        onArchive: { archiveKey(item: item) }
                    )
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(NSLocalizedString("API 密钥", comment: ""))
        .searchable(text: $search, prompt: NSLocalizedString("搜索密钥名称或 ID", comment: ""))
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingCreate = true
                } label: {
                    Label(NSLocalizedString("新建密钥", comment: ""), systemImage: "plus")
                }
                .disabled(!store.canManage)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task { await loadData() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(loading)
            }
        }
        .refreshable {
            await loadData()
        }
        .task {
            if let initProj = initialProjectID { projectID = initProj }
            await loadProjects()
            await loadData()
        }
        .onChange(of: projectID) { _ in
            Task { await loadData() }
        }
        .sheet(isPresented: $showingCreate) {
            APIKeyCreateSheet(store: store, projectID: projectID) { newKey, name in
                newlyCreatedKey = newKey
                newlyCreatedTitle = name
                showNewKeyAlert = true
                Task { await loadData() }
            }
        }
        .sheet(item: $editingItem) { item in
            APIKeyEditSheet(store: store, item: item) {
                Task { await loadData() }
            }
        }
        .sheet(isPresented: $showNewKeyAlert) {
            if let key = newlyCreatedKey {
                APIKeySecretRevealSheet(name: newlyCreatedTitle, secret: key) {
                    showNewKeyAlert = false
                    newlyCreatedKey = nil
                }
            }
        }
        .confirmationDialog(
            NSLocalizedString("轮换 API 密钥", comment: ""),
            isPresented: $showRotateConfirm,
            titleVisibility: .visible
        ) {
            Button(NSLocalizedString("确认轮换", comment: ""), role: .destructive) {
                if let target = rotatingItem {
                    executeRotate(item: target)
                }
            }
            Button(NSLocalizedString("取消", comment: ""), role: .cancel) {
                rotatingItem = nil
            }
        } message: {
            Text(NSLocalizedString("轮换后原密钥将立即失效，所有使用旧密钥的应用需更新。确定继续吗？", comment: ""))
        }
        .alert(NSLocalizedString("操作结果", comment: ""), isPresented: Binding(get: { alertNotice != nil }, set: { if !$0 { alertNotice = nil } })) {
            Button(NSLocalizedString("确定", comment: ""), role: .cancel) {}
        } message: {
            Text(alertNotice ?? "")
        }
    }

    private func loadProjects() async {
        guard let client = try? store.ensureClient(), store.canManage else { return }
        do {
            let data = try await client.graphql(query: AdminDocuments.adminMyProjects)
            if case .array(let projs) = data["myProjects"] {
                projectOptions = projs
            }
        } catch {
            // Unscoped instances may not have projects; keep empty
        }
    }

    private func loadData() async {
        guard !loading else { return }
        loading = true
        errorMessage = nil
        defer { loading = false }

        do {
            let client = try store.ensureClient()
            guard store.canManage else { throw AxonAPIError.forbidden }

            var variables: [String: Any] = [
                "first": 50,
                "orderBy": ["direction": "DESC", "field": "CREATED_AT"]
            ]
            if !projectID.isEmpty {
                variables["where"] = ["projectID": projectID]
            }

            let resp: JSON
            if !projectID.isEmpty {
                resp = try await client.adminScopedGraphql(
                    query: AdminDocuments.adminGetApiKeys,
                    variables: variables,
                    projectID: projectID
                )
            } else {
                resp = try await client.graphql(
                    query: AdminDocuments.adminGetApiKeys,
                    variables: variables
                )
            }

            let edges = resp["apiKeys"]["edges"].array
            items = edges.map { AdminAPIKeyItem.from(json: $0["node"]) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggleStatus(item: AdminAPIKeyItem, enabled: Bool) {
        Task {
            do {
                let client = try store.ensureClient()
                let targetStatus = enabled ? "enabled" : "disabled"
                let vars: [String: Any] = ["id": item.id, "status": targetStatus]
                _ = try await client.graphql(
                    query: AdminDocuments.adminUpdateAPIKeyStatus,
                    variables: vars
                )
                await loadData()
            } catch {
                alertNotice = error.localizedDescription
            }
        }
    }

    private func executeRotate(item: AdminAPIKeyItem) {
        Task {
            do {
                let client = try store.ensureClient()
                let vars: [String: Any] = ["id": item.id]
                let resp = try await client.graphql(
                    query: AdminDocuments.adminRotateAPIKey,
                    variables: vars
                )
                let newKey = resp["rotateAPIKey"]["key"].string
                newlyCreatedKey = newKey
                newlyCreatedTitle = item.name
                showNewKeyAlert = true
                await loadData()
            } catch {
                alertNotice = error.localizedDescription
            }
        }
    }

    private func archiveKey(item: AdminAPIKeyItem) {
        Task {
            do {
                let client = try store.ensureClient()
                let vars: [String: Any] = ["id": item.id, "status": "archived"]
                _ = try await client.graphql(
                    query: AdminDocuments.adminUpdateAPIKeyStatus,
                    variables: vars
                )
                await loadData()
            } catch {
                alertNotice = error.localizedDescription
            }
        }
    }
}

/// Native Card presentation for a single API Key.
struct APIKeyRowCard: View {
    let item: AdminAPIKeyItem
    let canManage: Bool
    let onToggle: (Bool) -> Void
    let onRotate: () -> Void
    let onEdit: () -> Void
    let onArchive: () -> Void

    @State private var copiedNotice = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(item.name)
                            .font(.headline)
                            .lineLimit(1)

                        if item.isServiceAccount {
                            Text(NSLocalizedString("服务账号", comment: ""))
                                .font(.caption2)
                                .fontWeight(.medium)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.purple.opacity(0.12))
                                .foregroundStyle(.purple)
                                .clipShape(Capsule())
                        }
                    }

                    HStack(spacing: 6) {
                        Circle()
                            .fill(item.isEnabled ? Color.green : (item.isArchived ? Color.gray : Color.orange))
                            .frame(width: 8, height: 8)
                        Text(statusTitle(item.status))
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        if let profile = item.activeProfile {
                            Text("·")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(profile)
                                .font(.caption2)
                                .foregroundStyle(.blue)
                        }
                    }
                }

                Spacer()

                if canManage && !item.isArchived {
                    Toggle(
                        NSLocalizedString("启用密钥", comment: ""),
                        isOn: Binding(
                            get: { item.isEnabled },
                            set: onToggle
                        )
                    )
                    .labelsHidden()
                }
            }

            HStack {
                Text(item.keyMasked)
                    .font(.caption.monospaced())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                Spacer()

                if !item.allowedIps.isEmpty {
                    Label(String(format: NSLocalizedString("IP 限制：%lld 项", comment: ""), Int64(item.allowedIps.count)), systemImage: "shield.checkered")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if canManage && !item.isArchived {
                Divider()

                HStack {
                    Button(action: onEdit) {
                        Label(NSLocalizedString("编辑", comment: ""), systemImage: "pencil")
                    }

                    Button(action: onRotate) {
                        Label(NSLocalizedString("轮换密钥", comment: ""), systemImage: "arrow.triangle.2.circlepath")
                    }

                    Spacer()

                    Button(role: .destructive, action: onArchive) {
                        Label(NSLocalizedString("归档", comment: ""), systemImage: "archivebox")
                    }
                }
                .buttonStyle(NeutralActionStyle())
                .controlSize(.regular)
            }
        }
        .padding(14)
        .liquidGlass()
    }

    private func statusTitle(_ raw: String) -> String {
        switch raw.lowercased() {
        case "enabled": return NSLocalizedString("启用中", comment: "")
        case "disabled": return NSLocalizedString("已禁用", comment: "")
        case "archived": return NSLocalizedString("已归档", comment: "")
        default: return raw
        }
    }
}

/// Create API Key native form.
struct APIKeyCreateSheet: View {
    @ObservedObject var store: AxonStore
    let projectID: String
    let onCreated: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var type = "user"
    @State private var allowedIPsText = ""
    @State private var busy = false
    @State private var error: String? = nil

    private var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !busy
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(NSLocalizedString("密钥基本信息", comment: "")) {
                    TextField(NSLocalizedString("密钥名称（如：Dev API Key）", comment: ""), text: $name)
                    Picker(NSLocalizedString("类型", comment: ""), selection: $type) {
                        Text(NSLocalizedString("普通用户密钥", comment: "")).tag("user")
                        Text(NSLocalizedString("服务账号", comment: "")).tag("service_account")
                    }
                }

                Section(NSLocalizedString("安全限制", comment: "")) {
                    TextField(NSLocalizedString("允许 IP 列表（每行一个，留空表示不限制）", comment: ""), text: $allowedIPsText, axis: .vertical)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                if let error = error {
                    Section {
                        Text(error).foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .navigationTitle(NSLocalizedString("新建 API 密钥", comment: ""))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("取消", comment: "")) { dismiss() }
                        .disabled(busy)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("创建", comment: "")) { submit() }
                        .disabled(!canSubmit)
                }
            }
        }
    }

    private func submit() {
        busy = true
        error = nil
        Task {
            do {
                let client = try store.ensureClient()
                var inputObj: [String: Any] = [
                    "name": name.trimmingCharacters(in: .whitespacesAndNewlines),
                    "type": type
                ]
                let ips = allowedIPsText.components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                if !ips.isEmpty {
                    inputObj["allowedIps"] = ips
                }
                if !projectID.isEmpty {
                    inputObj["projectID"] = projectID
                }

                let resp: JSON
                if !projectID.isEmpty {
                    resp = try await client.adminScopedGraphql(
                        query: AdminDocuments.adminCreateAPIKey,
                        variables: ["input": inputObj],
                        projectID: projectID
                    )
                } else {
                    resp = try await client.graphql(
                        query: AdminDocuments.adminCreateAPIKey,
                        variables: ["input": inputObj]
                    )
                }

                let created = resp["createAPIKey"]
                let rawKey = created["key"].string
                let title = created["name"].string
                dismiss()
                onCreated(rawKey, title)
            } catch {
                self.error = error.localizedDescription
                busy = false
            }
        }
    }
}

/// Edit existing API Key name and IP list.
struct APIKeyEditSheet: View {
    @ObservedObject var store: AxonStore
    let item: AdminAPIKeyItem
    let onUpdated: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var allowedIPsText: String
    @State private var busy = false
    @State private var error: String? = nil

    init(store: AxonStore, item: AdminAPIKeyItem, onUpdated: @escaping () -> Void) {
        self.store = store
        self.item = item
        self.onUpdated = onUpdated
        _name = State(initialValue: item.name)
        _allowedIPsText = State(initialValue: item.allowedIps.joined(separator: "\n"))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(NSLocalizedString("基本信息", comment: "")) {
                    TextField(NSLocalizedString("密钥名称", comment: ""), text: $name)
                }

                Section(NSLocalizedString("安全限制", comment: "")) {
                    TextField(NSLocalizedString("允许 IP 列表（每行一个）", comment: ""), text: $allowedIPsText, axis: .vertical)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                if let error = error {
                    Section {
                        Text(error).foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .navigationTitle(NSLocalizedString("编辑 API 密钥", comment: ""))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("取消", comment: "")) { dismiss() }
                        .disabled(busy)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("保存", comment: "")) { submit() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy)
                }
            }
        }
    }

    private func submit() {
        busy = true
        error = nil
        Task {
            do {
                let client = try store.ensureClient()
                var inputObj: [String: Any] = [
                    "name": name.trimmingCharacters(in: .whitespacesAndNewlines)
                ]
                let ips = allowedIPsText.components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                inputObj["allowedIps"] = ips

                _ = try await client.graphql(
                    query: AdminDocuments.adminUpdateAPIKey,
                    variables: ["id": item.id, "input": inputObj]
                )
                dismiss()
                onUpdated()
            } catch {
                self.error = error.localizedDescription
                busy = false
            }
        }
    }
}

/// Reveal secret once after creation or rotation with one-tap copy.
struct APIKeySecretRevealSheet: View {
    let name: String
    let secret: String
    let onDismiss: () -> Void

    @State private var copied = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.green)

                VStack(spacing: 8) {
                    Text(NSLocalizedString("新 API 密钥已就绪", comment: ""))
                        .font(.title2)
                        .fontWeight(.bold)
                    Text(name)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text(NSLocalizedString("完整密钥内容（请立即妥善保存，关闭后将无法再次完整查看）：", comment: ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Text(secret)
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(4)
                            .textSelection(.enabled)
                        Spacer()
                    }
                    .padding(14)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    Button {
                        UIPasteboard.general.string = secret
                        copied = true
                        let generator = UINotificationFeedbackGenerator()
                        generator.notificationOccurred(.success)
                    } label: {
                        HStack {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            Text(copied ? NSLocalizedString("已复制到剪贴板", comment: "") : NSLocalizedString("一键复制密钥", comment: ""))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal)

                Spacer()
            }
            .padding(.top, 30)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("完成并关闭", comment: "")) {
                        onDismiss()
                    }
                }
            }
        }
    }
}
