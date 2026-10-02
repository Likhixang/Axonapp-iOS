import SwiftUI
import UIKit

/// Native representation of a project item
struct ProjectListItem: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let description: String
    let status: String
    let createdAt: String
    let updatedAt: String
    let activeProfile: String?

    var isEnabled: Bool { status.lowercased() == "enabled" }

    static func from(json: JSON) -> ProjectListItem {
        ProjectListItem(
            id: json["id"].string,
            name: json["name"].string.isEmpty ? NSLocalizedString("未命名项目", comment: "") : json["name"].string,
            description: json["description"].string,
            status: json["status"].string.isEmpty ? "enabled" : json["status"].string,
            createdAt: json["createdAt"].string,
            updatedAt: json["updatedAt"].string,
            activeProfile: json["profiles"]["activeProfile"].string
        )
    }
}

/// Project management list view
struct ProjectsListView: View {
    @ObservedObject var store: AxonStore

    @State private var projects: [ProjectListItem] = []
    @State private var loading = false
    @State private var errorMessage: String? = nil
    @State private var search = ""
    @State private var showingCreate = false
    @State private var editingItem: ProjectListItem? = nil
    @State private var deletingItem: ProjectListItem? = nil
    @State private var managingUsersProject: ProjectListItem? = nil
    @State private var invitingProject: ProjectListItem? = nil

    var filteredProjects: [ProjectListItem] {
        projects.filter { item in
            guard !search.isEmpty else { return true }
            return item.name.localizedCaseInsensitiveContains(search) || item.id.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        List {
            if let err = errorMessage {
                Section {
                    Text(err).font(.caption).foregroundStyle(.orange)
                }
            }

            if loading && projects.isEmpty {
                Section {
                    HStack {
                        Spacer()
                        ProgressView(NSLocalizedString("正在读取项目列表...", comment: ""))
                        Spacer()
                    }
                    .padding(.vertical, 20)
                }
            } else if projects.isEmpty && !loading {
                Section {
                    Text(NSLocalizedString("暂无可用项目", comment: "")).foregroundStyle(.secondary)
                }
            } else {
                ForEach(filteredProjects) { proj in
                    ProjectCardView(
                        project: proj,
                        canManage: store.canManage,
                        onEdit: { editingItem = proj },
                        onManageUsers: { managingUsersProject = proj },
                        onInvite: { invitingProject = proj },
                        onDelete: { deletingItem = proj }
                    )
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.plain)
        .searchable(text: $search, prompt: NSLocalizedString("搜索项目名称或 ID", comment: ""))
        .navigationTitle(NSLocalizedString("项目空间", comment: ""))
        .refreshable { await loadData() }
        .task { await loadData() }
        .toolbar {
            if store.canManage {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingCreate = true
                    } label: {
                        Label(NSLocalizedString("新建项目", comment: ""), systemImage: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showingCreate) {
            ProjectEditorSheet(store: store, existing: nil) {
                await loadData()
            }
        }
        .sheet(item: $editingItem) { item in
            ProjectEditorSheet(store: store, existing: item) {
                await loadData()
            }
        }
        .sheet(item: $managingUsersProject) { item in
            NavigationStack {
                ProjectUsersSheetView(store: store, project: item)
            }
        }
        .sheet(item: $invitingProject) { item in
            NavigationStack {
                ProjectInvitationContainerView(store: store, projectID: item.id)
            }
        }
        .confirmationDialog(
            NSLocalizedString("删除项目", comment: ""),
            isPresented: Binding(get: { deletingItem != nil }, set: { if !$0 { deletingItem = nil } }),
            titleVisibility: .visible
        ) {
            Button(NSLocalizedString("永久删除", comment: ""), role: .destructive) {
                if let item = deletingItem {
                    deleteProject(item: item)
                }
            }
            Button(NSLocalizedString("取消", comment: ""), role: .cancel) {
                deletingItem = nil
            }
        } message: {
            Text(NSLocalizedString("将永久删除该项目及其配置，该操作无法撤销。确定继续吗？", comment: ""))
        }
    }

    private func loadData() async {
        guard !loading else { return }
        loading = true
        errorMessage = nil
        defer { loading = false }

        do {
            let client = try store.ensureClient()
            guard store.canManage else { return }

            let variables: [String: Any] = [
                "first": 100,
                "orderBy": ["direction": "DESC", "field": "CREATED_AT"]
            ]

            let resp = try await client.graphql(
                query: AdminDocuments.adminGetProjects,
                variables: variables
            )

            let edges = resp["projects"]["edges"].array
            projects = edges.map { ProjectListItem.from(json: $0["node"]) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteProject(item: ProjectListItem) {
        Task {
            do {
                let client = try store.ensureClient()
                _ = try await client.graphql(
                    query: AdminDocuments.adminDeleteProject,
                    variables: ["id": item.id]
                )
                deletingItem = nil
                await loadData()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// Project Card View
struct ProjectCardView: View {
    let project: ProjectListItem
    let canManage: Bool
    let onEdit: () -> Void
    let onManageUsers: () -> Void
    let onInvite: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(project.name)
                        .font(.headline)
                        .fontWeight(.semibold)

                }

                Spacer()

                Text(NativeAdminLabels.value(project.status))
                    .font(.caption2)
                    .fontWeight(.bold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(project.isEnabled ? Color.green.opacity(0.12) : Color.gray.opacity(0.12))
                    .foregroundStyle(project.isEnabled ? .green : .secondary)
                    .clipShape(Capsule())
            }

            if !project.description.isEmpty {
                Text(project.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let profile = project.activeProfile, !profile.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "slider.horizontal.2.square")
                        .font(.caption2)
                    Text(String(format: NSLocalizedString("生效配置: %@", comment: ""), profile))
                        .font(.caption2)
                }
                .foregroundStyle(.blue)
            }

            if canManage {
                Divider()

                HStack {
                    Button(action: onEdit) {
                        Label(NSLocalizedString("编辑", comment: ""), systemImage: "pencil")
                    }
                    Button(action: onManageUsers) {
                        Label(NSLocalizedString("成员", comment: ""), systemImage: "person.2")
                    }
                    Button(action: onInvite) {
                        Label(NSLocalizedString("邀请", comment: ""), systemImage: "link")
                    }
                    Spacer()
                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel(NSLocalizedString("删除项目", comment: ""))
                }
                .buttonStyle(NeutralActionStyle())
                .controlSize(.regular)
            }
        }
        .padding(14)
        .liquidGlass()
    }
}

/// Project Editor Sheet
struct ProjectEditorSheet: View {
    @ObservedObject var store: AxonStore
    let existing: ProjectListItem?
    let onSaved: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var descriptionText: String = ""
    @State private var saving: Bool = false
    @State private var errorMessage: String? = nil

    private var isEditing: Bool { existing != nil }

    init(store: AxonStore, existing: ProjectListItem?, onSaved: @escaping () async -> Void) {
        self.store = store
        self.existing = existing
        self.onSaved = onSaved
        _name = State(initialValue: existing?.name ?? "")
        _descriptionText = State(initialValue: existing?.description ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                if let err = errorMessage {
                    Section {
                        Text(err).font(.caption).foregroundStyle(.red)
                    }
                }

                Section(NSLocalizedString("基本信息", comment: "")) {
                    TextField(NSLocalizedString("项目名称", comment: ""), text: $name)
                    TextField(NSLocalizedString("描述（可选）", comment: ""), text: $descriptionText, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle(isEditing ? NSLocalizedString("编辑项目", comment: "") : NSLocalizedString("新建项目", comment: ""))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("取消", comment: "")) {
                        dismiss()
                    }
                    .disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("保存", comment: "")) {
                        save()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || saving)
                }
            }
        }
    }

    private func save() {
        guard !saving else { return }
        saving = true
        errorMessage = nil

        Task {
            do {
                let client = try store.ensureClient()
                let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                let cleanDesc = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)

                if let item = existing {
                    let input: [String: Any] = [
                        "name": cleanName,
                        "description": cleanDesc
                    ]
                    _ = try await client.graphql(
                        query: AdminDocuments.adminUpdateProject,
                        variables: ["id": item.id, "input": input]
                    )
                } else {
                    let input: [String: Any] = [
                        "name": cleanName,
                        "description": cleanDesc
                    ]
                    _ = try await client.graphql(
                        query: AdminDocuments.adminCreateProject,
                        variables: ["input": input]
                    )
                }

                await onSaved()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                saving = false
            }
        }
    }
}

/// Project Users Management Sheet
struct ProjectUsersSheetView: View {
    @ObservedObject var store: AxonStore
    let project: ProjectListItem
    @Environment(\.dismiss) private var dismiss

    @State private var users: [JSON] = []
    @State private var loading = false
    @State private var errorMessage: String? = nil

    var body: some View {
        List {
            if let err = errorMessage {
                Section {
                    Text(err).font(.caption).foregroundStyle(.orange)
                }
            }

            if loading && users.isEmpty {
                Section {
                    HStack {
                        Spacer()
                        ProgressView(NSLocalizedString("正在读取成员列表...", comment: ""))
                        Spacer()
                    }
                    .padding(.vertical, 20)
                }
            } else if users.isEmpty && !loading {
                Section {
                    Text(NSLocalizedString("暂无项目成员", comment: "")).foregroundStyle(.secondary)
                }
            } else {
                ForEach(users, id: \.self) { u in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(u["user"]["email"].string.isEmpty ? u["userID"].string : u["user"]["email"].string)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Spacer()
                            if !u["role"]["name"].string.isEmpty {
                                Text(u["role"]["name"].string)
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.12))
                                    .foregroundStyle(.blue)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle(String(format: NSLocalizedString("项目成员 - %@", comment: ""), project.name))
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(NSLocalizedString("完成", comment: "")) {
                    dismiss()
                }
            }
        }
        .task { await loadUsers() }
    }

    private func loadUsers() async {
        guard !loading else { return }
        loading = true
        errorMessage = nil
        defer { loading = false }

        do {
            let client = try store.ensureClient()
            let variables: [String: Any] = [
                "first": 100,
                "where": ["projectID": project.id]
            ]
            let resp = try await client.adminScopedGraphql(
                query: AdminDocuments.adminProjectUsers,
                variables: variables,
                projectID: project.id
            )
            let edges = resp["projectUsers"]["edges"].array
            users = edges.map { $0["node"] }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Container for AdminInvitationView
struct ProjectInvitationContainerView: View {
    @ObservedObject var store: AxonStore
    let projectID: String
    @Environment(\.dismiss) private var dismiss

    @State private var session: AdminSession? = nil
    @State private var failure: String? = nil

    var body: some View {
        Group {
            if let sess = session {
                AdminInvitationView(session: sess)
            } else if let fail = failure {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(fail)
                }
                .padding()
            } else {
                ProgressView()
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(NSLocalizedString("关闭", comment: "")) {
                    dismiss()
                }
            }
        }
        .task {
            do {
                let schema = try AdminSchema.loaded.get()
                session = try AdminSession(store: store, schema: schema, projectID: projectID)
            } catch {
                failure = error.localizedDescription
            }
        }
    }
}
