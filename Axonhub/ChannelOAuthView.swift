import SwiftUI

struct ChannelOAuthView: View {
    @ObservedObject var store: AxonStore
    let target: ManagementTarget
    let type: String
    @Binding var credential: String
    let proxy: JSON
    @Environment(\.openURL) private var openURL
    @State private var session = ""
    @State private var authURL = ""
    @State private var callback = ""
    @State private var importValue = ""
    @State private var userCode = ""
    @State private var projectID = ""
    @State private var busy = false
    @State private var message: String?
    private var provider: String { type == "github_copilot" ? "copilot" : type == "xai_subscription" ? "xai" : type }
    var body: some View {
        Form {
            Text("在供应商页面授权，凭据仅在保存后生效。").font(.caption)
            if provider == "antigravity" { TextField("Google Cloud 项目（可选）", text: $projectID).textInputAutocapitalization(.never).autocorrectionDisabled() }
            Button("开始授权") { run("oauth/start", body: provider == "antigravity" && !projectID.isEmpty ? .object(["project_id": .string(projectID)]) : .object([:])) }
            if !authURL.isEmpty {
                Button("打开授权页面") { if let u = URL(string: authURL), u.scheme == "https", u.user == nil, u.password == nil { openURL(u) } }
            }
            if !userCode.isEmpty { Text(userCode).monospaced() }
            if provider == "copilot" {
                Button("检查授权状态") { run("oauth/poll", body: .object(["session_id": .string(session)])) }.disabled(session.isEmpty)
            } else {
                SecureField("授权回调地址", text: $callback).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("获取授权凭据") {
                    var b: [String: JSON] = ["session_id": .string(session), "callback_url": .string(callback)]
                    if proxy["type"].string == "URL" { var p = proxy.object; p["type"] = .string("url"); b["proxy"] = .object(p) }
                    run("oauth/exchange", body: .object(b))
                }.disabled(session.isEmpty || callback.isEmpty)
            }
            if provider == "codex" || provider == "xai" {
                SecureField(provider == "codex" ? "Codex auth.json" : "xAI SSO Token", text: $importValue).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("解析并导入") { run(provider == "codex" ? "auth/decode" : "oauth/sso", body: .object([provider == "codex" ? "auth_json" : "sso_token": .string(importValue)])) }.disabled(importValue.isEmpty)
            }
            if let message = message { Text(message).font(.caption) }
        }.disabled(busy).navigationTitle("供应商授权")
        .onDisappear { session = ""; callback = ""; importValue = "" }
    }
    private func run(_ action: String, body: JSON) {
        busy = true
        Task { defer { busy = false }
            do {
                let r = try await store.managedOAuth(target, provider: provider, action: action, body: body)
                if action == "oauth/start" {
                    session = r["session_id"].string; authURL = provider == "copilot" ? r["verification_uri"].string : r["auth_url"].string; userCode = r["user_code"].string
                } else if provider == "copilot", !r["access_token"].string.isEmpty {
                    credential = JSON.object(["access_token": r["access_token"], "token_type": .string("bearer")]).prettyJSON; message = obsText("凭据已导入")
                } else if !r["credentials"].string.isEmpty {
                    credential = r["credentials"].string; callback = ""; importValue = ""; message = obsText("凭据已导入")
                } else { message = obsText("授权尚未完成或已过期") }
            } catch { message = error.localizedDescription }
        }
    }
}
