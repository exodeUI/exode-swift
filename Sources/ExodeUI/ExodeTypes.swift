import Foundation

/// Which platforms can host the WebView-backed canvas.
///
/// The package still builds on every Apple platform; where WebKit cannot host a
/// `WKWebView`, ``ExodeUICanvas`` renders an explanation instead of an artboard
/// so a multi-platform app can depend on ExodeUI unconditionally.
public enum ExodePlatform {
    /// `true` on iOS and macOS.
    public static var isSupported: Bool {
        #if os(iOS) || os(macOS)
        return true
        #else
        return false
        #endif
    }
}

/// How an artboard is scaled into the available space.
///
/// The raw values match the literals the JavaScript engine expects.
public enum ExodeFit: String, CaseIterable, Sendable {
    case contain = "Contain"
    case cover = "Cover"
    case fill = "Fill"
    case fitWidth = "FitWidth"
    case fitHeight = "FitHeight"
    case none = "None"
    case scaleDown = "ScaleDown"
    case layout = "Layout"
}

/// Where the artboard sits when it does not fill the canvas.
public enum ExodeAlignment: String, CaseIterable, Sendable {
    case topLeft = "TopLeft"
    case topCenter = "TopCenter"
    case topRight = "TopRight"
    case centerLeft = "CenterLeft"
    case center = "Center"
    case centerRight = "CenterRight"
    case bottomLeft = "BottomLeft"
    case bottomCenter = "BottomCenter"
    case bottomRight = "BottomRight"
}

/// Rendering options shared by the Swift API and the JavaScript bridge.
public struct ExodeOptions: Equatable, Sendable {
    /// How the artboard is scaled into the WebView.
    public var fit: ExodeFit
    /// Where the artboard sits when it does not fill the WebView.
    public var alignment: ExodeAlignment
    /// Extra multiplier applied to the fitted layout scale.
    public var layoutScaleFactor: Double
    /// Whether the render loop starts as soon as the artboard loads.
    public var autoPlay: Bool
    /// Whether pointer, keyboard and wheel input reach the artboard.
    public var interactive: Bool
    /// Whether scroll gestures are consumed instead of scrolling the page.
    public var preventScroll: Bool
    /// Named callbacks declared in the artboard's state machine.
    public var callbackNames: [String]

    public init(
        fit: ExodeFit = .contain,
        alignment: ExodeAlignment = .center,
        layoutScaleFactor: Double = 1,
        autoPlay: Bool = true,
        interactive: Bool = true,
        preventScroll: Bool = true,
        callbackNames: [String] = []
    ) {
        self.fit = fit
        self.alignment = alignment
        self.layoutScaleFactor = layoutScaleFactor
        self.autoPlay = autoPlay
        self.interactive = interactive
        self.preventScroll = preventScroll
        self.callbackNames = callbackNames
    }

    /// JSON-compatible representation understood by `ExodeBridge.setOptions`.
    public var dictionary: [String: Any] {
        [
            "fit": fit.rawValue,
            "alignment": alignment.rawValue,
            "layoutScaleFactor": layoutScaleFactor,
            "autoPlay": autoPlay,
            "interactive": interactive,
            "preventScroll": preventScroll,
            "callbackNames": callbackNames,
        ]
    }
}

/// A bridge or runtime failure.
public struct ExodeUIError: Error, Equatable, Sendable {
    /// Human-readable description.
    public let message: String
    /// JavaScript stack when the engine provided one.
    public let stack: String?
    /// Where the failure originated (`boot`, `window`, `load`, `bridge`, ...).
    public let source: String?

    public init(message: String, stack: String? = nil, source: String? = nil) {
        self.message = message
        self.stack = stack
        self.source = source
    }
}

extension ExodeUIError: LocalizedError {
    public var errorDescription: String? { message }
}

/// Callbacks emitted by the artboard.
///
/// Every closure is optional; create the struct with only the events you care
/// about and pass it to ``ExodeUICanvas``.
public struct ExodeCallbacks {
    /// Called once the artboard has loaded and painted its first frame.
    public var onReady: ((ExodeUICanvasController) -> Void)?
    /// Called when an animation trigger fires.
    public var onTrigger: ((_ trigger: String, _ animation: String) -> Void)?
    /// Called whenever a state-machine input changes.
    public var onInputUpdate: ((_ values: [String: Any]) -> Void)?
    /// Called for component changes (dropdowns, sliders, list views, ...).
    public var onComponentChange: ((_ event: [String: Any]) -> Void)?
    /// Called when a toggle or checkbox changes.
    public var onToggle: ((_ name: String, _ checked: Bool) -> Void)?
    /// Called as text is typed into an input component.
    public var onInputChange: ((_ name: String, _ text: String) -> Void)?
    /// Called when an input component gains focus.
    public var onInputFocus: ((_ name: String) -> Void)?
    /// Called when an input component loses focus.
    public var onInputBlur: ((_ name: String) -> Void)?
    /// Called when a button component is pressed.
    public var onButtonClick: ((_ name: String, _ objectId: String) -> Void)?
    /// Called when the artboard requests navigation.
    public var onNavigation: ((_ targetType: String, _ value: String) -> Void)?
    /// Called when a chart point is clicked.
    public var onGraphPointClick: ((_ point: [String: Any]) -> Void)?
    /// Called whenever the state machine logic updates.
    public var onLogicUpdate: ((_ state: [String: Any]) -> Void)?
    /// Called for every message the engine logs.
    public var onLog: ((_ message: String) -> Void)?
    /// Called for JavaScript or bridge failures.
    public var onError: ((_ message: String, _ stack: String?) -> Void)?
    /// Called for named callbacks declared in the artboard's state machine.
    ///
    /// The engine only emits names registered through
    /// ``ExodeUICanvas/callbackNames`` (or ``ExodeOptions/callbackNames``).
    public var onCallback: ((_ name: String, _ arguments: [Any]) -> Void)?

    public init(
        onReady: ((ExodeUICanvasController) -> Void)? = nil,
        onTrigger: ((String, String) -> Void)? = nil,
        onInputUpdate: (([String: Any]) -> Void)? = nil,
        onComponentChange: (([String: Any]) -> Void)? = nil,
        onToggle: ((String, Bool) -> Void)? = nil,
        onInputChange: ((String, String) -> Void)? = nil,
        onInputFocus: ((String) -> Void)? = nil,
        onInputBlur: ((String) -> Void)? = nil,
        onButtonClick: ((String, String) -> Void)? = nil,
        onNavigation: ((String, String) -> Void)? = nil,
        onGraphPointClick: (([String: Any]) -> Void)? = nil,
        onLogicUpdate: (([String: Any]) -> Void)? = nil,
        onLog: ((String) -> Void)? = nil,
        onError: ((String, String?) -> Void)? = nil,
        onCallback: ((String, [Any]) -> Void)? = nil
    ) {
        self.onReady = onReady
        self.onTrigger = onTrigger
        self.onInputUpdate = onInputUpdate
        self.onComponentChange = onComponentChange
        self.onToggle = onToggle
        self.onInputChange = onInputChange
        self.onInputFocus = onInputFocus
        self.onInputBlur = onInputBlur
        self.onButtonClick = onButtonClick
        self.onNavigation = onNavigation
        self.onGraphPointClick = onGraphPointClick
        self.onLogicUpdate = onLogicUpdate
        self.onLog = onLog
        self.onError = onError
        self.onCallback = onCallback
    }
}
