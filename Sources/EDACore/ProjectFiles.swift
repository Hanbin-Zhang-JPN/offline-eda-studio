import Foundation

public struct FileDigest: Codable, Equatable {
    public let path: String
    public let bytes: Int
    public let sha256: String
}
public struct SnapshotManifest: Codable {
    public var schemaVersion = 1
    public let id: String
    public let createdAt: String
    public let label: String
    public let files: [FileDigest]
}

public enum ProjectFiles {
    private static let excludedDirectories: Set<String> = ["outputs", ".eda-snapshots", ".git", ".build", "engine", "dist"]
    public static func sources(in root: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else {
            throw EDAError.invalid("无法读取项目目录")
        }
        var files = [URL]()
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true { throw EDAError.invalid("离线快照不接受符号链接：\(url.lastPathComponent)") }
            if values.isDirectory == true {
                if excludedDirectories.contains(url.lastPathComponent) || url.lastPathComponent.hasSuffix("-backups") { enumerator.skipDescendants() }
            } else if !url.lastPathComponent.hasPrefix(".") && !["kicad_prl", "lck"].contains(url.pathExtension) {
                files.append(url)
            }
        }
        return files.sorted { $0.path < $1.path }
    }
    public static func digests(in root: URL) throws -> [FileDigest] {
        // Foundation standardization can remove /private from /private/var on macOS.
        // Resolve both sides before deriving a relative path; never slice unmatched prefixes.
        let rootPath = root.resolvingSymlinksInPath().path + "/"
        return try sources(in: root).map { url in
            let canonical = url.resolvingSymlinksInPath()
            guard canonical.path.hasPrefix(rootPath) else { throw EDAError.invalid("源文件路径不位于项目目录内") }
            let data = try Data(contentsOf: url)
            return FileDigest(path: String(canonical.path.dropFirst(rootPath.count)), bytes: data.count, sha256: sha256(data))
        }
    }
    @discardableResult
    public static func copyVerified(from root: URL, to target: URL) throws -> [FileDigest] {
        let before = try digests(in: root)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        for digest in before {
            let source = root.appendingPathComponent(digest.path)
            let destination = target.appendingPathComponent(digest.path)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: source, to: destination)
        }
        guard try digests(in: root) == before, try digests(in: target) == before else {
            throw EDAError.invalid("项目在复制过程中发生变化，请保存编辑器并重试")
        }
        return before
    }
    public static func snapshot(_ project: EDAProject, label: String) throws -> URL {
        let id = UUID().uuidString.lowercased()
        let snapshots = try project.file(".eda-snapshots")
        let pending = snapshots.appendingPathComponent(".pending-\(id)")
        let target = snapshots.appendingPathComponent(id)
        do {
            let files = try copyVerified(from: project.root, to: pending.appendingPathComponent("source"))
            try JSONFile.write(SnapshotManifest(id: id, createdAt: ISO8601DateFormatter().string(from: Date()), label: label, files: files),
                               to: pending.appendingPathComponent("snapshot.json"))
            try FileManager.default.moveItem(at: pending, to: target)
            return target
        } catch { try? FileManager.default.removeItem(at: pending); throw error }
    }
    public static func verifySnapshot(at root: URL) throws -> Bool {
        let manifest = try JSONFile.read(SnapshotManifest.self, from: root.appendingPathComponent("snapshot.json"))
        return try manifest.files == digests(in: root.appendingPathComponent("source"))
    }
}
