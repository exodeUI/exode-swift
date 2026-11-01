import XCTest

@testable import ExodeUI

final class ExodeJSTests: XCTestCase {
    func testStringRoundTripsQuotesNewlinesAndBackslashes() throws {
        let samples = [
            "it's fine",
            "he said \"hello\"",
            "line one\nline two",
            "C:\\path\\to\\file",
            "emoji 🎛️ and unicode ✓",
            "",
        ]
        for sample in samples {
            let literal = ExodeJS.string(sample)
            let data = try XCTUnwrap(literal.data(using: .utf8))
            let decoded = try JSONSerialization.jsonObject(
                with: data,
                options: [.fragmentsAllowed]
            ) as? String
            XCTAssertEqual(decoded, sample)
        }
    }

    func testStringWrapsValuesInQuotes() {
        XCTAssertEqual(ExodeJS.string("plain"), "\"plain\"")
    }

    func testNumberClampsNonFiniteValues() {
        XCTAssertEqual(ExodeJS.number(3), "3")
        XCTAssertEqual(ExodeJS.number(1.5), "1.5")
        XCTAssertEqual(ExodeJS.number(-0.25), "-0.25")
        XCTAssertEqual(ExodeJS.number(.nan), "0")
        XCTAssertEqual(ExodeJS.number(.infinity), "0")
        XCTAssertEqual(ExodeJS.number(-.infinity), "0")
    }

    func testJsonEncodesFragmentsAndContainers() {
        XCTAssertEqual(ExodeJS.json(["a": 1]), "{\"a\":1}")
        XCTAssertEqual(ExodeJS.json([1, 2]), "[1,2]")
        XCTAssertEqual(ExodeJS.json("text"), "\"text\"")
        XCTAssertEqual(ExodeJS.json(true), "true")
        XCTAssertEqual(ExodeJS.json(NSNull()), "null")
    }

    func testBoolLiteral() {
        XCTAssertEqual(ExodeJS.bool(true), "true")
        XCTAssertEqual(ExodeJS.bool(false), "false")
    }
}
