import XCTest
@testable import AIUM

final class AppLinksTests: XCTestCase {
    func testAppStoreURLsUsePublishedCustomDomain() {
        XCTAssertEqual(
            AppLinks.privacyPolicy.absoluteString,
            "https://aium.studiofreesia.com/privacy/"
        )
        XCTAssertEqual(
            AppLinks.support.absoluteString,
            "https://aium.studiofreesia.com/support/"
        )
    }
}
