import XCTest
import Foundation
@testable import AxonCore

/// Responses captured from a real AxonHub server (looplj/axonhub at 029e1ed, SQLite, body storage on,
/// default data storage = file system) answering the app's own queries.
final class PayloadTests: XCTestCase {
    struct DetailEnvelope: Decodable { struct D: Decodable { let node: RequestDetail? }; let data: D }
    struct ExecutionEnvelope: Decodable { struct D: Decodable { let node: ExecutionPayload? }; let data: D }

    static let storedStreamDetail = #"{"data": {"node": {"id": "gid://axonhub/Request/6", "status": "completed", "stream": true, "projectID": "gid://axonhub/Project/1", "dataStorageID": "gid://axonhub/DataStorage/2", "requestHeaders": {"Accept": ["*/*"], "Authorization": ["******"], "Content-Length": ["92"], "Content-Type": ["application/json"], "User-Agent": ["curl/8.18.0"]}, "requestBody": {"model": "fake-model", "stream": true, "messages": [{"role": "user", "content": "ping fs stream"}]}, "responseHeaders": {"Access-Control-Allow-Origin": ["*"], "Ah-Request-Id": ["ar-6ab2b142-a7ce-445b-8ee5-0a52a3828b0c"], "Cache-Control": ["no-cache"], "Connection": ["keep-alive"], "Content-Type": ["text/event-stream;charset=utf-8"]}, "responseBody": {"id": "c1", "choices": [{"index": 0, "message": {"role": "assistant", "content": "Hello from fake"}, "finish_reason": "stop"}], "object": "chat.completion", "created": 1, "model": "fake-model", "usage": {"prompt_tokens": 5, "completion_tokens": 3, "total_tokens": 8, "prompt_tokens_details": null, "completion_tokens_details": null}}, "responseChunks": [{"event": "", "data": {"id": "c1", "choices": [{"index": 0, "delta": {"content": "Hello"}, "finish_reason": null, "logprobs": null}], "object": "chat.completion.chunk", "created": 1, "model": "fake-model", "usage": null}}, {"event": "", "data": {"id": "c1", "choices": [{"index": 0, "delta": {"content": " from"}, "finish_reason": null, "logprobs": null}], "object": "chat.completion.chunk", "created": 1, "model": "fake-model", "usage": null}}, {"event": "", "data": {"id": "c1", "choices": [{"index": 0, "delta": {"content": " fake"}, "finish_reason": null, "logprobs": null}], "object": "chat.completion.chunk", "created": 1, "model": "fake-model", "usage": null}}, {"event": "", "data": {"id": "c1", "choices": [{"index": 0, "delta": {}, "finish_reason": "stop", "logprobs": null}], "object": "chat.completion.chunk", "created": 1, "model": "fake-model", "usage": {"prompt_tokens": 5, "completion_tokens": 3, "total_tokens": 8, "prompt_tokens_details": {"audio_tokens": 0, "cached_tokens": 0}, "completion_tokens_details": {"audio_tokens": 0, "reasoning_tokens": 0, "accepted_prediction_tokens": 0, "rejected_prediction_tokens": 0}}}}], "createdAt": "2026-11-11T15:40:33.700219899Z", "modelID": "fake-model", "format": "openai/chat_completions", "source": "api", "clientIP": "::1", "userAgent": "curl/8.18.0", "reasoningEffort": "", "metricsLatencyMs": 10, "metricsFirstTokenLatencyMs": 10, "metricsReasoningDurationMs": null, "traceID": "gid://axonhub/Trace/0", "channel": {"id": "gid://axonhub/Channel/1", "name": "fake"}, "apiKey": {"id": "gid://axonhub/APIKey/1", "name": "k"}, "usageLogs": {"edges": [{"node": {"promptTokens": 5, "completionTokens": 3, "totalTokens": 8, "promptCachedTokens": 0, "completionReasoningTokens": 0, "totalCost": null}}]}, "executions": {"edges": [{"node": {"id": "gid://axonhub/RequestExecution/6", "createdAt": "2026-11-11T15:40:33.70142977Z", "modelID": "fake-model", "upstreamModelID": "fake-model", "format": "openai/chat_completions", "status": "completed", "stream": true, "errorMessage": "", "responseStatusCode": null, "metricsLatencyMs": 10, "metricsFirstTokenLatencyMs": 10, "requestURL": "http://127.0.0.1:9099/v1/chat/completions", "channel": {"id": "gid://axonhub/Channel/1", "name": "fake"}}}]}}}}"#

    static let storedPlainDetail = #"{"data": {"node": {"id": "gid://axonhub/Request/5", "status": "completed", "stream": false, "projectID": "gid://axonhub/Project/1", "dataStorageID": "gid://axonhub/DataStorage/2", "requestHeaders": {"Accept": ["*/*"], "Authorization": ["******"], "Content-Length": ["71"], "Content-Type": ["application/json"], "User-Agent": ["curl/8.18.0"], "X-Custom": ["fs"]}, "requestBody": {"model": "fake-model", "messages": [{"role": "user", "content": "ping fs"}]}, "responseHeaders": {"Ah-Request-Id": ["ar-f031f279-a33d-4ad9-91c5-596add13664a"], "Content-Length": ["451"], "Content-Type": ["application/json"]}, "responseBody": {"id": "c1", "choices": [{"index": 0, "message": {"role": "assistant", "content": "Hello from fake"}, "finish_reason": "stop", "logprobs": null}], "object": "chat.completion", "created": 1, "model": "fake-model", "usage": {"prompt_tokens": 5, "completion_tokens": 3, "total_tokens": 8, "prompt_tokens_details": {"audio_tokens": 0, "cached_tokens": 0}, "completion_tokens_details": {"audio_tokens": 0, "reasoning_tokens": 0, "accepted_prediction_tokens": 0, "rejected_prediction_tokens": 0}}}, "responseChunks": [], "createdAt": "2026-11-11T15:40:33.68097952Z", "modelID": "fake-model", "format": "openai/chat_completions", "source": "api", "clientIP": "::1", "userAgent": "curl/8.18.0", "reasoningEffort": "", "metricsLatencyMs": 10, "metricsFirstTokenLatencyMs": null, "metricsReasoningDurationMs": null, "traceID": "gid://axonhub/Trace/0", "channel": {"id": "gid://axonhub/Channel/1", "name": "fake"}, "apiKey": {"id": "gid://axonhub/APIKey/1", "name": "k"}, "usageLogs": {"edges": [{"node": {"promptTokens": 5, "completionTokens": 3, "totalTokens": 8, "promptCachedTokens": 0, "completionReasoningTokens": 0, "totalCost": null}}]}, "executions": {"edges": [{"node": {"id": "gid://axonhub/RequestExecution/5", "createdAt": "2026-11-11T15:40:33.682389771Z", "modelID": "fake-model", "upstreamModelID": "fake-model", "format": "openai/chat_completions", "status": "completed", "stream": false, "errorMessage": "", "responseStatusCode": null, "metricsLatencyMs": 10, "metricsFirstTokenLatencyMs": null, "requestURL": "http://127.0.0.1:9099/v1/chat/completions", "channel": {"id": "gid://axonhub/Channel/1", "name": "fake"}}}]}}}}"#

    static let storedStreamExecution = #"{"data": {"node": {"id": "gid://axonhub/RequestExecution/6", "status": "completed", "stream": true, "projectID": 1, "requestID": "gid://axonhub/Request/6", "dataStorageID": "gid://axonhub/DataStorage/2", "requestHeaders": {"Accept": ["application/json"], "Authorization": ["******"], "Content-Type": ["application/json"], "User-Agent": ["axonhub/1.0"]}, "requestBody": {"messages": [{"role": "user", "content": "ping fs stream"}], "model": "fake-model", "stream": true, "stream_options": {"include_usage": true}}, "responseHeaders": {"Content-Type": ["text/event-stream"], "Date": ["Wed, 11 Nov 2026 15:40:33 GMT"], "Server": ["BaseHTTP/0.6 Python/3.13.17"]}, "responseBody": {"id": "c1", "choices": [{"index": 0, "message": {"role": "assistant", "content": "Hello from fake"}, "finish_reason": "stop"}], "object": "chat.completion", "created": 1, "model": "fake-model", "usage": {"prompt_tokens": 5, "completion_tokens": 3, "total_tokens": 8, "prompt_tokens_details": null, "completion_tokens_details": null}}, "responseChunks": [{"event": "", "data": {"id": "c1", "object": "chat.completion.chunk", "created": 1, "model": "fake-model", "choices": [{"index": 0, "delta": {"content": "Hello"}}]}}, {"event": "", "data": {"id": "c1", "object": "chat.completion.chunk", "created": 1, "model": "fake-model", "choices": [{"index": 0, "delta": {"content": " from"}}]}}, {"event": "", "data": {"id": "c1", "object": "chat.completion.chunk", "created": 1, "model": "fake-model", "choices": [{"index": 0, "delta": {"content": " fake"}}]}}, {"event": "", "data": {"id": "c1", "object": "chat.completion.chunk", "created": 1, "model": "fake-model", "choices": [{"index": 0, "delta": {}, "finish_reason": "stop"}], "usage": {"prompt_tokens": 5, "completion_tokens": 3, "total_tokens": 8}}}]}}}"#

    static let oldQueryEmptyResponse = #"{"data": {"node": {"id": "gid://axonhub/Request/5", "createdAt": "2026-11-11T15:40:33.68097952Z", "modelID": "fake-model", "format": "openai/chat_completions", "source": "api", "status": "completed", "stream": false, "clientIP": "::1", "userAgent": "curl/8.18.0", "reasoningEffort": "", "metricsLatencyMs": 10, "metricsFirstTokenLatencyMs": null, "metricsReasoningDurationMs": null, "traceID": "gid://axonhub/Trace/0", "contentSaved": false, "requestHeaders": {"Accept": ["*/*"], "Authorization": ["******"], "Content-Length": ["71"], "Content-Type": ["application/json"], "User-Agent": ["curl/8.18.0"], "X-Custom": ["fs"]}, "requestBody": {}, "responseHeaders": {"Ah-Request-Id": ["ar-f031f279-a33d-4ad9-91c5-596add13664a"], "Content-Length": ["451"], "Content-Type": ["application/json"]}, "responseBody": {}, "responseChunks": [], "channel": {"id": "gid://axonhub/Channel/1", "name": "fake"}, "apiKey": {"id": "gid://axonhub/APIKey/1", "name": "k"}, "usageLogs": {"edges": [{"node": {"promptTokens": 5, "completionTokens": 3, "totalTokens": 8, "promptCachedTokens": 0, "completionReasoningTokens": 0, "totalCost": null}}]}, "executions": {"edges": [{"node": {"id": "gid://axonhub/RequestExecution/5", "createdAt": "2026-11-11T15:40:33.682389771Z", "modelID": "fake-model", "upstreamModelID": "fake-model", "format": "openai/chat_completions", "status": "completed", "stream": false, "errorMessage": "", "responseStatusCode": null, "metricsLatencyMs": 10, "metricsFirstTokenLatencyMs": null, "requestURL": "http://127.0.0.1:9099/v1/chat/completions", "channel": {"id": "gid://axonhub/Channel/1", "name": "fake"}}}]}}}}"#

    private func detail(_ text: String) throws -> RequestDetail {
        try XCTUnwrap(try JSONDecoder.axon.decode(DetailEnvelope.self, from: Data(text.utf8)).data.node)
    }

    // MARK: - Queries select what AxonHub's body resolvers need

    func testRequestQuerySelectsFieldsTheBodyResolversNeed() {
        for field in ["status", "stream", "projectID", "dataStorageID",
                      "requestHeaders", "requestBody", "responseHeaders", "responseBody", "responseChunks"] {
            XCTAssertTrue(AxonService.requestPayloadFields.split(whereSeparator: \.isWhitespace).contains(Substring(field)),
                          "request query lacks \(field)")
        }
        XCTAssertTrue(AxonService.requestDetailQuery.contains(AxonService.requestPayloadFields))
    }

    func testExecutionQuerySelectsFieldsTheBodyResolversNeed() {
        for field in ["status", "stream", "projectID", "requestID", "dataStorageID",
                      "requestHeaders", "requestBody", "responseHeaders", "responseBody", "responseChunks"] {
            XCTAssertTrue(AxonService.executionPayloadFields.split(whereSeparator: \.isWhitespace).contains(Substring(field)),
                          "execution query lacks \(field)")
        }
        XCTAssertTrue(AxonService.executionPayloadQuery.contains(AxonService.executionPayloadFields))
    }

    // MARK: - Real server responses decode and display in full

    func testStoredStreamingRequestShowsHeadersBodiesAndReply() throws {
        let d = try detail(Self.storedStreamDetail)
        XCTAssertEqual(d.requestStatus, .completed)
        XCTAssertEqual(d.dataStorageID, "gid://axonhub/DataStorage/2")

        let requestHeaders = PayloadText.headerLines(d.requestHeaders)
        XCTAssertTrue(requestHeaders.contains { $0.name == "Content-Type" && $0.value == "application/json" })
        XCTAssertFalse(PayloadText.headerLines(d.responseHeaders).isEmpty)

        let requestBody = try XCTUnwrap(PayloadText.body(d.requestBody))
        XCTAssertTrue(requestBody.prettyPrinted.contains("ping fs stream"))
        XCTAssertEqual(RequestPreview.messages(in: requestBody)?.first?.text, "ping fs stream")

        XCTAssertNotNil(PayloadText.body(d.responseBody))
        XCTAssertEqual(d.responseChunks?.count, 4)
        XCTAssertEqual(ResponseParser.parse(body: d.responseBody, chunks: d.responseChunks).content, "Hello from fake")
        XCTAssertEqual(d.executions?.items.count, 1)
    }

    func testStoredPlainRequestShowsCustomHeaderAndResponse() throws {
        let d = try detail(Self.storedPlainDetail)
        XCTAssertTrue(PayloadText.headerLines(d.requestHeaders).contains { $0.name == "X-Custom" && $0.value == "fs" })
        XCTAssertTrue(try XCTUnwrap(PayloadText.body(d.requestBody)).prettyPrinted.contains("ping fs"))
        XCTAssertEqual(ResponseParser.parse(body: d.responseBody, chunks: d.responseChunks).content, "Hello from fake")
    }

    func testStoredExecutionPayloadDecodesInFull() throws {
        let p = try XCTUnwrap(try JSONDecoder.axon.decode(ExecutionEnvelope.self, from: Data(Self.storedStreamExecution.utf8)).data.node)
        XCTAssertEqual(p.requestStatus, .completed)
        XCTAssertEqual(p.requestID, "gid://axonhub/Request/6")
        XCTAssertFalse(PayloadText.headerLines(p.requestHeaders).isEmpty)
        XCTAssertNotNil(PayloadText.body(p.requestBody))
        XCTAssertEqual(ResponseParser.parse(body: p.responseBody, chunks: p.responseChunks).content, "Hello from fake")
    }

    /// The 2.1.0 query did not select status / dataStorageID / projectID, so the same stored request came back empty.
    func testOldQueryShapeGotEmptyPayloadsFromServer() throws {
        let d = try detail(Self.oldQueryEmptyResponse)
        XCTAssertNil(PayloadText.body(d.requestBody))
        XCTAssertNil(PayloadText.body(d.responseBody))
        XCTAssertTrue(d.responseChunks?.isEmpty ?? true)
    }

    // MARK: - Helpers

    func testHeaderLinesHandleGoHeaderMapsStringsAndEncodedJSON() {
        let map = JSONValue.object(["b-Header": .array([.string("1"), .string("2")]), "A": .string("x")])
        XCTAssertEqual(PayloadText.headerLines(map), [.init(name: "A", value: "x"), .init(name: "b-Header", value: "1, 2")])
        XCTAssertEqual(PayloadText.headerLines(.string(#"{"K":["v"]}"#)), [.init(name: "K", value: "v")])
        XCTAssertTrue(PayloadText.headerLines(.object([:])).isEmpty)
        XCTAssertTrue(PayloadText.headerLines(nil).isEmpty)
    }

    func testEmptyBodyIsNil() {
        XCTAssertNil(PayloadText.body(.object([:])))
        XCTAssertNil(PayloadText.body(.null))
        XCTAssertNil(PayloadText.body(.string("")))
        XCTAssertNil(PayloadText.body(.string("{}")))
        XCTAssertNotNil(PayloadText.body(.string(#"{"a":1}"#)))
    }

    func testPreviewTruncatesLongBodies() {
        let text = (1...40).map { "line \($0)" }.joined(separator: "\n")
        let p = PayloadText.preview(text, lines: 10)
        XCTAssertTrue(p.truncated)
        XCTAssertEqual(p.text.split(separator: "\n").count, 10)
        XCTAssertFalse(PayloadText.preview("short").truncated)
    }

    func testEmptyBodyReasonExplainsFailedRequests() {
        XCTAssertTrue(PayloadText.emptyBodyReason(isResponse: true, status: .failed).contains("只保存成功完成"))
        XCTAssertTrue(PayloadText.emptyBodyReason(isResponse: true, status: .processing).contains("还没完成"))
        XCTAssertTrue(PayloadText.emptyBodyReason(isResponse: false, status: .failed).contains("请求体"))
    }
}

final class AccentTests: XCTestCase {
    func testDefaultIsSystemBlue() {
        XCTAssertEqual(AccentChoice(storageValue: nil), .preset(.blue))
        XCTAssertEqual(AccentChoice(storageValue: ""), .preset(.blue))
        XCTAssertEqual(AccentChoice(storageValue: "nonsense"), .preset(.blue))
        XCTAssertEqual(AccentChoice.default, .preset(.blue))
    }

    func testPresetsRoundTrip() {
        for preset in AccentPreset.allCases {
            let choice = AccentChoice.preset(preset)
            XCTAssertEqual(AccentChoice(storageValue: choice.storageValue), choice)
        }
    }

    func testCustomColorRoundTripsThroughHex() {
        let choice = AccentChoice.custom(RGBColor(red: 1, green: 0.4, blue: 0))
        XCTAssertEqual(choice.storageValue, "#FF6600")
        XCTAssertEqual(AccentChoice(storageValue: "#FF6600"), choice)
        XCTAssertEqual(AccentChoice(storageValue: "#f60"), choice)
        XCTAssertEqual(AccentChoice(storageValue: "#GGGGGG"), .preset(.blue))
    }
}
