import SwiftUI
import XCTest

@testable import ExodeUI

#if os(iOS) || os(macOS)
final class ExodeCSSTests: XCTestCase {
    func testOpaqueColourBecomesRGBA() {
        XCTAssertEqual(
            ExodeCSS.rgba(Color(red: 0, green: 0, blue: 0)),
            "rgba(0, 0, 0, 1.000)"
        )
        XCTAssertEqual(
            ExodeCSS.rgba(Color(red: 1, green: 0, blue: 0.5)),
            "rgba(255, 0, 128, 1.000)"
        )
    }

    func testAlphaIsPreserved() {
        XCTAssertEqual(
            ExodeCSS.rgba(Color(red: 0, green: 0, blue: 1, opacity: 0.5)),
            "rgba(0, 0, 255, 0.500)"
        )
    }

    func testClearColourIsSkipped() {
        XCTAssertNil(ExodeCSS.rgba(.clear))
    }

    @MainActor
    func testBackgroundScriptCreatesStyleElement() {
        let script = ExodeCanvasCoordinator.pageBackgroundScript(
            css: "rgba(0, 0, 0, 1.000)"
        )
        XCTAssertTrue(script.contains("exodeui-background"))
        XCTAssertTrue(script.contains("html,body{background:rgba(0, 0, 0, 1.000) !important;}"))
        XCTAssertTrue(script.contains("appendChild"))
    }

    @MainActor
    func testClearScriptRemovesStyleElement() {
        let script = ExodeCanvasCoordinator.pageBackgroundClearScript
        XCTAssertTrue(script.contains("exodeui-background"))
        XCTAssertTrue(script.contains("removeChild"))
    }
}
#endif
