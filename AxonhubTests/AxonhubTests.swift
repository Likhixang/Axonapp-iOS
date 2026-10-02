import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import Axonhub

final class AxonhubTests: XCTestCase {

    func testJSONLosslessCoding() throws {
        let jsonStr = """
        {
            "name": "Production Channel",
            "count": 42,
            "rate": 99.5,
            "active": true,
            "tags": ["gpt-4", "fast"],
            "meta": { "region": "us-east" }
        }
        """
        guard let json = JSON.from(jsonStr) else {
            XCTFail("Failed to parse JSON")
            return
        }
        XCTAssertEqual(json["name"].string, "Production Channel")
        XCTAssertEqual(json["count"].int, 42)
        XCTAssertEqual(json["rate"].number, 99.5)
        XCTAssertEqual(json["active"].bool, true)
        XCTAssertEqual(json["tags"].array.count, 2)
        XCTAssertEqual(json["meta"]["region"].string, "us-east")
    }

    func testURLValidation() {
        // Valid HTTPS
        XCTAssertNoThrow(try AxonClient(baseURL: "https://axon.example.com", authType: .apiKey, token: "test_key", allowHTTP: false))
        
        // Insecure HTTP rejected by default
        XCTAssertThrowsError(try AxonClient(baseURL: "http://axon.example.com", authType: .apiKey, token: "test_key", allowHTTP: false)) { error in
            XCTAssertEqual(error as? AxonAPIError, AxonAPIError.insecureURL)
        }

        // Insecure HTTP allowed when flag enabled
        XCTAssertNoThrow(try AxonClient(baseURL: "http://192.168.1.100:8090", authType: .apiKey, token: "test_key", allowHTTP: true))

        // Invalid URLs with credentials or query
        XCTAssertThrowsError(try AxonClient(baseURL: "https://user:pass@axon.example.com", authType: .apiKey, token: "key"))
        XCTAssertThrowsError(try AxonClient(baseURL: "https://axon.example.com?query=1", authType: .apiKey, token: "key"))
    }

    func testAxonAPIErrorDescriptions() {
        XCTAssertFalse(AxonAPIError.invalidURL.localizedDescription.isEmpty)
        XCTAssertFalse(AxonAPIError.insecureURL.localizedDescription.isEmpty)
        XCTAssertFalse(AxonAPIError.unauthorized.localizedDescription.isEmpty)
        XCTAssertFalse(AxonAPIError.forbidden.localizedDescription.isEmpty)
        XCTAssertFalse(AxonAPIError.transport.localizedDescription.isEmpty)
        XCTAssertFalse(AxonAPIError.timedOut.localizedDescription.isEmpty)
        XCTAssertFalse(AxonAPIError.httpStatus(500).localizedDescription.isEmpty)
        XCTAssertFalse(AxonAPIError.graphQLError("Test error").localizedDescription.isEmpty)
    }

    func testAxonAuthTypeTitles() {
        for type in AxonAuthType.allCases {
            XCTAssertFalse(type.title.isEmpty)
        }
    }
}
