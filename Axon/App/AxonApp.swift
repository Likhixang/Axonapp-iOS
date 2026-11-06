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
    @State private var selection: AppTab = .dashboard

    enum AppTab: Hashable { case dashboard, requests, channels, playground, more }

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack { DashboardView() }
                .tabItem { Label("概览", systemImage: "chart.bar.xaxis") }
                .tag(AppTab.dashboard)

            NavigationStack { RequestsView() }
                .tabItem { Label("请求", systemImage: "list.bullet.rectangle") }
                .tag(AppTab.requests)

            if session.canManageSystem {
                NavigationStack { ChannelsView() }
                    .tabItem { Label("渠道", systemImage: "server.rack") }
                    .tag(AppTab.channels)
            } else {
                NavigationStack { APIKeysView() }
                    .tabItem { Label("密钥", systemImage: "key") }
                    .tag(AppTab.channels)
            }

            NavigationStack { PlaygroundView() }
                .tabItem { Label("对话", systemImage: "bubble.left.and.text.bubble.right") }
                .tag(AppTab.playground)

            NavigationStack { MoreView() }
                .tabItem { Label("更多", systemImage: "ellipsis.circle") }
                .tag(AppTab.more)
        }
        .overlay(alignment: .top) {
            if let message = session.bannerMessage {
                Text(message)
                    .font(.footnote)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.top, 4)
                    .onTapGesture { session.bannerMessage = nil }
                    .task {
                        try? await Task.sleep(for: .seconds(4))
                        session.bannerMessage = nil
                    }
            }
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
