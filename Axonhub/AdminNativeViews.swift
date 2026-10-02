import SwiftUI
import UIKit

/// User representation parsed from GraphQL
struct UserListItem: Identifiable, Hashable, Sendable {
    let id: String
    let email: String
    let firstName: String
    let lastName: String
    let status: String
    let role: String
    let createdAt: String

    var isEnabled: Bool { status.lowercased() == "enabled" }

    var displayName: String {
        let full = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
        return full.isEmpty ? email : full
    }

    static func from(json: JSON) -> UserListItem {
        UserListItem(
            id: json["id"].string,
            email: json["email"].string,
            firstName: json["firstName"].string,
            lastName: json["lastName"].string,
            status: json["status"].string.isEmpty ? "enabled" : json["status"].string,
            role: json["role"]["name"].string,
            createdAt: json["createdAt"].string
        )
    }
}

/// Native Users and Roles Management View
struct UsersRolesView: View {
    @ObservedObject var store: AxonStore

    @State private var users: [UserListItem] = []
    @State private var loading = false
    @State private var errorMessage: String? = nil
    @State private var search = ""
    @State private var actionBusy = false

    var filteredUsers: [UserListItem] {
        users.filter { item in
            guard !search.isEmpty else { return true }
            return item.email.localizedCaseInsensitiveContains(search) ||
                   item.displayName.localizedCaseInsensitiveContains(search) ||
                   item.id.localizedCaseInsensitiveContains(search)
        }
    }

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
                        ProgressView(NSLocalizedString("正在读取用户列表...", comment: ""))
                        Spacer()
                    }
                    .padding(.vertical, 20)
                }
            } else if users.isEmpty && !loading {
                Section {
                    Text(NSLocalizedString("暂无用户", comment: "")).foregroundStyle(.secondary)
                }
            } else {
                ForEach(filteredUsers) { user in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(user.displayName)
                                    .font(.headline)
                                Text(user.email)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if store.canManage {
                                Toggle(NSLocalizedString("启用用户", comment: ""), isOn: Binding(
                                    get: { user.isEnabled },
                                    set: { toggleUserStatus(user: user, enabled: $0) }
                                ))
                                .labelsHidden()
                            } else {
                                Text(NativeAdminLabels.value(user.status))
                                    .font(.caption2)
                            }
                        }

                        HStack {
                            if !user.role.isEmpty {
                                Text(NativeAdminLabels.value(user.role))
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.12))
                                    .foregroundStyle(.blue)
                                    .clipShape(Capsule())
                            }
                            Spacer()

                        }
                    }
                    .padding(12)
                    .liquidGlass()
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.plain)
        .searchable(text: $search, prompt: NSLocalizedString("搜索用户邮箱、姓名或 ID", comment: ""))
        .navigationTitle(NSLocalizedString("用户管理", comment: ""))
        .refreshable { await loadUsers() }
        .task { await loadUsers() }
    }

    private func loadUsers() async {
        guard !loading else { return }
        loading = true
        errorMessage = nil
        defer { loading = false }

        do {
            let client = try store.ensureClient()
            guard store.canManage else { return }

            let variables: [String: Any] = [
                "first": 100
            ]

            let resp = try await client.graphql(
                query: AdminDocuments.adminAllUsers,
                variables: variables
            )

            let edges = resp["users"]["edges"].array
            users = edges.map { UserListItem.from(json: $0["node"]) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggleUserStatus(user: UserListItem, enabled: Bool) {
        guard !actionBusy else { return }
        actionBusy = true

        Task {
            defer { actionBusy = false }
            do {
                let client = try store.ensureClient()
                let targetStatus = enabled ? "enabled" : "disabled"
                _ = try await client.graphql(
                    query: AdminDocuments.adminUpdateUserStatus,
                    variables: ["id": user.id, "status": targetStatus]
                )
                await loadUsers()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// Native Prompt Protection Rule representation
struct ProtectionRuleItem: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let description: String
    let isEnabled: Bool
    let action: String

    static func from(json: JSON) -> ProtectionRuleItem {
        ProtectionRuleItem(
            id: json["id"].string,
            name: json["name"].string.isEmpty ? NSLocalizedString("未命名规则", comment: "") : json["name"].string,
            description: json["description"].string,
            isEnabled: json["status"].string.lowercased() == "enabled",
            action: json["action"].string
        )
    }
}

/// Prompt Protection Rules list view
struct PromptProtectionRulesView: View {
    @ObservedObject var store: AxonStore

    @State private var rules: [ProtectionRuleItem] = []
    @State private var loading = false
    @State private var errorMessage: String? = nil
    @State private var search = ""
    @State private var actionBusy = false

    var filteredRules: [ProtectionRuleItem] {
        rules.filter { item in
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

            if loading && rules.isEmpty {
                Section {
                    HStack {
                        Spacer()
                        ProgressView(NSLocalizedString("正在读取防护规则...", comment: ""))
                        Spacer()
                    }
                    .padding(.vertical, 20)
                }
            } else if rules.isEmpty && !loading {
                Section {
                    Text(NSLocalizedString("暂无防护规则", comment: "")).foregroundStyle(.secondary)
                }
            } else {
                ForEach(filteredRules) { rule in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(rule.name)
                                .font(.headline)
                            Spacer()
                            if store.canManage {
                                Toggle(NSLocalizedString("启用规则", comment: ""), isOn: Binding(
                                    get: { rule.isEnabled },
                                    set: { toggleRule(rule: rule, enabled: $0) }
                                ))
                                .labelsHidden()
                            }
                        }

                        if !rule.description.isEmpty {
                            Text(rule.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            Spacer()
                            if !rule.action.isEmpty {
                                Text(NativeAdminLabels.value(rule.action))
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                    .padding(12)
                    .liquidGlass()
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.plain)
        .searchable(text: $search, prompt: NSLocalizedString("搜索规则名称或 ID", comment: ""))
        .navigationTitle(NSLocalizedString("提示词防护", comment: ""))
        .refreshable { await loadRules() }
        .task { await loadRules() }
    }

    private func loadRules() async {
        guard !loading else { return }
        loading = true
        errorMessage = nil
        defer { loading = false }

        do {
            let client = try store.ensureClient()
            guard store.canManage else { return }

            let variables: [String: Any] = [
                "first": 50
            ]

            let resp = try await client.graphql(
                query: AdminDocuments.adminGetPromptProtectionRules,
                variables: variables
            )

            let edges = resp["promptProtectionRules"]["edges"].array
            rules = edges.map { ProtectionRuleItem.from(json: $0["node"]) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggleRule(rule: ProtectionRuleItem, enabled: Bool) {
        guard !actionBusy else { return }
        actionBusy = true

        Task {
            defer { actionBusy = false }
            do {
                let client = try store.ensureClient()
                let targetStatus = enabled ? "enabled" : "disabled"
                _ = try await client.graphql(
                    query: AdminDocuments.adminUpdatePromptProtectionRuleStatus,
                    variables: ["id": rule.id, "status": targetStatus]
                )
                await loadRules()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
