import XCTest
@testable import AxonCore

final class ModelOptionTests: XCTestCase {
    func testOptionSearchRanksExactThenPrefixThenContains() {
        XCTAssertEqual(OptionSearch.filter(["gpt-4o-mini", "o4", "gpt-4o", "chatgpt-4o", "gpt-4o"], query: "gpt-4o"),
                       ["gpt-4o", "gpt-4o-mini", "chatgpt-4o"])
        XCTAssertEqual(OptionSearch.filter(["a", "b", "c"], query: "", limit: 2), ["a", "b"])
        XCTAssertTrue(OptionSearch.canAddCustom(" my-model ", to: ["gpt-4o"]))
        XCTAssertFalse(OptionSearch.canAddCustom("gpt-4o", to: ["gpt-4o"]))
        XCTAssertFalse(OptionSearch.canAddCustom("  ", to: []))
        XCTAssertEqual(OptionSearch.merge(["a", "b"], ["b", "", "c"]), ["a", "b", "c"])
    }

    func testDeveloperAndIconLists() {
        XCTAssertEqual(DeveloperCatalog.ids.first, "deepseek")
        XCTAssertEqual(DeveloperCatalog.label("moonshot"), "月之暗面")
        XCTAssertEqual(DeveloperCatalog.icon(for: "anthropic"), "Claude")
        XCTAssertEqual(DeveloperCatalog.icon(for: "poolside"), "poolside")
        XCTAssertTrue(ModelIconCatalog.all.contains("OpenAI"))
        XCTAssertEqual(Set(ModelIconCatalog.all).count, ModelIconCatalog.all.count)
    }

    private let catalogJSON = """
    {"providers":{"openai":{"name":"OpenAI","models":[
      {"id":"gpt-4o","name":"GPT-4o","family":"gpt","type":"chat","reasoning":{"supported":false},"tool_call":true,
       "modalities":{"input":["text","image"],"output":["text"]},"cost":{"input":2.5,"output":10,"cache_read":1.25},
       "limit":{"context":128000,"output":16384},"knowledge":"2023-10","release_date":"2024-05-13"},
      {"id":"broken","cost":"oops"}]},
     "minimax":{"models":[{"id":"MiniMax-M1"},{"id":"MiniMax-M3"}]}}}
    """

    func testProvidersCatalogDecodesAndFillsTheDraft() throws {
        let data = try JSONDecoder().decode(JSONValue.self, from: Data(catalogJSON.utf8))
        // The server may send the catalog as a JSON string.
        let catalog = ProvidersCatalog.decode(.string(catalogJSON))
        XCTAssertEqual(catalog.providers.map(\.id), ProvidersCatalog.decode(data).providers.map(\.id))
        XCTAssertEqual(catalog.providers.map(\.id), ["minimax", "openai"])
        XCTAssertTrue(catalog.modelIDs(for: "openai").contains("gpt-4o"))
        XCTAssertEqual(catalog.modelIDs(for: "minimax"), ["MiniMax-M3"])
        XCTAssertEqual(catalog.developerIDs.prefix(DeveloperCatalog.ids.count).map { $0 }, DeveloperCatalog.ids)

        var draft = ModelDraft()
        draft.selectDeveloper("openai", isEditing: false)
        XCTAssertEqual(draft.icon, "OpenAI")
        draft.selectModelID("gpt-4o", catalog: catalog, isEditing: false)
        XCTAssertEqual(draft.name, "GPT-4o")
        XCTAssertEqual(draft.group, "gpt")
        XCTAssertTrue(draft.toolCall)
        XCTAssertEqual(draft.inputModalities, ["text", "image"])
        XCTAssertEqual(draft.costInput, "2.5")
        XCTAssertEqual(draft.costOutput, "10")
        XCTAssertEqual(draft.contextLimit, "128000")
        XCTAssertEqual(draft.knowledge, "2023-10")

        var editing = ModelDraft()
        editing.name = "kept"
        editing.selectModelID("gpt-4o", catalog: catalog, isEditing: true)
        XCTAssertEqual(editing.modelID, "gpt-4o")
        XCTAssertEqual(editing.name, "kept")
    }

    func testAssociationModelOptions() {
        let channels = [
            ChannelOption(id: "gid://axonhub/Channel/1", name: "A", type: "openai", status: "enabled", tags: nil, supportedModels: ["gpt-4o"]),
            ChannelOption(id: "gid://axonhub/Channel/2", name: "B", type: "anthropic", status: "enabled", tags: nil, supportedModels: ["claude"]),
        ]
        XCTAssertEqual(ChannelOption.associationModelOptions(kind: .channelModel, channelID: 2, channels: channels, allModels: ["x"]), ["claude"])
        XCTAssertEqual(ChannelOption.associationModelOptions(kind: .channelModel, channelID: nil, channels: channels, allModels: ["x"]), [])
        XCTAssertEqual(ChannelOption.associationModelOptions(kind: .model, channelID: nil, channels: channels, allModels: ["x"]),
                       ["x", "gpt-4o", "claude"])
    }

    func testAssociationConditionsRoundTrip() throws {
        let when = try JSONDecoder().decode(JSONValue.self, from: Data("""
        {"enabled":true,"condition":{"type":"group","logic":"and","conditions":[
          {"type":"group","logic":"or","conditions":[
            {"field":"prompt_tokens","operator":"lt","value":"4000"},
            {"field":"stream","operator":"eq","value":true},
            {"field":"bogus","operator":"eq","value":1}]},
          {"field":"request_header.X-Team","operator":"eq","value":"ops"}]}}
        """.utf8))
        let parsed = AssociationWhen(when)
        XCTAssertTrue(parsed.enabled)
        XCTAssertEqual(parsed.groups.count, 2)
        XCTAssertEqual(parsed.groups[0].logic, "or")
        XCTAssertEqual(parsed.groups[0].conditions.map(\.field), ["prompt_tokens", "stream"])
        XCTAssertEqual(parsed.groups[0].conditions[0].value, .number(4000))
        XCTAssertEqual(parsed.groups[1].conditions[0].headerName, "X-Team")
        XCTAssertNil(parsed.validationError)
        let out = try XCTUnwrap(parsed.json)
        let again = AssociationWhen(out)
        XCTAssertEqual(again, parsed.withIDs(of: again))

        var fresh = AssociationWhen(enabled: true)
        XCTAssertEqual(fresh.validationError, "至少添加一个条件")
        var condition = AssociationCondition.makeDefault()
        fresh.groups = [AssociationConditionGroup(conditions: [condition])]
        XCTAssertEqual(fresh.validationError, "请填写值")
        condition.setText("abc")
        fresh.groups[0].conditions = [condition]
        XCTAssertEqual(fresh.validationError, "值必须是数字")
        condition.setBaseField("stream")
        XCTAssertEqual(condition.value, .bool(true))
        condition.setBaseField("request_header")
        XCTAssertEqual(condition.field, ConditionCatalog.headerPrefix)
        XCTAssertNil(AssociationWhen(enabled: false, groups: fresh.groups).json)
    }
}

private extension AssociationWhen {
    /// Copies the condition ids of `other` so two parses of the same JSON compare equal.
    func withIDs(of other: AssociationWhen) -> AssociationWhen {
        var copy = self
        for g in copy.groups.indices where g < other.groups.count {
            copy.groups[g].id = other.groups[g].id
            for c in copy.groups[g].conditions.indices where c < other.groups[g].conditions.count {
                copy.groups[g].conditions[c].id = other.groups[g].conditions[c].id
            }
        }
        return copy
    }
}
