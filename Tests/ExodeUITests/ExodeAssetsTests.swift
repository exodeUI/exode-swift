import XCTest

@testable import ExodeUI

final class ExodeAssetsTests: XCTestCase {
    private let document =
        "<body><canvas id=\"exodeui-canvas\"></canvas>"
        + "<script src=\"engine.bundle.js\"></script></body>"

    func testComposeInlinesTheBundle() throws {
        let composed = try ExodeAssets.composeHTML(
            html: document,
            bundle: "window.__bundleCount = 1;"
        )
        XCTAssertTrue(composed.contains("<script>\nwindow.__bundleCount = 1;\n</script>"))
        XCTAssertFalse(composed.contains(ExodeAssets.scriptMarker))
        XCTAssertTrue(composed.contains("id=\"exodeui-canvas\""))
    }

    func testComposeFailsLoudlyWithoutMarker() {
        XCTAssertThrowsError(try ExodeAssets.composeHTML(html: "<body></body>", bundle: "")) { error in
            guard case ExodeAssetError.malformedDocument = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testComposeEscapesClosingScriptTags() throws {
        let composed = try ExodeAssets.composeHTML(
            html: document,
            bundle: #"const closing = "</script>";"#
        )
        XCTAssertTrue(composed.contains(#"const closing = "<\/script>";"#))
    }

    func testBexodeChunksSplitAt192KBAndReassemble() {
        let bytes = Data((0..<500_000).map { UInt8($0 % 251) })
        let chunks = ExodeAssets.bexodeChunks(bytes)
        XCTAssertEqual(chunks.count, 3)
        XCTAssertEqual(chunks[0].count, ExodeAssets.binaryChunkBytes)
        XCTAssertEqual(chunks[1].count, ExodeAssets.binaryChunkBytes)
        XCTAssertEqual(chunks.reduce(Data(), +), bytes)
    }

    func testBexodeChunksYieldNothingForEmptyInput() {
        XCTAssertTrue(ExodeAssets.bexodeChunks(Data()).isEmpty)
    }

    func testBundledDocumentContainsTheBridge() throws {
        let document = try ExodeAssets.loadDocument()
        XCTAssertTrue(document.contains("ExodeBridge"))
        XCTAssertTrue(document.contains("exodeui-canvas"))
        XCTAssertFalse(document.contains(ExodeAssets.scriptMarker))
    }

    func testDocumentIsComposedOncePerBundle() throws {
        ExodeAssets.clearDocumentCache()
        XCTAssertEqual(ExodeAssets.cachedDocumentCount, 0)

        let first = try ExodeAssets.loadDocument()
        XCTAssertEqual(ExodeAssets.cachedDocumentCount, 1)

        let second = try ExodeAssets.loadDocument()
        XCTAssertEqual(ExodeAssets.cachedDocumentCount, 1)
        XCTAssertTrue(first == second, "The second load should reuse the composed document")

        ExodeAssets.clearDocumentCache()
        XCTAssertEqual(ExodeAssets.cachedDocumentCount, 0)
    }

    func testMissingAssetThrows() {
        XCTAssertThrowsError(
            try ExodeAssets.assetData(named: "definitely-not-here.bexode")
        ) { error in
            guard case ExodeAssetError.assetMissing = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testAssetLookupAcceptsNamesWithAndWithoutAnExtension() throws {
        let extensionless = try ExodeAssets.assetData(named: "demo", bundle: .module)
        let explicit = try ExodeAssets.assetData(named: "demo.bexode", bundle: .module)
        XCTAssertEqual(extensionless, explicit)
        XCTAssertGreaterThan(extensionless.count, 4)
    }

    func testAssetLookupPrefersTheRequestedExtension() throws {
        let json = try ExodeAssets.assetText(named: "demo.exode", bundle: .module)
        XCTAssertTrue(json.contains("\"flutter-demo\""))
    }
}
