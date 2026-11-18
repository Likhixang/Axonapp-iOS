import XCTest
@testable import AxonCore

/// Runs the option queries against a real AxonHub server. Skipped unless AXON_LIVE_URL and
/// AXON_LIVE_TOKEN (an owner's JWT) are set, so CI does not need a server.
final class LiveServerTests: XCTestCase {
    private func service() throws -> AxonService {
        let env = ProcessInfo.processInfo.environment
        guard let raw = env["AXON_LIVE_URL"], let url = URL(string: raw), let token = env["AXON_LIVE_TOKEN"] else {
            throw XCTSkip("AXON_LIVE_URL / AXON_LIVE_TOKEN not set")
        }
        return AxonService(client: APIClient(baseURL: url, token: token))
    }

    func testOptionQueriesReturnData() async throws {
        let service = try service()
        let tags = try await service.allChannelTags()
        XCTAssertFalse(tags.isEmpty, "allChannelTags")
        _ = try await service.proxyPresets()
        let mode = try await service.quotaRoutingDefaultMode()
        XCTAssertTrue(ChannelChoices.quotaRoutingModes.contains { $0.value == mode }, mode)

        let channels = try await service.channelOptions()
        XCTAssertFalse(channels.isEmpty, "channelOptions")
        XCTAssertFalse(channels.flatMap { $0.allModelEntries ?? [] }.isEmpty, "allModelEntries")
        XCTAssertFalse(ChannelOption.playgroundChannels(channels).isEmpty, "playground channels")

        let models = try await service.queryModels(includeMapping: true, includePrefix: true)
        XCTAssertFalse(models.isEmpty, "queryModels")
        let catalog = try await service.providersCatalog()
        XCTAssertFalse(catalog.providers.isEmpty, "providersCatalog")
        print("LIVE tags=\(tags) quotaDefault=\(mode) channels=\(channels.count) queryModels=\(models.count) catalogProviders=\(catalog.providers.count)")
    }

    func testChannelSettingsRoundTrip() async throws {
        let service = try service()
        let created = try await service.createChannel([
            "type": .string("openai"), "name": .string("live-\(UUID().uuidString.prefix(6))"),
            "baseURL": .string("http://127.0.0.1:9/v1"),
            "credentials": .object(["apiKey": .string("sk-live")]),
            "supportedModels": .strings(["gpt-4o"]), "defaultTestModel": .string("gpt-4o"),
            "tags": .strings(["live"]),
            "settings": .object(ChannelChoices.settingsFields(
                apiKeyStrategy: "round_robin", switchAfter: 4, quotaRoutingMode: "BACKPRESSURE",
                proxy: ChannelChoices.proxyInput(type: "url", url: "http://proxy:8080", username: "u", password: "p", disableConnectionReuse: true))),
            "policies": .object(["stream": .string("require")]),
        ])
        var channel = try await service.channel(id: created.id)
        XCTAssertEqual(channel.settings?.apiKeyStrategy, "round_robin")
        XCTAssertEqual(channel.settings?.apiKeyRoundRobinSwitchAfter, 4)
        XCTAssertEqual(ChannelChoices.quotaRoutingMode(from: channel.settings), "BACKPRESSURE")
        XCTAssertEqual(ChannelChoices.proxyType(channel.settings?.proxy?.type), "url")
        XCTAssertEqual(channel.settings?.proxy?.url, "http://proxy:8080")
        XCTAssertEqual(ChannelChoices.streamPolicy(from: channel.policies), "require")

        _ = try await service.updateChannel(id: channel.id, [
            "policies": ChannelChoices.policiesInput(existing: channel.policies, stream: "forbid"),
        ])
        _ = try await service.updateChannelSettings(id: channel.id, ChannelChoices.settingsFields(
            apiKeyStrategy: "priority", switchAfter: 1, quotaRoutingMode: "INHERIT",
            proxy: ChannelChoices.proxyInput(type: "environment", url: "", username: "", password: "", disableConnectionReuse: false)))
        channel = try await service.channel(id: created.id)
        XCTAssertEqual(channel.settings?.apiKeyStrategy, "priority")
        XCTAssertEqual(ChannelChoices.quotaRoutingMode(from: channel.settings), "INHERIT")
        XCTAssertEqual(ChannelChoices.proxyType(channel.settings?.proxy?.type), "environment")
        XCTAssertEqual(ChannelChoices.streamPolicy(from: channel.policies), "forbid")
        let tagsAfter = try await service.allChannelTags()
        XCTAssertTrue(tagsAfter.contains("live"))
    }

    func testRolesUsersAndProfiles() async throws {
        let service = try service()
        let scopes = try await service.systemScopes()
        XCTAssertFalse(scopes.isEmpty, "allScopes")
        let picked = Array(scopes.prefix(2).map(\.scope))
        let role = try await service.createRole(RoleEditor.createInput(name: "live-role-\(UUID().uuidString.prefix(4))", scopes: picked))
        let roles = try await service.systemRoles()
        XCTAssertTrue(roles.contains { $0.id == role.id })
        let updatedRole = try await service.updateRole(id: role.id, RoleEditor.updateInput(name: role.name, scopes: [picked[0]]))
        XCTAssertEqual(updatedRole.scopes, [picked[0]])

        let email = "live\(UUID().uuidString.prefix(6).lowercased())@test.local"
        try await service.createUser(UserEditor.createInput(firstName: "Live", lastName: "User", email: email, password: "secret12",
                                                            isOwner: false, scopes: [picked[1]], roleIDs: [role.id]))
        let users = try await service.users(after: nil, search: email)
        let userID = try XCTUnwrap(users.items.first { $0.email == email }?.id)
        var detail = try await service.userDetail(id: userID)
        XCTAssertEqual(detail.roleIDs, [role.id])
        XCTAssertEqual(detail.scopes, [picked[1]])
        try await service.updateUser(id: userID, UserEditor.updateInput(firstName: "Live", lastName: "User", email: email, isOwner: false,
                                                                        scopes: [], roleIDs: [], currentRoleIDs: detail.roleIDs))
        detail = try await service.userDetail(id: userID)
        XCTAssertEqual(detail.roleIDs, [])
        XCTAssertEqual(detail.scopes ?? [], [])
        try await service.deleteRole(id: role.id)

        let projects = try await service.projects(after: nil)
        let project = try XCTUnwrap(projects.items.first)
        let channels = try await service.channelOptions()
        var draft = ProfilesDraft(project.profiles)
        draft.addProfile()
        let index = draft.profiles.count - 1
        draft.profiles[index].channelIDs = channels.compactMap(\.numericID).prefix(1).map { $0 }
        draft.profiles[index].channelTags = ["live"]
        draft.profiles[index].matchMode = "all"
        draft.activeProfile = draft.profiles[index].name
        let saved = try await service.updateProjectProfiles(id: project.id, draft)
        let stored = try XCTUnwrap(saved.profiles?.profiles?.last)
        XCTAssertEqual(saved.profiles?.activeProfile, draft.profiles[index].name)
        XCTAssertEqual(stored.channelTags, ["live"])
        XCTAssertEqual(stored.channelTagsMatchMode, "all")
        XCTAssertEqual(stored.channelIDs ?? [], draft.profiles[index].channelIDs)
        let reloaded = try await service.projects(after: nil).items.first { $0.id == project.id }
        XCTAssertEqual(reloaded?.profiles?.activeProfile, draft.profiles[index].name)
    }
}
