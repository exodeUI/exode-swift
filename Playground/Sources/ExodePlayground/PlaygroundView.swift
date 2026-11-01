import SwiftUI
import ExodeUI
import PlaygroundKit

struct PlaygroundView: View {
    @StateObject private var model = PlaygroundModel()

    var body: some View {
        HSplitView {
            canvasPane
                .frame(minWidth: 560, minHeight: 520)
            controlsPane
                .frame(width: 320)
        }
        .onReceive(NotificationCenter.default.publisher(for: .exodePlaygroundCapture)) { _ in
            model.capture()
        }
    }

    // MARK: Canvas

    private var canvasPane: some View {
        VStack(spacing: 0) {
            ZStack {
                Color(red: 0.06, green: 0.07, blue: 0.10)
                canvas
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(16)

            Divider()
            StatusBar(controller: model.controller)
        }
    }

    @ViewBuilder
    private var canvas: some View {
        switch model.selection.format {
        case .bexode:
            ExodeUICanvas(
                bexodeAsset: model.selection.assetName,
                assetBundle: PlaygroundArtboards.bundle,
                assetSubdirectory: PlaygroundArtboards.subdirectory,
                controller: model.controller,
                fit: model.fit,
                autoPlay: model.autoPlay,
                interactive: model.interactive,
                bootTimeout: 15,
                backgroundColor: Self.canvasBackdrop,
                callbacks: model.callbacks
            )
        case .exode:
            ExodeUICanvas(
                exodeAsset: "\(model.selection.assetName).exode",
                assetBundle: PlaygroundArtboards.bundle,
                assetSubdirectory: PlaygroundArtboards.subdirectory,
                controller: model.controller,
                fit: model.fit,
                autoPlay: model.autoPlay,
                interactive: model.interactive,
                bootTimeout: 15,
                backgroundColor: Self.canvasBackdrop,
                callbacks: model.callbacks
            )
        }
    }

    /// Matches the demo artboard so the letterbox around it stays dark.
    private static let canvasBackdrop = Color(red: 0.04, green: 0.07, blue: 0.13)

    // MARK: Controls

    private var controlsPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                artboardSection
                playbackSection
                layoutSection
                captureSection
                logSection
            }
            .padding(18)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ExodeUI Playground")
                .font(.title2.weight(.semibold))
            Text("Renders \(model.selection.formatDescription) inside a WKWebView using the public Swift API.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var artboardSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Artboard")
            ForEach(PlaygroundArtboards.all) { artboard in
                Button {
                    model.select(artboard)
                } label: {
                    HStack {
                        Image(systemName: artboard.format == .bexode ? "shippingbox" : "curlybraces")
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(artboard.assetName).font(.body)
                            Text(artboard.formatDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if artboard == model.selection {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.tint)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(artboard == model.selection
                            ? Color.accentColor.opacity(0.12)
                            : Color.clear)
                )
            }
        }
    }

    private var playbackSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Playback")

            HStack(spacing: 8) {
                Button {
                    model.togglePlayback()
                } label: {
                    Label(
                        model.isPlaying ? "Pause" : "Play",
                        systemImage: model.isPlaying ? "pause.fill" : "play.fill"
                    )
                    .frame(maxWidth: .infinity)
                }

                Button {
                    model.restart()
                } label: {
                    Label("Restart", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Slider(
                    value: Binding(
                        get: { model.seekTime },
                        set: { model.seek(to: $0) }
                    ),
                    in: 0...8
                )
                HStack {
                    Text(String(format: "seek %.2fs", model.seekTime))
                        .font(.caption.monospacedDigit())
                    Spacer()
                    Text("0–8s")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var layoutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Layout & options")

            Picker(
                "Fit",
                selection: Binding(
                    get: { model.fit },
                    set: {
                        model.fit = $0
                        model.applyOptions()
                    }
                )
            ) {
                ForEach(ExodeFit.allCases, id: \.self) { fit in
                    Text(fit.rawValue).tag(fit)
                }
            }

            Toggle(
                "Auto-play on load",
                isOn: Binding(
                    get: { model.autoPlay },
                    set: {
                        model.autoPlay = $0
                        model.applyOptions()
                    }
                )
            )

            Toggle(
                "Interactive",
                isOn: Binding(
                    get: { model.interactive },
                    set: {
                        model.interactive = $0
                        model.applyOptions()
                    }
                )
            )

            Text("Click the orb to fire the artboard's Click interaction.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var captureSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Snapshot")
            Button {
                model.capture()
            } label: {
                Label(model.isCapturing ? "Capturing…" : "Capture PNG", systemImage: "camera")
                    .frame(maxWidth: .infinity)
            }
            .disabled(model.isCapturing)

            if let url = model.captureURL {
                Text(url.lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Event log")
            if model.log.isEmpty {
                Text("No events yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(model.log.suffix(40)) { entry in
                HStack(alignment: .top, spacing: 6) {
                    Text(entry.time, style: .time)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                    Text(entry.text)
                        .font(.caption)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

/// Identifies the canvas configuration so SwiftUI rebuilds the representable
/// when the artboard or layout changes.
private struct StatusBar: View {
    @ObservedObject var controller: ExodeUICanvasController

    var body: some View {
        HStack(spacing: 16) {
            indicator("host", on: controller.isHostReady)
            indicator("artboard", on: controller.isReady)
            if let id = controller.artboardId {
                Text(id).font(.caption.monospaced())
            }
            if let version = controller.bridgeVersion {
                Text("engine \(version)").font(.caption.monospaced())
            }
            Spacer()
            if let error = controller.lastError {
                Text(error.message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            } else if controller.isLoading {
                Text("loading…").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func indicator(_ title: String, on: Bool) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(on ? Color.green : Color.secondary.opacity(0.4))
                .frame(width: 7, height: 7)
            Text(title).font(.caption)
        }
    }
}
