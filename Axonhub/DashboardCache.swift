import Foundation
import Combine
import CryptoKit

/// App-owned stale-while-revalidate state. A tab's lifetime never owns the request.
@MainActor final class DashboardCacheModel: ObservableObject {
    struct Entry: Codable {
        var values: [String: JSON] = [:]
        var updated: Date?
    }
    @Published private(set) var values: [String: JSON] = [:]
    @Published private(set) var failures: [String: String] = [:]
    @Published private(set) var loading = false
    @Published private(set) var updated: Date?
    @Published var window = "day"
    @Published var distribution = "channel"
    @Published var trendMetric = "count"
    private let defaults: UserDefaults
    private var entries: [String: Entry] = [:]
    private var scope = ""
    private var autoRefreshed = Set<String>()
    private var task: Task<Void, Never>?
    private var ticket = UUID()
    private var activeVariant = ""
    private var refreshingVariant = ""
    private var variant: String { window + "/" + distribution }
    init(defaults: UserDefaults) { self.defaults = defaults }

    static func cacheKey(instance: AxonInstance, credential: String) -> String {
        // Partition by server, account and credential; the secret itself is never persisted.
        let identity = [instance.id, instance.address, instance.authType.rawValue, instance.adminEmail, credential].joined(separator: "\u{0}")
        return "axon_dashboard_v2_" + SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    func prepare(_ store: AxonStore) {
        do {
            guard let instance = store.selectedInstance, instance.authType == .adminJWT else { resetConnection(); return }
            let client = try store.ensureClient()
            let next = Self.cacheKey(instance: instance, credential: client.token)
            if next != scope {
                task?.cancel(); ticket = UUID(); task = nil; loading = false
                scope = next; activeVariant = ""; failures = [:]
                entries = defaults.data(forKey: next).flatMap { try? JSONDecoder().decode([String: Entry].self, from: $0) } ?? [:]
            }
            showVariant()
        } catch { resetConnection(); failures["connection"] = error.localizedDescription }
    }
    private func showVariant() {
        guard activeVariant != variant else { return }
        activeVariant = variant
        values = entries[variant]?.values ?? [:]
        updated = entries[variant]?.updated
        failures = [:]
    }
    func activate(_ store: AxonStore) {
        prepare(store)
        guard !scope.isEmpty else { return }
        let key = scope + "/" + variant
        guard !autoRefreshed.contains(key) else { return }
        autoRefreshed.insert(key)
        refresh(store)
    }
    func refresh(_ store: AxonStore) {
        prepare(store)
        guard !scope.isEmpty else { return }
        if loading && refreshingVariant == variant { return }
        task?.cancel()
        let generation = UUID(); ticket = generation
        let key = scope, selectedVariant = variant, selectedWindow = window, dimension = distribution
        loading = true; refreshingVariant = selectedVariant; failures = [:]
        task = Task { @MainActor [weak self, weak store] in
            guard let self = self, let store = store else { return }
            defer { if self.ticket == generation { self.loading = false; self.task = nil } }
            do {
                let instance = store.selectedInstance
                let client = try store.ensureClient()
                let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
                let now = Date(), calendar = Calendar.current
                let start = selectedWindow == "week" ? calendar.dateInterval(of: .weekOfYear, for: now)?.start : selectedWindow == "month" ? calendar.dateInterval(of: .month, for: now)?.start : calendar.startOfDay(for: now)
                let filter: [String: Any] = ["startTime": formatter.string(from: start ?? now), "endTime": formatter.string(from: now)]
                var succeeded = false
                @MainActor func capture(_ name: String, root: String, query: () async throws -> JSON) async {
                    guard !Task.isCancelled else { return }
                    do {
                        let data = try await query()
                        try Task.checkCancellation()
                        guard self.ticket == generation, self.scope == key, store.selectedInstance == instance,
                              try store.ensureClient().token == client.token, let value = data.object[root] else { return }
                        let safe = Self.safeStatistics(value)
                        var entry = self.entries[selectedVariant] ?? Entry()
                        entry.values[name] = safe
                        self.entries[selectedVariant] = entry
                        if self.variant == selectedVariant { self.values[name] = safe; self.failures[name] = nil }
                        succeeded = true
                    } catch {
                        if self.ticket == generation && !(error is CancellationError) && !Task.isCancelled { self.failures[name] = error.localizedDescription }
                    }
                }
                await capture("overview", root: "dashboardOverview") { try await client.observeDashboardStats() }
                await capture("totals", root: "analyticsOverview") { try await client.observeAnalyticsOverview(variables: ["filter": filter]) }
                await capture("daily", root: "dailyRequestStats") { try await client.observeDailyRequestStats() }
                await capture("distribution", root: dimension == "model" ? "requestStatsByModel" : dimension == "apiKey" ? "requestStatsByAPIKey" : "requestStatsByChannel") {
                    switch dimension {
                    case "model": return try await client.observeRequestsByModel(variables: ["timeWindow": selectedWindow])
                    case "apiKey": return try await client.observeRequestsByAPIKey(variables: ["timeWindow": selectedWindow])
                    default: return try await client.observeRequestsByChannel(variables: ["timeWindow": selectedWindow])
                    }
                }
                await capture("health", root: "channelSuccessRates") { try await client.observeChannelSuccessRates(variables: ["timeWindow": selectedWindow, "limit": NSNull()]) }
                await capture("performance", root: "fastestChannels") { try await client.observeFastestChannels(variables: ["input": ["timeWindow": selectedWindow, "limit": 5]]) }
                guard self.ticket == generation, self.scope == key, succeeded else { return }
                self.entries[selectedVariant]?.updated = Date()
                if self.variant == selectedVariant { self.updated = self.entries[selectedVariant]?.updated }
                if let data = try? JSONEncoder().encode(self.entries) { self.defaults.set(data, forKey: key) }
            } catch { if self.ticket == generation { self.failures["connection"] = error.localizedDescription } }
        }
    }
    func refreshAndWait(_ store: AxonStore) async { refresh(store); await task?.value }
    func resetConnection() {
        task?.cancel(); task = nil; ticket = UUID(); scope = ""; activeVariant = ""
        entries = [:]; values = [:]; failures = [:]; updated = nil; loading = false
    }
    /// Only aggregate metrics and display labels can reach disk, never payloads or secrets.
    static func safeStatistics(_ value: JSON) -> JSON {
        let keys: Set<String> = ["totalRequests", "failedRequests", "averageResponseTime", "requestStats", "requestsToday", "requestsThisWeek", "requestsLastWeek", "requestsThisMonth", "totalTokens", "totalInputTokens", "totalCachedInputTokens", "totalUncachedInputTokens", "totalOutputTokens", "totalCost", "date", "count", "tokens", "cost", "channelName", "modelId", "apiKeyName", "channelType", "channelDisabled", "successCount", "failedCount", "successRate", "totalCount", "throughput", "tokensCount", "latencyMs", "requestCount"]
        switch value {
        case .object(let fields): return .object(fields.filter { keys.contains($0.key) }.mapValues(safeStatistics))
        case .array(let items): return .array(items.map(safeStatistics))
        default: return value
        }
    }
}
