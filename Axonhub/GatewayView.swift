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

/// The gateway opens directly on its working lists, not a directory of subpages.
struct GatewayView: View {
    @ObservedObject var store: AxonStore
    @State private var tab: GatewaySubTab = .channels
    @State private var showingProviders = false
    @State private var showingHealth = false

    var body: some View {
        Group {
            switch tab {
            case .channels: ChannelsListView(store: store, embedded: true, gatewayTab: $tab)
            case .models: ModelsListView(store: store, embedded: true, gatewayTab: $tab)
            case .providers: ProvidersCatalogView(store: store)
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Menu {
                    Button { showingProviders = true } label: { Label("供应商目录", systemImage: "building.2") }
                    Button { showingHealth = true } label: { Label("渠道健康与性能", systemImage: "waveform.path.ecg") }
                } label: { Label("更多操作", systemImage: "ellipsis.circle") }
            }
        }
        .sheet(isPresented: $showingProviders) {
            NavigationStack {
                ProvidersCatalogView(store: store).navigationTitle("供应商目录")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { showingProviders = false } } }
            }
        }
        .sheet(isPresented: $showingHealth) {
            NavigationStack {
                ObservabilityDashboardView(store: store)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { showingHealth = false } } }
            }
        }
    }
}

/// One working toolbar: module switch at left, status filter at right.
struct GatewayListFilters: View {
    let tab: Binding<GatewaySubTab>?
    @Binding var status: String
    let count: Int

    var body: some View {
        HStack(spacing: 12) {
            if let tab = tab {
                Picker("网关", selection: tab) {
                    Text("渠道").tag(GatewaySubTab.channels)
                    Text("模型").tag(GatewaySubTab.models)
                }.pickerStyle(.segmented).frame(maxWidth: 220)
            } else {
                Text(String(count)).font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Picker("状态筛选", selection: $status) {
                Text("全部").tag("all")
                Text("启用中").tag("enabled")
                Text("已禁用").tag("disabled")
            }.pickerStyle(.menu).labelsHidden()
                .accessibilityLabel("状态筛选")
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.regularMaterial)
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
