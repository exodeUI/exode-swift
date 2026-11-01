#if os(iOS) || os(macOS)
import WebKit
import XCTest

@testable import ExodeUI

/// End-to-end checks against a real `WKWebView`.
///
/// WebKit needs a running application run loop, which is not always available
/// on CI. Set `EXODE_RUN_WEBVIEW_TESTS=1` to opt in.
@MainActor
final class ExodeWebViewIntegrationTests: XCTestCase {
    /// WebKit needs a running application run loop, which is not always
    /// available on CI. The workflow opts in with `EXODE_RUN_WEBVIEW_TESTS=1`.
    private func requireWebKit() throws {
        guard ProcessInfo.processInfo.environment["EXODE_RUN_WEBVIEW_TESTS"] == "1" else {
            throw XCTSkip("Set EXODE_RUN_WEBVIEW_TESTS=1 to run WebKit integration tests")
        }
    }

    func testDocumentBootsAndLoadsAnArtboard() async throws {
        try requireWebKit()
        let harness = try await TestHarness.start()
        defer { harness.tearDown() }

        XCTAssertFalse(harness.controller.bridgeVersion?.isEmpty ?? true)

        let artboard = """
        {"id":"integration","width":640,"height":420,"objects":[]}
        """
        _ = try await harness.webView.evaluateJavaScript(
            "ExodeBridge.loadJson(\(ExodeJS.string(artboard)), \(ExodeJS.json(ExodeOptions().dictionary)))"
        )
        await harness.waitForArtboard()
        harness.assertNoEngineErrors()

        XCTAssertEqual(harness.controller.artboardId, "integration")
        XCTAssertTrue(harness.recorder.events.contains { $0.type == "ready" && $0.string("id") == "integration" })

        // Snapshots travel the same public path an application uses.
        _ = try await harness.webView.evaluateJavaScript(
            """
            (() => {
                const canvas = document.getElementById('exodeui-canvas');
                if (!canvas) return false;
                canvas.width = 320;
                canvas.height = 200;
                return true;
            })()
            """
        )

        let captured = await harness.controller.captureImage()
        let png = try XCTUnwrap(captured)
        XCTAssertEqual(
            Array(png.prefix(8)),
            [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
            "captureImage() should return PNG bytes"
        )
    }

    /// Loads the real `.bexode` fixture through the public controller API,
    /// exercising the chunked transfer, `.bexode` decoding, the ready event and
    /// the PNG snapshot path.
    func testLoadsABundledBexodeArtboard() async throws {
        try requireWebKit()
        let harness = try await TestHarness.start()
        defer { harness.tearDown() }

        try await harness.controller.loadBexodeAsset("demo", bundle: .module)
        await harness.waitForArtboard()
        harness.assertNoEngineErrors()

        XCTAssertEqual(harness.controller.artboardId, "flutter-demo")
        XCTAssertTrue(harness.controller.isReady)
        XCTAssertNil(harness.controller.lastError)

        let captured = await harness.controller.captureImage()
        let png = try XCTUnwrap(captured, "The demo artboard should render a frame")
        XCTAssertGreaterThan(png.count, 2_000, "A rendered demo frame is not a blank canvas")

        let size = try XCTUnwrap(pngSize(png))
        XCTAssertGreaterThanOrEqual(size.width, 640)
        XCTAssertGreaterThanOrEqual(size.height, 420)
    }

    /// Loads the `.exode` JSON fixture from the test bundle, matching how an
    /// application ships a decompressed artboard.
    func testLoadsABundledExodeArtboard() async throws {
        try requireWebKit()
        let harness = try await TestHarness.start()
        defer { harness.tearDown() }

        try await harness.controller.loadJsonAsset("demo", bundle: .module)
        await harness.waitForArtboard()
        harness.assertNoEngineErrors()

        XCTAssertEqual(harness.controller.artboardId, "flutter-demo")
        XCTAssertNil(harness.controller.lastError)

        let png = await harness.controller.captureImage()
        XCTAssertNotNil(png)
    }

    /// Playback and input commands must reach the engine without bridge errors.
    func testPlaybackAndInputsReachTheEngine() async throws {
        try requireWebKit()
        let harness = try await TestHarness.start()
        defer { harness.tearDown() }

        try await harness.controller.loadJsonAsset("demo", bundle: .module)
        await harness.waitForArtboard()

        harness.controller.pause()
        harness.controller.seek(1.25)
        harness.controller.play()
        harness.controller.setInputBool("isDark", true)
        harness.controller.setInputNumber("volume", 0.8)
        harness.controller.setInputText("name", "O'Brien")

        // Wait for the fire-and-forget queue to drain through the engine.
        _ = await waitUntil { harness.controller.pendingCallCount == 0 }
        try? await Task.sleep(nanoseconds: 200_000_000)

        harness.assertNoEngineErrors()
        XCTAssertNil(harness.controller.lastError)

        // The demo artboard declares no inputs, so unknown names read back nil.
        let unknown = await harness.controller.getInput("not-an-input")
        XCTAssertNil(unknown)
    }

    /// The injected page-background style must paint the letterbox behind a
    /// `contain`-fitted artboard instead of leaving the WebView's default white.
    func testPageBackgroundPaintsTheDocument() async throws {
        try requireWebKit()
        let harness = try await TestHarness.start(
            backgroundCSS: "rgba(18, 52, 86, 1.000)"
        )
        defer { harness.tearDown() }

        let painted = try await harness.webView.evaluateJavaScript(
            "getComputedStyle(document.body).backgroundColor"
        ) as? String
        XCTAssertEqual(painted, "rgb(18, 52, 86)")

        // Re-running with a different colour updates the same style element,
        // which is how a live `backgroundColor` change is applied.
        _ = try await harness.webView.evaluateJavaScript(
            ExodeCanvasCoordinator.pageBackgroundScript(css: "rgba(200, 30, 40, 1.000)")
        )
        let repainted = try await harness.webView.evaluateJavaScript(
            "getComputedStyle(document.body).backgroundColor"
        ) as? String
        XCTAssertEqual(repainted, "rgb(200, 30, 40)")
        let styleCount = try await harness.webView.evaluateJavaScript(
            "document.querySelectorAll('#exodeui-background').length"
        ) as? Int
        XCTAssertEqual(styleCount, 1)

        // Clearing removes the style element so the page is transparent again.
        _ = try await harness.webView.evaluateJavaScript(
            ExodeCanvasCoordinator.pageBackgroundClearScript
        )
        let cleared = try await harness.webView.evaluateJavaScript(
            "getComputedStyle(document.body).backgroundColor"
        ) as? String
        XCTAssertEqual(cleared, "rgba(0, 0, 0, 0)")
    }

    // MARK: - Helpers

    private func pngSize(_ data: Data) -> (width: Int, height: Int)? {
        // PNG IHDR: 8-byte signature, 4-byte length, "IHDR", width, height.
        guard data.count >= 24 else { return nil }
        func int32(_ range: Range<Int>) -> Int {
            data[range].reduce(0) { ($0 << 8) | Int($1) }
        }
        return (int32(16..<20), int32(20..<24))
    }

    @MainActor
    private final class TestHarness {
        let controller = ExodeUICanvasController()
        let recorder = EventRecorder()
        let executor = ExodeWebViewExecutor()
        let webView: WKWebView

        private init(webView: WKWebView) {
            self.webView = webView
        }

        static func start(backgroundCSS: String? = nil) async throws -> TestHarness {
            let configuration = WKWebViewConfiguration()
            let webView = WKWebView(
                frame: CGRect(x: 0, y: 0, width: 640, height: 420),
                configuration: configuration
            )
            let harness = TestHarness(webView: webView)
            configuration.userContentController.add(
                harness.recorder,
                name: ExodeMessageHandler.name
            )
            if let backgroundCSS {
                configuration.userContentController.addUserScript(
                    WKUserScript(
                        source: ExodeCanvasCoordinator.pageBackgroundScript(css: backgroundCSS),
                        injectionTime: .atDocumentEnd,
                        forMainFrameOnly: true
                    )
                )
            }
            harness.executor.webView = webView
            harness.controller.attach(executor: harness.executor)
            harness.controller.bootTimeout = 20

            harness.recorder.onEvent = { [weak harness] event in
                guard let harness else { return }
                switch event.type {
                case "hostReady":
                    harness.controller.markHostReady(bridgeVersion: event.string("bridgeVersion"))
                case "ready":
                    harness.controller.markReady(artboardId: event.string("id"))
                case "error":
                    harness.controller.report(
                        ExodeUIError(
                            message: event.string("message") ?? "unknown engine error",
                            stack: event.string("stack"),
                            source: event.string("source")
                        )
                    )
                default:
                    break
                }
            }

            let document = try ExodeAssets.loadDocument()
            webView.loadHTMLString(document, baseURL: URL(string: "https://localhost/exode/"))
            harness.controller.markLoading()
            harness.controller.startBootWatchdog()

            let booted = await waitUntil {
                harness.controller.isHostReady || harness.controller.lastError != nil
            }
            XCTAssertTrue(booted, "The ExodeUI engine never booted")
            if let error = harness.controller.lastError {
                XCTFail("Boot failed: \(error.message)")
                throw error
            }
            return harness
        }

        func waitForArtboard(timeout: TimeInterval = 20) async {
            let ready = await waitUntil(timeout: timeout) {
                controller.isReady || controller.lastError != nil
            }
            XCTAssertTrue(ready, "The artboard never became ready")
        }

        func assertNoEngineErrors() {
            XCTAssertFalse(
                recorder.events.contains { $0.type == "error" },
                "Engine errors: \(recorder.events.filter { $0.type == "error" })"
            )
        }

        func tearDown() {
            webView.configuration.userContentController
                .removeScriptMessageHandler(forName: ExodeMessageHandler.name)
            controller.cancelBootWatchdog()
            controller.dispose()
        }
    }

    /// The harness exposes this so tests can assert on raw events.
    @MainActor
    private final class EventRecorder: NSObject, WKScriptMessageHandler {
        var events: [ExodeEvent] = []
        var onEvent: ((ExodeEvent) -> Void)?

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard let raw = message.body as? String, let event = ExodeEvent.parse(raw) else { return }
            events.append(event)
            onEvent?(event)
        }
    }
}

@MainActor
private func waitUntil(
    timeout: TimeInterval = 20,
    _ condition: () -> Bool
) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
    return condition()
}
#endif
