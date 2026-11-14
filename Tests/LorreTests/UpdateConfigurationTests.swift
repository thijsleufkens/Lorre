import XCTest
@testable import Lorre

final class UpdateConfigurationTests: XCTestCase {
    private let key = "dGVzdC1rZXktbm90LXJlYWw="

    func testNeedsBothKeys() {
        XCTAssertNil(UpdateConfiguration.from(infoDictionary: nil))
        XCTAssertNil(UpdateConfiguration.from(infoDictionary: [:]))
        XCTAssertNil(UpdateConfiguration.from(infoDictionary: ["SUFeedURL": "https://example.com/appcast.xml"]))
        XCTAssertNil(UpdateConfiguration.from(infoDictionary: ["SUPublicEDKey": key]))
    }

    func testValidConfiguration() {
        let configuration = UpdateConfiguration.from(infoDictionary: [
            "SUFeedURL": "https://example.com/appcast.xml",
            "SUPublicEDKey": key,
        ])
        XCTAssertEqual(configuration?.feedURL.absoluteString, "https://example.com/appcast.xml")
        XCTAssertEqual(configuration?.publicKey, key)
    }

    func testRejectsEmptyKeyAndNonHTTPSFeeds() {
        XCTAssertNil(UpdateConfiguration.from(infoDictionary: ["SUFeedURL": "https://example.com/a.xml", "SUPublicEDKey": "  "]))
        XCTAssertNil(UpdateConfiguration.from(infoDictionary: ["SUFeedURL": "http://example.com/a.xml", "SUPublicEDKey": key]))
        XCTAssertNil(UpdateConfiguration.from(infoDictionary: ["SUFeedURL": "file:///tmp/a.xml", "SUPublicEDKey": key]))
        XCTAssertNil(UpdateConfiguration.from(infoDictionary: ["SUFeedURL": "not a url", "SUPublicEDKey": key]))
        XCTAssertNil(UpdateConfiguration.from(infoDictionary: ["SUFeedURL": "", "SUPublicEDKey": key]))
        XCTAssertNil(UpdateConfiguration.from(infoDictionary: ["SUFeedURL": 5, "SUPublicEDKey": key]))
    }
}
