import SwiftUI

extension AxonClient {
    func channelDiagnostics(id: String) async throws -> JSON {
        let query = """
        query ChannelDiagnostics($id: ID!) { channels(first: 1, where: {id: $id}) { edges { node { id liveLimiterStats { inFlight waiting capacity queueSize } providerQuotaStatus { id updatedAt providerType status nextResetAt ready nextCheckAt quotaData } allModelEntries { requestModel actualModel source } } } } }
        """
        let result = try await graphql(query: query, variables: ["id": id])["channels"]["edges"].array.first?["node"]
        guard let result = result, result["id"].string == id else { throw AxonAPIError.invalidResponse }
        return result
    }
    func resetManagedChannelQuota(id: String) async throws {
        let mutation = """
        mutation ChannelQuotaReset($id: ID!) { resetChannelQuotaNow(channelID: $id) }
        """
        guard try await graphql(query: mutation, variables: ["id": id])["resetChannelQuotaNow"].bool else { throw ManagementError.verification }
    }
    func channelTestHistory(id: String, after: String?) async throws -> JSON {
        let query = """
        query ChannelTestHistory($id: ID!, $after: Cursor) { requests(first: 50, after: $after, where: {channelID: $id, sourceIn: [test]}, orderBy: {field: CREATED_AT, direction: DESC}) { edges { node { id createdAt modelID status metricsLatencyMs } } pageInfo { hasNextPage endCursor } totalCount } }
        """
        var vars: [String: Any] = ["id": id]; if let after = after { vars["after"] = after }
        return try await graphql(query: query, variables: vars)["requests"]
    }
}

struct ChannelDiagnosticsView: View {
    @ObservedObject var store: AxonStore
    let target: ManagementTarget
    @State private var diagnostics: JSON = .object([:])
    @State private var history: [JSON] = []
    @State private var next: String?
    @State private var busy = false
    @State private var confirmation = false
    @State private var message: String?
    @StateObject private var observation = ObservabilitySession()
    var body: some View {
        List {
            Text(target.instance.name)
            Section("并发限制") {
                let limiter = diagnostics["liveLimiterStats"]
                Text("执行中：\(limiter["inFlight"].int) · 等待：\(limiter["waiting"].int)")
                Text("容量：\(limiter["capacity"].int) · 队列：\(limiter["queueSize"].int)")
            }
            Section("供应商配额") {
                let q = diagnostics["providerQuotaStatus"]
                Text(NativeAdminLabels.value(q["providerType"].string) + " · " + NativeAdminLabels.value(q["status"].string))
                Text(obsText("下次重置：") + NativeDisplay.date(q["nextResetAt"].string))
                Text(obsText("下次检查：") + NativeDisplay.date(q["nextCheckAt"].string))
                NavigationLink("配额详情") { ObservabilityJSONView(value: ObservabilityRedaction.clean(q["quotaData"])).navigationTitle("供应商配额") }
                Button("重置配额") { confirmation = true }
            }
            Section("模型映射") {
                ForEach(Array(diagnostics["allModelEntries"].array.enumerated()), id: \.offset) { _, row in
                    Text(row["requestModel"].string + " → " + row["actualModel"].string + " · " + NativeAdminLabels.value(row["source"].string))
                }
            }
            Section("测试记录") {
                Button("载入测试记录") { loadHistory(reset: true) }
                ForEach(history, id: \.channelHistoryID) { row in
                    NavigationLink(row["modelID"].string + " · " + NativeAdminLabels.value(row["status"].string) + " · " + NativeDisplay.date(row["createdAt"].string)) {
                        ObservabilityDetailView(store: store, kind: .requests, id: row["id"].string, origin: observation)
                    }
                }
                if next != nil { Button("加载更多") { loadHistory(reset: false) } }
            }
            if let message = message { Text(message).font(.caption) }
        }.navigationTitle("渠道诊断").disabled(busy || store.managementBusy)
        .task { await reload(); do { try observation.bind(store, expected: target.instance) } catch { message = error.localizedDescription } }
        .confirmationDialog("确认重置配额", isPresented: $confirmation, titleVisibility: .visible) {
            Button("重置") { Task { busy = true; defer { busy = false }; do {
                let cli = try store.beginManagement(target); defer { store.endManagement() }
                guard let id = target.entityID else { throw ManagementError.changedTarget }
                try await cli.resetManagedChannelQuota(id: id)
                diagnostics = try await cli.channelDiagnostics(id: id)
                try store.validateTarget(target)
                message = obsText("重置已提交，配额采集需等待上游更新。")
            } catch { message = error.localizedDescription } } }
        } message: { Text(target.instance.name + " · " + target.instance.address) }
    }
    @MainActor private func reload() async {
        busy = true; defer { busy = false }
        do { guard let id = target.entityID else { throw ManagementError.changedTarget }; let result = try await store.managementClient(target).channelDiagnostics(id: id); try store.validateTarget(target); diagnostics = result }
        catch { message = error.localizedDescription }
    }
    private func loadHistory(reset: Bool) {
        busy = true
        Task { defer { busy = false }; do {
            guard let id = target.entityID else { throw ManagementError.changedTarget }
            let page = try await store.managementClient(target).channelTestHistory(id: id, after: reset ? nil : next)
            try store.validateTarget(target)
            guard case .array = page["edges"], case .bool = page["pageInfo"]["hasNextPage"] else { throw AxonAPIError.invalidResponse }
            let rows = page["edges"].array.map { $0["node"] }
            history = reset ? rows : history + rows
            next = page["pageInfo"]["hasNextPage"].bool ? page["pageInfo"]["endCursor"].string : nil
        } catch { message = error.localizedDescription } }
    }
}
private extension JSON { var channelHistoryID: String { self["id"].string } }
