import XCTest
@testable import Axonhub

final class PlaygroundProtocolTests: XCTestCase {
    private func parameters() -> PlaygroundParameters {
        var parameters = PlaygroundParameters()
        parameters.model = "contract-model"
        parameters.system = "system"
        return parameters
    }
    private func events(_ wire: String) throws -> [String] {
        var parser = PlaygroundSSEParser(); var output: [String] = []
        for byte in wire.utf8 { if let data = try parser.feed(byte) { output.append(data) } }
        if let data = try parser.finish() { output.append(data) }
        return output
    }
    func testAdminUsesOfficialAISDKEndpointAndJWT() throws {
        let client = try AxonClient(baseURL: "https://contract.invalid/base/", authType: .adminJWT, token: "fixture-only")
        let request = try PlaygroundService.chatRequest(client: client, parameters: parameters(),
            messages: [.user(text: "hello", images: [])], project: "project-id", channel: "channel-id")
        XCTAssertEqual(request.url?.path, "/base/admin/playground/chat")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-only")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Project-ID"), "project-id")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Channel-ID"), "channel-id")
        let json = try JSONDecoder().decode(JSON.self, from: XCTUnwrap(request.httpBody))
        XCTAssertEqual(json["messages"]["content"], .null)
        XCTAssertEqual(json["messages"].array.first?["parts"].array.first?["text"].string, "hello")
        XCTAssertEqual(json["system"].string, "system")
    }
    func testAPIKeyUsesOpenAIEndpointNeverAdminJWT() throws {
        let client = try AxonClient(baseURL: "https://contract.invalid/base/", authType: .apiKey, token: "fixture-only")
        let request = try PlaygroundService.chatRequest(client: client, parameters: parameters(), messages: [.user(text: "hello", images: [])])
        XCTAssertEqual(request.url?.path, "/base/v1/chat/completions")
        XCTAssertNil(request.value(forHTTPHeaderField: "X-Channel-ID"))
        let json = try JSONDecoder().decode(JSON.self, from: XCTUnwrap(request.httpBody))
        XCTAssertEqual(json["messages"].array.first?["role"].string, "system")
        XCTAssertTrue(json["stream"].bool)
        XCTAssertThrowsError(try PlaygroundService.chatRequest(client: client, parameters: parameters(),
            messages: [.user(text: "hello", images: [])], channel: "forbidden"))
    }
    func testImageUsesFilePartsForAdminAndImageURLForKey() throws {
        // A synthetic, non-secret transport fixture; no file upload or provider request is made.
        let image = try PlaygroundImage(filename: "fixture.png", mediaType: "image/png", data: Data([1, 2, 3]))
        let messages = [PlaygroundMessage.user(text: "describe", images: [image])]
        let admin = try parameters().payload(auth: .adminJWT, messages: messages)
        let key = try parameters().payload(auth: .apiKey, messages: messages)
        XCTAssertEqual(admin["messages"].array[0]["parts"].array[1]["url"].string, "data:image/png;base64,AQID")
        XCTAssertEqual(key["messages"].array[1]["content"].array[1]["image_url"]["url"].string, image.dataURL)
    }
    func testInvalidParametersDoNotProducePayload() {
        var parameters = parameters()
        parameters.temperature = .nan
        XCTAssertThrowsError(try parameters.payload(auth: .adminJWT, messages: [.user(text: "hi", images: [])]))
        parameters.temperature = 0.6; parameters.maxTokens = 0
        XCTAssertThrowsError(try parameters.payload(auth: .apiKey, messages: [.user(text: "hi", images: [])]))
    }
    func testSSEFramingNewlinesCommentsMultilineAndUTF8() throws {
        XCTAssertEqual(try events(": heartbeat\r\ndata: 你好\r\ndata: 第二行\r\n\r\ndata: [DONE]\n\n"), ["你好\n第二行", "[DONE]"])
        XCTAssertEqual(try events("data: one\r\rdata: two\n\ndata: tail"), ["one", "two", "tail"])
    }
    func testSSELineLimitAndInvalidUTF8() throws {
        var parser = PlaygroundSSEParser()
        _ = try parser.feed(255)
        XCTAssertThrowsError(try parser.feed(10))
        var bounded = PlaygroundSSEParser()
        for _ in 0..<(1024 * 1024) { _ = try bounded.feed(120) }
        XCTAssertThrowsError(try bounded.feed(120))
    }
    func testAISDKIndependentReasoningAndTextBlocks() throws {
        var result = PlaygroundStreamAccumulator()
        for event in [
            "{\"type\":\"start\",\"messageId\":\"official-id\"}",
            "{\"type\":\"reasoning-start\",\"id\":\"r\"}",
            "{\"type\":\"reasoning-delta\",\"id\":\"r\",\"delta\":\"think\"}",
            "{\"type\":\"text-delta\",\"id\":\"a\",\"delta\":\"hello\"}",
            "{\"type\":\"text-delta\",\"id\":\"b\",\"delta\":\"world\"}",
            "{\"type\":\"finish\"}"
        ] { try result.consume(event, auth: .adminJWT) }
        XCTAssertEqual(result.message.id, "official-id")
        XCTAssertEqual(result.message.parts[0]["text"].string, "think")
        XCTAssertEqual(result.message.text, "hello\nworld")
        XCTAssertTrue(result.complete)
    }
    func testOpenAIReasoningUsageAndDone() throws {
        var result = PlaygroundStreamAccumulator()
        try result.consume("{\"id\":\"chat\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"hi\",\"reasoning_content\":\"think\"},\"finish_reason\":\"stop\"}]}", auth: .apiKey)
        XCTAssertFalse(result.complete) // finish_reason is not end-of-stream; usage can follow.
        try result.consume("{\"choices\":[],\"usage\":{\"prompt_tokens\":2,\"completion_tokens\":3}}", auth: .apiKey)
        try result.consume("[DONE]", auth: .apiKey)
        XCTAssertEqual(result.message.text, "hi")
        XCTAssertEqual(result.usage["completion_tokens"].int, 3)
        XCTAssertTrue(result.complete)
    }
    func testInBandErrorsDoNotEchoServerSecrets() throws {
        var result = PlaygroundStreamAccumulator()
        XCTAssertThrowsError(try result.consume("{\"type\":\"error\",\"errorText\":\"Bearer secret-fixture\"}", auth: .adminJWT)) { error in
            XCTAssertFalse(error.localizedDescription.contains("secret-fixture"))
        }
        XCTAssertThrowsError(try result.consume("{\"error\":{\"message\":\"secret-fixture\"}}", auth: .apiKey))
    }
    @MainActor func testNoAutomaticModelRequestOnEmptyStore() {
        let defaults = UserDefaults(suiteName: "PlaygroundProtocolTests")!
        defaults.removePersistentDomain(forName: "PlaygroundProtocolTests")
        let store = AxonStore(defaults: defaults)
        let state = PlaygroundState()
        state.bind(store: store)
        XCTAssertFalse(state.busy)
        XCTAssertTrue(state.messages.isEmpty)
        state.run(store: store)
        XCTAssertFalse(state.busy)
        state.leave()
    }
}
