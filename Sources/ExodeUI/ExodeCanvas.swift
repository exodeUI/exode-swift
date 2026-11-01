import SwiftUI

#if os(iOS) || os(macOS)
import WebKit
#endif

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// The WebView-backed SwiftUI canvas that renders `.exode` and `.bexode`
/// artboards with the ExodeUI engine.
///
/// Supply exactly one artboard source:
///
/// ```swift
/// ExodeUICanvas(bexodeAsset: "hero")
///     .frame(height: 320)
/// ```
///
/// ```swift
/// ExodeUICanvas(
///     bexodeData: data,
///     fit: .cover,
///     callbacks: ExodeCallbacks(
///         onReady: { $0.play() },
///         onTrigger: { trigger, animation in
///             print(trigger, animation)
///         }
///     )
/// )
/// ```
public struct ExodeUICanvas: View {
    @StateObject private var controller: ExodeUICanvasController

    private let configuration: ExodeCanvasConfiguration
    private let callbacks: ExodeCallbacks
    private let ownsController: Bool
    private let loadingView: (() -> AnyView)?
    private let errorView: ((ExodeUIError) -> AnyView)?

    /// Creates a canvas.
    ///
    /// - Parameters:
    ///   - artboardJson: `.exode` JSON text.
    ///   - artboard: an already-decoded artboard dictionary.
    ///   - exodeAsset: name of an `.exode` file in `assetBundle`.
    ///   - bexodeData: raw `.bexode` bytes.
    ///   - bexodeAsset: name of a `.bexode` file in `assetBundle`.
    ///   - assetBundle: bundle used to resolve `exodeAsset` / `bexodeAsset`.
    ///   - assetSubdirectory: optional subdirectory inside `assetBundle`.
    ///   - controller: an external controller. Do not swap it after mounting.
    ///   - fit: how the artboard is scaled.
    ///   - alignment: where the artboard sits when it does not fill the view.
    ///   - layoutScaleFactor: extra multiplier applied to the fitted scale.
    ///   - autoPlay: whether the render loop starts immediately.
    ///   - interactive: whether input reaches the artboard.
    ///   - preventScroll: whether scroll gestures are consumed.
    ///   - bootTimeout: seconds to wait for the engine before showing an error.
    ///     Pass `0` to wait forever.
    ///   - backgroundColor: colour painted behind and around the artboard.
    ///     Defaults to `.clear`, which leaves the canvas transparent.
    ///   - callbackNames: names of state-machine callbacks to forward to
    ///     ``ExodeCallbacks/onCallback``. Only registered names are emitted.
    ///   - callbacks: artboard event callbacks.
    ///   - loadingView: optional custom loading view.
    ///   - errorView: optional custom error view.
    public init(
        artboardJson: String? = nil,
        artboard: [String: Any]? = nil,
        exodeAsset: String? = nil,
        bexodeData: Data? = nil,
        bexodeAsset: String? = nil,
        assetBundle: Bundle = .main,
        assetSubdirectory: String? = nil,
        controller: ExodeUICanvasController? = nil,
        fit: ExodeFit = .contain,
        alignment: ExodeAlignment = .center,
        layoutScaleFactor: Double = 1,
        autoPlay: Bool = true,
        interactive: Bool = true,
        preventScroll: Bool = true,
        bootTimeout: TimeInterval = 15,
        backgroundColor: Color = .clear,
        callbackNames: [String] = [],
        callbacks: ExodeCallbacks = ExodeCallbacks(),
        loadingView: (() -> AnyView)? = nil,
        errorView: ((ExodeUIError) -> AnyView)? = nil
    ) {
        let sources = [
            artboardJson.map { ExodeArtboardSource.json($0) },
            artboard.map { ExodeArtboardSource.object($0) },
            exodeAsset.map { ExodeArtboardSource.exodeAsset($0) },
            bexodeData.map { ExodeArtboardSource.bexodeData($0) },
            bexodeAsset.map { ExodeArtboardSource.bexodeAsset($0) },
        ].compactMap { $0 }

        assert(
            sources.count <= 1,
            "ExodeUICanvas accepts at most one artboard source "
                + "(artboardJson, artboard, exodeAsset, bexodeData or bexodeAsset)."
        )

        let resolved = controller ?? ExodeUICanvasController()
        _controller = StateObject(wrappedValue: resolved)
        self.ownsController = controller == nil
        self.configuration = ExodeCanvasConfiguration(
            source: sources.first,
            options: ExodeOptions(
                fit: fit,
                alignment: alignment,
                layoutScaleFactor: layoutScaleFactor,
                autoPlay: autoPlay,
                interactive: interactive,
                preventScroll: preventScroll,
                callbackNames: callbackNames
            ),
            bootTimeout: bootTimeout,
            backgroundColor: backgroundColor,
            assetBundle: assetBundle,
            assetSubdirectory: assetSubdirectory
        )
        self.callbacks = callbacks
        self.loadingView = loadingView
        self.errorView = errorView
    }

    public var body: some View {
        #if os(iOS) || os(macOS)
        canvas
        #else
        ExodeUnsupportedPlatformView()
        #endif
    }

    #if os(iOS) || os(macOS)
    private var canvas: some View {
        ZStack {
            ExodeWebViewRepresentable(
                controller: controller,
                configuration: configuration,
                callbacks: callbacks,
                ownsController: ownsController
            )

            if controller.isLoading, controller.lastError == nil {
                if let loadingView {
                    loadingView()
                } else {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .padding(20)
                }
            }

            if let error = controller.lastError, !controller.isReady {
                if let errorView {
                    errorView(error)
                } else {
                    ExodeDefaultErrorView(error: error)
                }
            }
        }
    }
    #endif
}

// MARK: - Configuration

struct ExodeCanvasConfiguration {
    let source: ExodeArtboardSource?
    let options: ExodeOptions
    let bootTimeout: TimeInterval
    let backgroundColor: Color
    let assetBundle: Bundle
    let assetSubdirectory: String?
}

enum ExodeArtboardSource {
    case json(String)
    case object([String: Any])
    case exodeAsset(String)
    case bexodeData(Data)
    case bexodeAsset(String)

    var signature: String {
        switch self {
        case .json(let json):
            return "json:\(json.count):\(json.hashValue)"
        case .object(let artboard):
            // `ExodeJS.json` falls back to `null` for non-JSON values; keep the
            // description in that case so two different artboards do not share
            // a signature and skip a reload.
            let encoded = ExodeJS.json(artboard)
            let fingerprint = encoded == "null" ? String(describing: artboard) : encoded
            return "object:\(fingerprint.hashValue)"
        case .exodeAsset(let name):
            return "exode-asset:\(name)"
        case .bexodeData(let data):
            return "bexode-data:\(data.count):\(data.hashValue)"
        case .bexodeAsset(let name):
            return "bexode-asset:\(name)"
        }
    }
}

// MARK: - Platform representable

#if os(iOS)
struct ExodeWebViewRepresentable: UIViewRepresentable {
    let controller: ExodeUICanvasController
    let configuration: ExodeCanvasConfiguration
    let callbacks: ExodeCallbacks
    let ownsController: Bool

    func makeCoordinator() -> ExodeCanvasCoordinator {
        ExodeCanvasCoordinator(
            controller: controller,
            configuration: configuration,
            callbacks: callbacks,
            ownsController: ownsController
        )
    }

    func makeUIView(context: Context) -> WKWebView {
        context.coordinator.makeWebView()
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.update(configuration: configuration, callbacks: callbacks)
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: ExodeCanvasCoordinator) {
        coordinator.dismantle()
    }
}
#elseif os(macOS)
struct ExodeWebViewRepresentable: NSViewRepresentable {
    let controller: ExodeUICanvasController
    let configuration: ExodeCanvasConfiguration
    let callbacks: ExodeCallbacks
    let ownsController: Bool

    func makeCoordinator() -> ExodeCanvasCoordinator {
        ExodeCanvasCoordinator(
            controller: controller,
            configuration: configuration,
            callbacks: callbacks,
            ownsController: ownsController
        )
    }

    func makeNSView(context: Context) -> WKWebView {
        context.coordinator.makeWebView()
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.update(configuration: configuration, callbacks: callbacks)
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: ExodeCanvasCoordinator) {
        coordinator.dismantle()
    }
}
#endif

// MARK: - Coordinator

#if os(iOS) || os(macOS)
@MainActor
final class ExodeCanvasCoordinator: NSObject {
    private let controller: ExodeUICanvasController
    private let ownsController: Bool
    private let executor = ExodeWebViewExecutor()
    private var messageHandler: ExodeMessageHandler?
    private var configuration: ExodeCanvasConfiguration
    private var callbacks: ExodeCallbacks
    private weak var webView: WKWebView?
    private var isHostReady = false
    private var loadedSignature: String?
    private var appliedPageBackgroundCSS: String?

    init(
        controller: ExodeUICanvasController,
        configuration: ExodeCanvasConfiguration,
        callbacks: ExodeCallbacks,
        ownsController: Bool
    ) {
        self.controller = controller
        self.configuration = configuration
        self.callbacks = callbacks
        self.ownsController = ownsController
        super.init()

        controller.configure(options: configuration.options)
        controller.bootTimeout = configuration.bootTimeout
        controller.onCommandError = { [weak self] error in
            self?.callbacks.onError?(error.message, error.stack)
        }
    }

    func makeWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        #if os(iOS)
        configuration.dataDetectorTypes = []
        #endif

        let handler = ExodeMessageHandler { [weak self] raw in
            Task { @MainActor in self?.handle(rawMessage: raw) }
        }
        messageHandler = handler
        configuration.userContentController.add(handler, name: ExodeMessageHandler.name)

        // The page ships with a transparent body. Paint the requested colour
        // from inside the document so the letterbox around a `contain`-fitted
        // artboard is not the WebView's default white (macOS ignores
        // `underPageBackgroundColor` for `loadHTMLString` documents).
        if let backgroundScript = pageBackgroundScript() {
            configuration.userContentController.addUserScript(
                WKUserScript(
                    source: backgroundScript,
                    injectionTime: .atDocumentEnd,
                    forMainFrameOnly: true
                )
            )
            // Applied by the user script as soon as the document finishes
            // loading, so `update` does not need to repeat it.
            appliedPageBackgroundCSS = pageBackgroundCSS()
        }

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        self.webView = webView
        executor.webView = webView
        controller.attach(executor: executor)
        controller.markLoading()
        controller.startBootWatchdog()

        #if os(iOS)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isOpaque = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.bounces = false
        webView.allowsBackForwardNavigationGestures = false
        #elseif os(macOS)
        if #available(macOS 12.0, *) {
            webView.underPageBackgroundColor = .clear
        }
        webView.allowsBackForwardNavigationGestures = false
        #endif

        #if DEBUG
        if #available(iOS 16.4, macOS 13.3, *) {
            webView.isInspectable = true
        }
        #endif

        applyAppearance()
        loadDocument(in: webView)
        return webView
    }

    func update(configuration: ExodeCanvasConfiguration, callbacks: ExodeCallbacks) {
        self.callbacks = callbacks
        let previous = self.configuration
        self.configuration = configuration

        applyAppearance()
        updateScrollBehavior()

        if previous.options != configuration.options {
            controller.configure(options: configuration.options)
            if isHostReady {
                controller.setOptions(configuration.options)
            }
        }

        if previous.source?.signature != configuration.source?.signature {
            loadedSignature = nil
            if isHostReady {
                if configuration.source == nil {
                    controller.clear()
                } else {
                    loadSource(force: true)
                }
            }
        }
    }

    func dismantle() {
        controller.cancelBootWatchdog()
        webView?.configuration.userContentController
            .removeScriptMessageHandler(forName: ExodeMessageHandler.name)
        webView?.navigationDelegate = nil
        executor.webView = nil
        if ownsController {
            controller.dispose()
        } else {
            controller.detach()
        }
        webView = nil
        messageHandler = nil
    }

    // MARK: Document

    private func loadDocument(in webView: WKWebView) {
        do {
            let document = try ExodeAssets.loadDocument()
            webView.loadHTMLString(document, baseURL: URL(string: "https://localhost/exode/"))
        } catch {
            let failure = ExodeUIError(
                message: error.localizedDescription,
                source: "load"
            )
            controller.report(failure)
        }
    }

    private func loadSource(force: Bool = false) {
        guard isHostReady, let source = configuration.source else { return }
        if !force, source.signature == loadedSignature { return }
        loadedSignature = source.signature
        controller.markLoading()

        let options = configuration.options
        let bundle = configuration.assetBundle
        let subdirectory = configuration.assetSubdirectory
        let signature = source.signature

        Task { @MainActor in
            do {
                switch source {
                case .json(let json):
                    try await controller.loadJson(json, options: options)
                case .object(let artboard):
                    try await controller.loadArtboard(artboard, options: options)
                case .exodeAsset(let name):
                    try await controller.loadJsonAsset(
                        name,
                        bundle: bundle,
                        subdirectory: subdirectory,
                        options: options
                    )
                case .bexodeData(let data):
                    try await controller.loadBexode(data, options: options)
                case .bexodeAsset(let name):
                    try await controller.loadBexodeAsset(
                        name,
                        bundle: bundle,
                        subdirectory: subdirectory,
                        options: options
                    )
                }
            } catch {
                // A newer source may have replaced this load while it was in
                // flight; only the current source may report or retry.
                guard signature == self.configuration.source?.signature else { return }
                // Let the next update retry the same source instead of treating
                // a failed load as loaded.
                self.loadedSignature = nil
                let failure = ExodeUIError(
                    message: "Unable to load the ExodeUI artboard: \(error.localizedDescription)",
                    source: "load"
                )
                controller.report(failure)
            }
        }
    }

    private func applyAppearance() {
        #if os(iOS)
        // The page paints `backgroundColor` itself; keeping the native layers
        // clear avoids compositing a translucent colour twice.
        webView?.backgroundColor = .clear
        webView?.scrollView.backgroundColor = .clear
        #elseif os(macOS)
        if #available(macOS 12.0, *) {
            webView?.underPageBackgroundColor = .clear
        }
        #endif
        applyPageBackground()
    }

    /// CSS colour for `configuration.backgroundColor`, or `nil` when the colour
    /// is fully transparent (so the page keeps its transparent default).
    private func pageBackgroundCSS() -> String? {
        ExodeCSS.rgba(configuration.backgroundColor)
    }

    private func pageBackgroundScript() -> String? {
        guard let css = pageBackgroundCSS() else { return nil }
        return Self.pageBackgroundScript(css: css)
    }

    /// Re-applies the page background after the document loaded or the colour
    /// changed, because the injected user script only runs once per load.
    private func applyPageBackground(force: Bool = false) {
        guard isHostReady, let webView else { return }
        let css = pageBackgroundCSS()
        if !force, css == appliedPageBackgroundCSS { return }
        appliedPageBackgroundCSS = css
        let script = css.map(Self.pageBackgroundScript(css:)) ?? Self.pageBackgroundClearScript
        webView.evaluateJavaScript(script) { _, _ in
            // The document may still be navigating; the `hostReady` handler
            // applies the colour again once the engine is available.
        }
    }

    /// Creates or updates the style element that paints the page background.
    /// `css` is generated from numeric colour components, never user text.
    static func pageBackgroundScript(css: String) -> String {
        """
        (function() {
          var id = 'exodeui-background';
          var style = document.getElementById(id);
          if (!style) {
            style = document.createElement('style');
            style.id = id;
            (document.head || document.documentElement).appendChild(style);
          }
          style.textContent = 'html,body{background:\(css) !important;}';
        })();
        """
    }

    static let pageBackgroundClearScript = """
    (function() {
      var style = document.getElementById('exodeui-background');
      if (style) { style.parentNode.removeChild(style); }
    })();
    """

    private func updateScrollBehavior() {
        #if os(iOS)
        webView?.scrollView.isScrollEnabled = !configuration.options.preventScroll
        webView?.scrollView.bounces = !configuration.options.preventScroll
        webView?.allowsLinkPreview = false
        #endif
    }

    // MARK: Events

    private func handle(rawMessage: String) {
        guard let event = ExodeEvent.parse(rawMessage) else { return }

        switch event.type {
        case "hostReady":
            isHostReady = true
            controller.markHostReady(bridgeVersion: event.string("bridgeVersion"))
            applyPageBackground(force: true)
            if configuration.source == nil {
                controller.clear()
                callbacks.onReady?(controller)
            } else {
                loadSource(force: true)
            }

        case "ready":
            controller.markReady(artboardId: event.string("id"))
            callbacks.onReady?(controller)

        case "trigger":
            callbacks.onTrigger?(
                event.string("name") ?? "",
                event.string("animation") ?? ""
            )

        case "inputUpdate":
            if let id = event.string("id") {
                callbacks.onInputUpdate?([id: event.payload["value"] ?? NSNull()])
            }

        case "componentChange":
            callbacks.onComponentChange?(event.map("event") ?? [:])

        case "toggle":
            callbacks.onToggle?(
                event.string("name") ?? "",
                event.bool("checked") ?? false
            )

        case "inputChange":
            callbacks.onInputChange?(
                event.string("name") ?? "",
                event.string("text") ?? ""
            )

        case "inputFocus":
            callbacks.onInputFocus?(event.string("name") ?? "")

        case "inputBlur":
            callbacks.onInputBlur?(event.string("name") ?? "")

        case "buttonClick":
            callbacks.onButtonClick?(
                event.string("name") ?? "",
                event.string("objectId") ?? ""
            )

        case "navigation":
            callbacks.onNavigation?(
                event.string("targetType") ?? "",
                event.string("value") ?? ""
            )

        case "graphPointClick":
            callbacks.onGraphPointClick?(event.map("point") ?? event.payload)

        case "logicUpdate":
            callbacks.onLogicUpdate?(event.map("state") ?? [:])

        case "log":
            callbacks.onLog?(event.string("message") ?? "")

        case "callback":
            if let name = event.string("name") {
                callbacks.onCallback?(name, event.list("args") ?? [])
            }

        case "error":
            let error = ExodeUIError(
                message: event.string("message") ?? "Unknown JavaScript error",
                stack: event.string("stack"),
                source: event.string("source")
            )
            controller.report(error)

        default:
            break
        }
    }
}

// MARK: - Navigation

extension ExodeCanvasCoordinator: WKNavigationDelegate {
    // `decisionHandler` is main-actor isolated in WebKit's headers; matching it
    // keeps this a real protocol witness instead of a "nearly matches" method.
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        decisionHandler(ExodeCanvasCoordinator.isAllowed(url: url) ? .allow : .cancel)
    }

    nonisolated static func isAllowed(url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return true }
        switch scheme {
        case "about", "data", "blob":
            return true
        case "https":
            return url.host == "localhost"
        default:
            return false
        }
    }
}

// MARK: - JavaScript plumbing

/// Converts SwiftUI colours into the CSS values injected into the WebView page.
enum ExodeCSS {
    /// `rgba(...)` for an sRGB colour, or `nil` when the colour is fully
    /// transparent (the page then keeps its transparent default).
    static func rgba(_ color: Color) -> String? {
        guard let components = sRGBComponents(color), components.alpha > 0 else {
            return nil
        }
        let red = channel(components.red)
        let green = channel(components.green)
        let blue = channel(components.blue)
        let alpha = String(format: "%.3f", Double(min(max(components.alpha, 0), 1)))
        return "rgba(\(red), \(green), \(blue), \(alpha))"
    }

    private static func channel(_ value: CGFloat) -> Int {
        Int((min(max(value, 0), 1) * 255).rounded())
    }

    #if os(iOS)
    private static func sRGBComponents(
        _ color: Color
    ) -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat)? {
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard
            let converted = UIColor(color).cgColor.converted(
                to: space,
                intent: .defaultIntent,
                options: nil
            ),
            let components = converted.components,
            components.count >= 4
        else {
            return nil
        }
        return (components[0], components[1], components[2], components[3])
    }
    #elseif os(macOS)
    private static func sRGBComponents(
        _ color: Color
    ) -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat)? {
        guard let converted = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        return (
            converted.redComponent,
            converted.greenComponent,
            converted.blueComponent,
            converted.alphaComponent
        )
    }
    #endif
}

@MainActor
final class ExodeWebViewExecutor: ExodeJavaScriptEvaluating {
    weak var webView: WKWebView?

    func evaluate(_ script: String) async throws -> Any? {
        guard let webView else {
            throw ExodeUIError(message: "The ExodeUI WebView is not attached.", source: "bridge")
        }
        return try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { result, error in
                if let error {
                    continuation.resume(
                        throwing: ExodeUIError(
                            message: error.localizedDescription,
                            source: "bridge"
                        )
                    )
                } else {
                    continuation.resume(returning: result)
                }
            }
        }
    }
}

final class ExodeMessageHandler: NSObject, WKScriptMessageHandler {
    static let name = "exodeui"

    private let onMessage: @Sendable (String) -> Void

    init(onMessage: @escaping @Sendable (String) -> Void) {
        self.onMessage = onMessage
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == Self.name else { return }
        guard let raw = Self.rawString(from: message.body) else { return }
        onMessage(raw)
    }

    private static func rawString(from body: Any) -> String? {
        if let string = body as? String { return string }
        guard
            JSONSerialization.isValidJSONObject(body),
            let data = try? JSONSerialization.data(withJSONObject: body),
            let string = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return string
    }
}

#endif // os(iOS) || os(macOS)

// MARK: - Default error view

struct ExodeDefaultErrorView: View {
    let error: ExodeUIError

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 24, weight: .medium))
            Text("ExodeUI could not start")
                .font(.headline)
            Text(error.message)
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.06))
    }
}

// MARK: - Unsupported platforms

/// Shown on platforms without `WKWebView` (tvOS, watchOS, visionOS) so the
/// package compiles and links everywhere without rendering a blank rectangle.
struct ExodeUnsupportedPlatformView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 24, weight: .medium))
            Text("ExodeUI is unavailable on this platform")
                .font(.headline)
            Text("Artboards render in a WKWebView, which only iOS and macOS provide. Use the React, Flutter, Angular, Vue, Svelte, Solid or vanilla JavaScript SDK here.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.06))
    }
}
