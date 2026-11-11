import XCTest
@testable import AxonCore

final class FormattingTests: XCTestCase {
    func testParsesGoNanosecondTimestamps() throws {
        let date = try XCTUnwrap(DateParsing.parse("2026-11-06T09:05:01.123456789+08:00"))
        XCTAssertEqual(date.timeIntervalSince1970, 1_793_927_101.123, accuracy: 0.001)
        XCTAssertNotNil(DateParsing.parse("2026-11-06T01:05:01Z"))
        XCTAssertNotNil(DateParsing.parse("2026-11-06T01:05:01.5Z"))
        XCTAssertNil(DateParsing.parse("not a date"))
    }

    func testCompactNumbers() {
        XCTAssertEqual(Fmt.compact(999), "999")
        XCTAssertEqual(Fmt.compact(12_345), "12.3K")
        XCTAssertEqual(Fmt.compact(2_000_000), "2M")
        XCTAssertEqual(Fmt.compact(1_260_000_000), "1.3B")
        XCTAssertEqual(Fmt.compact(nil as Int?), "—")
    }

    func testCostAndLatency() {
        XCTAssertEqual(Fmt.cost(0), "$0")
        XCTAssertEqual(Fmt.cost(0.0012), "$0.0012")
        XCTAssertEqual(Fmt.cost(12.5), "$12.50")
        XCTAssertEqual(Fmt.latency(850 as Int?), "850ms")
        XCTAssertEqual(Fmt.latency(1530 as Int?), "1.53s")
        XCTAssertEqual(Fmt.percent(0.987), "98.7%")
        XCTAssertEqual(Fmt.percent(1.0), "100%")
    }

    func testListItemsAndMask() {
        XCTAssertEqual("a, b\nc，d,,".listItems, ["a", "b", "c", "d"])
        XCTAssertEqual(Fmt.mask("ah-1234567890abcdef"), "ah-123••••••cdef")
        XCTAssertEqual(GUID.numeric("gid://axonhub/channel/42"), 42)
        XCTAssertEqual(GUID.short("gid://axonhub/request/7"), "#7")
    }
}

final class APIClientTests: XCTestCase {
    func testNormalizesBaseURL() {
        XCTAssertEqual(APIClient.normalizeBaseURL("axon.example.com")?.absoluteString, "https://axon.example.com")
        XCTAssertEqual(APIClient.normalizeBaseURL(" http://10.0.0.2:8090/ ")?.absoluteString, "http://10.0.0.2:8090")
        XCTAssertEqual(APIClient.normalizeBaseURL("https://a.b/admin/")?.absoluteString, "https://a.b")
        XCTAssertEqual(APIClient.normalizeBaseURL("https://a.b/v1")?.absoluteString, "https://a.b")
        XCTAssertEqual(APIClient.normalizeBaseURL("https://a.b/sub/path")?.absoluteString, "https://a.b/sub/path")
        XCTAssertNil(APIClient.normalizeBaseURL("   "))
    }

    func testEndpointJoinsPaths() {
        let base = URL(string: "https://a.b/prefix")!
        XCTAssertEqual(APIClient.endpoint(base, "admin/graphql").absoluteString, "https://a.b/prefix/admin/graphql")
    }

    func testServerMessageExtraction() {
        XCTAssertEqual(APIClient.serverMessage(Data(#"{"error":"Invalid email or password"}"#.utf8)), "Invalid email or password")
        XCTAssertEqual(APIClient.serverMessage(Data(#"{"error":{"message":"nope"}}"#.utf8)), "nope")
        XCTAssertEqual(APIClient.serverMessage(Data(#"{"errors":[{"message":"gql"}]}"#.utf8)), "gql")
        XCTAssertEqual(APIClient.serverMessage(Data("plain text".utf8)), "plain text")
    }

    func testAuthorizedRequestHeaders() {
        let client = APIClient(baseURL: URL(string: "https://a.b")!, token: "jwt", projectID: "gid://axonhub/project/1")
        let request = client.authorizedRequest("admin/graphql", method: "POST", body: Data("{}".utf8))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer jwt")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Project-ID"), "gid://axonhub/project/1")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let noProject = client.authorizedRequest("admin/graphql", includeProject: false)
        XCTAssertNil(noProject.value(forHTTPHeaderField: "X-Project-ID"))
    }
}

final class DecodingTests: XCTestCase {
    func testDecodesSignInResponseWithRESTStyleIDs() throws {
        let json = """
        {"user":{"id":{"type":"user","id":1},"email":"owner@example.com","firstName":"Li","lastName":"",
          "isOwner":true,"preferLanguage":"zh","avatar":null,"scopes":["read_channels"],"roles":[],
          "projects":[{"projectID":{"type":"project","id":1},"isOwner":true,"scopes":[],"roles":[]}]},
         "token":"abc"}
        """
        let response = try JSONDecoder.axon.decode(SignInResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.token, "abc")
        XCTAssertEqual(response.user.id.gid, "gid://axonhub/user/1")
        XCTAssertEqual(response.user.projects?.first?.projectID.gid, "gid://axonhub/project/1")
        XCTAssertEqual(response.user.displayName, "Li")
    }

    func testDecodesRequestConnection() throws {
        let json = """
        {"edges":[{"node":{"id":"gid://axonhub/request/9","createdAt":"2026-11-06T09:00:00.123456789Z",
          "modelID":"gpt-4o","format":"openai/chat_completions","source":"api","status":"completed","stream":true,
          "clientIP":"1.2.3.4","userAgent":null,"reasoningEffort":null,"metricsLatencyMs":1234,"metricsFirstTokenLatencyMs":200,
          "traceID":null,"channel":{"id":"gid://axonhub/channel/1","name":"OpenAI"},"apiKey":null,
          "usageLogs":{"edges":[{"node":{"promptTokens":10,"completionTokens":20,"totalTokens":30,
            "promptCachedTokens":0,"completionReasoningTokens":null,"totalCost":0.0012}}]}}}],
         "pageInfo":{"hasNextPage":true,"endCursor":"c1"},"totalCount":120}
        """
        let connection = try JSONDecoder.axon.decode(Connection<RequestLog>.self, from: Data(json.utf8))
        XCTAssertEqual(connection.nodes.count, 1)
        XCTAssertEqual(connection.totalCount, 120)
        let request = try XCTUnwrap(connection.nodes.first)
        XCTAssertEqual(request.requestStatus, .completed)
        XCTAssertEqual(request.usage?.totalTokens, 30)
        XCTAssertEqual(request.usage?.totalCost, 0.0012)
        XCTAssertEqual(request.channel?.name, "OpenAI")
    }

    func testDecodesRequestDetailWithRawBodies() throws {
        let json = """
        {"id":"gid://axonhub/request/9","createdAt":"2026-11-06T09:00:00Z","modelID":"m","format":"f","source":"api",
         "status":"failed","stream":false,"requestHeaders":{"a":"b"},"requestBody":{"messages":[{"role":"user"}]},
         "responseHeaders":null,"responseBody":null,"executions":{"edges":[{"node":{"id":"gid://axonhub/request_execution/1",
         "createdAt":"2026-11-06T09:00:00Z","modelID":"m","upstreamModelID":"m2","format":"f","status":"failed","stream":false,
         "errorMessage":"boom","responseStatusCode":500,"metricsLatencyMs":10,"metricsFirstTokenLatencyMs":null,"requestURL":null,
         "channel":{"id":"c","name":"X"}}}]}}
        """
        let detail = try JSONDecoder.axon.decode(RequestDetail.self, from: Data(json.utf8))
        XCTAssertEqual(detail.requestStatus, .failed)
        XCTAssertEqual(detail.executions?.items.first?.errorMessage, "boom")
        XCTAssertTrue(detail.requestBody?.prettyPrinted.contains("\"role\" : \"user\"") ?? false)
        XCTAssertTrue(detail.responseBody?.isEmptyPayload ?? true)
    }

    func testDecodesChannelAndDashboard() throws {
        let channel = """
        {"id":"gid://axonhub/channel/3","createdAt":"2026-11-06T09:00:00Z","updatedAt":"2026-11-06T09:00:00Z",
         "type":"deepseek","baseURL":"https://api.deepseek.com/v1","name":"DS","status":"enabled",
         "supportedModels":["deepseek-chat"],"manualModels":[],"autoSyncSupportedModels":false,"tags":["cn"],
         "defaultTestModel":"deepseek-chat","orderingWeight":10,"errorMessage":null,"remark":null,"autoDisabledAt":null}
        """
        let decoded = try JSONDecoder.axon.decode(Channel.self, from: Data(channel.utf8))
        XCTAssertEqual(decoded.channelStatus, .enabled)
        XCTAssertEqual(decoded.provider.name, "DeepSeek")

        let daily = try JSONDecoder.axon.decode([DailyRequestStat].self, from: Data(#"[{"date":"2026-11-05","count":3,"tokens":100,"cost":0.5}]"#.utf8))
        XCTAssertNotNil(daily.first?.day)
    }

    func testUnknownProviderFallsBack() {
        let provider = ChannelProvider.of("some_new_anthropic")
        XCTAssertEqual(provider.format, .anthropic)
        XCTAssertTrue(ChannelProvider.creatable.allSatisfy(\.apiKeyBased))
    }
}

final class JSONValueTests: XCTestCase {
    func testRoundTripPreservesIntegers() throws {
        let value: JSONValue = ["first": 30, "ratio": 0.5, "name": "x", "flag": true, "none": nil, "list": [1, 2]]
        let data = try JSONEncoder().encode(value)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("\"first\":30"))
        XCTAssertFalse(text.contains("30.0"))
        XCTAssertEqual(try JSONDecoder().decode(JSONValue.self, from: data), value)
    }
}

final class StreamParserTests: XCTestCase {
    private func parse(_ text: String) throws -> [StreamChunk] {
        var parser = UIMessageStreamParser()
        var chunks: [StreamChunk] = []
        for line in UIMessageStreamParser.lines(text) { chunks += try parser.feed(line) }
        chunks += try parser.finish()
        return chunks
    }

    func testParsesUIMessageStream() throws {
        let stream = """
        data: {"type":"start","messageId":"m1"}

        data: {"type":"reasoning-delta","id":"r","delta":"think"}

        data: {"type":"text-delta","id":"t","delta":"Hel"}

        data: {"type":"text-delta","id":"t","delta":"lo"}

        data: {"type":"finish","finishReason":"stop"}

        data: [DONE]

        """
        let chunks = try parse(stream)
        XCTAssertEqual(chunks, [.reasoning("think"), .text("Hel"), .text("lo"), .finish(reason: "stop"), .finish(reason: nil)])
    }

    func testHandlesCRLFAndComments() throws {
        let chunks = try parse(": keep-alive\r\ndata: {\"type\":\"text-delta\",\"delta\":\"x\"}\r\n\r\n")
        XCTAssertEqual(chunks, [.text("x")])
    }

    func testErrorEventThrows() {
        XCTAssertThrowsError(try parse("event: error\ndata: {\"error\":{\"message\":\"no channel\"}}\n\n")) { error in
            XCTAssertEqual((error as? APIError)?.errorDescription, "no channel")
        }
        XCTAssertThrowsError(try parse("data: {\"type\":\"error\",\"errorText\":\"upstream 500\"}\n\n"))
    }

    func testBuildsPlaygroundBody() throws {
        var options = PlaygroundOptions(model: "gpt-4o")
        options.systemPrompt = "be brief"
        options.temperature = 0.3
        let body = PlaygroundService.body(turns: [ChatTurn(role: .user, text: "hi")], options: options)
        XCTAssertEqual(body["model"]?.stringValue, "gpt-4o")
        XCTAssertEqual(body["system"]?.stringValue, "be brief")
        XCTAssertEqual(body["temperature"]?.doubleValue, 0.3)
        guard case .array(let messages)? = body["messages"], case .array(let parts)? = messages.first?["parts"] else {
            return XCTFail("messages missing")
        }
        XCTAssertEqual(messages.first?["role"]?.stringValue, "user")
        XCTAssertEqual(parts.first?["text"]?.stringValue, "hi")
    }
}

final class ResponseParserTests: XCTestCase {
    private func json(_ text: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }

    func testOpenAIChatBody() throws {
        let body = try json(#"{"choices":[{"message":{"role":"assistant","content":"你好","reasoning_content":"想一想","tool_calls":[{"id":"c1","function":{"name":"get","arguments":"{\"a\":1}"}}]}}]}"#)
        let r = ResponseParser.parse(body: body, chunks: nil)
        XCTAssertEqual(r.content, "你好")
        XCTAssertEqual(r.reasoning, "想一想")
        XCTAssertEqual(r.toolCalls.first?.name, "get")
        XCTAssertEqual(r.toolCalls.first?.arguments, #"{"a":1}"#)
    }

    func testAnthropicBodyAndStringEncodedBody() throws {
        let raw = #"{"role":"assistant","content":[{"type":"thinking","thinking":"hm"},{"type":"text","text":"Hi"},{"type":"tool_use","id":"t","name":"calc","input":{"x":2}}]}"#
        let r = ResponseParser.parse(body: .string(raw), chunks: nil)
        XCTAssertEqual(r.content, "Hi")
        XCTAssertEqual(r.reasoning, "hm")
        XCTAssertEqual(r.toolCalls.first?.arguments, #"{"x":2}"#)
    }

    func testResponsesAPIAndGeminiBodies() throws {
        let responses = try json(#"{"output":[{"type":"reasoning","summary":[{"type":"summary_text","text":"r"}]},{"type":"message","content":[{"type":"output_text","text":"ok"}]}]}"#)
        XCTAssertEqual(ResponseParser.parse(body: responses, chunks: nil).content, "ok")
        let gemini = try json(#"{"candidates":[{"content":{"parts":[{"text":"t","thought":true},{"text":"answer"}]}}]}"#)
        let g = ResponseParser.parse(body: gemini, chunks: nil)
        XCTAssertEqual(g.content, "answer")
        XCTAssertEqual(g.reasoning, "t")
    }

    func testRebuildsOpenAIStreamFromChunks() throws {
        let chunks = try [
            json(#"{"choices":[{"delta":{"role":"assistant","content":"Hel"}}]}"#),
            json(#"{"choices":[{"delta":{"content":"lo"}}]}"#),
            json(#"{"choices":[{"delta":{"tool_calls":[{"index":0,"id":"x","function":{"name":"f","arguments":"{\"q\""}}]}}]}"#),
            json(#"{"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":":1}"}}]}}]}"#),
        ]
        let r = ResponseParser.parse(body: nil, chunks: chunks)
        XCTAssertEqual(r.content, "Hello")
        XCTAssertEqual(r.toolCalls.count, 1)
        XCTAssertEqual(r.toolCalls.first?.arguments, #"{"q":1}"#)
    }

    func testRebuildsAnthropicStreamWithEventWrapper() throws {
        let chunks = try [
            json(#"{"event":"message_start","data":"{\"type\":\"message_start\"}"}"#),
            json(#"{"event":"content_block_start","data":{"type":"content_block_start","index":0,"content_block":{"type":"thinking"}}}"#),
            json(#"{"data":{"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"a"}}}"#),
            json(#"{"data":{"type":"content_block_start","index":1,"content_block":{"type":"text"}}}"#),
            json(#"{"data":{"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"B"}}}"#),
            json(#"{"data":{"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"C"}}}"#),
        ]
        let r = ResponseParser.parse(body: .null, chunks: chunks)
        XCTAssertEqual(r.reasoning, "a")
        XCTAssertEqual(r.content, "BC")
    }

    func testResponsesStreamAndEmptyBodyFallsBackToChunks() throws {
        let chunks = try [
            json(#"{"type":"response.output_text.delta","delta":"x"}"#),
            json(#"{"type":"response.output_text.delta","delta":"y"}"#),
        ]
        XCTAssertEqual(ResponseParser.parse(body: .object([:]), chunks: chunks).content, "xy")
        XCTAssertTrue(ResponseParser.parse(body: nil, chunks: []).isEmpty)
    }

    func testRequestPreviewMessages() throws {
        let body = try json(#"{"system":"be nice","messages":[{"role":"user","content":[{"type":"text","text":"hi"},{"type":"image_url","image_url":{}}]},{"role":"assistant","content":"yo"}]}"#)
        let messages = try XCTUnwrap(RequestPreview.messages(in: body))
        XCTAssertEqual(messages.map(\.role), ["system", "user", "assistant"])
        XCTAssertEqual(messages[1].text, "hi\n〔图片〕")
    }
}

final class EditingTests: XCTestCase {
    func testTabLayoutResolvesAndFallsBack() {
        let all = AppDestination.allCases
        XCTAssertEqual(TabLayout.resolve(stored: "", available: all), [.dashboard, .requests, .models, .apiKeys])
        XCTAssertEqual(TabLayout.resolve(stored: "playground,models,bogus,models", available: all), [.playground, .models])
        let limited = AppDestination.available(isAdmin: false, isOwner: false)
        XCTAssertFalse(limited.contains(.channels))
        XCTAssertEqual(TabLayout.resolve(stored: "channels", available: limited), TabLayout.defaults(available: limited))
        XCTAssertEqual(TabLayout.resolve(stored: "a,b,c,d,e,f", available: all), TabLayout.defaults(available: all))
        XCTAssertEqual(TabLayout.resolve(stored: "dashboard,requests,channels,models,apiKeys", available: all).count, TabLayout.maxPinned)
    }

    func testModelDraftBuildsInputs() throws {
        var draft = ModelDraft()
        XCTAssertNotNil(draft.validationError)
        draft.developer = "openai"
        draft.modelID = "gpt-x"
        draft.name = "GPT X"
        draft.contextLimit = "128k"
        draft.costInput = "abc"
        XCTAssertEqual(draft.validationError, "输入价格不是有效数字")
        draft.costInput = "2.5"
        XCTAssertNil(draft.validationError)
        let input = draft.createInput
        XCTAssertEqual(input["modelID"], .string("gpt-x"))
        XCTAssertEqual(input["modelCard"]?["limit"]?["context"], .number(128_000))
        XCTAssertEqual(input["modelCard"]?["cost"]?["input"], .number(2.5))
    }

    func testProfilesValidation() {
        let a = APIKeyProfile(name: "Default")
        XCTAssertEqual(ProfilesEditor.validationError(active: "", profiles: []), "至少需要一个配置")
        XCTAssertEqual(ProfilesEditor.validationError(active: "x", profiles: [a]), "请选择一个生效的配置")
        XCTAssertEqual(ProfilesEditor.validationError(active: "Default", profiles: [a, APIKeyProfile(name: "default")]), "配置名称“default”重复")
        XCTAssertNil(ProfilesEditor.validationError(active: "Default", profiles: [a]))
        let input = ProfilesEditor.input(active: "Default", profiles: [a])
        XCTAssertEqual(input["activeProfile"], .string("Default"))
    }
}
