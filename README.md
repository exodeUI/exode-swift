# ExodeUI for Swift

The official Swift runtime for the **ExodeUI Animation Engine**. It renders
`.exode` and `.bexode` artboards — vector animation, physics, state machines,
charts and interactive components — inside a `WKWebView`, with a native SwiftUI
API on iOS and macOS.

The package ships the same engine as the
[React](https://www.npmjs.com/package/exodeui), React Native, vanilla JavaScript
and Flutter SDKs. The bundle in `Sources/ExodeUI/Resources/engine.bundle.js` is
generated from `packages/flutter/bridge` (which itself is built from
`packages/react/src`), so animation, layout and `.bexode` decoding behave
identically across platforms.

## Platform support

| Platform | Renders artboards | Backend |
| --- | --- | --- |
| iOS 14+ | ✅ | `WKWebView` |
| macOS 11+ | ✅ | `WKWebView` |
| tvOS / watchOS / visionOS | ❌ | Use the React, Flutter or vanilla JavaScript SDK |

The package still builds and links on every Apple platform, so a multi-platform
app can depend on ExodeUI unconditionally: `ExodeUICanvas` renders an
"unavailable" message where WebKit cannot host a canvas, and
`ExodePlatform.isSupported` reports `false`.

## Installation

### In Xcode

1. Open your project in Xcode.
2. Go to **File → Add Package Dependencies...**
3. Paste the repository URL:
   ```
   https://github.com/exodeUI/exode-swift.git
   ```
4. Choose **Up to Next Major Version** from `7.6.0` (or your preferred version/branch).
5. Click **Add Package** and link `ExodeUI` to your target.

### In `Package.swift`

Add ExodeUI to your package's `dependencies`:

```swift
dependencies: [
    .package(url: "https://github.com/exodeUI/exode-swift.git", from: "7.6.0"),
]
```

Then add `ExodeUI` to your target:

```swift
.target(
    name: "MyApp",
    dependencies: [
        .product(name: "ExodeUI", package: "exode-swift"),
    ]
)
```

The engine bundle and `index.html` are pre-compiled and committed into the package resources, so building does not require Node.js or any external tooling.

## Quick start

```swift
import SwiftUI
import ExodeUI

struct HeroView: View {
    var body: some View {
        ExodeUICanvas(bexodeAsset: "hero")
            .frame(height: 320)
    }
}
```

`.bexode` is the recommended format: one binary file, no parsing on the Swift
side. Add it to your app target's resources. Asset names work with or without
an extension: `bexodeAsset: "hero"` finds `hero.bexode`, and
`exodeAsset: "hero"` finds `hero.exode`. If the file lives in a subdirectory,
pass `assetSubdirectory:`.

From JSON or in-memory data:

```swift
ExodeUICanvas(artboardJson: jsonString)
ExodeUICanvas(artboard: artboardDictionary)
ExodeUICanvas(bexodeData: data)
ExodeUICanvas(exodeAsset: "hero.exode")
```

Supply exactly one source.

## Controller

`ExodeUICanvasController` is the imperative handle for playback, state-machine
inputs and component updates. Obtain one from `onReady`, or create your own and
pass it in:

```swift
@State private var controller = ExodeUICanvasController()

var body: some View {
    ExodeUICanvas(
        bexodeAsset: "hero",
        controller: controller,
        callbacks: ExodeCallbacks(
            onReady: { controller in
                controller.play()
            }
        )
    )
}
```

Commands sent before the engine boots (or before an artboard is ready) are
queued and replayed in order. The queue is bounded (1,024 pending commands);
`lastError` reports an overflow if an artboard never becomes ready.

### Boot timeout

If the WebView never posts `hostReady` — missing package resources, a crashed
web content process — the canvas would otherwise spin forever. `bootTimeout`
(default `15` seconds) reports an `ExodeUIError` with `source == "boot"` instead:

```swift
ExodeUICanvas(bexodeAsset: "hero", bootTimeout: 8)
```

Pass `0` to disable the watchdog.

### Playback and layout

```swift
controller.play()
controller.pause()
controller.seek(1.5)
controller.resize()

controller.setLayout(fit: .cover, alignment: .center)
controller.setOptions(
    ExodeOptions(fit: .contain, autoPlay: false, interactive: true)
)
```

### State-machine inputs

```swift
controller.setInputBool("isDark", true)
controller.setInputNumber("volume", 0.8)
controller.setInputText("name", "Ada")
controller.setInputStringArray("tags", ["a", "b"])
controller.setInputNumberArray("series", [1, 2, 3])
controller.setInput("payload", ["nested": true])

let value = await controller.getInput("volume")
controller.fireTrigger("pulse")
```

### Components and charts

```swift
controller.updateObjectOptions("list-1", ["selectedIndex": 2])
controller.updateGraphData("revenue", [12, 18, 24], categories: ["Q1", "Q2", "Q3"])
controller.updateBarChartData("bars", [["data": [1, 2, 3]]])
controller.updatePieChartData("pie", [["label": "A", "value": 60]])
controller.setDropdownOptions("country", ["US", "GB", "DE"])
```

### External scroll sensors

```swift
controller.handleScroll(x: offset.x, y: offset.y)
controller.setViewportScroll(x: 0, y: 240)
```

### Snapshots

```swift
if let png = await controller.captureImage() {
    // Share, persist, or hand to ImageRenderer / UIImage.
}
```

`captureImage()` returns the current frame as PNG `Data`, or `nil` when no
artboard is ready or the canvas has no size yet.

## Callbacks

Pass an `ExodeCallbacks` value; every closure is optional.

| Callback | Signature | Fires when |
| --- | --- | --- |
| `onReady` | `(ExodeUICanvasController) -> Void` | The first frame is painted |
| `onTrigger` | `(String, String) -> Void` | An animation trigger fires |
| `onInputUpdate` | `([String: Any]) -> Void` | A state-machine input changes |
| `onComponentChange` | `([String: Any]) -> Void` | A component changes |
| `onToggle` | `(String, Bool) -> Void` | A toggle/checkbox changes |
| `onInputChange` | `(String, String) -> Void` | Text is typed into an input |
| `onInputFocus` / `onInputBlur` | `(String) -> Void` | An input gains/loses focus |
| `onButtonClick` | `(String, String) -> Void` | A button component is pressed |
| `onNavigation` | `(String, String) -> Void` | The artboard requests navigation |
| `onGraphPointClick` | `([String: Any]) -> Void` | A chart point is clicked |
| `onLogicUpdate` | `([String: Any]) -> Void` | The state machine updates |
| `onLog` | `(String) -> Void` | The engine logs a message |
| `onError` | `(String, String?) -> Void` | A bridge or runtime error occurs |
| `onCallback` | `(String, [Any]) -> Void` | A registered named callback fires |

`ExodeUICanvasController` also publishes `isHostReady`, `isReady`, `isLoading`,
`artboardId`, `bridgeVersion` and `lastError`, so you can drive your own
overlays.

## Loading artboards from code

```swift
try await controller.loadBexodeAsset("hero")
try await controller.loadJsonAsset("hero.exode")
try await controller.loadJson(jsonString)
try await controller.loadBexode(data)
controller.clear()
```

`.bexode` bytes are transferred in 192 KB base64 chunks, which keeps
`evaluateJavaScript` responsive on large artboards.

## Platform behaviour

- **Canvas background** — `backgroundColor` is painted behind the artboard and
  inside the WebView page, so the letterbox around a `contain`-fitted artboard
  matches your app instead of showing WebKit's white. It defaults to `.clear`.
- **Transparent canvas** — with the default `.clear` background the canvas is
  transparent. On macOS 11, WebKit cannot make the page transparent; pin the
  canvas to an opaque colour or raise the deployment target to macOS 12.
- **Scrolling** — `preventScroll: true` (the default) disables the WebView's
  scroll view so the artboard consumes gestures.
- **Navigation** — only `about:`, `data:`, `blob:` and `https://localhost/`
  URLs are allowed. External links are cancelled; listen to `onNavigation` to
  handle them yourself.
- **Inspection** — in `DEBUG` builds the WebView is inspectable on iOS 16.4+ /
  macOS 13.3+.
- **Lifecycle** — when the view is dismantled the coordinator removes the
  script-message handler. A controller created by the canvas is disposed
  (`ExodeBridge.destroy()` + queued calls drained); an externally supplied
  controller is only detached, so you decide when to call `dispose()`.

## Keeping the engine in sync

The JavaScript resources are generated from the Flutter bridge, which is built
from the React runtime:

```bash
npm run build:swift    # regenerate Resources/
npm run check:swift    # fail if Resources/ is stale (CI)
```

`check:swift` runs in CI on every change to the React runtime, the Flutter
bridge or the Swift package.

## Testing

```bash
cd packages/swift
swift build
swift test
```

The unit tests cover JavaScript encoding, event parsing, resource composition,
asset lookup, `.bexode` chunking, controller queueing, the boot watchdog, the
navigation allow-list and platform support. Swift Package Manager only builds
the host platform, so CI also compiles the iOS and tvOS slices:

```bash
xcodebuild -scheme ExodeUI -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

A real `WKWebView` integration test is opt-in because WebKit needs an
application run loop. It loads the bundled `.exode` and `.bexode` fixtures,
drains the chunked transfer, renders a frame and checks the PNG:

```bash
EXODE_RUN_WEBVIEW_TESTS=1 swift test --filter ExodeWebViewIntegrationTests
```

## Playground

`Playground/` is a separate macOS package with an interactive SwiftUI app and a
headless renderer for trying the SDK without wiring it into an app first:

```bash
cd packages/swift/Playground
swift run ExodePlayground            # interactive window
swift run ExodeSmoke --output /tmp/exode.png   # render a PNG from the CLI
```

See [Playground/README.md](Playground/README.md) for every flag.

## Troubleshooting

**"The ExodeUI WebView resources are missing"** — the package resources were not
copied. Clean the build folder and rebuild; if you vendored the sources by hand,
make sure `Sources/ExodeUI/Resources/` is included.

**The canvas spins forever** — `bootTimeout` should have reported an error with
`source == "boot"`. If it did not, `onError` is not wired up or the timeout is
`0`.

**The artboard is blank** — check `controller.lastError`, or set `onError` and
`onLog`. A blank canvas with no error usually means the artboard has no visible
objects at `t = 0` and `autoPlay` is `false`.

**Input does not reach the artboard** — make sure `interactive` is `true` and
that a native gesture recognizer in your app is not swallowing touches.

## License

MIT. See [LICENSE](LICENSE).
