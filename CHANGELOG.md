## Unreleased

### Added

- `ExodePlatform.isSupported`, so an app can branch before relying on canvas
  callbacks.
- `ExodeUICanvas` renders an "unavailable" view on tvOS, watchOS and visionOS.
- `ExodeUICanvas(bootTimeout:)` and `ExodeUICanvasController.bootTimeout`: the
  canvas now reports a `boot`-sourced `ExodeUIError` when the WebView never
  becomes ready instead of spinning forever. `0` disables the watchdog.
- `ExodeAssets.artboardExtensions` and an `extensions:` lookup parameter, so
  `loadBexodeAsset` prefers `.bexode` and `loadJsonAsset` prefers `.exode`
  instead of guessing from the bundle contents.
- `Playground/`: a separate macOS package with an interactive SwiftUI app
  (`ExodePlayground`) and a headless PNG renderer (`ExodeSmoke`) that also
  serves as a CI smoke test.
- Real-artboard WebKit integration tests (`.exode` and `.bexode` fixtures,
  chunked transfer, snapshot size) and unit tests for document caching, the
  boot watchdog and the bounded command queue.

### Changed

- `ExodeAssets.loadDocument()` composes and caches the multi-megabyte WebView
  document per resource bundle, so several canvases on one screen no longer
  each read and concatenate the engine. `ExodeAssets.clearDocumentCache()`
  resets it.
- Extension-less asset names (`bexodeAsset: "hero"`) now resolve reliably.
  They previously depended on the platform's resource lookup and could fail
  with `assetMissing`.

### Fixed

- `backgroundColor` now paints the WebView page itself, not only the native view
  behind it. A `contain`-fitted artboard no longer shows a white letterbox on
  macOS, and the colour follows live updates.
- The package now compiles on tvOS, watchOS and visionOS. It previously failed
  with "unable to resolve module dependency: 'WebKit'", which made ExodeUI
  unusable as a dependency of a multi-platform app.
- A failed artboard load no longer records the source as loaded, so the next
  view update retries it instead of staying on the error state. A load that
  finishes after the source changed no longer reports against the new source.
- `clear()` no longer marks the canvas as ready, so commands that need an
  artboard stay queued instead of firing at an empty canvas.
- The navigation policy delegate matches `WKNavigationDelegate`'s main-actor
  `decisionHandler`, so it is a real protocol witness and no longer reports the
  Swift 6 "nearly matches" warning.
- The command queue is bounded, so a canvas whose artboard never loads cannot
  grow memory without limit.

## 1.1.1

### Added

- `ExodeUICanvasController.captureImage()` returns the current frame as PNG
  `Data`, matching the Flutter SDK.

### Fixed

- Rebuilt `Sources/ExodeUI/Resources/engine.bundle.js` against the current
  React runtime, so Swift no longer ships an engine revision behind the other
  SDKs.

## 1.1.0

A full rewrite of the Swift runtime so it matches the React, React Native,
Flutter and vanilla JavaScript SDKs.

### Added

- SwiftUI `ExodeUICanvas` for iOS 14+ and macOS 11+, with `.exode` JSON,
  decoded artboard dictionaries, `.bexode` bytes and bundled assets as sources.
- `ExodeUICanvasController` with playback (`play`, `pause`, `seek`, `resize`),
  layout and option updates, state-machine inputs, triggers, component/chart
  updates and external scroll sensors.
- Imperative calls made before the engine boots are queued and replayed in
  order.
- Typed `ExodeCallbacks` for ready, triggers, inputs, components, toggles,
  navigation, charts, logic updates, logs, errors and named callbacks.
- `ObservableObject` state (`isReady`, `isLoading`, `artboardId`,
  `bridgeVersion`, `lastError`) plus custom loading and error views.
- `.bexode` support through 192 KB base64 chunks, decoded by the same bridge
  the Flutter SDK uses.
- Shared engine pipeline: `npm run build:swift` generates the resources from the
  Flutter bridge and React runtime; `npm run check:swift` fails on drift.
- Unit tests plus an opt-in `WKWebView` integration test, and a CI workflow.

### Fixed

- JavaScript arguments were interpolated without escaping, breaking artboards
  with quotes or newlines.
- The WebView was never torn down, leaking its script-message handler.
- The old bridge API (`window.exodeui`) did not exist in the current engine
  bundle, so artboards never loaded.
- Transparent backgrounds, scroll capture and navigation allow-listing were
  undefined.

### Changed

- Requires iOS 14 / macOS 11 and Swift 5.7 (Xcode 14+).
- `fit` and `alignment` are enums (`ExodeFit`, `ExodeAlignment`) instead of
  loose strings.
- The package has no external Swift dependencies.

## 1.0.0

- Initial release.
