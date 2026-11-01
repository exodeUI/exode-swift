import XCTest

@testable import ExodeUI

final class ExodeEventTests: XCTestCase {
    func testParsesBridgeMessages() throws {
        let event = try XCTUnwrap(
            ExodeEvent.parse(#"{"type":"ready","id":"hero","width":640,"height":420}"#)
        )
        XCTAssertEqual(event.type, "ready")
        XCTAssertEqual(event.string("id"), "hero")
        XCTAssertEqual(event.double("width"), 640)
        XCTAssertNil(event.double("missing"))
    }

    func testRejectsUnrelatedMessages() {
        XCTAssertNil(ExodeEvent.parse("not json"))
        XCTAssertNil(ExodeEvent.parse("[]"))
        XCTAssertNil(ExodeEvent.parse(#"{"id":"no-type"}"#))
        XCTAssertNil(ExodeEvent.parse(#"{"type":""}"#))
    }

    func testTypedHelpers() throws {
        let event = try XCTUnwrap(
            ExodeEvent.parse(
                #"{"type":"toggle","name":"visible","checked":true,"event":{"objectId":"a"},"args":[1,2]}"#
            )
        )
        XCTAssertEqual(event.bool("checked"), true)
        XCTAssertEqual(event.map("event")?["objectId"] as? String, "a")
        XCTAssertEqual(event.list("args")?.count, 2)
        XCTAssertNil(event.map("missing"))
        XCTAssertNil(event.list("missing"))
    }

    func testNumbersAndStringsAreCoerced() throws {
        let event = try XCTUnwrap(
            ExodeEvent.parse(#"{"type":"x","count":"7","flag":"true"}"#)
        )
        XCTAssertEqual(event.int("count"), 7)
        XCTAssertEqual(event.string("count"), "7")
        XCTAssertNil(event.bool("flag"))
    }
}
