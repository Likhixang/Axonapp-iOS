import XCTest
@testable import Axonhub

private final class ContractURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, String))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw AxonAPIError.invalidResponse }
            let (status, body) = try handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                           httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

final class APIContractTests: XCTestCase {
    private func client(_ auth: AxonAuthType = .adminJWT) throws -> AxonClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ContractURLProtocol.self]
        return try AxonClient(baseURL: "https://axon.example.com/gateway/", authType: auth,
                              token: "test-credential", configuration: config)
    }
    private func payload(_ request: URLRequest) throws -> [String: Any] {
        let data: Data
        if let body = request.httpBody { data = body }
        else if let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var result = Data(), buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                result.append(buffer, count: count)
            }
            data = result
        } else { throw AxonAPIError.invalidResponse }
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }
    private func query(_ request: URLRequest) throws -> String {
        try payload(request)["query"] as! String
    }
    override func tearDown() { ContractURLProtocol.handler = nil; super.tearDown() }

    func testAdminOverviewMatchesRequestSchema() async throws {
        ContractURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/gateway/admin/graphql")
            let query = try self.query(request)
            if query.contains("query ModelAllPages") {
                return (200, #"{"data":{"models":{"edges":[],"pageInfo":{"hasNextPage":false,"endCursor":null},"totalCount":0}}}"#)
            }
            XCTAssertFalse(query.contains("userAgent"))
            XCTAssertTrue(query.contains("executions(first: 1"))
            return (200, """
            {"data":{"dashboardOverview":{"totalRequests":7},"requests":{"edges":[{"node":{"id":"r1","clientIP":"127.0.0.1","executions":{"edges":[{"node":{"errorMessage":"upstream failed"}}]}}}]}}}
            """)
        }
        let snapshot = try await client().fetchSnapshot()
        XCTAssertEqual(snapshot.dashboard.totalRequests, 7)
        XCTAssertEqual(snapshot.requests.first?.errorMessage, "upstream failed")
    }
    func test422NeverEchoesServerMessagesOrCredentialVariables() async throws {
        ContractURLProtocol.handler = { _ in
            (422, #"{"errors":[{"message":"Cannot query field; test-credential; secret-api-key; oauth-secret"}]}"#)
        }
        do { _ = try await client().graphql(query: "query { __typename }", variables: ["credentials": ["apiKey": "secret-api-key"]]); XCTFail("Expected validation error") }
        catch let error as AxonAPIError {
            if case .graphQLError = error {} else { XCTFail("Expected GraphQL rejection") }
            XCTAssertFalse(error.localizedDescription.contains("test-credential"))
            XCTAssertFalse(error.localizedDescription.contains("secret-api-key"))
            XCTAssertFalse(error.localizedDescription.contains("oauth-secret"))
        }
    }
    func testModelStatusReturnsBooleanWithoutSelection() async throws {
        ContractURLProtocol.handler = { request in
            let query = try self.query(request)
            XCTAssertFalse(query.contains("status: $status) {"))
            return (200, #"{"data":{"updateModelStatus":true}}"#)
        }
        try await client().updateModelStatus(id: "gid://axonhub/Model/1", enabled: true)
    }
    func testChannelTestUsesOfficialPayload() async throws {
        ContractURLProtocol.handler = { request in
            let query = try self.query(request)
            XCTAssertTrue(query.contains("latency"))
            XCTAssertFalse(query.contains("latencyMs"))
            XCTAssertFalse(query.contains("errorMessage"))
            return (200, #"{"data":{"testChannel":{"success":true,"latency":0.125,"error":null}}}"#)
        }
        let result = try await client().testChannel(id: "gid://axonhub/Channel/1")
        XCTAssertTrue(result.success)
        XCTAssertEqual(result.latencyMs, 125)
    }
    func testUserAPIKeyUsesModelsNotManagementOpenAPI() async throws {
        ContractURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/gateway/v1/models")
            XCTAssertEqual(request.httpMethod, "GET")
            return (200, #"{"data":[{"id":"available-model"}]}"#)
        }
        let snapshot = try await client(.apiKey).fetchSnapshot()
        XCTAssertEqual(snapshot.models.first?.modelID, "available-model")
    }
    func testInvalidAPIKeyDoesNotBecomeSuccessfulEmptySnapshot() async throws {
        ContractURLProtocol.handler = { _ in (401, #"{"error":"Invalid API key"}"#) }
        do { _ = try await client(.apiKey).fetchSnapshot(); XCTFail("Expected auth failure") }
        catch let error as AxonAPIError { XCTAssertEqual(error, .unauthorized) }
    }
    func testCRUDMutationVariablesUseActualDraftSerialization() async throws {
        var draft = ChannelDraft()
        draft.name = "New"; draft.supportedModels = "chat"; draft.defaultTestModel = "chat"; draft.apiKey = "fixture-key"
        ContractURLProtocol.handler = { request in
            let body = try self.payload(request)
            let query = body["query"] as! String
            XCTAssertTrue(query.contains("mutation CreateChannel"))
            XCTAssertFalse(query.contains("fixture-key")) // Secrets stay in variables, not operation source.
            let variables = body["variables"] as! [String: Any]
            let input = variables["input"] as! [String: Any]
            XCTAssertEqual(input["name"] as? String, "New")
            XCTAssertEqual(input["supportedModels"] as? [String], ["chat"])
            XCTAssertEqual((input["credentials"] as? [String: String])?["apiKey"], "fixture-key")
            return (200, #"{"data":{"createChannel":{"id":"42"}}}"#)
        }
        let result = try await client().createChannel(input: draft.payload())
        XCTAssertEqual(result, "42")
    }
    func testDeleteRequiresTrueServerAcknowledgement() async throws {
        ContractURLProtocol.handler = { _ in (200, #"{"data":{"deleteChannel":false}}"#) }
        do { try await client().deleteChannel(id: "1"); XCTFail("False acknowledgement must fail") }
        catch { XCTAssertTrue(error is ManagementError) }
    }
    func testDeletionReadbackRejectsMalformedResponseInsteadOfConfirmingAbsence() async throws {
        ContractURLProtocol.handler = { _ in (200, #"{"data":{"channels":{}}}"#) }
        do { _ = try await client().channelDetail(id: "1"); XCTFail("Missing edges is not evidence of deletion") }
        catch { XCTAssertEqual(error as? AxonAPIError, .invalidResponse) }
        ContractURLProtocol.handler = { _ in (200, #"{"data":{"channels":{"edges":[]}}}"#) }
        let absent = try await client().channelDetail(id: "1")
        XCTAssertNil(absent)
    }
    func testCRUDCannotRunOnOrdinaryAPIKey() async throws {
        ContractURLProtocol.handler = { _ in XCTFail("API key must not send management request"); return (200, "{}") }
        do { try await client(.apiKey).deleteModel(id: "1"); XCTFail("Must reject API key") }
        catch { XCTAssertEqual(error as? AxonAPIError, .forbidden) }
    }
    func testGraphQLForbiddenErrorIsSafeAndActionable() async throws {
        ContractURLProtocol.handler = { _ in (200, #"{"errors":[{"message":"unsafe-secret","extensions":{"code":"FORBIDDEN"}}]}"#) }
        do { try await client().deleteModel(id: "1"); XCTFail("Must reject") }
        catch { XCTAssertEqual(error as? AxonAPIError, .forbidden) }
    }
    func testAllManagedModelsContinuesPastFirstPageAndRejectsMissingPagination() async throws {
        var calls = 0
        ContractURLProtocol.handler = { request in
            calls += 1
            let variables = try self.payload(request)["variables"] as! [String:Any]
            if calls == 1 {
                XCTAssertNil(variables["after"])
                return (200, #"{"data":{"models":{"edges":[{"node":{"id":"1","modelID":"older"}}],"pageInfo":{"hasNextPage":true,"endCursor":"continue"},"totalCount":2}}}"#)
            }
            XCTAssertEqual(variables["after"] as? String, "continue")
            return (200, #"{"data":{"models":{"edges":[{"node":{"id":"2","modelID":"oldest"}}],"pageInfo":{"hasNextPage":false,"endCursor":null},"totalCount":2}}}"#)
        }
        let records = try await client().allManagedModels()
        XCTAssertEqual(records.map(\.modelID), ["older","oldest"]); XCTAssertEqual(calls,2)
        ContractURLProtocol.handler = { _ in (200, #"{"data":{"models":{}}}"#) }
        do { _ = try await client().allManagedModels(); XCTFail("Missing metadata must not be successful empty page") }
        catch { XCTAssertEqual(error as? AxonAPIError,.invalidResponse) }
    }
    func testModelDetailExpandsTruncatedConditionWithoutCombiningVersions() async throws {
        var calls = 0
        ContractURLProtocol.handler = { request in
            calls += 1
            let query = try self.query(request)
            if calls == 1 {
                return (200, #"{"data":{"models":{"edges":[{"node":{"id":"1","settings":{"associations":[{"when":{"condition":{"type":"group","conditions":[{"type":"condition"}]}}}]}}}]}}}"#)
            }
            XCTAssertTrue(query.contains("conditions { type logic field operator value conditions { type } }"))
            return (200, #"{"data":{"models":{"edges":[{"node":{"id":"1","settings":{"associations":[{"when":{"condition":{"type":"group","conditions":[{"type":"condition","field":"stream","operator":"eq","value":true}]}}}]}}}]}}}"#)
        }
        let detail = try await client().modelDetail(id:"1")
        XCTAssertEqual(calls,2)
        XCTAssertEqual(detail?["settings"]["associations"].array.first?["when"]["condition"]["conditions"].array.first?["field"], .string("stream"))
    }
    func testEndpointRetainsDeploymentPrefix() throws {
        let url = AxonClient.endpoint(baseURL: URL(string: "https://axon.example.com/gateway/")!, path: "admin/graphql")
        XCTAssertEqual(url.absoluteString, "https://axon.example.com/gateway/admin/graphql")
        XCTAssertFalse(url.absoluteString.contains("%2F"))
    }
}
