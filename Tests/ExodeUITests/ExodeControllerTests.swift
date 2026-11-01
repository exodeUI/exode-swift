import XCTest

@testable import ExodeUI

@MainActor
final class ExodeControllerTests: XCTestCase {
    func testCommandsQueueUntilTheArtboardIsReady() async {
        let controller = ExodeUICanvasController()
        let executor = RecordingExecutor()
        controller.attach(executor: executor)

        controller.play()
        XCTAssertEqual(controller.pendingCallCount, 1)
        XCTAssertTrue(executor.scripts.isEmpty)

        controller.markHostReady(bridgeVersion: "7.2.20")
        XCTAssertEqual(controller.bridgeVersion, "7.2.20")
        XCTAssertEqual(controller.pendingCallCount, 1, "play() waits for an artboard, not just the host")

        controller.markReady(artboardId: "hero")
        await waitUntil { controller.pendingCallCount == 0 }

        XCTAssertEqual(executor.scripts, ["ExodeBridge.play()"])
        XCTAssertEqual(controller.artboardId, "hero")
        XCTAssertTrue(controller.isReady)
    }

    func testArgumentsAreEscaped() async {
        let controller = ExodeUICanvasController()
        let executor = RecordingExecutor()
        controller.attach(executor: executor)
        controller.markHostReady(bridgeVersion: nil)
        controller.markReady(artboardId: "hero")

        controller.setInputText("name", "O'Brien \"quoted\"\nnext")
        await waitUntil { executor.scripts.count == 1 }

        let script = executor.scripts.first ?? ""
        XCTAssertTrue(script.hasPrefix("ExodeBridge.setInputText(\"name\", \""))
        XCTAssertTrue(script.contains(#"O'Brien \"quoted\"\nnext"#))
    }

    func testLoadJsonWaitsForTheHostAndForwardsOptions() async throws {
        let controller = ExodeUICanvasController()
        let executor = RecordingExecutor()
        controller.attach(executor: executor)

        let task = Task {
            try await controller.loadJson(
                #"{"id":"hero","width":640}"#,
                options: ExodeOptions(fit: .cover)
            )
        }

        XCTAssertTrue(executor.scripts.isEmpty)
        controller.markHostReady(bridgeVersion: nil)
        try await task.value

        let script = try XCTUnwrap(executor.scripts.first)
        XCTAssertTrue(script.hasPrefix("ExodeBridge.loadJson("))
        XCTAssertTrue(script.contains(#""fit":"Cover""#))
        XCTAssertTrue(script.contains(#"\"id\":\"hero\""#))
    }

    func testGetInputReturnsTheBridgeValue() async {
        let controller = ExodeUICanvasController()
        let executor = RecordingExecutor()
        executor.result = #"{"value":42}"#
        controller.attach(executor: executor)
        controller.markHostReady(bridgeVersion: nil)
        controller.markReady(artboardId: "hero")

        let value = await controller.getInput("score")

        XCTAssertEqual(value as? NSNumber, 42)
        XCTAssertEqual(
            executor.scripts.first,
            #"JSON.stringify(ExodeBridge.getInput("score"))"#
        )
    }

    func testSetLayoutKeepsTheOptionsItDoesNotChange() async {
        let controller = ExodeUICanvasController()
        let executor = RecordingExecutor()
        controller.attach(executor: executor)
        controller.configure(options: ExodeOptions(alignment: .bottomLeft, layoutScaleFactor: 0.5))
        controller.markHostReady(bridgeVersion: nil)
        controller.markReady(artboardId: "hero")

        controller.setLayout(fit: .fill)
        await waitUntil { executor.scripts.count == 1 }

        XCTAssertEqual(
            executor.scripts.first,
            "ExodeBridge.setLayout(\"Fill\", \"BottomLeft\", 0.5)"
        )
    }

    func testCommandFailuresPublishAnError() async {
        let controller = ExodeUICanvasController()
        let executor = FailingExecutor()
        controller.attach(executor: executor)
        controller.markHostReady(bridgeVersion: nil)
        controller.markReady(artboardId: "hero")

        controller.play()
        await waitUntil { controller.lastError != nil }

        XCTAssertEqual(controller.lastError?.source, "bridge")
    }

    func testDisposeDrainsQueuedCalls() async {
        let controller = ExodeUICanvasController()
        let executor = RecordingExecutor()
        controller.attach(executor: executor)
        controller.play()

        XCTAssertEqual(controller.pendingCallCount, 1)
        controller.dispose()

        XCTAssertTrue(controller.isDisposed)
        XCTAssertEqual(controller.pendingCallCount, 0)
        controller.play()
        XCTAssertTrue(executor.scripts.isEmpty)
    }

    func testClearKeepsTheHostReady() async {
        let controller = ExodeUICanvasController()
        let executor = RecordingExecutor()
        controller.attach(executor: executor)
        controller.markHostReady(bridgeVersion: nil)
        controller.markReady(artboardId: "hero")

        controller.clear()
        await waitUntil { executor.scripts.count == 1 }

        XCTAssertEqual(executor.scripts, ["ExodeBridge.clear()"])
        XCTAssertFalse(controller.isReady)
    }

    func testClearKeepsArtboardCommandsQueued() async {
        let controller = ExodeUICanvasController()
        let executor = RecordingExecutor()
        controller.attach(executor: executor)
        controller.markHostReady(bridgeVersion: nil)
        controller.markReady(artboardId: "hero")

        controller.clear()
        await waitUntil { executor.scripts.count == 1 }

        controller.play()
        await Task.yield()
        XCTAssertEqual(controller.pendingCallCount, 1, "play() must wait for a new artboard")
        XCTAssertEqual(executor.scripts, ["ExodeBridge.clear()"])

        controller.markReady(artboardId: "next")
        await waitUntil { controller.pendingCallCount == 0 }
        XCTAssertEqual(executor.scripts.last, "ExodeBridge.play()")
    }

    func testBootWatchdogReportsWhenTheEngineNeverBoots() async {
        let controller = ExodeUICanvasController()
        controller.bootTimeout = 0.05
        controller.attach(executor: RecordingExecutor())
        controller.startBootWatchdog()

        await waitUntil { controller.lastError != nil }

        XCTAssertEqual(controller.lastError?.source, "boot")
        XCTAssertFalse(controller.isHostReady)
        XCTAssertFalse(controller.isLoading)
        controller.cancelBootWatchdog()
    }

    func testBootWatchdogIsCancelledWhenTheHostIsReady() async {
        let controller = ExodeUICanvasController()
        controller.bootTimeout = 0.05
        controller.attach(executor: RecordingExecutor())
        controller.startBootWatchdog()
        controller.markHostReady(bridgeVersion: "7.2.20")

        try? await Task.sleep(nanoseconds: 150_000_000)

        XCTAssertNil(controller.lastError)
        XCTAssertTrue(controller.isHostReady)
        XCTAssertEqual(controller.bridgeVersion, "7.2.20")
    }

    func testBootWatchdogDoesNotReplaceAnEarlierFailure() async {
        let controller = ExodeUICanvasController()
        controller.bootTimeout = 0.05
        controller.attach(executor: RecordingExecutor())
        controller.report(ExodeUIError(message: "resources missing", source: "load"))
        controller.startBootWatchdog()

        try? await Task.sleep(nanoseconds: 150_000_000)

        XCTAssertEqual(controller.lastError?.source, "load")
        XCTAssertEqual(controller.lastError?.message, "resources missing")
    }

    func testDisposeCancelsTheBootWatchdog() async {
        let controller = ExodeUICanvasController()
        controller.bootTimeout = 0.05
        controller.attach(executor: RecordingExecutor())
        controller.startBootWatchdog()
        controller.dispose()

        try? await Task.sleep(nanoseconds: 150_000_000)

        XCTAssertNil(controller.lastError)
        XCTAssertNil(controller.bridgeVersion)
    }

    func testQueuedCommandsAreBounded() {
        let controller = ExodeUICanvasController()
        controller.attach(executor: RecordingExecutor())

        for _ in 0..<(ExodeUICanvasController.maxQueuedCalls + 8) {
            controller.play()
        }

        XCTAssertEqual(controller.pendingCallCount, ExodeUICanvasController.maxQueuedCalls)
        XCTAssertEqual(controller.lastError?.source, "queue")

        // Recovery re-arms the overflow report for a later outage.
        controller.markHostReady(bridgeVersion: nil)
        controller.markReady(artboardId: "hero")
    }

    func testCaptureImageDecodesPNGData() async {
        let controller = ExodeUICanvasController()
        let executor = RecordingExecutor()
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        executor.result = "data:image/png;base64,\(png.base64EncodedString())"
        controller.attach(executor: executor)
        controller.markHostReady(bridgeVersion: nil)
        controller.markReady(artboardId: "hero")

        let captured = await controller.captureImage()

        XCTAssertEqual(captured, png)
        XCTAssertEqual(executor.scripts.first, "ExodeBridge.captureImage()")
    }

    func testCaptureImageReturnsNilForUnusableResults() async {
        for result in [nil, "", "not-a-data-url", "data:image/webp;base64,AAAA"] as [Any?] {
            let controller = ExodeUICanvasController()
            let executor = RecordingExecutor()
            executor.result = result
            controller.attach(executor: executor)
            controller.markHostReady(bridgeVersion: nil)
            controller.markReady(artboardId: "hero")

            let captured = await controller.captureImage()

            XCTAssertNil(captured, "Expected nil for \(String(describing: result))")
        }
    }

    // MARK: - Helpers

    private func waitUntil(
        timeout: TimeInterval = 2,
        _ condition: @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }
}

@MainActor
private final class RecordingExecutor: ExodeJavaScriptEvaluating {
    var scripts: [String] = []
    var result: Any?

    func evaluate(_ script: String) async throws -> Any? {
        scripts.append(script)
        return result
    }
}

@MainActor
private final class FailingExecutor: ExodeJavaScriptEvaluating {
    func evaluate(_ script: String) async throws -> Any? {
        throw ExodeUIError(message: "boom", source: "bridge")
    }
}
