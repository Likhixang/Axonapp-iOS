import SwiftUI

@main
struct AxonhubApp: App {
    #if DEBUG && targetEnvironment(simulator)
    @StateObject private var store = ReadmePreview.makeStore()
    #else
    @StateObject private var store = AxonStore()
    #endif
    @State private var selectedTab = "dashboard"
    @AppStorage("appAppearance") private var appMode = AppearanceMode.system.rawValue
    @AppStorage("accentHex") private var hex = "#6366F1"

    var body: some Scene {
        WindowGroup {
            Group {
                if store.selectedInstance == nil {
                    NavigationStack { SettingsView(store: store) }
                } else {
                    TabView(selection: $selectedTab) {
                        if store.selectedInstance?.authType == .adminJWT {
                            NavigationStack { ManagementDashboardView(store: store) }
                                .tag("dashboard")
                                .tabItem { Label("仪表盘", systemImage: "chart.bar.xaxis") }
                            NavigationStack { GatewayView(store: store) }
                                .tag("gateway")
                                .tabItem { Label("网关", systemImage: "point.3.connected.trianglepath.dotted") }
                            NavigationStack { KeysWorkspaceView(store: store) }
                                .tag("keys")
                                .tabItem { Label("密钥", systemImage: "key") }
                            NavigationStack { ManagementWorkspaceView(store: store) }
                                .tag("management")
                                .tabItem { Label("管理中心", systemImage: "square.grid.2x2") }
                        } else {
                            NavigationStack { ModelsListView(store: store) }
                                .tag("models")
                                .tabItem { Label("模型", systemImage: "cpu") }
                            NavigationStack { SettingsView(store: store) }
                                .tag("settings")
                                .tabItem { Label("设置", systemImage: "gearshape") }
                        }
                    }
                    .id(store.selectedInstance)
                }
            }
            .tint(resolvedAccentColor(hex))
            .accentColor(resolvedAccentColor(hex))
            .preferredColorScheme((AppearanceMode(rawValue: appMode) ?? .system).scheme)
            .task(id: store.selectedInstance) {
                if store.selectedInstance?.authType == .adminJWT {
                    if !["dashboard", "gateway", "keys", "management"].contains(selectedTab) { selectedTab = "dashboard" }
                } else if !["models", "settings"].contains(selectedTab) { selectedTab = "settings" }
                await store.refresh()
            }
        }
    }
}
