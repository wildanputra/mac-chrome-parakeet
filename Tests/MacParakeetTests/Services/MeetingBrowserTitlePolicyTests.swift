import XCTest

@testable import MacParakeetCore

final class MeetingBrowserTitlePolicyTests: XCTestCase {
    func testFallbackTitlesAreReplaceable() {
        XCTAssertTrue(MeetingBrowserTitlePolicy.canReplaceTitle("Meeting"))
        XCTAssertTrue(MeetingBrowserTitlePolicy.canReplaceTitle("Meeting Jun 17, 2026 at 09:59"))
        XCTAssertTrue(MeetingBrowserTitlePolicy.canReplaceTitle("Google Meet"))
        XCTAssertTrue(MeetingBrowserTitlePolicy.canReplaceTitle("Zoom Meeting"))
        XCTAssertTrue(MeetingBrowserTitlePolicy.canReplaceTitle("Teams Meeting"))
        XCTAssertTrue(MeetingBrowserTitlePolicy.canReplaceTitle("Webex Meeting"))
    }

    func testRealTitlesAreNotReplaceable() {
        XCTAssertFalse(MeetingBrowserTitlePolicy.canReplaceTitle("Weekly sync"))
        XCTAssertFalse(MeetingBrowserTitlePolicy.canReplaceTitle("Meeting 2026 Budget Planning"))
        XCTAssertFalse(MeetingBrowserTitlePolicy.canReplaceTitle("Quarterly planning"))
    }

    func testNormalizedBrowserTitleCollapsesWhitespaceAndRejectsJunk() {
        XCTAssertEqual(
            MeetingBrowserTitlePolicy.normalizedBrowserTitle("  Quarterly   planning \n review "),
            "Quarterly planning review"
        )
        XCTAssertNil(MeetingBrowserTitlePolicy.normalizedBrowserTitle(nil))
        XCTAssertNil(MeetingBrowserTitlePolicy.normalizedBrowserTitle("   "))
        // A page title equal to a platform fallback adds nothing over the
        // label the coordinator would use anyway.
        XCTAssertNil(MeetingBrowserTitlePolicy.normalizedBrowserTitle("Google Meet"))
        XCTAssertNil(MeetingBrowserTitlePolicy.normalizedBrowserTitle(String(repeating: "x", count: 200)))
    }
}
