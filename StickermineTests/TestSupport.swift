import Foundation

/// The repository's own files, for tests that guard rules no runtime check can see.
enum SourceFiles {
    /// The repository root, found from this file's location in `<repo>/StickermineTests`.
    static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    /// `<repo>/Stickermine`, the app target's synchronized folder.
    static var appRoot: URL {
        repoRoot.appendingPathComponent("Stickermine")
    }

    static func contents(of relativePath: String) throws -> String {
        try String(contentsOf: appRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    static func swiftFiles() -> [URL] {
        let enumerator = FileManager.default.enumerator(at: appRoot, includingPropertiesForKeys: nil)
        var files: [URL] = []
        while let url = enumerator?.nextObject() as? URL {
            if url.pathExtension == "swift" { files.append(url) }
        }
        return files.sorted { $0.path < $1.path }
    }
}
