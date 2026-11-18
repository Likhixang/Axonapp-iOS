import XCTest
@testable import AxonCore

final class ChannelChoiceTests: XCTestCase {
    func testFixedSelectsMatchTheWebConsole() {
        XCTAssertEqual(ChannelChoices.apiKeyStrategies.map(\.value),
                       ["sticky", "random", "round_robin", "round_robin_success", "priority", "fixed"])
        XCTAssertEqual(ChannelChoices.quotaRoutingModes.map(\.value),
                       ["INHERIT", "IGNORE_QUOTA", "REMOVE_ON_EXHAUSTED", "BACKPRESSURE"])
        XCTAssertEqual(ChannelChoices.streamPolicies.map(\.value), ["unlimited", "require", "forbid"])
        XCTAssertEqual(ChannelChoices.proxyTypes.map(\.value), ["disabled", "environment", "url"])
        XCTAssertTrue(ChannelChoices.isRoundRobin("round_robin_success"))
        XCTAssertFalse(ChannelChoices.isRoundRobin("sticky"))
    }

    func testQuotaRoutingLabelNamesTheSystemDefault() {
        XCTAssertEqual(ChannelChoices.quotaRoutingLabel("INHERIT", systemDefault: "REMOVE_ON_EXHAUSTED"),
                       "继承全局默认值（当前：达到限额后摘除）")
        XCTAssertEqual(ChannelChoices.quotaRoutingLabel("INHERIT", systemDefault: nil), "继承全局默认值")
        XCTAssertEqual(ChannelChoices.quotaRoutingLabel("BACKPRESSURE", systemDefault: "IGNORE_QUOTA"), "基于用量和时长限流")
    }

    func testStoredValuesNormalize() throws {
        let settings = try JSONDecoder().decode(ChannelSettings.self, from: Data("""
        {"extraModelPrefix":null,"modelMappings":[],"proxy":{"type":"URL","url":"http://p:8080"},
         "apiKeyStrategy":"round_robin","apiKeyRoundRobinSwitchAfter":3,"quotaRoutingMode":"BACKPRESSURE"}
        """.utf8))
        XCTAssertEqual(ChannelChoices.proxyType(settings.proxy?.type), "url")
        XCTAssertEqual(settings.apiKeyRoundRobinSwitchAfter, 3)
        XCTAssertEqual(ChannelChoices.quotaRoutingMode(from: settings), "BACKPRESSURE")
        XCTAssertEqual(ChannelChoices.quotaRoutingMode(from: nil), "INHERIT")
        XCTAssertEqual(ChannelChoices.proxyType(nil), "disabled")
        XCTAssertEqual(ChannelChoices.proxyType("bogus"), "disabled")
    }

    func testPoliciesInputKeepsAutoDisableRules() throws {
        let stored = try JSONDecoder().decode(JSONValue.self, from: Data("""
        {"stream":"unlimited","apiKeyAutoDisableMode":"custom",
         "apiKeyAutoDisableRules":[{"statusCodes":[429],"times":3}],"unused":null}
        """.utf8))
        XCTAssertEqual(ChannelChoices.streamPolicy(from: stored), "unlimited")
        let input = ChannelChoices.policiesInput(existing: stored, stream: "forbid")
        XCTAssertEqual(input["stream"]?.stringValue, "forbid")
        XCTAssertEqual(input["apiKeyAutoDisableMode"]?.stringValue, "custom")
        XCTAssertNotNil(input["apiKeyAutoDisableRules"])
        XCTAssertNil(input["unused"])
        XCTAssertEqual(ChannelChoices.policiesInput(existing: nil, stream: "require"), .object(["stream": .string("require")]))
        XCTAssertEqual(ChannelChoices.streamPolicy(from: nil), "unlimited")
    }

    func testProxyAndSettingsInputs() {
        XCTAssertEqual(ChannelChoices.proxyInput(type: "disabled", url: "http://x", username: "u", password: "p", disableConnectionReuse: true),
                       .object(["type": .string("disabled")]))
        XCTAssertEqual(ChannelChoices.proxyInput(type: "url", url: " http://p:8080 ", username: "", password: "", disableConnectionReuse: false),
                       .object(["type": .string("url"), "url": .string("http://p:8080")]))
        let full = ChannelChoices.proxyInput(type: "url", url: "http://p", username: "u", password: "pw", disableConnectionReuse: true)
        XCTAssertEqual(full["username"]?.stringValue, "u")
        XCTAssertEqual(full["password"]?.stringValue, "pw")
        XCTAssertEqual(full["disableConnectionReuse"], .bool(true))

        let proxy = JSONValue.object(["type": .string("environment")])
        let sticky = ChannelChoices.settingsFields(apiKeyStrategy: "sticky", switchAfter: 5, quotaRoutingMode: "INHERIT", proxy: proxy)
        XCTAssertNil(sticky["apiKeyRoundRobinSwitchAfter"])
        XCTAssertEqual(sticky["proxy"], proxy)
        let rr = ChannelChoices.settingsFields(apiKeyStrategy: "round_robin", switchAfter: 0, quotaRoutingMode: "IGNORE_QUOTA", proxy: proxy)
        XCTAssertEqual(rr["apiKeyRoundRobinSwitchAfter"], .int(1))
        XCTAssertEqual(rr["quotaRoutingMode"]?.stringValue, "IGNORE_QUOTA")
    }

    func testTagsSuggestAndParse() {
        XCTAssertEqual(ChannelChoices.parseTags("prod, cn，us\nbeta  "), ["prod", "cn", "us", "beta"])
        XCTAssertEqual(ChannelChoices.addTags("cn, new", to: ["prod", "cn"]), ["prod", "cn", "new"])
        XCTAssertEqual(ChannelChoices.tagSuggestions(all: ["prod", "dev", "cn"], selected: ["prod"], query: ""), ["dev", "cn"])
        XCTAssertEqual(ChannelChoices.tagSuggestions(all: ["prod", "dev", "cn"], selected: [], query: "D"), ["dev", "prod"])
    }

    func testQuickAddModelsComeFromTheWebDefaults() {
        XCTAssertEqual(ChannelDefaultModels.table.count, 75)
        XCTAssertFalse(ChannelDefaultModels.models(for: "openai").isEmpty)
        XCTAssertFalse(ChannelDefaultModels.models(for: "anthropic").isEmpty)
        XCTAssertEqual(ChannelDefaultModels.models(for: "no-such-type"), [])
        let all = ChannelDefaultModels.models(for: "openai")
        let rest = ChannelChoices.quickAddModels(type: "openai", existing: [all[0]])
        XCTAssertEqual(rest.count, all.count - 1)
        XCTAssertFalse(rest.contains(all[0]))
    }
}

final class PlaygroundChoiceTests: XCTestCase {
    private func channel(_ id: Int, status: String, models: [String]) -> ChannelOption {
        ChannelOption(id: "gid://axonhub/Channel/\(id)", name: "C\(id)", type: "openai", status: status, tags: nil, supportedModels: models)
    }

    func testPlaygroundOffersEnabledChannelsWithModels() {
        let channels = [channel(1, status: "enabled", models: ["a"]), channel(2, status: "disabled", models: ["b"]),
                        channel(3, status: "enabled", models: [])]
        XCTAssertEqual(ChannelOption.playgroundChannels(channels).map(\.numericID), [1])
    }

    func testChoosingAChannelNarrowsAndResolvesTheModel() {
        let channels = [channel(1, status: "enabled", models: ["gpt-4o", "gpt-4o-mini"])]
        let models = ChannelOption.playgroundModels(channelID: 1, channels: channels, fallback: ["claude"])
        XCTAssertEqual(models, ["gpt-4o", "gpt-4o-mini"])
        XCTAssertEqual(ChannelOption.playgroundModels(channelID: nil, channels: channels, fallback: ["claude"]), ["claude"])
        XCTAssertEqual(ChannelOption.resolveModel("claude", in: models), "gpt-4o")
        XCTAssertEqual(ChannelOption.resolveModel("gpt-4o-mini", in: models), "gpt-4o-mini")
        XCTAssertEqual(ChannelOption.resolveModel("x", in: []), "")
    }
}

final class AdminEditingTests: XCTestCase {
    func testUserInputs() {
        XCTAssertEqual(UserEditor.validationError(isEditing: false, email: "a@b.c", password: "12345", confirm: "12345"), "密码至少 6 位")
        XCTAssertEqual(UserEditor.validationError(isEditing: false, email: "a@b.c", password: "123456", confirm: "1234567"), "两次输入的密码不一致")
        XCTAssertEqual(UserEditor.validationError(isEditing: false, email: "nope", password: "123456", confirm: "123456"), "请填写有效的邮箱")
        XCTAssertNil(UserEditor.validationError(isEditing: true, email: "a@b.c", password: "", confirm: ""))

        let create = UserEditor.createInput(firstName: " A ", lastName: "B", email: "a@b.c ", password: "secret1",
                                            isOwner: false, scopes: ["read_channels"], roleIDs: ["r1"])
        XCTAssertEqual(create["firstName"]?.stringValue, "A")
        XCTAssertEqual(create["email"]?.stringValue, "a@b.c")
        XCTAssertEqual(create["roleIDs"], .strings(["r1"]))

        let update = UserEditor.updateInput(firstName: "A", lastName: "B", email: "a@b.c", isOwner: false,
                                            scopes: [], roleIDs: ["r2", "r3"], currentRoleIDs: ["r1", "r2"])
        XCTAssertEqual(update["addRoleIDs"], .strings(["r3"]))
        XCTAssertEqual(update["removeRoleIDs"], .strings(["r1"]))
        XCTAssertNil(update["password"])
        let unchanged = UserEditor.updateInput(firstName: "A", lastName: "B", email: "a@b.c", isOwner: true,
                                               scopes: [], roleIDs: ["r1"], currentRoleIDs: ["r1"])
        XCTAssertNil(unchanged["addRoleIDs"])
        XCTAssertNil(unchanged["removeRoleIDs"])

        XCTAssertEqual(MultiSelect.toggle("b", in: ["a", "b", "c"]), ["a", "c"])
        XCTAssertEqual(MultiSelect.toggle("d", in: ["a"]), ["a", "d"])
        XCTAssertEqual(RoleEditor.createInput(name: " Ops ", scopes: ["read_channels"])["level"]?.stringValue, "system")
    }

    func testUserDetailDecodesRoleEdges() throws {
        let user = try JSONDecoder().decode(UserDetail.self, from: Data("""
        {"id":"u","email":"a@b.c","firstName":"A","lastName":"B","isOwner":false,"scopes":["read_channels"],
         "roles":{"edges":[{"node":{"id":"r1","name":"Ops","level":"system","scopes":[]}}]}}
        """.utf8))
        XCTAssertEqual(user.roleIDs, ["r1"])
    }

    func testProfilesDraft() throws {
        var draft = ProfilesDraft()
        XCTAssertEqual(draft.validationError, "至少需要一个配置")
        draft.addProfile()
        draft.addProfile()
        XCTAssertEqual(draft.profiles.map(\.name), ["Profile 1", "Profile 2"])
        XCTAssertEqual(draft.activeProfile, "Profile 1")
        draft.rename(id: draft.profiles[0].id, to: "prod")
        XCTAssertEqual(draft.activeProfile, "prod")
        draft.rename(id: draft.profiles[1].id, to: "PROD")
        XCTAssertEqual(draft.validationError, "配置名称不能重复")
        draft.rename(id: draft.profiles[1].id, to: "dev")
        draft.profiles[0].channelIDs = [1, 2]
        draft.profiles[0].channelTags = ["cn"]
        draft.profiles[0].matchMode = "all"
        XCTAssertNil(draft.validationError)
        let input = draft.input
        XCTAssertEqual(input["activeProfile"]?.stringValue, "prod")
        guard case .array(let profiles)? = input["profiles"] else { return XCTFail("profiles") }
        XCTAssertEqual(profiles[0]["channelIDs"], .array([.int(1), .int(2)]))
        XCTAssertEqual(profiles[0]["channelTagsMatchMode"]?.stringValue, "all")
        draft.removeProfile(id: draft.profiles[0].id)
        XCTAssertEqual(draft.activeProfile, "dev")

        let stored = try JSONDecoder().decode(ProjectProfiles.self, from: Data("""
        {"activeProfile":"","profiles":[{"name":"x","channelIDs":null,"channelTags":["a"],"channelTagsMatchMode":"weird"}]}
        """.utf8))
        let loaded = ProfilesDraft(stored)
        XCTAssertEqual(loaded.activeProfile, "")
        XCTAssertEqual(loaded.profiles[0].matchMode, "any")
        XCTAssertEqual(loaded.profiles[0].channelIDs, [])
    }
}
