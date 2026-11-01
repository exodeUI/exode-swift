import Foundation
import SwiftUI
import ExodeUI
import PlaygroundKit

/// Observable state for the playground window.
@MainActor
final class PlaygroundModel: ObservableObject {
    struct LogEntry: Identifiable {
        let id = UUID()
        let time = Date()
        let text: String
    }

    @Published var selection: PlaygroundArtboard
    @Published var isPlaying = true
    @Published var autoPlay = true
    @Published var interactive = true
    @Published var fit: ExodeFit = .contain
    @Published var seekTime: Double = 0
    @Published var log: [LogEntry] = []
    @Published var captureURL: URL?
    @Published var isCapturing = false

    let controller = ExodeUICanvasController()

    init(selection: PlaygroundArtboard? = nil) {
        self.selection = selection ?? PlaygroundArtboards.demo
            ?? PlaygroundArtboard(id: "empty", title: "Empty", format: .exode, url: URL(fileURLWithPath: "/dev/null"))
    }

    var callbacks: ExodeCallbacks {
        ExodeCallbacks(
            onReady: { [weak self] controller in
                self?.record("ready id=\(controller.artboardId ?? "nil") bridge=\(controller.bridgeVersion ?? "?")")
                self?.controller.play()
            },
            onTrigger: { [weak self] trigger, animation in
                self?.record("trigger \(trigger) → \(animation)")
            },
            onComponentChange: { [weak self] event in
                self?.record("component \(event)")
            },
            onToggle: { [weak self] name, checked in
                self?.record("toggle \(name)=\(checked)")
            },
            onInputChange: { [weak self] name, text in
                self?.record("input \(name)=\"\(text)\"")
            },
            onButtonClick: { [weak self] name, objectId in
                self?.record("button \(name) (\(objectId))")
            },
            onNavigation: { [weak self] target, value in
                self?.record("navigation \(target)=\(value)")
            },
            onLogicUpdate: { [weak self] state in
                self?.record("logic \(state)")
            },
            onLog: { [weak self] message in
                self?.record("log \(message)")
            },
            onError: { [weak self] message, stack in
                self?.record("error \(message)\(stack.map { "\n\($0)" } ?? "")")
            },
            onCallback: { [weak self] name, args in
                self?.record("callback \(name) \(args)")
            }
        )
    }

    func select(_ artboard: PlaygroundArtboard) {
        selection = artboard
        seekTime = 0
        isPlaying = true
        record("load \(artboard.title)")
    }

    func togglePlayback() {
        isPlaying.toggle()
        if isPlaying {
            controller.play()
        } else {
            controller.pause()
        }
        record(isPlaying ? "play" : "pause")
    }

    func seek(to seconds: Double) {
        seekTime = seconds
        isPlaying = false
        controller.pause()
        controller.seek(seconds)
    }

    func restart() {
        seekTime = 0
        isPlaying = true
        controller.seek(0)
        controller.play()
    }

    func applyOptions() {
        controller.setOptions(
            ExodeOptions(
                fit: fit,
                alignment: .center,
                layoutScaleFactor: 1,
                autoPlay: autoPlay,
                interactive: interactive,
                preventScroll: true,
                callbackNames: []
            )
        )
    }

    func capture() {
        guard !isCapturing else { return }
        isCapturing = true
        Task { [weak self] in
            guard let self else { return }
            let png = await self.controller.captureImage()
            self.isCapturing = false
            guard let png else {
                self.record("capture failed (no frame yet)")
                return
            }
            let name = "ExodeUI-\(self.selection.assetName)-\(Int(Date().timeIntervalSince1970)).png"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            do {
                try png.write(to: url)
                self.captureURL = url
                self.record("captured \(png.count) bytes → \(url.path)")
                #if os(macOS)
                NSWorkspace.shared.activateFileViewerSelecting([url])
                #endif
            } catch {
                self.record("capture write failed: \(error.localizedDescription)")
            }
        }
    }

    func record(_ text: String) {
        log.append(LogEntry(text: text))
        if log.count > 120 {
            log.removeFirst(log.count - 120)
        }
    }
}
