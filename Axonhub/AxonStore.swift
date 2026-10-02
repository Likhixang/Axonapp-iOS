import Foundation
import Combine
import Security

/// Small seams for native regression tests; the production AxonClient API is unchanged.
@MainActor struct AxonStoreDependencies {
    var loadCredential: (String) throws -> String
    var saveCredential: (String, String) throws -> Void
    var deleteCredential: (String) -> Void
    var authenticate: (AxonInstance, String) async throws -> String
    var fetchSnapshot: (AxonClient) async throws -> AxonSnapshot

    static let live = AxonStoreDependencies(
        loadCredential: { try Keychain.load(account: $0) },
        saveCredential: { token, account in
            // Core's save deletes before inserting. Update in place so a failed edit
            // cannot destroy the existing credential.
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: account
            ]
            let attributes: [String: Any] = [kSecValueData as String: Data(token.utf8)]
            let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            if status == errSecItemNotFound {
                try Keychain.save(key: token, account: account)
            } else if status != errSecSuccess {
                throw AxonAPIError.invalidCredentials
            }
        },
        deleteCredential: { Keychain.delete(account: $0) },
        authenticate: { instance, secret in
            guard !secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AxonAPIError.invalidCredentials
            }
            // Validate before signIn, which otherwise has less strict URL checks.
            _ = try AxonClient(baseURL: instance.address, authType: instance.authType,
                               token: "", allowHTTP: instance.allowHTTP)
            let token: String
            if instance.authType == .adminJWT {
                guard !instance.adminEmail.isEmpty else { throw AxonAPIError.invalidCredentials }
                token = try await AxonClient.signIn(baseURL: instance.address,
                    email: instance.adminEmail, password: secret, allowHTTP: instance.allowHTTP)
            } else {
                token = secret.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let candidate = try AxonClient(baseURL: instance.address, authType: instance.authType,
                                          token: token, allowHTTP: instance.allowHTTP)
            _ = try await candidate.fetchSnapshot()
            try Task.checkCancellation()
            return token
        },
        fetchSnapshot: { try await $0.fetchSnapshot() }
    )
}

@MainActor final class AxonStore: ObservableObject {
    @Published var instances: [AxonInstance] = [] {
        didSet {
            guard !isRestoring else { return }
            persist()
            let previous = oldValue.first(where: { $0.id == selectedID })
            if previous?.id != selectedInstance?.id ||
                previous?.address != selectedInstance?.address ||
                previous?.allowHTTP != selectedInstance?.allowHTTP ||
                previous?.authType != selectedInstance?.authType ||
                previous?.adminEmail != selectedInstance?.adminEmail {
                invalidateClient()
            }
        }
    }
    @Published var selectedID: String = "" {
        didSet {
            guard !isRestoring else { return }
            persist()
            if oldValue != selectedID {
                invalidateClient()
            }
        }
    }

    @Published var snapshot: AxonSnapshot = AxonSnapshot()
    @Published var loading: Bool = false
    @Published var error: String? = nil
    @Published var lastUpdated: Date? = nil

    let pageCache = NativePageCache()
    let entityNames = EntityNameDirectory()
    let dashboard: DashboardCacheModel
    private let defaults: UserDefaults
    private let dependencies: AxonStoreDependencies
    private var isRestoring = true
    private var client: AxonClient? = nil
    private var fetchTask: Task<Void, Never>? = nil
    private var refreshGeneration = UUID()
    private var instanceRevisions: [String: UUID] = [:]
    private var managementRevision = UUID()
    @Published private(set) var managementBusy = false

    var canManage: Bool { selectedInstance?.authType == .adminJWT }

    func managementTarget(kind: ManagementKind, entityID: String? = nil) throws -> ManagementTarget {
        guard let instance = selectedInstance, canManage else { throw AxonAPIError.forbidden }
        return ManagementTarget(instance: instance, connectionRevision: managementRevision, entityID: entityID, kind: kind)
    }

    func validateTarget(_ target: ManagementTarget) throws {
        guard selectedID == target.instance.id, selectedInstance == target.instance,
              managementRevision == target.connectionRevision else { throw ManagementError.changedTarget }
        guard canManage else { throw AxonAPIError.forbidden }
        try Task.checkCancellation()
    }

    func managementClient(_ target: ManagementTarget) throws -> AxonClient {
        try validateTarget(target)
        return try ensureClient()
    }

    func managementDetail(_ target: ManagementTarget) async throws -> JSON {
        let cli = try managementClient(target)
        guard let id = target.entityID else { throw AxonAPIError.invalidResponse }
        let detail: JSON?
        switch target.kind {
        case .channel: detail = try await cli.channelDetail(id: id)
        case .model: detail = try await cli.modelDetail(id: id)
        }
        try validateTarget(target)
        guard let detail = detail, detail["id"].string == id else { throw AxonAPIError.invalidResponse }
        return detail
    }

    func beginManagement(_ target: ManagementTarget) throws -> AxonClient {
        guard !managementBusy else { throw ManagementError.busy }
        let cli = try managementClient(target)
        managementBusy = true
        return cli
    }

    func endManagement() { managementBusy = false }

    func verify(_ actual: JSON, input: [String: JSON]) throws {
        for (key, value) in input {
            if key == "credentials" { continue } // Never fetch saved secrets.
            if key == "clearBaseURL" {
                guard actual["baseURL"].isNull || actual["baseURL"].string.isEmpty else { throw ManagementError.verification }
            } else {
                guard Self.matches(actual[key], expected: value) else { throw ManagementError.verification }
            }
        }
    }

    static func matches(_ actual: JSON, expected: JSON) -> Bool {
        switch expected {
        case .object(let fields): return fields.allSatisfy { matches(actual[$0.key], expected: $0.value) }
        case .array(let items):
            guard actual.array.count == items.count else { return false }
            return zip(actual.array, items).allSatisfy { matches($0.0, expected: $0.1) }
        default: return actual == expected
        }
    }

    /// Only changed fields are sent; config omitted from a mutation remains server-owned.
    func saveChannel(_ draft: ChannelDraft, target: ManagementTarget, willWrite: () -> Void) async throws {
        guard target.kind == .channel, target.entityID == draft.original?["id"].string else { throw ManagementError.changedTarget }
        let input = try draft.payload()
        let cli = try beginManagement(target)
        defer { managementBusy = false }
        if let id = target.entityID {
            guard let fresh = try await cli.channelDetail(id: id), let original = draft.original else { throw AxonAPIError.invalidResponse }
            if input["credentials"] != nil || input["settings"] != nil {
                guard fresh["updatedAt"] == original["updatedAt"] else { throw ManagementError.changedTarget }
            }
            try checkConflicts(fresh, original: original, input: input.filter { $0.key != "settings" })
        }
        try validateTarget(target)
        if input.isEmpty { return }
        willWrite()
        let id: String
        if let existing = target.entityID { try await cli.editChannel(id: existing, input: input); id = existing }
        else if let source = draft.duplicateSourceID { id = try await cli.duplicateChannel(sourceID: source, input: input) }
        else { id = try await cli.createChannel(input: input) }
        guard let publicDetail = try await cli.channelDetail(id: id), publicDetail["id"].string == id else { throw ManagementError.verification }
        var detail = publicDetail
        if draft.secretsLoaded || draft.authorizeReadback {
            let authorized = try await cli.channelSecrets(id: id)
            var fields = detail.object; fields["settings"] = authorized["settings"]; detail = .object(fields)
            if let expected = input["credentials"] { try Self.verifyCredentials(authorized["credentials"], expected: expected) }
        }
        try verify(detail, input: input.filter { draft.secretsLoaded || draft.authorizeReadback || $0.key != "settings" })
        try validateTarget(target)
        await refresh()
        try validateTarget(target)
    }

    func saveModel(_ draft: ModelDraft, target: ManagementTarget, willWrite: () -> Void) async throws {
        guard target.kind == .model, target.entityID == draft.original?["id"].string else { throw ManagementError.changedTarget }
        let input = try draft.payload()
        let cli = try beginManagement(target)
        defer { managementBusy = false }
        if let id = target.entityID {
            guard let fresh = try await cli.modelDetail(id: id), let original = draft.original else { throw AxonAPIError.invalidResponse }
            try checkConflicts(fresh, original: original, input: input)
        }
        // Disabled/unroutable models are valid web configuration; preview is explicit,
        // do not prevent operators from storing draft routing or empty associations.
        try validateTarget(target)
        if input.isEmpty { return }
        willWrite()
        let id: String
        if let existing = target.entityID { try await cli.editModel(id: existing, input: input); id = existing }
        else { id = try await cli.createModel(input: input) }
        guard let detail = try await cli.modelDetail(id: id), detail["id"].string == id else { throw ManagementError.verification }
        try verify(detail, input: input)
        try validateTarget(target)
        await refresh()
        try validateTarget(target)
    }

    private func checkConflicts(_ fresh: JSON, original: JSON, input: [String: JSON]) throws {
        for key in input.keys {
            if key == "credentials" { continue } // protected credential revision is checked separately.
            let field = key == "clearBaseURL" ? "baseURL" : key
            guard fresh[field] == original[field] else { throw ManagementError.changedTarget }
        }
    }

    func deleteManagedEntity(_ target: ManagementTarget) async throws {
        let cli = try beginManagement(target)
        defer { managementBusy = false }
        guard let id = target.entityID else { throw AxonAPIError.invalidResponse }
        switch target.kind {
        case .channel:
            try await cli.deleteChannel(id: id)
            guard try await cli.channelDetail(id: id) == nil else { throw ManagementError.verification }
        case .model:
            try await cli.deleteModel(id: id)
            guard try await cli.modelDetail(id: id) == nil else { throw ManagementError.verification }
        }
        try validateTarget(target)
        await refresh()
        try validateTarget(target)
    }

    static func verifyCredentials(_ actual: JSON, expected: JSON) throws {
        for (key, value) in expected.object where key != "managementApiKey" {
            if key == "apiKey", !value.string.isEmpty, actual["apiKey"].string.isEmpty {
                guard actual["apiKeys"].array.contains(value) else { throw ManagementError.verification }
            } else { guard matches(actual[key], expected: value) else { throw ManagementError.verification } }
        }
        // beta10 output has no managementApiKey field; ZenMux preserves it in Go.
    }

    var selectedInstance: AxonInstance? {
        instances.first { $0.id == selectedID }
    }

    init(defaults: UserDefaults = .standard, dependencies: AxonStoreDependencies? = nil) {
        self.defaults = defaults
        self.dashboard = DashboardCacheModel(defaults: defaults)
        self.dependencies = dependencies ?? .live
        // Read both values before assigning any @Published property: its observer
        // must not overwrite the saved selection with the initial empty string.
        let savedID = defaults.string(forKey: "axon_selected_id") ?? ""
        let saved = defaults.data(forKey: "axon_instances")
            .flatMap { try? JSONDecoder().decode([AxonInstance].self, from: $0) } ?? []
        self.instances = saved
        self.selectedID = saved.contains(where: { $0.id == savedID }) ? savedID : saved.first?.id ?? ""
        isRestoring = false
        persist()
        dashboard.prepare(self)
    }

    func persist() {
        guard !isRestoring else { return }
        if let data = try? JSONEncoder().encode(instances) {
            defaults.set(data, forKey: "axon_instances")
        }
        defaults.set(selectedID, forKey: "axon_selected_id")
    }

    func invalidateClient() {
        pageCache.invalidate()
        entityNames.reset()
        managementRevision = UUID()
        refreshGeneration = UUID()
        fetchTask?.cancel()
        fetchTask = nil
        loading = false
        client = nil
        snapshot = AxonSnapshot()
        error = nil
        lastUpdated = nil
        dashboard.prepare(self)
    }

    func ensureClient() throws -> AxonClient {
        if let client = client { return client }
        guard let current = selectedInstance else {
            throw AxonAPIError.invalidURL
        }
        let token = try dependencies.loadCredential(current.id)
        var configuration = URLSessionConfiguration.ephemeral
        #if DEBUG && targetEnvironment(simulator)
        if ReadmePreview.enabled { configuration = ReadmePreview.configuration }
        #endif
        let newClient = try AxonClient(
            baseURL: current.address,
            authType: current.authType,
            token: token,
            allowHTTP: current.allowHTTP,
            configuration: configuration
        )
        self.client = newClient
        return newClient
    }

    func refresh() async {
        pageCache.invalidate()
        guard !Task.isCancelled, let current = selectedInstance else { return }
        fetchTask?.cancel()
        let generation = UUID()
        refreshGeneration = generation
        loading = true
        error = nil

        let task = Task { @MainActor [weak self] in
            guard let self = self else { return }
            defer {
                if self.refreshGeneration == generation {
                    self.loading = false
                    self.fetchTask = nil
                }
            }
            do {
                try Task.checkCancellation()
                let cli = try self.ensureClient()
                let snap = try await self.dependencies.fetchSnapshot(cli)
                try Task.checkCancellation()
                guard self.refreshGeneration == generation, self.selectedID == current.id else { return }
                self.snapshot = snap
                self.lastUpdated = Date()
                self.error = nil
            } catch {
                guard !Task.isCancelled, !(error is CancellationError),
                      self.refreshGeneration == generation, self.selectedID == current.id else { return }
                self.error = error.localizedDescription
            }
        }
        fetchTask = task
        await withTaskCancellationHandler(operation: {
            await task.value
        }, onCancel: {
            task.cancel()
        })
    }

    func addInstance(name: String, address: String, allowHTTP: Bool, authType: AxonAuthType, email: String, secret: String) async throws {
        let instance = AxonInstance(
            id: UUID().uuidString,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            address: address.trimmingCharacters(in: .whitespacesAndNewlines),
            allowHTTP: allowHTTP,
            authType: authType,
            adminEmail: email.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        guard !instance.name.isEmpty else { throw AxonAPIError.invalidCredentials }
        let token = try await dependencies.authenticate(instance, secret)
        try Task.checkCancellation()
        try dependencies.saveCredential(token, instance.id)
        instances.append(instance)
        selectedID = instance.id
        await refresh()
    }

    func updateInstance(id: String, name: String, address: String, allowHTTP: Bool, authType: AxonAuthType, email: String, secret: String) async throws {
        guard let original = instances.first(where: { $0.id == id }) else {
            throw AxonAPIError.invalidResponse
        }
        let revision = instanceRevisions[id]
        var updated = original // Keep id and createdAt, never expose the saved secret.
        updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.allowHTTP = allowHTTP
        updated.authType = authType
        updated.adminEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !updated.name.isEmpty else { throw AxonAPIError.invalidCredentials }
        let requiresNewSecret = original.address != updated.address ||
            original.authType != updated.authType || original.adminEmail != updated.adminEmail
        let hasSecret = !secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard !requiresNewSecret || hasSecret else { throw AxonAPIError.invalidCredentials }
        // URL validation is local; it does not send the old token to a changed origin.
        _ = try AxonClient(baseURL: updated.address, authType: updated.authType,
                           token: "", allowHTTP: updated.allowHTTP)
        let token: String?
        if hasSecret {
            token = try await dependencies.authenticate(updated, secret)
        } else {
            token = nil // Name-only edits leave Keychain untouched, including expired keys.
        }
        try Task.checkCancellation()
        // Authentication suspends. Do not resurrect a deleted instance or overwrite
        // a newer edit that completed while this one was checking credentials.
        guard instances.first(where: { $0.id == id }) == original, instanceRevisions[id] == revision,
              let index = instances.firstIndex(where: { $0.id == id }) else {
            throw AxonAPIError.invalidResponse
        }
        if let token = token {
            try dependencies.saveCredential(token, id)
        }
        instanceRevisions[id] = UUID()
        instances[index] = updated
        if selectedID == id && (token != nil || original.allowHTTP != updated.allowHTTP) {
            invalidateClient()
            await refresh()
        }
    }

    func deleteInstance(id: String) {
        instanceRevisions[id] = UUID()
        dependencies.deleteCredential(id)
        instances.removeAll { $0.id == id }
        if selectedID == id {
            selectedID = instances.first?.id ?? ""
        }
    }

    func toggleChannel(id: String, enabled: Bool, target: ManagementTarget? = nil) async throws {
        let bound = try target ?? managementTarget(kind: .channel, entityID: id)
        guard bound.entityID == id else { throw ManagementError.changedTarget }
        let cli = try beginManagement(bound)
        defer { managementBusy = false }
        try await cli.updateChannelStatus(id: id, enabled: enabled)
        guard let detail = try await cli.channelDetail(id: id), detail["id"].string == id,
              detail["status"].string == (enabled ? "enabled" : "disabled") else { throw ManagementError.verification }
        try validateTarget(bound)
        await refresh()
        try validateTarget(bound)
    }

    func toggleModel(id: String, enabled: Bool, target: ManagementTarget? = nil) async throws {
        let bound = try target ?? managementTarget(kind: .model, entityID: id)
        guard bound.entityID == id else { throw ManagementError.changedTarget }
        let cli = try beginManagement(bound)
        defer { managementBusy = false }
        try await cli.updateModelStatus(id: id, enabled: enabled)
        guard let detail = try await cli.modelDetail(id: id), detail["id"].string == id,
              detail["status"].string == (enabled ? "enabled" : "disabled") else { throw ManagementError.verification }
        try validateTarget(bound)
        await refresh()
        try validateTarget(bound)
    }

    func testChannel(id: String, model: String? = nil, target: ManagementTarget? = nil) async throws -> (success: Bool, latencyMs: Int, error: String?) {
        let bound = try target ?? managementTarget(kind: .channel, entityID: id)
        guard bound.entityID == id else { throw ManagementError.changedTarget }
        let cli = try beginManagement(bound)
        defer { managementBusy = false }
        let result = try await cli.testChannel(id: id, model: model)
        try validateTarget(bound)
        // Provider errors can contain sensitive request headers or credentials.
        return (result.success, result.latencyMs, result.success ? nil : NSLocalizedString("服务端连通性测试失败。为保护凭据，不显示上游原始错误文本。", comment: ""))
    }
}
