import XCTest

@testable import ExodeUI

final class ExodeOptionsTests: XCTestCase {
    func testDefaultsMatchTheBridgeContract() {
        let options = ExodeOptions()
        XCTAssertEqual(options.fit, .contain)
        XCTAssertEqual(options.alignment, .center)
        XCTAssertEqual(options.layoutScaleFactor, 1)
        XCTAssertTrue(options.autoPlay)
        XCTAssertTrue(options.interactive)
        XCTAssertTrue(options.preventScroll)
        XCTAssertTrue(options.callbackNames.isEmpty)
    }

    func testDictionaryUsesEngineLiterals() {
        let options = ExodeOptions(
            fit: .fitWidth,
            alignment: .bottomRight,
            layoutScaleFactor: 0.5,
            autoPlay: false,
            interactive: false,
            preventScroll: false,
            callbackNames: ["onPurchase", "onShare"]
        )
        let dictionary = options.dictionary

        XCTAssertEqual(dictionary["fit"] as? String, "FitWidth")
        XCTAssertEqual(dictionary["alignment"] as? String, "BottomRight")
        XCTAssertEqual(dictionary["layoutScaleFactor"] as? Double, 0.5)
        XCTAssertEqual(dictionary["autoPlay"] as? Bool, false)
        XCTAssertEqual(dictionary["interactive"] as? Bool, false)
        XCTAssertEqual(dictionary["preventScroll"] as? Bool, false)
        XCTAssertEqual(dictionary["callbackNames"] as? [String], ["onPurchase", "onShare"])
        XCTAssertTrue(JSONSerialization.isValidJSONObject(dictionary))
    }

    func testEnumRawValuesCoverEveryEngineOption() {
        XCTAssertEqual(ExodeFit.allCases.map(\.rawValue), [
            "Contain", "Cover", "Fill", "FitWidth", "FitHeight",
            "None", "ScaleDown", "Layout",
        ])
        XCTAssertEqual(ExodeAlignment.allCases.count, 9)
        XCTAssertEqual(ExodeAlignment.centerRight.rawValue, "CenterRight")
    }
}
