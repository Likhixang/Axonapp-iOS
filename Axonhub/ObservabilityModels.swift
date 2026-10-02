import Foundation
import SwiftUI
import Combine

func obsText(_ key: String) -> String { NSLocalizedString(key, comment: "Observability") }

enum ObservabilityKind: String, CaseIterable, Identifiable {
    case requests, traces, threads, usage
    var id: String { rawValue }
    var title: String {
        switch self {
        case .requests: return obsText("请求审计")
        case .traces: return obsText("追踪")
        case .threads: return obsText("会话线程")
        case .usage: return obsText("用量日志")
        }
    }
    var root: String { self == .usage ? "usageLogs" : rawValue }
}

struct ObservabilityRecord: Identifiable {
    let value: JSON
    var id: String { value["id"].string }
    var title: String {
        for key in ["modelID", "name", "title"] {
            if !value[key].string.isEmpty { return value[key].string }
        }
        return NativeDisplay.date(value["createdAt"].string)
    }
}

/// Never transport an old screen's action to a newly selected instance or credential.
@MainActor
final class ObservabilitySession: ObservableObject {
    @Published var busy = false
    @Published var error: String?
    @Published var invalidated = false
    private(set) var instance: AxonInstance?
    private var credential: String?
    private var generation = UUID()

    func bind(_ store: AxonStore, expected: AxonInstance? = nil) throws {
        guard let instance = store.selectedInstance else { throw AxonAPIError.invalidURL }
        guard expected == nil || instance == expected else { invalidate(); throw AxonAPIError.invalidResponse }
        guard instance.authType == .adminJWT else { throw AxonAPIError.forbidden }
        let client = try store.ensureClient()
        self.instance = instance
        credential = client.token
        invalidated = false
    }

    func invalidate() {
        generation = UUID()
        invalidated = true
        busy = false
        error = obsText("实例或凭据已改变，请返回并重新打开。")
    }

    func checkedClient(_ store: AxonStore) throws -> AxonClient {
        guard !invalidated, let instance = instance, instance == store.selectedInstance else {
            invalidate()
            throw AxonAPIError.invalidResponse
        }
        let client = try store.ensureClient()
        guard credential == client.token else {
            invalidate()
            throw AxonAPIError.invalidCredentials
        }
        return client
    }

    /// Assignment occurs only after read-back and a fresh instance/credential check.
    func read(_ store: AxonStore, query: (AxonClient) async throws -> JSON) async -> JSON? {
        guard !busy, !invalidated else { return nil }
        busy = true
        error = nil
        let ticket = UUID()
        generation = ticket
        defer { if generation == ticket { busy = false } }
        do {
            let client = try checkedClient(store)
            let value = try await query(client)
            try Task.checkCancellation()
            _ = try checkedClient(store)
            guard generation == ticket else { return nil }
            return value
        } catch {
            guard generation == ticket, !(error is CancellationError) else { return nil }
            self.error = invalidated ? obsText("实例或凭据已改变，请返回并重新打开。") : (error as? AxonAPIError)?.localizedDescription ?? AxonAPIError.transport.localizedDescription
            return nil
        }
    }

    func sanitize(_ value: JSON) -> JSON {
        ObservabilityRedaction.clean(value, credential: credential ?? "")
    }
}

enum ObservabilityRedaction {
    static func clean(_ value: JSON, credential: String = "") -> JSON {
        switch value {
        case .object(let dictionary):
            // Hide every header value, not just a known list; providers use arbitrary credential headers.
            if dictionary["key"] != nil, dictionary["value"] != nil {
                return .object(["key": clean(dictionary["key"] ?? .null, credential: credential), "value": .string("[REDACTED]")])
            }
            var out: [String: JSON] = [:]
            for (key, item) in dictionary {
                let normalized = key.lowercased().filter { $0.isLetter || $0.isNumber }
                if ["apikeyid", "apikeyids"].contains(normalized) {
                    out[key] = item
                } else if ["requestheaders", "responseheaders", "headers", "authorization", "proxyauthorization", "cookie", "setcookie", "token", "auth", "authentication"].contains(normalized)
                    || ["password", "secret", "credential", "apikey", "accesstoken", "refreshtoken"].contains(where: { normalized.contains($0) }) {
                    out[key] = .string("[REDACTED]")
                } else if normalized.hasSuffix("url"), !item.string.isEmpty, var url = URLComponents(string: item.string) {
                    url.user = nil; url.password = nil; url.query = nil; url.fragment = nil
                    out[key] = .string(url.string ?? "[REDACTED]")
                } else { out[key] = clean(item, credential: credential) }
            }
            return .object(out)
        case .array(let array): return .array(array.map { clean($0, credential: credential) })
        case .string(var text):
            // Some JSON scalars are returned as encoded strings by external storage resolvers.
            if let decoded = JSON.from(text), case .object = decoded { return clean(decoded, credential: credential) }
            if let decoded = JSON.from(text), case .array = decoded { return clean(decoded, credential: credential) }
            if !credential.isEmpty { text = text.replacingOccurrences(of: credential, with: "[REDACTED]") }
            for pattern in [
                #"(?i)\b(?:Bearer|Basic)\s+[A-Za-z0-9._~+/=-]+"#,
                #"(?i)(?:authorization|proxy-authorization|cookie|set-cookie|x-api-key|api[-_]?key|password|secret|access[-_]?token|refresh[-_]?token)\s*[=:]\s*[^\r\n,;]+"#,
                #"\bsk-[A-Za-z0-9_-]{8,}"#,
                #"\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+"#
            ] {
                text = text.replacingOccurrences(of: pattern, with: "[REDACTED]", options: .regularExpression)
            }
            return .string(text)
        default: return value
        }
    }
    static func printable(_ value: JSON) -> String {
        if case .string(let text) = value { return text }
        guard let data = try? JSONEncoder().encode(value),
              let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]) else { return "—" }
        return String(decoding: pretty, as: UTF8.self)
    }
}

struct ObservabilityFilters {
    var search = ""
    var statuses: Set<String> = []
    var sources: Set<String> = []
    var projects = ""
    var channels = ""
    var apiKeys = ""
    var clientIP = ""
    var format = ""
    var externalID = ""
    var stream = "all"
    var useDateRange = false
    var start = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    var end = Date()
    var ascending = false
    var size = 25

    func identifiers(_ text: String) -> [String] {
        text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
    func whereInput(_ kind: ObservabilityKind) throws -> [String: Any] {
        var result: [String: Any] = [:]
        if useDateRange {
            guard start <= end else { throw AxonAPIError.invalidResponse }
            result["createdAtGTE"] = ISO8601DateFormatter().string(from: start)
            result["createdAtLTE"] = ISO8601DateFormatter().string(from: end)
        }
        if !statuses.isEmpty && kind != .usage { result["statusIn"] = statuses.sorted() }
        if !projects.isEmpty { result["projectIDIn"] = identifiers(projects) }
        if kind == .requests || kind == .usage {
            if !search.isEmpty { result["modelIDContainsFold"] = search }
            if !channels.isEmpty { result["channelIDIn"] = identifiers(channels) }
            if !apiKeys.isEmpty {
                let ids = identifiers(apiKeys)
                if kind == .usage {
                    let numbers = ids.compactMap(Int.init)
                    guard numbers.count == ids.count else { throw AxonAPIError.invalidResponse }
                    result["apiKeyIDIn"] = numbers
                } else { result["apiKeyIDIn"] = ids }
            }
            if !sources.isEmpty { result["sourceIn"] = sources.sorted() }
            if !format.isEmpty { result["formatContainsFold"] = format }
        } else if !search.isEmpty { result[kind == .traces ? "traceIDContainsFold" : "threadIDContainsFold"] = search }
        if kind == .requests {
            if !clientIP.isEmpty { result["clientIPContains"] = clientIP }
            if !externalID.isEmpty { result["externalIDContains"] = externalID }
            if stream != "all" { result["stream"] = stream == "yes" }
        }
        return result
    }
}

@MainActor
final class ObservabilityListModel: ObservableObject {
    @Published var records: [ObservabilityRecord] = []
    @Published var total: Int?
    @Published var next: String?
    @Published var filterError: String?
    let session = ObservabilitySession()
    private var cursors: [String?] = [nil]
    private var observation: AnyCancellable?
    @Published private(set) var page = 0

    init() {
        observation = session.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }

    func reset() {
        records = []; total = nil; next = nil; page = 0; cursors = [nil]; filterError = nil
    }
    func load(store: AxonStore, kind: ObservabilityKind, filters: ObservabilityFilters, move: Int = 0) async {
        if session.busy { return }
        do {
            let whereInput = try filters.whereInput(kind)
            if move == 0 { page = 0; cursors = [nil]; next = nil; filterError = nil }
            let requestedPage = max(0, page + move)
            var cursor: String?
            if move > 0 {
                guard let next = next else { return }
                cursor = next
            } else { cursor = cursors[requestedPage] }
            var variables: [String: Any] = ["first": filters.size, "where": whereInput, "order": ["field": "CREATED_AT", "direction": filters.ascending ? "ASC" : "DESC"]]
            if let cursor = cursor { variables["after"] = cursor }
            let keyData = try JSONSerialization.data(withJSONObject: variables, options: [.sortedKeys])
            let cacheKey = "audit/" + kind.rawValue + "/" + keyData.base64EncodedString()
            _ = try session.checkedClient(store)
            let cached = store.pageCache.value(cacheKey)
            let response: JSON?
            if let cached = cached { response = cached }
            else { response = await session.read(store) { client in
                switch kind {
                case .requests: return try await client.observeRequestPage(variables: variables)
                case .traces: return try await client.observeTracePage(variables: variables)
                case .threads: return try await client.observeThreadPage(variables: variables)
                case .usage: return try await client.observeUsageLogPage(variables: variables)
                }
            }
            }
            guard let response = response else { return }
            store.pageCache.save(session.sanitize(response), key: cacheKey)
            let connection = response[kind.root]
            guard !connection.isNull else { throw AxonAPIError.invalidResponse }
            records = connection["edges"].array.map { ObservabilityRecord(value: session.sanitize($0["node"])) }
            total = connection["totalCount"].int
            next = connection["pageInfo"]["hasNextPage"].bool ? connection["pageInfo"]["endCursor"].string : nil
            if requestedPage >= cursors.count { cursors.append(cursor) }
            page = requestedPage
            filterError = nil
        } catch { filterError = obsText("筛选条件无效，请检查日期范围与 ID。") }
    }
}
