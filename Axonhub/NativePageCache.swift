import Foundation

/// App-owned, memory-only cache for public list/aggregate data. Never cache secrets,
/// editable drafts, request bodies, responses or authorized configuration reads.
@MainActor final class NativePageCache {
    private var entries: [String: JSON] = [:]
    private(set) var revision = UUID()
    func value(_ key: String) -> JSON? { entries[key] }
    func save(_ value: JSON, key: String) {
        if entries.count >= 128 && entries[key] == nil { entries.removeAll() }
        entries[key] = value
    }
    func invalidate() { revision = UUID(); entries.removeAll() }
}
