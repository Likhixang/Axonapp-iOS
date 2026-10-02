import SwiftUI

/// Display copy only. API keys, enum tags and mutation payloads remain unchanged.
enum NativeAdminLabels {
    private struct Catalog: Decodable {
        let fields: [String: String]
        let values: [String: String]
        let operations: [String: String]
    }
    private static let catalog: Catalog = {
        guard let url = Bundle.main.url(forResource: "PresentationLabels", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let result = try? JSONDecoder().decode(Catalog.self, from: data) else {
            return Catalog(fields: [:], values: [:], operations: [:])
        }
        return result
    }()
    static var fields: [String: String] { catalog.fields }
    static func field(_ key: String) -> String {
        if let title = fields[key] { return obsText(title) }
        // JSON payload keys can be supplied by users, tools and future providers.
        // Keep that data intact, but never use an unmapped server key as UI copy.
        return obsText("自定义字段")
    }
    static func path(_ path: String) -> String {
        path.split(separator: ".").map { part in
            let key = String(part).split(separator: "[").first.map(String.init) ?? "item"
            return field(key)
        }.joined(separator: " › ")
    }
    static func value(_ value: String) -> String { obsText(catalog.values[value] ?? value) }
    static func operation(_ id: String) -> String {
        obsText(catalog.operations[id] ?? "管理操作")
    }
    /// Only translate enum-like fields, never free text, names, model IDs or messages.
    static func scalar(_ item: JSON, key: String = "") -> String {
        if DisplayFormat.isTokenQuantity(key) {
            if case .number(let count) = item { return DisplayFormat.compact(count) }
            if case .string(let text) = item, let count = Double(text) { return DisplayFormat.compact(count) }
        }
        switch item {
        case .bool(let flag): return obsText(flag ? "是" : "否")
        case .null: return "—"
        case .number(let number): return number.formatted()
        case .string(let text):
            if key.hasSuffix("At") || ["startTime", "endTime", "timestamp", "date"].contains(key) { return NativeDisplay.date(text) }
            let enumFields: Set<String> = ["status", "source", "type", "role", "action", "op", "mode", "unit", "period", "direction", "field", "loadBalancerStrategy", "loadBalanceStrategy", "traceStickyMode", "channelType", "providerType", "itemCode", "variantCode", "apiFormat", "apiFormats", "format", "operator", "logic", "stream", "finishReason", "finish_reason", "modelConflictStrategy", "modelPriceConflictStrategy", "apiKeyConflictStrategy", "channelConflictStrategy", "scopes", "effectiveScopes", "levels", "statuses", "resourceType", "frequency"]
            return enumFields.contains(key) ? value(text) : text
        default: return ""
        }
    }
}

struct NativeSystemSettingsView: View {
    @ObservedObject var store: AxonStore
    @State private var session: AdminSession?
    @State private var error: String?
    private let sections: [(String, [(String, String, String)])] = [
        ("基础设置", [("通用设置", "systemGeneralSettings", "updateSystemGeneralSettings"), ("品牌设置", "brandSettings", "updateBrandSettings"), ("安全设置", "securitySettings", "updateSecuritySettings")]),
        ("网关行为", [("重试与负载均衡", "retryPolicy", "updateRetryPolicy"), ("渠道默认配置", "systemChannelSettings", "updateSystemChannelSettings"), ("模型默认配置", "systemModelSettings", "updateSystemModelSettings"), ("请求透传", "passThroughSettings", "updatePassThroughSettings"), ("User-Agent 透传", "userAgentPassThroughSettings", "updateUserAgentPassThroughSettings"), ("费用注入", "usageCostInjectionSettings", "updateUsageCostInjectionSettings")]),
        ("配额与目录", [("配额执行", "quotaEnforcementSettings", "updateQuotaEnforcementSettings"), ("供应商配额采集", "providerQuotaCollectionSettings", "updateProviderQuotaCollectionSettings"), ("模型目录", "catalogSettings", "updateCatalogSettings")]),
        ("存储与通知", [("存储策略", "storagePolicy", "updateStoragePolicy"), ("视频存储", "videoStorageSettings", "updateVideoStorageSettings"), ("自动备份", "autoBackupSettings", "updateAutoBackupSettings"), ("Webhook 通知", "webhookNotifierConfig", "updateWebhookNotifierConfig")])
    ]
    var body: some View {
        List {
            if let session = session {
                ForEach(sections, id: \.0) { section in
                    Section(obsText(section.0)) {
                        ForEach(section.1, id: \.1) { item in
                            NavigationLink(obsText(item.0)) { NativeSettingsEditor(session: session, title: obsText(item.0), read: item.1, write: item.2) }
                        }
                    }
                }
                Section("运维") {
                    NavigationLink("代理预设") { NativeProxyPresetsView(session: session) }
                    NavigationLink("默认数据存储") { NativeDefaultStorageView(session: session) }
                    NavigationLink("备份与恢复") { NativeBackupView(session: session) }
                    NavigationLink("缓存与清理") { NativeMaintenanceView(session: session) }
                    NavigationLink("版本信息") { NativeServerVersionView(session: session) }
                }
            } else if let error = error { ObservabilityErrorView(message: error) }
            else { ProgressView() }
        }.navigationTitle("系统设置")
        .task { do { session = try AdminSession(store: store, schema: AdminSchema.loaded.get()) } catch { self.error = error.localizedDescription } }
    }
}

struct NativeSettingsEditor: View {
    @ObservedObject var session: AdminSession
    let title: String
    let read: String
    let write: String
    @State private var baseline: JSON = .null
    @State private var value: JSON = .object([:])
    @State private var operation: AdminOperation?
    @State private var loaded = false
    @State private var uncertain = false
    @State private var authorized = false
    @State private var showAuthorization = false
    var body: some View {
        Form {
            if read == "webhookNotifierConfig" && !authorized {
                Button("读取敏感配置") { showAuthorization = true }
            } else if !loaded { ProgressView("正在读取服务器数据") }
            else if let operation = operation, let input = operation.variables.first(where: { $0.name == "input" }), let type = session.schema.types[session.schema.base(input.type)] {
                AdminSchemaForm(schema: session.schema, fields: type.fields, value: $value)
            }
            if let error = session.error { ObservabilityErrorView(message: error) }
            if uncertain { Text("写入可能已经完成。请关闭编辑器并刷新核对，勿重复提交。").foregroundStyle(.orange) }
        }.navigationTitle(title)
        .disabled(session.busy || session.invalidated || uncertain)
        .toolbar { Button("保存") { save() }.disabled(!loaded || uncertain) }
        .task { if read != "webhookNotifierConfig" { await load() } }
        .confirmationDialog("读取敏感配置", isPresented: $showAuthorization, titleVisibility: .visible) {
            Button("读取") { authorized = true; Task { await load() } }
        }
        .onDisappear { value = .null; baseline = .null }
    }
    @MainActor private func load() async {
        do {
            operation = try session.schema.operation(write)
            baseline = try await session.read(read == "webhookNotifierConfig" ? "revealwebhookNotifierConfig" : read)
            guard let field = operation?.variables.first(where: { $0.name == "input" }) else { throw AdminError.schemaMissing }
            value = session.schema.project(baseline, type: field.type); loaded = true
        } catch { session.error = error.localizedDescription }
    }
    private func save() {
        guard let operation = operation else { return }
        session.start {
            var input = value
            if !operation.replacement, let field = operation.variables.first(where: { $0.name == "input" }) {
                let original = session.schema.project(baseline, type: field.type)
                input = .object(value.object.filter { original[$0.key] != $0.value })
            }
            uncertain = true
            _ = try await session.execute(operation, variables: .object(["input": input]), baseline: baseline)
            uncertain = false; await load()
        }
    }
}

struct NativeAccountView: View {
    @ObservedObject var store: AxonStore
    @State private var session: AdminSession?
    @State private var me: JSON = .null
    var body: some View {
        List {
            if let session = session {
                Section("个人账号") { NativeDetailFieldsView(store: store, value: me) }
                NavigationLink("编辑个人信息") {
                    if let operation = try? session.schema.operation("updateMe") { NativeEntityEditor(session: session, operation: operation, seed: .object(["input": session.schema.project(me, type: "UpdateMeInput")]), baseline: me) }
                }
                NavigationLink("修改密码") {
                    if let operation = try? session.schema.operation("updateMyPassword") { NativeEntityEditor(session: session, operation: operation) }
                }
                ForEach(me["oidcIdentities"].array, id: \.self) { identity in
                    NavigationLink(identity["idpName"].string) {
                        if let operation = try? session.schema.operation("unlinkOIDCIdentity") { AdminOperationView(session: session, operation: operation, seed: .object(["id": identity["id"]])) }
                    }
                }
            } else { ProgressView() }
        }.navigationTitle("个人账号")
        .task {
            do { let s = try AdminSession(store: store, schema: AdminSchema.loaded.get()); session = s; me = try await s.read("me") }
            catch { session?.error = error.localizedDescription }
        }
    }
}

struct NativeProjectMembersView: View {
    @ObservedObject var session: AdminSession
    let projectID: String
    @State private var members: [JSON] = []
    var body: some View {
        List {
            ForEach(members, id: \.self) { member in
                NavigationLink(AdminOperationView.label(member["user"])) {
                    Form {
                        ForEach(["updateProjectUser", "removeUserFromProject"], id: \.self) { key in
                            if let operation = try? session.schema.operation(key) {
                                NavigationLink(NativeAdminLabels.operation(key)) {
                                    NativeEntityEditor(session: session, operation: operation, seed: .object(["input": .object(["projectId": .string(projectID), "userId": member["userID"], "isOwner": member["isOwner"], "scopes": member["scopes"]].filter { !$0.value.isNull })]))
                                }
                            }
                        }
                    }.navigationTitle("项目成员")
                }
            }
            if let op = try? session.schema.operation("addUserToProject") { NavigationLink("添加项目成员") { NativeEntityEditor(session: session, operation: op, seed: .object(["input": .object(["projectId": .string(projectID)])])) } }
            NavigationLink("创建项目邀请") { AdminInvitationView(session: session) }
            if let error = session.error { ObservabilityErrorView(message: error) }
        }.navigationTitle("项目成员")
        .task {
            do { members = try await session.read("projectUsers", variables: .object(["projectId": .string(projectID)]))["projectUsers"].array }
            catch { session.error = error.localizedDescription }
        }
    }
}

struct NativeProxyPresetsView: View {
    @ObservedObject var session: AdminSession
    @State private var presets: [JSON] = []
    @State private var authorized = false
    var body: some View {
        List {
            if !authorized { Button("读取敏感配置") { authorized = true; Task { await load() } } }
            ForEach(presets, id: \.self) { preset in
                NavigationLink(preset["url"].string) {
                    if let op = try? session.schema.operation("saveProxyPreset") { NativeEntityEditor(session: session, operation: op, seed: .object(["input": session.schema.project(preset, type: "SaveProxyPresetInput")]), baseline: preset) }
                }
                if let op = try? session.schema.operation("deleteProxyPreset") { NavigationLink("删除代理预设") { AdminOperationView(session: session, operation: op, seed: .object(["url": preset["url"]])) } }
            }
            if let op = try? session.schema.operation("saveProxyPreset") { NavigationLink("新增") { NativeEntityEditor(session: session, operation: op) } }
        }.navigationTitle("代理预设").onDisappear { presets = [] }
    }
    private func load() async { do { presets = try await session.read("revealproxyPresets").array } catch { session.error = error.localizedDescription } }
}

struct NativeDefaultStorageView: View {
    @ObservedObject var session: AdminSession
    @State private var storages: [JSON] = []
    @State private var selected = ""
    var body: some View {
        Form {
            Picker("默认数据存储", selection: $selected) { ForEach(storages, id: \.self) { Text($0["name"].string).tag($0["id"].string) } }
            if let error = session.error { ObservabilityErrorView(message: error) }
        }.navigationTitle("默认数据存储")
        .toolbar { Button("保存") { session.start { let op = try session.schema.operation("updateDefaultDataStorage"); _ = try await session.execute(op, variables: .object(["input": .object(["dataStorageID": .string(selected)])])) } } }
        .task { do { storages = try await session.read("dataStorages", variables: .object(["first": .number(100)]) )["edges"].array.map { $0["node"] }; selected = try await session.read("defaultDataStorageID").string } catch { session.error = error.localizedDescription } }
    }
}

struct NativeBackupView: View {
    @ObservedObject var session: AdminSession
    var body: some View {
        List {
            if let op = try? session.schema.operation("backup") { NavigationLink("创建备份") { AdminOperationView(session: session, operation: op) } }
            NavigationLink("从备份文件恢复") { AdminRestoreView(session: session) }
            if let op = try? session.schema.operation("triggerAutoBackup") { NavigationLink("立即自动备份") { AdminOperationView(session: session, operation: op) } }
        }.navigationTitle("备份与恢复")
    }
}

struct NativeMaintenanceView: View {
    @ObservedObject var session: AdminSession
    var body: some View {
        List {
            ForEach(["getCacheDiagnostics", "clearCache", "previewGcCleanup", "triggerGcCleanup"], id: \.self) { key in
                if let op = try? session.schema.operation(key) { NavigationLink(key == "getCacheDiagnostics" ? obsText("缓存诊断") : key == "clearCache" ? obsText("清理缓存") : key == "previewGcCleanup" ? obsText("预览 GC 清理") : obsText("触发 GC 清理")) { AdminOperationView(session: session, operation: op) } }
            }
        }.navigationTitle("缓存与清理")
    }
}

struct NativeServerVersionView: View {
    @ObservedObject var session: AdminSession
    @State private var info: JSON = .null
    @State private var update: JSON = .null
    var body: some View {
        List {
            Section("版本信息") { NativeDetailFieldsView(store: session.store, value: info) }
            Button("检查更新") { session.start { update = try await session.read("checkForUpdate", variables: .object(["includeBeta": .bool(true)])) } }
            if !update.isNull { Section { AdminResultTree(value: update) } }
            if let error = session.error { ObservabilityErrorView(message: error) }
        }.navigationTitle("版本信息")
        .task { do { info = try await session.read("systemVersion") } catch { session.error = error.localizedDescription } }
    }
}
