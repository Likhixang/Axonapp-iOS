import SwiftUI

struct ChannelKeysView: View {
    @ObservedObject var store: AxonStore
    let target: ManagementTarget
    @State private var authorized = false
    @State private var confirmation = false
    @State private var busy = false
    @State private var uncertain = false
    @State private var secrets: JSON = .object([:])
    @State private var selected = Set<String>()
    @State private var model = ""
    @State private var key = ""
    @State private var pending = ""
    @State private var message: String?
    var body: some View {
        Form {
            if !authorized {
                Text("密钥仅在授权后读取，不以明文显示。")
                Button("读取密钥") { pending = "read"; confirmation = true }
            } else {
                SecureField("指定密钥（可选）", text: $key).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("测试模型", text: $model).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("测试全部密钥") { perform("testAll") }
                Button("测试指定密钥") { perform("test") }.disabled(key.isEmpty)
                Button("启用指定密钥") { pending = "enable"; confirmation = true }.disabled(key.isEmpty)
                Button("禁用指定密钥") { pending = "disable"; confirmation = true }.disabled(key.isEmpty)
                Button("启用全部密钥") { pending = "enableAll"; confirmation = true }
                Section("已禁用密钥") {
                    ForEach(Array(secrets["disabledAPIKeys"].array.enumerated()), id: \.offset) { index, row in
                        Toggle(String(format: obsText("密钥 %lld · HTTP %lld · %@"), Int64(index + 1), Int64(row["errorCode"].int), row["key"].string == "__oauth__" ? "OAuth" : obsText("API Key")), isOn: Binding(get: { selected.contains(row["key"].string) }, set: { if $0 { selected.insert(row["key"].string) } else { selected.remove(row["key"].string) } }))
                    }
                    Button("启用所选密钥") { pending = "enableSelected"; confirmation = true }.disabled(selected.isEmpty)
                    Button("删除所选密钥", role: .destructive) { pending = "deleteDisabled"; confirmation = true }.disabled(selected.isEmpty || selected.contains("__oauth__"))
                }
            }
            if let message = message { Text(message).font(.caption) }
            if uncertain { Text("写入可能已完成，请刷新后再试。").foregroundStyle(.orange) }
        }.disabled(busy || store.managementBusy || uncertain).navigationTitle("密钥管理")
        .alert("确认敏感操作", isPresented: $confirmation) {
            Button("授权并执行", role: pending == "deleteDisabled" ? .destructive : nil) { perform(pending) }
            Button("取消", role: .cancel) { }
        } message: { Text("\(target.instance.name) · \(target.instance.address)\n\(pendingTitle)") }
        .onDisappear { secrets = .object([:]); selected.removeAll(); key = "" }
    }
    private var pendingTitle: String {
        switch pending {
        case "read": return obsText("读取密钥")
        case "enable": return obsText("启用指定密钥")
        case "disable": return obsText("禁用指定密钥")
        case "enableAll": return obsText("启用全部密钥")
        case "enableSelected": return obsText("启用所选密钥")
        case "deleteDisabled": return obsText("删除所选密钥")
        default: return obsText("操作")
        }
    }
    private func perform(_ action: String) {
        busy = true; Task { defer { busy = false }
            do {
                if action == "read" { secrets = try await store.authorizedChannelSecrets(target); authorized = true; return }
                let r = try await store.managedKeyAction(target, action: action, key: key, keys: selected.sorted(), model: model)
                if action == "testAll" { message = String(format: obsText("成功：%lld / %lld · 失败：%lld"), Int64(r["successCount"].int), Int64(r["total"].int), Int64(r["failedCount"].int)) }
                else if action == "test" { message = obsText(r["success"].bool ? "测试成功" : "测试失败") }
                else { secrets = r; selected.removeAll(); message = obsText("已确认") }
            } catch { uncertain = action != "read" && !action.hasPrefix("test"); message = error.localizedDescription }
        }
    }
}
