import Combine
import Foundation

/// Runs JavaScript inside the WebView.
///
/// The production implementation is ``ExodeWebViewExecutor``; tests inject a
/// recording implementation.
@MainActor
public protocol ExodeJavaScriptEvaluating: AnyObject {
    func evaluate(_ script: String) async throws -> Any?
}

/// Imperative handle for an ``ExodeUICanvas``.
///
/// Obtain one from ``ExodeCallbacks/onReady`` or pass your own to the canvas.
/// Calls made before the engine has booted are queued and executed in order.
@MainActor
public final class ExodeUICanvasController: ObservableObject {
    /// Whether the JavaScript host booted (`hostReady`).
    @Published public private(set) var isHostReady = false
    /// Whether an artboard has loaded and painted its first frame.
    @Published public private(set) var isReady = false
    /// Whether the canvas is loading its first frame.
    @Published public private(set) var isLoading = false
    /// Id/name reported by the last loaded artboard.
    @Published public private(set) var artboardId: String?
    /// Engine version reported by the bridge at boot.
    @Published public private(set) var bridgeVersion: String?
    /// Last bridge or runtime failure, if any.
    @Published public private(set) var lastError: ExodeUIError?
    /// Whether the controller was torn down.
    public private(set) var isDisposed = false

    /// Seconds to wait for the engine to boot before reporting an error.
    ///
    /// A WebView that never posts `hostReady` (missing resources, a crashed web
    /// content process) would otherwise leave the canvas spinning forever.
    /// Set to `0` to disable the watchdog.
    public var bootTimeout: TimeInterval = 15

    private weak var executor: (any ExodeJavaScriptEvaluating)?
    private var options = ExodeOptions()
    private var pending: [PendingCall] = []
    private var isFlushing = false
    private var bootWatchdog: Task<Void, Never>?
    private var didReportQueueOverflow = false

    /// Commands that may wait for the engine before running.
    ///
    /// Calls are queued until the host boots; if the engine never boots the
    /// queue would grow forever, so fire-and-forget commands are dropped once
    /// this limit is reached. Awaitable calls are never dropped.
    static let maxQueuedCalls = 1_024

    /// Called for failures raised by queued commands, so the canvas can forward
    /// them to ``ExodeCallbacks/onError``.
    var onCommandError: ((ExodeUIError) -> Void)?

    public init() {}

    // MARK: - Wiring

    func attach(executor: any ExodeJavaScriptEvaluating) {
        self.executor = executor
    }

    func detach() {
        cancelBootWatchdog()
        abortPending()
        executor = nil
        isHostReady = false
        isReady = false
        isLoading = false
    }

    func configure(options: ExodeOptions) {
        self.options = options
    }

    // MARK: - Boot watchdog

    /// Starts the countdown that reports a failure if the engine never boots.
    ///
    /// Called by the canvas once the WebView document is dispatched.
    func startBootWatchdog() {
        cancelBootWatchdog()
        guard !isHostReady, !isDisposed, bootTimeout > 0 else { return }

        let seconds = min(max(bootTimeout, 0), 600)
        bootWatchdog = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            guard !self.isHostReady, !self.isDisposed, self.lastError == nil else { return }
            self.report(
                ExodeUIError(
                    message: """
                    The ExodeUI engine did not start within \(Int(seconds)) seconds. \
                    Make sure the package resources are bundled and that a \
                    WKWebView is available on this platform.
                    """,
                    source: "boot"
                )
            )
        }
    }

    func cancelBootWatchdog() {
        bootWatchdog?.cancel()
        bootWatchdog = nil
    }

    func markHostReady(bridgeVersion: String?) {
        guard !isDisposed else { return }
        cancelBootWatchdog()
        self.bridgeVersion = bridgeVersion
        isHostReady = true
        flush()
    }

    func markLoading() {
        guard !isDisposed else { return }
        isLoading = true
        lastError = nil
    }

    func markReady(artboardId: String?) {
        guard !isDisposed else { return }
        cancelBootWatchdog()
        didReportQueueOverflow = false
        self.artboardId = artboardId
        isReady = true
        isLoading = false
        lastError = nil
        flush()
    }

    /// Records that the artboard was removed without pretending a frame painted.
    ///
    /// Commands that need an artboard stay queued, so the next `load…` call
    /// drains them in order instead of firing them at a blank canvas.
    func markCleared() {
        guard !isDisposed else { return }
        artboardId = nil
        isReady = false
        isLoading = false
        lastError = nil
    }

    func report(_ error: ExodeUIError) {
        lastError = error
        isLoading = false
        onCommandError?(error)
    }

    /// Destroys the engine and releases the WebView.
    public func dispose() {
        guard !isDisposed else { return }
        cancelBootWatchdog()
        if let executor {
            Task { try? await executor.evaluate("ExodeBridge.destroy()") }
        }
        isDisposed = true
        executor = nil
        abortPending()
        isHostReady = false
        isReady = false
        isLoading = false
        artboardId = nil
        bridgeVersion = nil
        onCommandError = nil
    }

    // MARK: - Loading

    /// Replaces the current artboard with `.exode` JSON text.
    public func loadJson(_ json: String, options: ExodeOptions? = nil) async throws {
        try await load(
            "ExodeBridge.loadJson(\(ExodeJS.string(json)), \(optionsJSON(options)))"
        )
        if let options { configure(options: options) }
    }

    /// Replaces the current artboard with an already-decoded artboard.
    public func loadArtboard(_ artboard: [String: Any], options: ExodeOptions? = nil) async throws {
        try await load(
            "ExodeBridge.loadObject(\(ExodeJS.json(artboard)), \(optionsJSON(options)))"
        )
        if let options { configure(options: options) }
    }

    /// Transfers raw `.bexode` bytes to the bridge in 192 KB chunks.
    public func loadBexode(_ data: Data, options: ExodeOptions? = nil) async throws {
        if let options { configure(options: options) }
        _ = try await evaluate("ExodeBridge.beginBexode(\(data.count))", requiresArtboard: false)

        for chunk in ExodeAssets.bexodeChunks(data) {
            _ = try await evaluate(
                "ExodeBridge.pushBexodeChunk(\(ExodeJS.string(chunk.base64EncodedString())))",
                requiresArtboard: false
            )
        }

        _ = try await evaluate(
            "ExodeBridge.finishBexode(\(optionsJSON(options)))",
            requiresArtboard: false
        )
    }

    /// Loads a `.bexode` file from the host application bundle.
    public func loadBexodeAsset(
        _ name: String,
        bundle: Bundle = .main,
        subdirectory: String? = nil,
        options: ExodeOptions? = nil
    ) async throws {
        let data = try ExodeAssets.assetData(
            named: name,
            bundle: bundle,
            subdirectory: subdirectory,
            extensions: ["bexode"]
        )
        try await loadBexode(data, options: options)
    }

    /// Loads an `.exode` JSON file from the host application bundle.
    public func loadJsonAsset(
        _ name: String,
        bundle: Bundle = .main,
        subdirectory: String? = nil,
        options: ExodeOptions? = nil
    ) async throws {
        let json = try ExodeAssets.assetText(
            named: name,
            bundle: bundle,
            subdirectory: subdirectory,
            extensions: ["exode", "json"]
        )
        try await loadJson(json, options: options)
    }

    /// Removes the current artboard and clears the canvas.
    public func clear() {
        guard !isDisposed else { return }
        markCleared()
        send("ExodeBridge.clear()", requiresArtboard: false)
    }

    // MARK: - Playback

    /// Starts the render loop.
    public func play() {
        send("ExodeBridge.play()")
    }

    /// Pauses the render loop, keeping the current frame.
    public func pause() {
        send("ExodeBridge.pause()")
    }

    /// Seeks to `seconds` and repaints once.
    public func seek(_ seconds: Double) {
        send("ExodeBridge.seek(\(ExodeJS.number(seconds)))")
    }

    /// Re-measures the canvas after an external size change.
    public func resize() {
        send("ExodeBridge.resize()")
    }

    /// Updates fit, alignment and scale factor.
    public func setLayout(
        fit: ExodeFit? = nil,
        alignment: ExodeAlignment? = nil,
        layoutScaleFactor: Double? = nil
    ) {
        let resolved = ExodeOptions(
            fit: fit ?? options.fit,
            alignment: alignment ?? options.alignment,
            layoutScaleFactor: layoutScaleFactor ?? options.layoutScaleFactor,
            autoPlay: options.autoPlay,
            interactive: options.interactive,
            preventScroll: options.preventScroll,
            callbackNames: options.callbackNames
        )
        options = resolved
        send(
            "ExodeBridge.setLayout("
                + "\(ExodeJS.string(resolved.fit.rawValue)), "
                + "\(ExodeJS.string(resolved.alignment.rawValue)), "
                + "\(ExodeJS.number(resolved.layoutScaleFactor))"
                + ")"
        )
    }

    /// Updates rendering options without reloading the artboard.
    public func setOptions(_ next: ExodeOptions) {
        options = next
        send("ExodeBridge.setOptions(\(ExodeJS.json(next.dictionary)))")
    }

    // MARK: - State variables

    /// Sets a state-machine input to any JSON-compatible value.
    public func setInput(_ name: String, _ value: Any) {
        send("ExodeBridge.setInput(\(ExodeJS.string(name)), \(ExodeJS.json(value)))")
    }

    public func setInputBool(_ name: String, _ value: Bool) {
        send("ExodeBridge.setInputBool(\(ExodeJS.string(name)), \(ExodeJS.bool(value)))")
    }

    public func setInputNumber(_ name: String, _ value: Double) {
        send("ExodeBridge.setInputNumber(\(ExodeJS.string(name)), \(ExodeJS.number(value)))")
    }

    public func setInputText(_ name: String, _ value: String) {
        send("ExodeBridge.setInputText(\(ExodeJS.string(name)), \(ExodeJS.string(value)))")
    }

    public func setInputStringArray(_ name: String, _ values: [String]) {
        send("ExodeBridge.setInputStringArray(\(ExodeJS.string(name)), \(ExodeJS.json(values)))")
    }

    public func setInputNumberArray(_ name: String, _ values: [Double]) {
        send("ExodeBridge.setInputNumberArray(\(ExodeJS.string(name)), \(ExodeJS.json(values)))")
    }

    /// Reads the current value of a state-machine input.
    public func getInput(_ name: String) async -> Any? {
        guard
            let raw = try? await evaluate(
                "JSON.stringify(ExodeBridge.getInput(\(ExodeJS.string(name))))",
                requiresArtboard: true
            ) as? String,
            let data = raw.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        let value = object["value"]
        return value is NSNull ? nil : value
    }

    /// Fires a named trigger (same as a state-machine listener trigger).
    public func fireTrigger(_ name: String) {
        send("ExodeBridge.fireTrigger(\(ExodeJS.string(name)))")
    }

    // MARK: - Components and charts

    /// Merges new options into a list/dropdown/slider component.
    public func updateObjectOptions(_ objectId: String, _ options: [String: Any]) {
        send(
            "ExodeBridge.updateObjectOptions("
                + "\(ExodeJS.string(objectId)), \(ExodeJS.json(options))"
                + ")"
        )
    }

    /// Replaces the data of a line/area graph component.
    public func updateGraphData(
        _ nameOrId: String,
        _ data: [Any],
        categories: [String]? = nil
    ) {
        var script = "ExodeBridge.updateGraphData("
            + "\(ExodeJS.string(nameOrId)), \(ExodeJS.json(data))"
        if let categories {
            script += ", \(ExodeJS.json(categories))"
        }
        send(script + ")")
    }

    /// Replaces the datasets of a bar chart component.
    public func updateBarChartData(
        _ nameOrId: String,
        _ datasets: [Any],
        categories: [String]? = nil
    ) {
        var script = "ExodeBridge.updateBarChartData("
            + "\(ExodeJS.string(nameOrId)), \(ExodeJS.json(datasets))"
        if let categories {
            script += ", \(ExodeJS.json(categories))"
        }
        send(script + ")")
    }

    /// Replaces the slices of a pie chart component.
    public func updatePieChartData(_ nameOrId: String, _ slices: [Any]) {
        send("ExodeBridge.updatePieChartData(\(ExodeJS.string(nameOrId)), \(ExodeJS.json(slices)))")
    }

    /// Replaces the option list of a dropdown component.
    public func setDropdownOptions(_ nameOrId: String, _ options: [String]) {
        send("ExodeBridge.setDropdownOptions(\(ExodeJS.string(nameOrId)), \(ExodeJS.json(options)))")
    }

    // MARK: - External sensors

    /// Feeds an external page/scroll offset into scroll-driven behaviours.
    public func handleScroll(x: Double, y: Double) {
        send("ExodeBridge.handleScroll(\(ExodeJS.number(x)), \(ExodeJS.number(y)))")
    }

    /// Sets the viewport scroll without simulating a pointer.
    public func setViewportScroll(x: Double, y: Double) {
        send("ExodeBridge.setViewportScroll(\(ExodeJS.number(x)), \(ExodeJS.number(y)))")
    }

    // MARK: - Snapshots

    /// Prefix the bridge uses for PNG snapshots.
    private static let pngDataURLPrefix = "data:image/png;base64,"

    /// Renders the current frame to PNG bytes.
    ///
    /// Returns `nil` when no artboard is ready, the canvas has no size yet, or
    /// the WebView cannot read its pixels.
    ///
    /// ```swift
    /// if let png = await controller.captureImage() {
    ///     UIImage(data: png)?.write(to: url)
    /// }
    /// ```
    public func captureImage() async -> Data? {
        guard
            let dataURL = try? await evaluate(
                "ExodeBridge.captureImage()",
                requiresArtboard: true
            ) as? String,
            dataURL.hasPrefix(Self.pngDataURLPrefix),
            let png = Data(
                base64Encoded: String(dataURL.dropFirst(Self.pngDataURLPrefix.count))
            )
        else {
            return nil
        }
        return png
    }

    // MARK: - Bridge plumbing

    private struct PendingCall {
        let script: String
        let requiresArtboard: Bool
        let continuation: CheckedContinuation<Any?, Error>?
    }

    private func load(_ script: String) async throws {
        _ = try await evaluate(script, requiresArtboard: false)
    }

    private func optionsJSON(_ options: ExodeOptions?) -> String {
        ExodeJS.json((options ?? self.options).dictionary)
    }

    private func gateOpen(requiresArtboard: Bool) -> Bool {
        requiresArtboard ? isReady : isHostReady
    }

    private func send(_ script: String, requiresArtboard: Bool = true) {
        guard !isDisposed else { return }
        enqueue(
            PendingCall(script: script, requiresArtboard: requiresArtboard, continuation: nil)
        )
        flush()
    }

    private func evaluate(_ script: String, requiresArtboard: Bool) async throws -> Any? {
        guard !isDisposed else { return nil }
        if gateOpen(requiresArtboard: requiresArtboard), let executor {
            return try await executor.evaluate(script)
        }
        return try await withCheckedThrowingContinuation { continuation in
            enqueue(
                PendingCall(
                    script: script,
                    requiresArtboard: requiresArtboard,
                    continuation: continuation
                )
            )
            flush()
        }
    }

    private func enqueue(_ call: PendingCall) {
        if call.continuation == nil, pending.count >= Self.maxQueuedCalls {
            reportQueueOverflow()
            return
        }
        pending.append(call)
    }

    /// Reports a full queue once, then stays quiet so a long outage cannot spam
    /// the error callback.
    private func reportQueueOverflow() {
        guard !didReportQueueOverflow else { return }
        didReportQueueOverflow = true
        report(
            ExodeUIError(
                message: """
                ExodeUI dropped commands because more than \
                \(Self.maxQueuedCalls) were queued before the engine became \
                ready. Check `lastError` and that an artboard is loading.
                """,
                source: "queue"
            )
        )
    }

    private func flush() {
        guard !isFlushing, !isDisposed else { return }
        isFlushing = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            while let call = self.pending.first, self.gateOpen(requiresArtboard: call.requiresArtboard) {
                self.pending.removeFirst()
                do {
                    let value = try await self.executor?.evaluate(call.script)
                    call.continuation?.resume(returning: value)
                } catch {
                    let wrapped = ExodeUIError(
                        message: String(describing: error),
                        stack: nil,
                        source: "bridge"
                    )
                    self.report(wrapped)
                    call.continuation?.resume(throwing: wrapped)
                }
            }
            self.isFlushing = false
        }
    }

    private func abortPending() {
        let calls = pending
        pending.removeAll()
        for call in calls {
            call.continuation?.resume(returning: nil)
        }
    }

    /// Number of queued bridge calls. Exposed for tests.
    var pendingCallCount: Int { pending.count }
}
