import Foundation

/// Errors raised while preparing the WebView document or reading assets.
public enum ExodeAssetError: Error, LocalizedError, Equatable {
    case resourcesMissing
    case malformedDocument(String)
    case assetMissing(String)

    public var errorDescription: String? {
        switch self {
        case .resourcesMissing:
            return """
            The ExodeUI WebView resources are missing from the package bundle. \
            Reinstall the package or run `npm run build:swift` in the repository.
            """
        case .malformedDocument(let detail):
            return "The bundled index.html is invalid: \(detail)"
        case .assetMissing(let name):
            return "Unable to find the ExodeUI asset \"\(name)\" in the application bundle."
        }
    }
}

/// Resource loading and HTML composition shared by the controller and the view.
public enum ExodeAssets {
    /// Marker replaced by the inlined engine bundle.
    public static let scriptMarker = "<script src=\"engine.bundle.js\"></script>"

    /// Bytes transferred per `pushBexodeChunk` call.
    ///
    /// A 192 KB slice becomes a ~256 KB base64 string, comfortably below the
    /// payload sizes where `evaluateJavaScript` starts to stall.
    public static let binaryChunkBytes = 192 * 1024

    /// Inlines `bundle` into `html`, replacing the engine `<script>` marker.
    ///
    /// `</script` is escaped so a string inside the bundle cannot close the
    /// inline tag early. The escape is a no-op for JavaScript.
    public static func composeHTML(html: String, bundle: String) throws -> String {
        guard html.contains(scriptMarker) else {
            throw ExodeAssetError.malformedDocument(
                "missing the \"\(scriptMarker)\" marker"
            )
        }
        let safeBundle = bundle.replacingOccurrences(of: "</script", with: "<\\/script")
        return html.replacingOccurrences(
            of: scriptMarker,
            with: "<script>\n\(safeBundle)\n</script>"
        )
    }

    /// Reads `index.html` and `engine.bundle.js` from the package bundle.
    ///
    /// The composed document is cached per bundle because the inlined engine is
    /// a multi-megabyte string: composing it once keeps several canvases on a
    /// screen from each paying the read + concatenate cost.
    ///
    /// - Parameter bundle: overrides the package resource bundle (tests only).
    public static func loadDocument(bundle: Bundle? = nil) throws -> String {
        let resolved = bundle ?? .module
        let key = resolved.bundleURL.standardizedFileURL.path

        if let cached = documentCache.value(for: key) {
            return cached
        }

        let resources = try resourceBundle(resolved)
        guard
            let html = try? String(contentsOf: resources.html, encoding: .utf8),
            let script = try? String(contentsOf: resources.bundle, encoding: .utf8)
        else {
            throw ExodeAssetError.resourcesMissing
        }

        let document = try composeHTML(html: html, bundle: script)
        documentCache.store(document, for: key)
        return document
    }

    /// Drops the composed documents held in memory.
    ///
    /// Call this after updating the engine resources on disk in a long-running
    /// process. Normal applications never need it.
    public static func clearDocumentCache() {
        documentCache.removeAll()
    }

    /// Number of composed documents currently cached. Exposed for tests.
    static var cachedDocumentCount: Int { documentCache.count }

    /// Thread-safe store for composed documents, keyed by resource bundle path.
    final class ExodeDocumentCache: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [String: String] = [:]

        func value(for key: String) -> String? {
            lock.lock()
            defer { lock.unlock() }
            return storage[key]
        }

        func store(_ value: String, for key: String) {
            lock.lock()
            defer { lock.unlock() }
            storage[key] = value
        }

        func removeAll() {
            lock.lock()
            defer { lock.unlock() }
            storage.removeAll()
        }

        var count: Int {
            lock.lock()
            defer { lock.unlock() }
            return storage.count
        }
    }

    static let documentCache = ExodeDocumentCache()

    /// Returns the raw bytes of an asset in the host application bundle.
    ///
    /// When `name` omits an extension, `extensions` controls the lookup order.
    public static func assetData(
        named name: String,
        bundle: Bundle = .main,
        subdirectory: String? = nil,
        extensions: [String] = artboardExtensions
    ) throws -> Data {
        guard
            let url = assetURL(
                named: name,
                bundle: bundle,
                subdirectory: subdirectory,
                extensions: extensions
            )
        else {
            throw ExodeAssetError.assetMissing(name)
        }
        return try Data(contentsOf: url)
    }

    /// Returns an asset as UTF-8 text.
    public static func assetText(
        named name: String,
        bundle: Bundle = .main,
        subdirectory: String? = nil,
        extensions: [String] = artboardExtensions
    ) throws -> String {
        let data = try assetData(
            named: name,
            bundle: bundle,
            subdirectory: subdirectory,
            extensions: extensions
        )
        guard let text = String(data: data, encoding: .utf8) else {
            throw ExodeAssetError.malformedDocument("\(name) is not valid UTF-8")
        }
        return text
    }

    /// Splits `.bexode` bytes into base64-sized chunks for the bridge.
    public static func bexodeChunks(
        _ data: Data,
        chunkSize: Int = ExodeAssets.binaryChunkBytes
    ) -> [Data] {
        precondition(chunkSize > 0, "chunkSize must be positive")
        guard !data.isEmpty else { return [] }
        var chunks: [Data] = []
        chunks.reserveCapacity((data.count + chunkSize - 1) / chunkSize)
        var offset = 0
        while offset < data.count {
            let end = min(offset + chunkSize, data.count)
            chunks.append(data.subdata(in: offset..<end))
            offset = end
        }
        return chunks
    }

    // MARK: - Private

    private static func resourceBundle(
        _ bundle: Bundle
    ) throws -> (html: URL, bundle: URL) {
        let html = bundle.url(forResource: "index", withExtension: "html", subdirectory: "Resources")
            ?? bundle.url(forResource: "index", withExtension: "html")
        let script = bundle.url(
            forResource: "engine.bundle",
            withExtension: "js",
            subdirectory: "Resources"
        ) ?? bundle.url(forResource: "engine.bundle", withExtension: "js")
        guard let html, let script else { throw ExodeAssetError.resourcesMissing }
        return (html, script)
    }

    private static func assetURL(
        named name: String,
        bundle: Bundle,
        subdirectory: String?,
        extensions: [String]
    ) -> URL? {
        let path = name as NSString
        let ext = path.pathExtension
        let base = ext.isEmpty ? name : path.deletingPathExtension

        func find(_ resource: String, _ fileExtension: String?) -> URL? {
            if let subdirectory,
               let url = bundle.url(
                   forResource: resource,
                   withExtension: fileExtension,
                   subdirectory: subdirectory
               ) {
                return url
            }
            return bundle.url(forResource: resource, withExtension: fileExtension)
        }

        if !ext.isEmpty {
            return find(base, ext) ?? find(name, nil)
        }

        // Extension-less names are the documented default
        // (`bexodeAsset: "hero"`), so try every format the caller allows before
        // falling back to an exact file-name match.
        for candidate in extensions {
            if let url = find(name, candidate) { return url }
        }
        return find(name, nil)
    }

    /// Extensions the package understands when an asset name omits one.
    public static let artboardExtensions = ["bexode", "exode", "json"]
}
