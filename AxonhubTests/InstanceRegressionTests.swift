import XCTest
@testable import Axonhub

/// Runs real AxonStore state transitions with isolated defaults and controlled I/O.
/// Run with the Axonhub scheme on an iOS simulator; Linux fallback is instance_regression.py.
@MainActor final class InstanceRegressionTests: XCTestCase {
    @MainActor private final class Harness {
        let defaults: UserDefaults
        var keys: [String: String] = [:]
        var authCalls = 0
        var saveCalls = 0
        var failAuthentication = false
        var failSave = false
        var authenticateHook: ((AxonInstance, String) async throws -> String)?
        var fetchHook: ((AxonClient) async throws -> AxonSnapshot)?

        init() {
            defaults = UserDefaults(suiteName: "AxonInstanceRegression.\(UUID().uuidString)")!
        }

        func seed(_ records: [AxonInstance], selection: String?) throws {
            defaults.set(try JSONEncoder().encode(records), forKey: "axon_instances")
            if let selection = selection { defaults.set(selection, forKey: "axon_selected_id") }
            for item in records { keys[item.id] = "key-\(item.id)" }
        }

        func makeStore() -> AxonStore {
            let dependencies = AxonStoreDependencies(
                loadCredential: { id in
                    guard let token = self.keys[id] else { throw AxonAPIError.unauthorized }
                    return token
                },
                saveCredential: { token, id in
                    self.saveCalls += 1
                    if self.failSave { throw AxonAPIError.invalidCredentials }
                    self.keys[id] = token
                },
                deleteCredential: { self.keys.removeValue(forKey: $0) },
                authenticate: { instance, secret in
                    self.authCalls += 1
                    if let hook = self.authenticateHook { return try await hook(instance, secret) }
                    if self.failAuthentication { throw AxonAPIError.unauthorized }
                    return secret
                },
                fetchSnapshot: { client in
                    if let hook = self.fetchHook { return try await hook(client) }
                    return AxonSnapshot()
                }
            )
            return AxonStore(defaults: defaults, dependencies: dependencies)
        }
    }

    @MainActor private final class FetchGate {
        var pending: [String: CheckedContinuation<AxonSnapshot, Error>] = [:]
        func fetch(_ client: AxonClient) async throws -> AxonSnapshot {
            try await withCheckedThrowingContinuation { pending[client.token] = $0 }
        }
        func waitFor(_ key: String) async {
            for _ in 0..<1000 {
                if pending[key] != nil { return }
                await Task.yield()
            }
            XCTFail("Fetch did not start: \(key)")
        }
        func complete(_ key: String, count: Int) {
            var snapshot = AxonSnapshot()
            snapshot.dashboard.totalRequests = count
            pending.removeValue(forKey: key)?.resume(returning: snapshot)
        }
    }

    private func instance(_ id: String) -> AxonInstance {
        AxonInstance(id: id, name: id, address: "https://\(id).example", authType: .apiKey,
                     createdAt: Date(timeIntervalSince1970: 123))
    }

    private func update(_ store: AxonStore, _ item: AxonInstance, secret: String = "") async throws {
        try await store.updateInstance(id: item.id, name: item.name, address: item.address,
            allowHTTP: item.allowHTTP, authType: item.authType, email: item.adminEmail, secret: secret)
    }

    func testSelectedSecondInstanceSurvivesRestorationAndRelaunch() throws {
        let h = Harness()
        try h.seed([instance("a"), instance("b")], selection: "b")
        let store = h.makeStore()
        XCTAssertEqual(store.selectedID, "b")
        XCTAssertEqual(h.defaults.string(forKey: "axon_selected_id"), "b")
        XCTAssertEqual(h.makeStore().selectedID, "b")
        store.selectedID = "a"
        XCTAssertEqual(h.makeStore().selectedID, "a")
    }

    func testMissingEmptyAndDeletedSelectionFallBackToFirstInstance() throws {
        for selection in [nil, "", "deleted"] as [String?] {
            let h = Harness()
            try h.seed([instance("a"), instance("b")], selection: selection)
            XCTAssertEqual(h.makeStore().selectedID, "a")
            XCTAssertEqual(h.defaults.string(forKey: "axon_selected_id"), "a")
        }
        let h = Harness()
        try h.seed([], selection: "deleted")
        XCTAssertEqual(h.makeStore().selectedID, "")
        h.defaults.set(Data("not JSON".utf8), forKey: "axon_instances")
        XCTAssertTrue(h.makeStore().instances.isEmpty)
    }

    func testNameOnlyEditKeepsIdentityCreationDateAndCredential() async throws {
        let h = Harness()
        let original = instance("a")
        try h.seed([original], selection: "a")
        let store = h.makeStore()
        store.snapshot.dashboard.totalRequests = 42
        var changed = original
        changed.name = "  Renamed  "
        try await update(store, changed)
        XCTAssertEqual(store.instances[0].name, "Renamed")
        XCTAssertEqual(store.instances[0].id, original.id)
        XCTAssertEqual(store.instances[0].createdAt, original.createdAt)
        XCTAssertEqual(h.keys[original.id], "key-a")
        XCTAssertEqual(h.authCalls, 0)
        XCTAssertEqual(h.saveCalls, 0)
        XCTAssertEqual(store.snapshot.dashboard.totalRequests, 42)
        XCTAssertEqual(h.makeStore().instances[0].name, "Renamed")
    }

    func testAddressAuthTypeAndEmailChangesRequireNewCredential() async throws {
        let h = Harness()
        let original = instance("a")
        try h.seed([original], selection: "a")
        let store = h.makeStore()
        var address = original; address.address = "https://new.example"
        var auth = original; auth.authType = .adminJWT
        var email = original; email.adminEmail = "admin@example.org"
        for item in [address, auth, email] {
            do {
                try await update(store, item)
                XCTFail("Changed credential context must not reuse old token")
            } catch { XCTAssertEqual(error as? AxonAPIError, .invalidCredentials) }
            XCTAssertEqual(store.instances, [original])
            XCTAssertEqual(h.keys[original.id], "key-a")
        }
        XCTAssertEqual(h.authCalls, 0)
        XCTAssertEqual(h.saveCalls, 0)
    }

    func testFailedAuthenticationAndFailedSaveLeaveExistingEditUntouched() async throws {
        let h = Harness()
        let original = instance("a")
        try h.seed([original], selection: "a")
        let store = h.makeStore()
        var changed = original
        changed.address = "https://new.example"
        changed.name = "changed"
        h.failAuthentication = true
        do { try await update(store, changed, secret: "replacement"); XCTFail("Must fail") }
        catch { XCTAssertEqual(error as? AxonAPIError, .unauthorized) }
        XCTAssertEqual(h.saveCalls, 0)
        XCTAssertEqual(store.instances, [original])
        XCTAssertEqual(h.keys[original.id], "key-a")
        h.failAuthentication = false
        h.failSave = true
        do { try await update(store, changed, secret: "replacement"); XCTFail("Must fail") }
        catch { XCTAssertEqual(error as? AxonAPIError, .invalidCredentials) }
        XCTAssertEqual(store.instances, [original])
        XCTAssertEqual(h.keys[original.id], "key-a")
        XCTAssertEqual(h.makeStore().instances, [original])
    }

    func testCredentialRotationPreservesSelectionAndInvalidatesCachedClient() async throws {
        let h = Harness()
        let original = instance("a")
        try h.seed([original, instance("b")], selection: "a")
        let store = h.makeStore()
        XCTAssertEqual(try store.ensureClient().token, "key-a")
        try await update(store, original, secret: "replacement")
        XCTAssertEqual(try store.ensureClient().token, "replacement")
        XCTAssertEqual(store.selectedID, "a")
        XCTAssertEqual(store.instances[0].createdAt, original.createdAt)
        var other = instance("b"); other.name = "other renamed"
        try await update(store, other)
        XCTAssertEqual(store.selectedID, "a")
        XCTAssertEqual(h.makeStore().selectedID, "a")
    }

    func testSuccessfulAddressEditUsesOnlyReplacementCredential() async throws {
        let h = Harness()
        let original = instance("a")
        try h.seed([original], selection: "a")
        let store = h.makeStore()
        _ = try store.ensureClient()
        var changed = original
        changed.address = "https://new.example/deployment"
        h.authenticateHook = { candidate, secret in
            XCTAssertEqual(candidate.address, changed.address)
            XCTAssertEqual(secret, "replacement")
            XCTAssertEqual(h.keys[original.id], "key-a") // Old key remains until validation succeeds.
            XCTAssertEqual(store.instances, [original])
            return "replacement"
        }
        try await update(store, changed, secret: "replacement")
        XCTAssertEqual(store.instances[0].address, changed.address)
        XCTAssertEqual(store.instances[0].id, original.id)
        XCTAssertEqual(store.instances[0].createdAt, original.createdAt)
        XCTAssertEqual(store.selectedID, "a")
        XCTAssertEqual(try store.ensureClient().token, "replacement")
        XCTAssertEqual(try store.ensureClient().baseURL.absoluteString, changed.address)
        XCTAssertEqual(h.makeStore().instances, [changed])
    }

    func testInvalidAddressFailsBeforeAuthenticationOrStorage() async throws {
        let h = Harness()
        let original = instance("a")
        try h.seed([original], selection: "a")
        let store = h.makeStore()
        var changed = original
        changed.address = "https://user:password@new.example"
        do { try await update(store, changed, secret: "replacement"); XCTFail("Invalid URL must fail") }
        catch { XCTAssertEqual(error as? AxonAPIError, .invalidURL) }
        XCTAssertEqual(h.authCalls, 0)
        XCTAssertEqual(h.saveCalls, 0)
        XCTAssertEqual(store.instances, [original])
    }

    func testConcurrentCredentialOnlyEditCannotOverwriteNewerCredential() async throws {
        let h = Harness()
        let original = instance("a")
        try h.seed([original], selection: "a")
        var continuation: CheckedContinuation<String, Error>?
        h.authenticateHook = { _, secret in
            if secret == "old replacement" {
                return try await withCheckedThrowingContinuation { continuation = $0 }
            }
            return secret
        }
        let store = h.makeStore()
        let old = Task { try await self.update(store, original, secret: "old replacement") }
        for _ in 0..<1000 {
            if continuation != nil { break }
            await Task.yield()
        }
        XCTAssertNotNil(continuation)
        try await update(store, original, secret: "new replacement")
        continuation?.resume(returning: "old replacement")
        do { try await old.value; XCTFail("Older edit must fail even when metadata is identical") }
        catch { XCTAssertEqual(error as? AxonAPIError, .invalidResponse) }
        XCTAssertEqual(h.keys[original.id], "new replacement")
        XCTAssertEqual(h.saveCalls, 1)
    }

    func testDeletedInstanceCannotBeResurrectedBySuspendedEdit() async throws {
        let h = Harness()
        let original = instance("a")
        try h.seed([original], selection: "a")
        var continuation: CheckedContinuation<String, Error>?
        h.authenticateHook = { _, _ in
            try await withCheckedThrowingContinuation { continuation = $0 }
        }
        let store = h.makeStore()
        let edit = Task { try await self.update(store, original, secret: "replacement") }
        for _ in 0..<1000 {
            if continuation != nil { break }
            await Task.yield()
        }
        XCTAssertNotNil(continuation)
        store.deleteInstance(id: original.id)
        continuation?.resume(returning: "replacement")
        do { try await edit.value; XCTFail("Deleted target must fail") }
        catch { XCTAssertEqual(error as? AxonAPIError, .invalidResponse) }
        XCTAssertTrue(store.instances.isEmpty)
        XCTAssertNil(h.keys[original.id])
        XCTAssertEqual(h.saveCalls, 0)
    }

    func testLateRefreshCannotOverwriteNewInstanceOrStopItsLoading() async throws {
        let h = Harness()
        try h.seed([instance("a"), instance("b")], selection: "a")
        let gate = FetchGate()
        h.fetchHook = { try await gate.fetch($0) }
        let store = h.makeStore()
        let first = Task { await store.refresh() }
        await gate.waitFor("key-a")
        store.selectedID = "b"
        let second = Task { await store.refresh() }
        await gate.waitFor("key-b")
        gate.complete("key-a", count: 111) // Transport deliberately ignores cancellation.
        await first.value
        XCTAssertEqual(store.selectedID, "b")
        XCTAssertTrue(store.loading)
        XCTAssertEqual(store.snapshot.dashboard.totalRequests, 0)
        gate.complete("key-b", count: 222)
        await second.value
        XCTAssertEqual(store.snapshot.dashboard.totalRequests, 222)
        XCTAssertFalse(store.loading)
        XCTAssertEqual(h.makeStore().selectedID, "b")
    }

    func testCancelledRefreshAndLateFailureNeverClearSelection() async throws {
        let h = Harness()
        try h.seed([instance("a"), instance("b")], selection: "a")
        let gate = FetchGate()
        h.fetchHook = { try await gate.fetch($0) }
        let store = h.makeStore()
        let first = Task { await store.refresh() }
        await gate.waitFor("key-a")
        first.cancel()
        gate.complete("key-a", count: 111)
        await first.value
        XCTAssertEqual(store.selectedID, "a")
        XCTAssertFalse(store.loading)
        XCTAssertEqual(store.snapshot.dashboard.totalRequests, 0)
        let old = Task { await store.refresh() }
        await gate.waitFor("key-a")
        store.selectedID = "b"
        gate.pending.removeValue(forKey: "key-a")?.resume(throwing: AxonAPIError.unauthorized)
        await old.value
        XCTAssertNil(store.error)
        XCTAssertEqual(store.selectedID, "b")
    }

    func testDeletionKeepsOtherSelectionAndFallsBackAfterSelectedDeletion() throws {
        let h = Harness()
        try h.seed([instance("a"), instance("b"), instance("c")], selection: "b")
        let store = h.makeStore()
        store.deleteInstance(id: "a")
        XCTAssertEqual(store.selectedID, "b")
        store.deleteInstance(id: "b")
        XCTAssertEqual(store.selectedID, "c")
        XCTAssertEqual(h.makeStore().selectedID, "c")
        store.deleteInstance(id: "c")
        XCTAssertEqual(store.selectedID, "")
        XCTAssertTrue(h.makeStore().instances.isEmpty)
    }
}
