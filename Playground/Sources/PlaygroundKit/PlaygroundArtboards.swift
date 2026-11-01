import Foundation
import ExodeUI

/// An artboard the playground can render.
public struct PlaygroundArtboard: Identifiable, Hashable {
    public enum Format: String, Hashable {
        case exode
        case bexode
    }

    public let id: String
    public let title: String
    public let format: Format
    public let url: URL

    public init(id: String, title: String, format: Format, url: URL) {
        self.id = id
        self.title = title
        self.format = format
        self.url = url
    }

    public var assetName: String { url.deletingPathExtension().lastPathComponent }

    public var formatDescription: String {
        switch format {
        case .exode: return ".exode JSON"
        case .bexode: return ".bexode binary"
        }
    }
}

/// Artboards shipped with the playground.
///
/// `demo.exode` / `demo.bexode` come from
/// `packages/flutter/example/assets/` so every SDK renders the same document.
public enum PlaygroundArtboards {
    public static let subdirectory = "Artboards"

    /// Bundle that holds the artboard resources.
    public static var bundle: Bundle { .module }

    public static let all: [PlaygroundArtboard] = {
        ["demo.exode", "demo.bexode"].compactMap { file in
            let url = bundle.url(
                forResource: (file as NSString).deletingPathExtension,
                withExtension: (file as NSString).pathExtension,
                subdirectory: subdirectory
            )
            guard let url else { return nil }
            let format = PlaygroundArtboard.Format(
                rawValue: (file as NSString).pathExtension
            ) ?? .exode
            return PlaygroundArtboard(
                id: file,
                title: file,
                format: format,
                url: url
            )
        }
    }()

    /// The `.bexode` demo, used when no artboard is specified.
    public static var demo: PlaygroundArtboard? {
        all.first { $0.format == .bexode } ?? all.first
    }

    /// Finds an artboard by file name, extension optional.
    public static func named(_ name: String) -> PlaygroundArtboard? {
        let base = (name as NSString).deletingPathExtension.lowercased()
        return all.first { $0.assetName.lowercased() == base }
    }
}
