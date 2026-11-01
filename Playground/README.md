# ExodeUI Swift Playground

A small macOS app plus a headless smoke renderer for the
[ExodeUI](../README.md) Swift package.

The playground is a **separate package** (`packages/swift/Playground`) that
depends on `packages/swift` through a local path, so the published library stays
free of demo code and `swift test` in the library stays fast.

## Requirements

- macOS 13 or newer
- Xcode 15 / Swift 5.9 or newer

## Run the app

```bash
cd packages/swift/Playground
swift run ExodePlayground
```

The window renders the bundled `demo.bexode` through `ExodeUICanvas` and lets
you:

- switch between the `.bexode` binary and the `.exode` JSON version of the
  same artboard,
- pause, resume and seek the timeline,
- change the `fit` (Contain, Cover, Fill, FitWidth, …),
- toggle auto-play and interactivity at runtime with `setOptions`,
- capture the current frame with `ExodeUICanvasController.captureImage()` and
  reveal it in Finder,
- watch the state-machine event log (`hostReady`, `ready`, `trigger`, `log`,
  and errors).

Click the orb in the artboard to fire its `Click` interaction through the
engine.

## Run the smoke renderer

`ExodeSmoke` boots a real `WKWebView`, loads an artboard through the public
`ExodeUICanvas` API, captures a PNG and prints a JSON summary. It exits non-zero
on any failure, so it works as a CI check.

```bash
# Bundled demo artboard
swift run ExodeSmoke --output /tmp/exode.png

# Your own .bexode or .exode, paused at 1.5s
swift run ExodeSmoke \
  --input ~/Downloads/hero.bexode \
  --output /tmp/hero.png \
  --time 1.5 \
  --size 900x600
```

```
{
  "artboardId" : "flutter-demo",
  "bytes" : 72644,
  "engine" : "7.2.20",
  "height" : 420,
  "milliseconds" : 812,
  "ok" : true,
  "output" : "/tmp/exode.png",
  "ready" : "artboard=flutter-demo engine=7.2.20",
  "width" : 640
}
```

Run `swift run ExodeSmoke --help` for every flag.

## Add an artboard

Drop the file into
`Sources/PlaygroundKit/Resources/Artboards/` and add it to the list in
`Sources/PlaygroundKit/PlaygroundArtboards.swift`. Both `.bexode` and `.exode`
are supported; the app passes the file name without an extension, which
exercises the extension-less asset lookup the README documents.

## Layout

| Path | Purpose |
| --- | --- |
| `Sources/PlaygroundKit` | Artboard catalog + bundled demo resources |
| `Sources/ExodePlayground` | SwiftUI app |
| `Sources/ExodeSmoke` | Headless render → PNG CLI |
| `Sources/PlaygroundKit/Resources/Artboards` | `demo.exode` / `demo.bexode` |

The demo assets are copied from `packages/flutter/example/assets/`, which the
Flutter SDK also uses, so every runtime renders the same document.
