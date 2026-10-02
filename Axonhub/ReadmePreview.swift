#if DEBUG && targetEnvironment(simulator)
import Foundation

/// Offline data used only by the documentation screenshot UI test.
@MainActor enum ReadmePreview {
    static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("--readme-preview") }
    static func makeStore() -> AxonStore {
        guard enabled else { return AxonStore() }
        let defaults = UserDefaults(suiteName: "ReadmePreview-" + UUID().uuidString)!
        let instance = AxonInstance(id: "readme-preview", name: "AxonHub", address: "https://preview.invalid")
        defaults.set(try! JSONEncoder().encode([instance]), forKey: "axon_instances")
        defaults.set(instance.id, forKey: "axon_selected_id")
        let dependencies = AxonStoreDependencies(
            loadCredential: { _ in "[REDACTED]" },
            saveCredential: { _, _ in }, deleteCredential: { _ in },
            authenticate: { _, _ in throw AxonAPIError.forbidden },
            fetchSnapshot: { try await $0.fetchSnapshot() })
        return AxonStore(defaults: defaults, dependencies: dependencies)
    }
    static var configuration: URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ReadmePreviewProtocol.self]
        return config
    }
}

final class ReadmePreviewProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        guard request.url?.host == "preview.invalid", let body = request.httpBody ?? bodyFromStream(),
              let payload = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let query = payload["query"] as? String,
              let data = Self.response(query) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL)); return
        }
        let bytes = try! JSONSerialization.data(withJSONObject: ["data": data])
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: bytes)
        client?.urlProtocolDidFinishLoading(self)
    }
    private func bodyFromStream() -> Data? {
        guard let stream = request.httpBodyStream else { return nil }
        stream.open(); defer { stream.close() }
        var body = Data(), buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count >= 0 else { return nil }
            if count == 0 { break }
            body.append(contentsOf: buffer.prefix(count))
        }
        return body
    }
    private static let channels: [[String: Any]] = [
        channel("openai", "OpenAI", "openai", "https://api.openai.com/v1", ["gpt-4.1", "gpt-4.1-mini", "o3"]),
        channel("anthropic", "Anthropic", "anthropic", "https://api.anthropic.com", ["claude-sonnet-4", "claude-opus-4"]),
        channel("gemini", "Google Gemini", "gemini", "https://generativelanguage.googleapis.com", ["gemini-2.5-pro", "gemini-2.5-flash"]),
        channel("deepseek", "DeepSeek", "deepseek", "https://api.deepseek.com", ["deepseek-chat", "deepseek-reasoner"])
    ]
    private static func channel(_ id: String, _ name: String, _ type: String, _ url: String, _ models: [String]) -> [String: Any] {
        ["id": id, "name": name, "type": type, "baseURL": url, "status": "enabled",
         "supportedModels": models, "orderingWeight": 1, "tags": [], "errorMessage": NSNull(),
         "autoDisabledAt": NSNull(), "remark": NSNull()]
    }
    private static let models: [[String: Any]] = [
        model("gpt-4.1", "GPT-4.1", "OpenAI", "openai"),
        model("claude-sonnet-4", "Claude Sonnet 4", "Anthropic", "anthropic"),
        model("gemini-2.5-pro", "Gemini 2.5 Pro", "Google", "gemini"),
        model("deepseek-chat", "DeepSeek V3", "DeepSeek", "deepseek")
    ]
    private static func model(_ id: String, _ name: String, _ developer: String, _ icon: String) -> [String: Any] {
        ["id": id, "modelID": id, "name": name, "developer": developer, "type": "chat",
         "group": "", "icon": icon, "status": "enabled", "remark": NSNull()]
    }
    private static var modelPage: [String: Any] {
        ["edges": models.map { ["node": $0] }, "totalCount": models.count,
         "pageInfo": ["hasNextPage": false, "endCursor": NSNull()]]
    }
    private static let overview: [String: Any] = [
        "totalRequests": 128640, "failedRequests": 214, "averageResponseTime": 842,
        "requestStats": ["requestsToday": 2486, "requestsThisWeek": 16942, "requestsLastWeek": 15328, "requestsThisMonth": 72480]
    ]
    private static let totals: [String: Any] = ["totalTokens": 3840000, "totalInputTokens": 2980000,
        "totalOutputTokens": 860000, "totalCost": 12.48]
    private static let health: [[String: Any]] = [
        ["channelName": "OpenAI", "channelType": "openai", "channelDisabled": false, "successCount": 1075, "failedCount": 3, "totalCount": 1078, "successRate": 99.72],
        ["channelName": "Anthropic", "channelType": "anthropic", "channelDisabled": false, "successCount": 842, "failedCount": 2, "totalCount": 844, "successRate": 99.76],
        ["channelName": "Google Gemini", "channelType": "gemini", "channelDisabled": false, "successCount": 388, "failedCount": 1, "totalCount": 389, "successRate": 99.74],
        ["channelName": "DeepSeek", "channelType": "deepseek", "channelDisabled": false, "successCount": 174, "failedCount": 1, "totalCount": 175, "successRate": 99.43]
    ]
    private static var daily: [[String: Any]] {
        let counts = [1842, 2176, 1954, 2630, 2288, 2964, 2486]
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        return counts.enumerated().map { index, count in
            let date = Calendar.current.date(byAdding: .day, value: index - 6, to: Date())!
            return ["date": formatter.string(from: date), "count": count, "tokens": count * 1500, "cost": Double(count) * 0.005]
        }
    }
    private static func response(_ query: String) -> [String: Any]? {
        // Reject unknown operations and every mutation instead of reaching a network.
        if query.contains("mutation ") { return nil }
        if query.contains("query AxonOverview") {
            return ["dashboardOverview": overview, "tokenStats": [:], "allChannelSummarys": channels,
                    "models": modelPage, "requests": ["edges": []], "apiKeys": ["edges": []]]
        }
        if query.contains("query ModelAllPages") { return ["models": modelPage] }
        if query.contains("query ObserveDashboardStats") { return ["dashboardOverview": overview] }
        if query.contains("query ObserveAnalyticsOverview") { return ["analyticsOverview": totals] }
        if query.contains("query ObserveDailyRequestStats") { return ["dailyRequestStats": daily] }
        if query.contains("query ObserveRequestsByChannel") {
            return ["requestStatsByChannel": health.map { ["channelName": $0["channelName"]!, "count": $0["totalCount"]!] }]
        }
        if query.contains("query ObserveChannelSuccessRates") { return ["channelSuccessRates": health] }
        if query.contains("query ObserveFastestChannels") {
            return ["fastestChannels": [["channelName": "DeepSeek", "throughput": 92.4],
                ["channelName": "Google Gemini", "throughput": 78.6], ["channelName": "OpenAI", "throughput": 64.2]]]
        }
        return nil
    }
}
#endif
