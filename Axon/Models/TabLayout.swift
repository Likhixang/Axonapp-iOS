import Foundation

/// Every page that can sit in the tab bar or in “更多”.
enum AppDestination: String, CaseIterable, Identifiable, Sendable {
    case dashboard, requests, channels, models, apiKeys, playground, guide, users, projects

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "概览"
        case .requests: return "请求日志"
        case .channels: return "渠道"
        case .models: return "模型"
        case .apiKeys: return "API 密钥"
        case .playground: return "对话测试"
        case .guide: return "接入指南"
        case .users: return "用户"
        case .projects: return "项目"
        }
    }

    /// Shorter label for the tab bar.
    var tabTitle: String {
        switch self {
        case .requests: return "请求"
        case .apiKeys: return "密钥"
        case .playground: return "对话"
        case .guide: return "接入"
        default: return title
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: return "chart.bar.xaxis"
        case .requests: return "list.bullet.rectangle"
        case .channels: return "server.rack"
        case .models: return "cpu"
        case .apiKeys: return "key"
        case .playground: return "bubble.left.and.text.bubble.right"
        case .guide: return "link"
        case .users: return "person.2"
        case .projects: return "folder"
        }
    }

    enum Requirement: Sendable { case any, admin, owner }

    var requirement: Requirement {
        switch self {
        case .channels: return .admin
        case .users, .projects: return .owner
        default: return .any
        }
    }

    static func available(isAdmin: Bool, isOwner: Bool) -> [AppDestination] {
        allCases.filter {
            switch $0.requirement {
            case .any: return true
            case .admin: return isAdmin || isOwner
            case .owner: return isOwner
            }
        }
    }
}

/// Which pages the user pinned to the tab bar, stored as a comma-separated string.
enum TabLayout {
    /// Pinned pages; “更多” always takes the last slot, so the iPhone bar never overflows.
    static let maxPinned = 4
    static let storageKey = "tabbar.pinned"

    static let defaultPinned: [AppDestination] = [.dashboard, .requests, .models, .apiKeys]
    /// Used to fill free slots when a default page is unavailable (e.g. no channel access).
    static let fillOrder: [AppDestination] = [.channels, .guide, .playground]

    static func encode(_ pinned: [AppDestination]) -> String { pinned.map(\.rawValue).joined(separator: ",") }

    static func decode(_ raw: String) -> [AppDestination] {
        raw.split(separator: ",").compactMap { AppDestination(rawValue: String($0).trimmingCharacters(in: .whitespaces)) }
    }

    /// Resolves the stored layout against what the user may open.
    static func resolve(stored: String, available: [AppDestination]) -> [AppDestination] {
        let allowed = Set(available)
        var seen = Set<AppDestination>()
        let chosen = decode(stored).filter { allowed.contains($0) && seen.insert($0).inserted }
        if !chosen.isEmpty { return Array(chosen.prefix(maxPinned)) }
        return defaults(available: available)
    }

    static func defaults(available: [AppDestination]) -> [AppDestination] {
        let allowed = Set(available)
        var result = defaultPinned.filter { allowed.contains($0) }
        for item in fillOrder where result.count < maxPinned && allowed.contains(item) && !result.contains(item) {
            result.append(item)
        }
        return result
    }

    /// Pages that are not pinned, in their natural order, for “更多”.
    static func unpinned(_ pinned: [AppDestination], available: [AppDestination]) -> [AppDestination] {
        available.filter { !pinned.contains($0) }
    }
}
