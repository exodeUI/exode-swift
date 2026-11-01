import AppKit
import Foundation
import SwiftUI
import ExodeUI
import PlaygroundKit

/// Headless-ish smoke renderer.
///
/// Boots a real `WKWebView`, loads an artboard through the public
/// `ExodeUICanvas` API, captures the first frame with
/// `ExodeUICanvasController.captureImage()` and writes it to disk. Non-zero exit
/// on any failure, so it can run in CI.
///
/// ```bash
/// swift run ExodeSmoke --output /tmp/exode.png
/// swift run ExodeSmoke --input ~/Downloads/hero.bexode --time 1.5
/// ```
enum SmokeCLI {
    struct Options {
        var input: URL?
        var output: URL
        var width: CGFloat = 800
        var height: CGFloat = 540
        var time: Double? = nil
        var timeout: Double = 25
        var json = false
    }

    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    @MainActor
    static func main() async -> Int32 {
        // AppKit must exist before WebKit is touched.
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let options: Options
        do {
            options = try parse(CommandLine.arguments.dropFirst())
        } catch {
            FileHandle.standardError.write(Data("exode-smoke: \(error)\n\n\(usage)\n".utf8))
            return 2
        }

        do {
            let summary = try await render(options)
            print(summary)
            return 0
        } catch {
            FileHandle.standardError.write(Data("exode-smoke: \(error)\n".utf8))
            return 1
        }
    }

    @MainActor
    private static func render(_ options: Options) async throws -> String {
        let started = Date()
        let controller = ExodeUICanvasController()
        controller.bootTimeout = options.timeout

        var bootError: String?
        var readyDescription: String?

        let callbacks = ExodeCallbacks(
            onReady: { controller in
                readyDescription = "artboard=\(controller.artboardId ?? "nil") engine=\(controller.bridgeVersion ?? "?")"
            },
            onLog: { message in
                if message.lowercased().contains("error") {
                    FileHandle.standardError.write(Data("engine log: \(message)\n".utf8))
                }
            },
            onError: { message, stack in
                bootError = stack.map { "\(message)\n\($0)" } ?? message
            }
        )

        let source = try loadSource(options)
        let canvas = ExodeUICanvas(
            artboardJson: source.json,
            bexodeData: source.data,
            controller: controller,
            fit: .contain,
            autoPlay: options.time == nil,
            interactive: false,
            bootTimeout: options.timeout,
            callbacks: callbacks
        )
        .frame(width: options.width, height: options.height)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: options.width, height: options.height),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = "ExodeUI smoke"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: canvas)
        window.center()
        window.orderFrontRegardless()
        window.displayIfNeeded()

        defer {
            window.orderOut(nil)
            controller.dispose()
        }

        guard await wait(until: { controller.isReady || bootError != nil }, timeout: options.timeout) else {
            throw Failure(description: "timed out after \(options.timeout)s waiting for the artboard (lastError: \(controller.lastError?.message ?? "none"))")
        }
        if let bootError {
            throw Failure(description: bootError)
        }

        if let time = options.time {
            controller.pause()
            controller.seek(time)
        }

        // Give the engine two frames to paint before reading pixels.
        try? await Task.sleep(nanoseconds: 350_000_000)
        if let error = controller.lastError {
            throw Failure(description: error.message)
        }

        guard let png = await controller.captureImage() else {
            throw Failure(description: "captureImage() returned nil (no artboard or zero-sized canvas)")
        }
        try png.write(to: options.output)

        let milliseconds = Int(Date().timeIntervalSince(started) * 1_000)
        let summary: [String: Any] = [
            "ok": true,
            "input": options.input?.path ?? "bundled:\(PlaygroundArtboards.demo?.title ?? "none")",
            "output": options.output.path,
            "bytes": png.count,
            "width": Int(options.width),
            "height": Int(options.height),
            "engine": controller.bridgeVersion ?? "unknown",
            "artboardId": controller.artboardId ?? "",
            "ready": readyDescription ?? "",
            "milliseconds": milliseconds,
        ]
        let data = try JSONSerialization.data(
            withJSONObject: summary,
            options: [.sortedKeys, .prettyPrinted]
        )
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: Input

    private struct Source {
        var json: String?
        var data: Data?
    }

    private static func loadSource(_ options: Options) throws -> Source {
        guard let input = options.input else {
            guard let demo = PlaygroundArtboards.demo else {
                throw Failure(description: "no bundled artboard; pass --input <file>")
            }
            return try read(demo.url)
        }
        return try read(input)
    }

    private static func read(_ url: URL) throws -> Source {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw Failure(description: "no such file: \(url.path)")
        }
        let data = try Data(contentsOf: url)
        switch url.pathExtension.lowercased() {
        case "bexode":
            return Source(json: nil, data: data)
        case "exode", "json", "":
            guard let text = String(data: data, encoding: .utf8) else {
                throw Failure(description: "\(url.lastPathComponent) is not UTF-8 JSON")
            }
            return Source(json: text, data: nil)
        default:
            throw Failure(description: "unsupported extension .\(url.pathExtension); use .exode or .bexode")
        }
    }

    // MARK: Helpers

    @MainActor
    private static func wait(
        until condition: () -> Bool,
        timeout: Double
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return condition()
    }

    private static func parse(_ arguments: some Sequence<String>) throws -> Options {
        var options = Options(
            output: FileManager.default.temporaryDirectory
                .appendingPathComponent("exode-smoke.png")
        )
        var iterator = Array(arguments).makeIterator()

        while let argument = iterator.next() {
            switch argument {
            case "--input", "-i":
                guard let value = iterator.next() else {
                    throw Failure(description: "--input needs a path")
                }
                options.input = URL(fileURLWithPath: value).standardizedFileURL
            case "--output", "-o":
                guard let value = iterator.next() else {
                    throw Failure(description: "--output needs a path")
                }
                options.output = URL(fileURLWithPath: value).standardizedFileURL
            case "--time", "-t":
                guard let value = iterator.next(), let seconds = Double(value) else {
                    throw Failure(description: "--time needs a number")
                }
                options.time = seconds
            case "--timeout":
                guard let value = iterator.next(), let seconds = Double(value) else {
                    throw Failure(description: "--timeout needs a number")
                }
                options.timeout = seconds
            case "--size", "-s":
                guard
                    let value = iterator.next(),
                    let parsed = parseSize(value)
                else {
                    throw Failure(description: "--size needs WIDTHxHEIGHT, e.g. 800x540")
                }
                options.width = parsed.width
                options.height = parsed.height
            case "--help", "-h":
                print(usage)
                exit(0)
            default:
                throw Failure(description: "unknown argument: \(argument)")
            }
        }
        return options
    }

    private static func parseSize(_ value: String) -> (width: CGFloat, height: CGFloat)? {
        let parts = value.lowercased().split(separator: "x")
        guard
            parts.count == 2,
            let width = Double(parts[0]),
            let height = Double(parts[1]),
            width >= 16, height >= 16
        else {
            return nil
        }
        return (CGFloat(width), CGFloat(height))
    }

    private static let usage = """
    USAGE: ExodeSmoke [options]

      -i, --input <path>     .exode JSON or .bexode file (default: bundled demo)
      -o, --output <path>    PNG destination (default: $TMPDIR/exode-smoke.png)
      -s, --size <WxH>       Canvas size in points (default: 800x540)
      -t, --time <seconds>   Pause and seek before capturing
          --timeout <sec>    Boot/load timeout (default: 25)
      -h, --help             Show this help
    """
}

// MARK: - Entry point

let code = await SmokeCLI.main()
exit(code)
