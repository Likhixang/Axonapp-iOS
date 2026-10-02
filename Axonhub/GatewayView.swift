import SwiftUI

/// Top navigation tab items for AxonHub
enum GatewaySubTab: String, CaseIterable, Identifiable {
    case channels = "channels"
    case models = "models"
    case providers = "providers"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .channels: return NSLocalizedString("渠道", comment: "")
        case .models: return NSLocalizedString("模型", comment: "")
        case .providers: return NSLocalizedString("供应商目录", comment: "")
        }
    }
}

/// Unified Gateway view seamlessly combining Channels, Models, and Provider Catalog
struct GatewayView: View {
    @ObservedObject var store: AxonStore
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(store.selectedInstance?.name ?? "AxonHub").font(.headline)
                    HStack(spacing: 18) {
                        Label(String(store.snapshot.channels.filter(\.isEnabled).count) + " / " + String(store.snapshot.channels.count), systemImage: "point.3.connected.trianglepath.dotted")
                        Label(String(store.snapshot.models.count), systemImage: "cpu")
                    }.font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }.padding(.vertical, 8)
            }
            Section("路由配置") {
                NavigationLink { ChannelsListView(store: store) } label: {
                    ManagementMenuRow(title: obsText("渠道"), symbol: "point.3.filled.connected.trianglepath.dotted")
                }
                NavigationLink { ModelsListView(store: store) } label: {
                    ManagementMenuRow(title: obsText("模型"), symbol: "cpu")
                }
                NavigationLink { ProvidersCatalogView(store: store) } label: {
                    ManagementMenuRow(title: obsText("供应商目录"), symbol: "building.2")
                }
            }
            Section("运行状况") {
                NavigationLink { ObservabilityDashboardView(store: store) } label: {
                    ManagementMenuRow(title: obsText("渠道健康与性能"), symbol: "waveform.path.ecg")
                }
            }
            if store.loading { ProgressView("正在读取服务器数据") }
            if let error = store.error { ObservabilityErrorView(message: error) }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("网关")
        .refreshable { await store.refresh() }
    }
}

/// Native Providers Catalog view displaying official supported model providers
struct ProvidersCatalogView: View {
    @ObservedObject var store: AxonStore
    @State private var providers: [JSON] = []
    @State private var loading = false
    @State private var errorMessage: String? = nil
    @State private var filterText = ""
    @State private var refreshing = false

    var filteredProviders: [JSON] {
        providers.filter { item in
            guard !filterText.isEmpty else { return true }
            let name = item["name"].string
            let id = item["id"].string
            return name.localizedCaseInsensitiveContains(filterText) || id.localizedCaseInsensitiveContains(filterText)
        }
    }

    var body: some View {
        List {
            if let err = errorMessage {
                Section {
                    Text(err).font(.caption).foregroundStyle(.orange)
                }
            }

            if loading && providers.isEmpty {
                Section {
                    HStack {
                        Spacer()
                        ProgressView(NSLocalizedString("正在读取服务商目录...", comment: ""))
                        Spacer()
                    }
                    .padding(.vertical, 20)
                }
            } else if providers.isEmpty && !loading {
                Section {
                    Text(NSLocalizedString("暂无服务商目录", comment: "")).foregroundStyle(.secondary)
                }
            } else {
                ForEach(filteredProviders, id: \.self) { p in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            BrandMark(asset: BrandIdentity.asset(icon: p["icon"].string) ?? BrandIdentity.channel(p["id"].string), name: NativeDisplay.name(p), size: 28)
                            Text(NativeDisplay.name(p))
                                .font(.headline)
                            Spacer()
                            if !p["type"].string.isEmpty {
                                Text(NativeAdminLabels.value(p["type"].string))
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.12))
                                    .foregroundStyle(.blue)
                                    .clipShape(Capsule())
                            }
                        }


                        if !p["defaultBaseUrl"].string.isEmpty {
                            Text(p["defaultBaseUrl"].string)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(12)
                    .liquidGlass()
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.plain)
        .searchable(text: $filterText, prompt: NSLocalizedString("搜索名称", comment: ""))
        .refreshable { await refreshCatalog() }
        .task { if providers.isEmpty { await loadCatalog() } }
        .toolbar {
            if store.canManage {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await refreshCatalog() }
                    } label: {
                        Label(NSLocalizedString("刷新目录", comment: ""), systemImage: "arrow.clockwise")
                    }
                    .disabled(loading || refreshing)
                }
            }
        }
    }

    private func loadCatalog() async {
        guard !loading else { return }
        loading = true
        errorMessage = nil
        defer { loading = false }

        do {
            let client = try store.ensureClient()
            guard store.canManage else { return }
            if let cached = store.pageCache.value("providersCatalog") { providers = cached.array; return }
            let data = try await client.graphql(query: AdminDocuments.adminProvidersCatalog)
            guard try store.ensureClient().token == client.token else { return }
            store.pageCache.save(data["providersCatalog"], key: "providersCatalog")
            if case .array(let list) = data["providersCatalog"] {
                providers = list
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshCatalog() async {
        guard !refreshing else { return }
        refreshing = true
        errorMessage = nil
        defer { refreshing = false }

        do {
            let client = try store.ensureClient()
            guard store.canManage else { return }
            let instance = store.selectedInstance
            let data = try await client.graphql(query: AdminDocuments.adminRefreshProvidersCatalog)
            guard store.selectedInstance == instance, try store.ensureClient().token == client.token else { return }
            if case .array(let list) = data["refreshProvidersCatalog"] {
                providers = list
                store.pageCache.save(.array(list), key: "providersCatalog")
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
