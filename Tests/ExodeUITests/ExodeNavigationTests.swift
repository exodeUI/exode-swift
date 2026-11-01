#if os(iOS) || os(macOS)
import XCTest

@testable import ExodeUI

/// The allow-list stops an artboard from steering the host WebView to arbitrary
/// URLs; only the local document and inline data may load.
final class ExodeNavigationTests: XCTestCase {
    func testAllowsTheLocalDocumentAndInlineData() {
        let allowed = [
            "https://localhost/exode/",
            "https://localhost/",
            "about:blank",
            "data:text/html,hi",
            "blob:https://localhost/1234",
        ]
        for value in allowed {
            XCTAssertTrue(
                ExodeCanvasCoordinator.isAllowed(url: URL(string: value)!),
                "Expected \(value) to be allowed"
            )
        }
    }

    func testBlocksExternalAndLocalFileURLs() {
        let blocked = [
            "https://example.com/",
            "http://localhost/",
            "file:///etc/passwd",
            "javascript:alert(1)",
            "tel:+15551234567",
        ]
        for value in blocked {
            XCTAssertFalse(
                ExodeCanvasCoordinator.isAllowed(url: URL(string: value)!),
                "Expected \(value) to be blocked"
            )
        }
    }

    func testTrustsURLsWithoutAScheme() {
        let url = URL(string: "//localhost/exode/")!
        XCTAssertNil(url.scheme)
        XCTAssertTrue(ExodeCanvasCoordinator.isAllowed(url: url))
    }
}

final class ExodePlatformTests: XCTestCase {
    func testReportsSupportOnApplePlatformsWithWebKit() {
        XCTAssertTrue(ExodePlatform.isSupported)
    }
}
#endif
