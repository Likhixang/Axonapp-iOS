import SwiftUI

@main
struct AxonApp: App {
    @State private var session = SessionStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .tint(Theme.accent)
        }
    }
}

struct RootView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        Group {
            switch session.phase {
            case .restoring:
                SplashView()
            case .signedOut:
                LoginView()
                    .transition(.opacity)
            case .signedIn:
                MainTabView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: session.phase)
        .task { await session.restore() }
    }
}

private struct SplashView: View {
    var body: some View {
        VStack(spacing: 16) {
            BrandMark(size: 64)
            ProgressView()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}

struct BrandMark: View {
    var size: CGFloat = 56

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(LinearGradient(colors: [Theme.accent, Theme.accent.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: Theme.accent.opacity(0.3), radius: size * 0.2, y: size * 0.08)
    }
}

struct MainTabView: View {
    @Environment(SessionStore.self) private var session
    @AppStorage(TabLayout.storageKey) private var storedPinned = ""
    @State private var selection: String = AppDestination.dashboard.rawValue

    static let moreTag = "more"

    private var available: [AppDestination] {
        AppDestination.available(isAdmin: session.canManageSystem, isOwner: session.isOwner)
    }

    private var pinned: [AppDestination] {
        TabLayout.resolve(stored: storedPinned, available: available)
    }

    var body: some View {
        TabView(selection: $selection) {
            ForEach(pinned) { destination in
                NavigationStack { destination.rootView }
                    .tabItem { Label(destination.tabTitle, systemImage: destination.systemImage) }
                    .tag(destination.rawValue)
            }

            NavigationStack { MoreView() }
                .tabItem { Label("更多", systemImage: "ellipsis.circle") }
                .tag(Self.moreTag)
        }
        .adaptiveTabBarMinimize()
        .onChange(of: storedPinned) { _, _ in keepSelectionValid() }
        .onChange(of: session.canManageSystem) { _, _ in keepSelectionValid() }
        .onAppear { keepSelectionValid() }
        .overlay(alignment: .top) {
            if let message = session.bannerMessage {
                Text(message)
                    .font(.footnote)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .adaptiveGlass(in: Capsule())
                    .padding(.top, 4)
                    .onTapGesture { session.bannerMessage = nil }
                    .task {
                        try? await Task.sleep(for: .seconds(4))
                        session.bannerMessage = nil
                    }
            }
        }
    }

    private func keepSelectionValid() {
        if selection == Self.moreTag { return }
        if !pinned.contains(where: { $0.rawValue == selection }) {
            selection = pinned.first?.rawValue ?? Self.moreTag
        }
    }
}

extension AppDestination {
    @MainActor @ViewBuilder
    var rootView: some View {
        switch self {
        case .dashboard: DashboardView()
        case .requests: RequestsView()
        case .channels: ChannelsView()
        case .models: ModelsView()
        case .apiKeys: APIKeysView()
        case .playground: PlaygroundView()
        case .guide: ConnectGuideView()
        case .users: UsersView()
        case .projects: ProjectsView()
        }
    }
}

/// Toolbar menu for switching the active project (sent as `X-Project-ID`).
struct ProjectPicker: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        if session.projects.count > 1 {
            Menu {
                Picker("项目", selection: Binding(
                    get: { session.selectedProjectID ?? "" },
                    set: { session.selectProject($0.isEmpty ? nil : $0) }
                )) {
                    ForEach(session.projects) { project in
                        Text(project.name).tag(project.id)
                    }
                }
            } label: {
                Label(session.selectedProject?.name ?? "项目", systemImage: "folder")
                    .labelStyle(.titleAndIcon)
                    .font(.subheadline)
            }
        }
    }
}
