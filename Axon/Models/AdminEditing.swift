import Foundation

// MARK: - Roles

/// A role as the user and role dialogs list it.
struct RoleItem: Decodable, Hashable, Sendable, Identifiable {
    let id: String
    let name: String
    let level: String?
    let scopes: [String]?
    var createdAt: Date? = nil
}

/// A user with the roles and scopes the edit dialog needs.
struct UserDetail: Decodable, Hashable, Sendable, Identifiable {
    let id: String
    let email: String
    let firstName: String?
    let lastName: String?
    let isOwner: Bool
    let scopes: [String]?
    let roles: RoleEdges?

    struct RoleEdges: Decodable, Hashable, Sendable {
        struct Edge: Decodable, Hashable, Sendable { let node: RoleItem? }
        let edges: [Edge]?
    }

    var roleIDs: [String] { roles?.edges?.compactMap(\.node?.id) ?? [] }
}

/// Builds the user dialog's inputs the way `users-action-dialog.tsx` does.
enum UserEditor {
    static func validationError(isEditing: Bool, email: String, password: String, confirm: String) -> String? {
        let email = email.trimmed
        if email.isEmpty || !email.contains("@") { return "请填写有效的邮箱" }
        if !isEditing {
            if password.count < 6 { return "密码至少 6 位" }
            if password != confirm { return "两次输入的密码不一致" }
        }
        return nil
    }

    static func createInput(firstName: String, lastName: String, email: String, password: String,
                            isOwner: Bool, scopes: [String], roleIDs: [String]) -> [String: JSONValue] {
        [
            "firstName": .string(firstName.trimmed),
            "lastName": .string(lastName.trimmed),
            "email": .string(email.trimmed),
            "password": .string(password),
            "isOwner": .bool(isOwner),
            "scopes": .strings(scopes),
            "roleIDs": .strings(roleIDs),
        ]
    }

    /// Role changes go out as add/remove lists, and only when there are any.
    static func updateInput(firstName: String, lastName: String, email: String, isOwner: Bool,
                            scopes: [String], roleIDs: [String], currentRoleIDs: [String]) -> [String: JSONValue] {
        var input: [String: JSONValue] = [
            "firstName": .string(firstName.trimmed),
            "lastName": .string(lastName.trimmed),
            "email": .string(email.trimmed),
            "isOwner": .bool(isOwner),
            "scopes": .strings(scopes),
        ]
        let added = roleIDs.filter { !currentRoleIDs.contains($0) }
        let removed = currentRoleIDs.filter { !roleIDs.contains($0) }
        if !added.isEmpty { input["addRoleIDs"] = .strings(added) }
        if !removed.isEmpty { input["removeRoleIDs"] = .strings(removed) }
        return input
    }
}

enum RoleEditor {
    static func createInput(name: String, scopes: [String]) -> [String: JSONValue] {
        ["name": .string(name.trimmed), "level": .string("system"), "scopes": .strings(scopes)]
    }

    static func updateInput(name: String, scopes: [String]) -> [String: JSONValue] {
        ["name": .string(name.trimmed), "scopes": .strings(scopes)]
    }
}

/// Toggling one value in a multi-select keeps the others in order.
enum MultiSelect {
    static func toggle(_ value: String, in values: [String]) -> [String] {
        values.contains(value) ? values.filter { $0 != value } : values + [value]
    }
}

// MARK: - Project profiles

struct ProjectProfile: Codable, Hashable, Sendable {
    var name: String
    var channelIDs: [Int]?
    var channelTags: [String]?
    var channelTagsMatchMode: String?
}

struct ProjectProfiles: Decodable, Hashable, Sendable {
    let activeProfile: String
    let profiles: [ProjectProfile]?
}

/// The project channel-access profiles dialog (`project-profiles-dialog.tsx`).
struct ProfilesDraft: Equatable, Sendable {
    struct Profile: Equatable, Sendable, Identifiable {
        var id = UUID()
        var name: String
        var channelIDs: [Int] = []
        var channelTags: [String] = []
        var matchMode = "any"
    }

    var profiles: [Profile] = []
    /// Empty means no restriction.
    var activeProfile = ""

    static let matchModes: [Choice] = [
        Choice(value: "any", label: "包含任一标签"),
        Choice(value: "all", label: "包含全部标签"),
        Choice(value: "none", label: "不包含任一标签"),
    ]

    init() {}

    init(_ stored: ProjectProfiles?) {
        profiles = (stored?.profiles ?? []).map { stored in
            let mode = stored.channelTagsMatchMode ?? "any"
            return Profile(name: stored.name, channelIDs: stored.channelIDs ?? [], channelTags: stored.channelTags ?? [],
                           matchMode: Self.matchModes.contains { $0.value == mode } ? mode : "any")
        }
        activeProfile = stored?.activeProfile ?? ""
    }

    /// New profiles are named "Profile N"; the first one added becomes active.
    mutating func addProfile() {
        let name = "Profile \(profiles.count + 1)"
        profiles.append(Profile(name: name))
        if activeProfile.isEmpty { activeProfile = name }
    }

    /// Removing the active profile activates the first remaining one.
    mutating func removeProfile(id: UUID) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        let removed = profiles.remove(at: index)
        if removed.name == activeProfile { activeProfile = profiles.first?.name ?? "" }
    }

    /// Renaming the active profile keeps it active.
    mutating func rename(id: UUID, to name: String) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        if profiles[index].name == activeProfile { activeProfile = name }
        profiles[index].name = name
    }

    var validationError: String? {
        if profiles.isEmpty { return "至少需要一个配置" }
        if profiles.contains(where: { $0.name.trimmed.isEmpty }) { return "配置名称不能为空" }
        let names = profiles.map { $0.name.trimmed.lowercased() }
        if Set(names).count != names.count { return "配置名称不能重复" }
        if !activeProfile.isEmpty && !profiles.contains(where: { $0.name == activeProfile }) { return "当前激活配置不在列表里" }
        return nil
    }

    var input: [String: JSONValue] {
        [
            "activeProfile": .string(activeProfile),
            "profiles": .array(profiles.map { profile in
                .object([
                    "name": .string(profile.name),
                    "channelIDs": .array(profile.channelIDs.map { .int($0) }),
                    "channelTags": .strings(profile.channelTags),
                    "channelTagsMatchMode": .string(profile.matchMode),
                ])
            }),
        ]
    }
}
