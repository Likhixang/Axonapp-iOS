import SwiftUI

struct ChannelDetailToolsView: View {
    @ObservedObject var store: AxonStore
    let target: ManagementTarget
    @State private var detail: JSON = .object([:])
    @State private var prices: JSON = .array([])
    @State private var selectedModels = Set<String>()
    @State private var message: String?
    @State private var busy = false
    @State private var confirmation = false
    @State private var uncertain = false
    @State private var pending = ""
    var body: some View {
        Form {
            Section("目标") { Text(target.instance.name); Text(store.snapshot.channels.first { $0.id == target.entityID }?.name ?? "—").font(.headline) }
            Section("模型测试") {
                Text("测试会向上游发送请求并消耗额度。").font(.caption)
                ForEach(detail["supportedModels"].array.map(\.string), id: \.self) { m in
                    Toggle(m, isOn: Binding(get: { selectedModels.contains(m) }, set: { if $0 { selectedModels.insert(m) } else { selectedModels.remove(m) } }))
                }
                Button("全选模型") { selectedModels = Set(detail["supportedModels"].array.map(\.string)) }
                Button("测试所选模型") { pending = "test"; confirmation = true }.disabled(selectedModels.isEmpty)
            }
            Section("模型价格") {
                Button("载入价格") { loadPrices() }
                NavigationLink("价格配置") { Form { ChannelSchemaFields(value: $prices, type: "[SaveChannelModelPriceInput!]", path: "prices") } }
                Button("保存模型价格") { pending = "prices"; confirmation = true }.disabled(uncertain)
            }
            Section("渠道诊断") {
                NavigationLink("渠道诊断") { ChannelDiagnosticsView(store: store, target: target) }
                Button("清除错误") { pending = "clearError"; confirmation = true }.disabled(uncertain)
            }
            if let message = message { Text(message).font(.caption) }
            if uncertain { Text("写入可能已完成，请刷新后再试。").foregroundStyle(.orange) }
        }.disabled(busy || store.managementBusy).navigationTitle("模型与价格")
        .task { if detail.object.isEmpty { await load() } }
        .alert("确认执行操作", isPresented: $confirmation) {
            Button("执行") { execute() }
            Button("取消", role: .cancel) { }
        } message: { Text("\(target.instance.name) · \(target.instance.address)\n\(pending == "prices" ? obsText("保存模型价格") : pending == "test" ? obsText("测试模型") : obsText("清除错误"))") }
    }
    @MainActor private func load() async {
        busy = true; defer { busy = false }
        do { detail = try await store.managementDetail(target) } catch { message = error.localizedDescription }
    }
    private func loadPrices() {
        busy = true; Task { defer { busy = false }; do {
            guard let id = target.entityID else { throw ManagementError.changedTarget }
            prices = try await store.managementClient(target).channelPrices(id: id)
            try store.validateTarget(target)
        } catch { message = error.localizedDescription } }
    }
    private func execute() {
        busy = true
        Task { defer { busy = false }
            var started = false
            do {
                guard let id = target.entityID else { throw ManagementError.changedTarget }
                let cli = try store.beginManagement(target); defer { store.endManagement() }
                switch pending {
                case "test":
                    var rows: [String] = []
                    for model in selectedModels.sorted() {
                        try store.validateTarget(target)
                        let r = try await cli.testChannel(id: id, model: model)
                        rows.append("\(model): \(r.success ? "OK" : "Failed") · \(r.latencyMs) ms")
                    }
                    message = rows.joined(separator: "\n")
                case "prices":
                    try ChannelInputSchema.validate(prices, type: "[SaveChannelModelPriceInput!]!")
                    started = true
                    _ = try await cli.saveChannelModelPrices(input: prices, id: id)
                    let actual = try await cli.channelPrices(id: id)
                    for expected in prices.array {
                        guard let saved = actual.array.first(where: { $0["modelId"] == expected["modelId"] }), AxonStore.matches(saved["price"], expected: expected["price"]) else { throw ManagementError.verification }
                    }
                    message = String(format: obsText("已保存 %lld 项"), Int64(prices.array.count))
                default:
                    started = true
                    try await cli.clearChannelError(id: id)
                    // Exact target separate readback, not solely the mutation response.
                    guard let saved = try await cli.channelDetail(id: id) else { throw ManagementError.verification }
                    guard saved["errorMessage"].isNull else { throw ManagementError.verification }
                    detail = saved; message = obsText("已确认")
                }
                try store.validateTarget(target)
            } catch { uncertain = started; message = error.localizedDescription }
        }
    }
}
