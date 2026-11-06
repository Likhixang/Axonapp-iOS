import Foundation
import Observation

/// Owns authentication state, the active server and the selected project.
@MainActor
@Observable
final class SessionStore {
    enum Phase: Equatable {
        case restoring
        case signedOut
        case signedIn
    }

    private(set) var phase: Phase = .restoring
    private(set) var user: UserInfo?
    private(set) var projects: [Project] = []
    private(set) var selectedProjectID: String?
    private(set) var serverURL: URL?
    private(set) var service: AxonService?
    var bannerMessage: String?

    private let defaults = UserDefaults.standard
    private enum Keys {
        static let server = "axon.server"
        static let email = "axon.email"
        static let project = "axon.project"
        static let recentServers = "axon.recentServers"
        static let token = "token"
    }

    var lastServer: String { defaults.string(forKey: Keys.server) ?? "" }
    var lastEmail: String { defaults.string(forKey: Keys.email) ?? "" }
    var recentServers: [String] { defaults.stringArray(forKey: Keys.recentServers) ?? [] }

    var selectedProject: Project? { projects.first { $0.id == selectedProjectID } }
    var isOwner: Bool { user?.isOwner ?? false }

    /// True when the user may manage system-wide resources (channels, models, users).
    var canManageSystem: Bool {
        guard let user else { return false }
        if user.isOwner { return true }
        let scopes = Set(user.scopes ?? [])
        return !scopes.isDisjoint(with: ["write_channels", "read_channels", "write_settings"])
    }

    // MARK: - Lifecycle

    func restore() async {
        guard let url = URL(string: lastServer), !lastServer.isEmpty,
              let token = Keychain.read(Keys.token), !token.isEmpty else {
            phase = .signedOut
            return
        }
        let client = makeClient(url: url, token: token)
        serverURL = url
        service = AxonService(client: client)
        do {
            let me: UserInfo = try await fetchMe(client)
            user = me
            phase = .signedIn
            await loadProjects()
        } catch let error as APIError where error.isUnauthorized {
            signOut(message: "登录已过期，请重新登录")
        } catch {
            // Server unreachable: keep the session and let screens show their own errors.
            phase = .signedIn
            bannerMessage = error.localizedDescription
        }
    }

    func signIn(server: String, email: String, password: String) async throws {
        guard let url = APIClient.normalizeBaseURL(server) else { throw APIError.invalidURL }
        let response = try await APIClient.signIn(baseURL: url, email: email.trimmed, password: password)
        Keychain.save(response.token, for: Keys.token)
        defaults.set(url.absoluteString, forKey: Keys.server)
        defaults.set(email.trimmed, forKey: Keys.email)
        rememberServer(url.absoluteString)

        let client = makeClient(url: url, token: response.token)
        serverURL = url
        service = AxonService(client: client)
        user = response.user
        phase = .signedIn
        await loadProjects()
    }

    func signOut(message: String? = nil) {
        Keychain.delete(Keys.token)
        service = nil
        user = nil
        projects = []
        selectedProjectID = nil
        phase = .signedOut
        bannerMessage = message
    }

    func refreshProfile() async {
        guard let client = service?.client else { return }
        if let me = try? await fetchMe(client) { user = me }
        await loadProjects()
    }

    func selectProject(_ id: String?) {
        selectedProjectID = id
        service?.client.setProjectID(id)
        defaults.set(id, forKey: Keys.project)
    }

    // MARK: - Private

    private func makeClient(url: URL, token: String) -> APIClient {
        let client = APIClient(baseURL: url, token: token, projectID: defaults.string(forKey: Keys.project))
        client.onTokenRefresh = { token in
            Keychain.save(token, for: Keys.token)
        }
        client.onUnauthorized = { [weak self] in
            Task { @MainActor in
                guard let self, self.phase == .signedIn else { return }
                self.signOut(message: "登录已过期，请重新登录")
            }
        }
        return client
    }

    private func fetchMe(_ client: APIClient) async throws -> UserInfo {
        try await AxonService(client: client).me()
    }

    private func loadProjects() async {
        guard let service else { return }
        do {
            let list = try await service.myProjects()
            projects = list
            let stored = defaults.string(forKey: Keys.project)
            if let stored, list.contains(where: { $0.id == stored }) {
                selectProject(stored)
            } else {
                selectProject(list.first?.id)
            }
        } catch {
            projects = []
        }
    }

    private func rememberServer(_ server: String) {
        var list = recentServers.filter { $0 != server }
        list.insert(server, at: 0)
        defaults.set(Array(list.prefix(5)), forKey: Keys.recentServers)
    }
}
