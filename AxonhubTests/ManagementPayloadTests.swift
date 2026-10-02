import XCTest
@testable import Axonhub

/// Exercises production draft serialization and target checks, not a parallel state model.
final class ManagementPayloadTests: XCTestCase {
    private let channel = JSON.from(#"{"id":"1","name":"Original","type":"openai","baseURL":null,"supportedModels":["upstream-chat"],"defaultTestModel":"upstream-chat","tags":[],"orderingWeight":0,"remark":null,"autoSyncSupportedModels":true,"manualModels":["manual"],"settings":{"unseen":true},"credentials":{"apiKeys":["a","b"],"oauth":{"accessToken":"keep"}}}"#)!
    private let model = JSON.from(#"{"id":"2","name":"Original","modelID":"alias","developer":"provider","type":"chat","group":"default","icon":"OpenAI","remark":null,"modelCard":{},"settings":{"associations":[{"type":"regex","regex":{"pattern":".*"},"when":{"enabled":true,"condition":{"type":"group","conditions":[{"field":"model","value":"alias"}]}}}],"loadBalancerStrategy":"failover"}}"#)!

    func testChannelNoOpDoesNotTouchHiddenConfigurationOrSecrets() throws {
        XCTAssertTrue(try ChannelDraft(detail: channel).payload().isEmpty)
    }
    func testUneditedWhitespaceAndDuplicateModelsAreNotNormalizedOnSave() throws {
        var fields = channel.object
        fields["name"] = .string(" Original ")
        fields["supportedModels"] = .array([.string("upstream-chat"), .string("upstream-chat")])
        var draft = ChannelDraft(detail: .object(fields)); draft.remark = "Only remark"
        XCTAssertEqual(try draft.payload(), ["remark": .string("Only remark")])
    }
    func testChannelOnlyChangedFieldIsSent() throws {
        var draft = ChannelDraft(detail: channel)
        draft.name = "Renamed"
        XCTAssertEqual(try draft.payload(), ["name": .string("Renamed")])
    }
    func testExistingCredentialRotationAndTypeMigrationAreExplicitlyRejected() {
        var draft = ChannelDraft(detail: channel); draft.apiKey = "new-key"
        XCTAssertThrowsError(try draft.payload())
        draft.apiKey = ""; draft.type = "anthropic"
        XCTAssertThrowsError(try draft.payload())
    }
    func testClearURLUsesEffectiveBeta10StringInsteadOfIgnoredClearFlag() throws {
        var detail = channel.object; detail["baseURL"] = .string("https://upstream.example")
        var draft = ChannelDraft(detail: .object(detail)); draft.baseURL = ""
        XCTAssertEqual(try draft.payload(), ["baseURL": .string("")])
    }
    func testNewChannelIncludesRequiredSingleKeyCredentialAndExplicitSyncPolicy() throws {
        var draft = ChannelDraft(); draft.name = "New"; draft.supportedModels = "upstream-chat"; draft.defaultTestModel = "upstream-chat"; draft.apiKey = "new-key"
        let input = try draft.payload()
        XCTAssertEqual(input["credentials"], .object(["apiKey": .string("new-key")]))
        XCTAssertEqual(input["autoSyncSupportedModels"], .bool(false))
        draft.type = "anthropic_gcp"; XCTAssertThrowsError(try draft.payload())
    }
    func testModelBasicEditPreservesRecursiveRoutingAndCard() throws {
        var draft = ModelDraft(detail: model); draft.name = "Renamed"
        XCTAssertEqual(try draft.payload(), ["name": .string("Renamed")])
    }
    func testNewModelPermitsDraftRouteAndUsesOfficialModelAssociationDiscriminator() throws {
        var draft = ModelDraft(); draft.name = "Alias"; draft.modelID = "alias"; draft.developer = "provider"; draft.group = "default"; draft.icon = "OpenAI"
        XCTAssertEqual(try draft.payload()["settings"]?["associations"], .array([]))
        draft.routeModelID = "upstream-chat"
        let input = try draft.payload()
        XCTAssertEqual(input["settings"]?["associations"].array.first?["type"], .string("model"))
        XCTAssertEqual(input["settings"]?["associations"].array.first?["modelId"]["modelId"], .string("upstream-chat"))
    }
    func testModelCardValidatesNestedInputShape() throws {
        var draft = ModelDraft(detail: model)
        for bad in [#"{"limit":{"context":1.5}}"#, #"{"reasoning":{"supported":"yes"}}"#, #"{"unknown":true}"#, #"{"cost":{"input":-1}}"#] {
            draft.modelCard = bad; XCTAssertThrowsError(try draft.payload())
        }
        draft.modelCard = #"{"limit":{"context":128000,"output":8192},"toolCall":true}"#
        XCTAssertNotNil(try draft.payload()["modelCard"])
    }

    func testModelCardRejectsNullGoValueFieldsBeforeExactReadback() throws {
        var draft = ModelDraft(detail: model)
        for bad in [#"{"vision":null}"#, #"{"knowledge":null}"#, #"{"cost":{"input":null}}"#, #"{"reasoning":null}"#, #"{"limit":{"context":null}}"#, #"{"modalities":{"input":null}}"#] {
            draft.modelCard = bad; XCTAssertThrowsError(try draft.payload(), bad)
        }
        draft.modelCard = #"{"vision":false,"cost":{"input":0},"knowledge":""}"#
        XCTAssertNotNil(try draft.payload()["modelCard"])
    }
    func testModelCardOmittedFieldsBecomeExactGoDefaultsBeforeWrite() throws {
        var draft = ModelDraft(detail: model); draft.modelCard = #"{"vision":true,"cost":{"input":0.25}}"#
        let card = try draft.payload()["modelCard"]!
        XCTAssertEqual(card["cost"]["output"], .number(0)); XCTAssertEqual(card["knowledge"], .string(""))
        XCTAssertEqual(card["reasoning"]["default"], .bool(false)); XCTAssertEqual(card["vision"], .bool(true))
        XCTAssertEqual(card["modalities"]["input"], .array([]))
    }
    func testFullCredentialsAndSettingsOnlyAfterExplicitRead() throws {
        var draft = ChannelDraft(detail: channel)
        let secret = JSON.from(#"{"credentials":{"apiKeys":["a","b"],"oauth":{"accessToken":"keep"}},"settings":{"proxy":{"type":"URL","url":"https://proxy.invalid","password":"protected"},"bodyOverrideOperations":[{"op":"set","path":"user","value":"protected"}]}}"#)!
        draft.loadSecrets(secret)
        var fields = draft.settings.object; fields["passThroughBody"] = .bool(true); draft.settings = .object(fields)
        let input = try draft.payload()
        XCTAssertNil(input["credentials"])
        XCTAssertEqual(input["settings"]?["proxy"]["password"], .string("protected"))
        XCTAssertEqual(input["settings"]?["bodyOverrideOperations"], secret["settings"]["bodyOverrideOperations"])
    }
    func testCredentialRotationRetainsOtherFieldsAndRequiresFullReplacementAuthorization() throws {
        var draft = ChannelDraft(detail: channel)
        draft.loadSecrets(channel); draft.apiKey = "new"
        let credentials = try draft.payload()["credentials"]!
        XCTAssertEqual(credentials["apiKeys"], channel["credentials"]["apiKeys"])
        XCTAssertEqual(credentials["oauth"], channel["credentials"]["oauth"])
        var replacing = ChannelDraft(detail: channel); replacing.apiKey = "new"; replacing.replaceCredentials = true
        XCTAssertThrowsError(try replacing.payload())
        replacing.authorizeReadback = true
        XCTAssertEqual(try replacing.payload()["credentials"]?["apiKey"], .string("new"))
    }
    func testAllTypeMigrationResetsEndpointsAndRequiresAuthorization() throws {
        var draft = ChannelDraft(detail: channel)
        draft.migrate(to: "anthropic"); XCTAssertEqual(draft.endpoints, .array([]))
        XCTAssertThrowsError(try draft.payload())
        draft.loadSecrets(JSON.from(#"{"credentials":{"apiKeys":["fixture"]},"settings":{}}"#)!)
        draft.migrationConfirmed = true
        XCTAssertEqual(try draft.payload()["type"], .string("anthropic"))
        XCTAssertEqual(try draft.payload()["endpoints"], .array([]))
    }
    func testInputMetadataRejectsNullRequiredUnknownAndInvalidEnums() {
        XCTAssertThrowsError(try ChannelInputSchema.validate(.object(["times": .null]), type: "APIKeyAutoDisableRuleInput!"))
        XCTAssertThrowsError(try ChannelInputSchema.validate(.object(["unknown": .bool(true)]), type: "ChannelSettingsInput!"))
        XCTAssertThrowsError(try ChannelInputSchema.validate(.string("llm"), type: "ModelType!"))
        XCTAssertThrowsError(try ChannelInputSchema.validate(.number(1.5), type: "Int!"))
    }
    func testThreeGroupConditionsAcceptedAndFourthGroupRejected() throws {
        let leaf = JSON.from(#"{"type":"condition","field":"prompt_tokens","operator":"gte","value":1000}"#)!
        func group(_ c: JSON) -> JSON { .object(["type": .string("group"), "logic": .string("and"), "conditions": .array([c])]) }
        try ChannelSemantics.condition(group(group(group(leaf))))
        XCTAssertThrowsError(try ChannelSemantics.condition(group(group(group(group(leaf))))))
        XCTAssertThrowsError(try ChannelSemantics.condition(group(JSON.from(#"{"type":"condition","field":"request_header.Authorization","operator":"eq","value":"secret"}"#)!)))
    }
    func testConditionSelectionDetectsTruncatedLeaf() {
        XCTAssertTrue(AxonClient.hasTruncatedCondition(JSON.from(#"{"associations":[{"when":{"condition":{"type":"group","conditions":[{"type":"condition"}]}}}]}"#)!))
        XCTAssertFalse(AxonClient.hasTruncatedCondition(JSON.from(#"{"condition":{"type":"condition","field":"stream","operator":"eq","value":true}}"#)!))
    }
    func testBackendCanonicalizesRetryAndDisablePolicies() throws {
        let p = JSON.from(#"{"stream":"unlimited","apiKeyAutoDisableRules":[{"times":2,"action":"permanent_disable","statusCodes":[503,429,503],"keywordPatterns":[" limit ","limit"],"disableUntilCron":"0 0 * * *","disableDurationMinutes":5}]}"#)!
        let normalized = ChannelSemantics.normalizedPolicies(p)["apiKeyAutoDisableRules"].array[0]
        XCTAssertEqual(normalized["statusCodes"], .array([.number(429),.number(503)]))
        XCTAssertEqual(normalized["keywordPatterns"], .array([.string("limit")]))
        XCTAssertEqual(normalized["disableUntilCron"], .string("")); XCTAssertTrue(normalized["disableDurationMinutes"].isNull)
    }
    func testTemplateHeaderMergeFollowsGoNotOutdatedFrontendAlgorithm() throws {
        let a = JSON.from(#"{"op":"set","path":"X-Key","value":"a"}"#)!, b = JSON.from(#"{"op":"set","path":"x-key","value":"b"}"#)!, c = JSON.from(#"{"op":"delete","path":"X-KEY"}"#)!
        XCTAssertEqual(ChannelTemplatesView.merge([a], template: [b,c], header: true), [c])
    }
    func testTemplateBodyMergeRetainsConditionalOperationOrder() throws {
        let a = JSON.from(#"{"op":"set","path":"x","value":"a"}"#)!, b = JSON.from(#"{"op":"set","path":"x","value":"b","condition":"exists"}"#)!, c = JSON.from(#"{"op":"set","path":"x","value":"c","condition":"absent"}"#)!
        XCTAssertEqual(ChannelTemplatesView.merge([a], template: [b,c], header: false), [b,c])
    }
    @MainActor func testSwitchAwayAndBackInvalidatesOpenedManagementTarget() throws {
        let defaults = UserDefaults(suiteName: "Management.\(UUID().uuidString)")!
        let store = AxonStore(defaults: defaults)
        store.instances = [AxonInstance(id: "a", name: "A", address: "https://a.example"), AxonInstance(id: "b", name: "B", address: "https://b.example")]
        store.selectedID = "a"
        let target = try store.managementTarget(kind: .channel, entityID: "1")
        store.selectedID = "b"; store.selectedID = "a"
        XCTAssertThrowsError(try store.validateTarget(target))
    }
    @MainActor func testAPIKeyConnectionCannotOpenManagement() {
        let store = AxonStore(defaults: UserDefaults(suiteName: "Management.\(UUID().uuidString)")!)
        store.instances = [AxonInstance(id: "a", name: "A", address: "https://a.example", authType: .apiKey)]
        store.selectedID = "a"
        XCTAssertFalse(store.canManage)
        XCTAssertThrowsError(try store.managementTarget(kind: .model))
    }
}
