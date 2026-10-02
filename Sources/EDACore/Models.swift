import Foundation
import CryptoKit

public enum EDAError: Error, LocalizedError {
    case invalid(String)
    case engineMissing
    case command(String)
    public var errorDescription: String? {
        switch self {
        case .invalid(let text), .command(let text): return text
        case .engineMissing: return "未找到 KiCad 10 引擎。安装官方 KiCad，或在设置中选择 kicad-cli。"
        }
    }
}

public enum JSONFile {
    public static func read<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }
    public static func write<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}

public func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

public struct ProjectManifest: Codable, Equatable {
    public var schemaVersion: Int
    public var name: String
    public var projectFile: String
    public var schematicFile: String
    public var boardFile: String
    public var partsFile: String
    public var harnessFile: String
    public init(name: String, stem: String = "design") {
        schemaVersion = 1; self.name = name
        projectFile = "\(stem).kicad_pro"; schematicFile = "\(stem).kicad_sch"
        boardFile = "\(stem).kicad_pcb"; partsFile = "parts.json"; harnessFile = "harness.json"
    }
}

public struct EDAProject: Identifiable, Equatable {
    public let root: URL
    public var manifest: ProjectManifest
    public var id: String { root.path }
    public init(root: URL) throws {
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
        manifest = try JSONFile.read(ProjectManifest.self, from: self.root.appendingPathComponent("eda-project.json"))
        guard manifest.schemaVersion == 1 else { throw EDAError.invalid("不支持的项目版本 \(manifest.schemaVersion)") }
        guard !manifest.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw EDAError.invalid("项目名称不能为空")
        }
        for path in [manifest.projectFile, manifest.boardFile, manifest.schematicFile, manifest.partsFile, manifest.harnessFile] {
            _ = try file(path)
        }
    }
    public func file(_ path: String) throws -> URL {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.split(separator: "/").contains("..") else {
            throw EDAError.invalid("路径必须位于项目目录内：\(path)")
        }
        // resolvingSymlinksInPath may leave an unresolved ancestor when the leaf
        // does not exist. Check each existing path component before composing it.
        var componentURL = root
        for component in path.split(separator: "/") {
            componentURL.appendPathComponent(String(component))
            if (try? componentURL.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                throw EDAError.invalid("项目路径不接受符号链接：\(path)")
            }
        }
        let url = root.appendingPathComponent(path).standardizedFileURL.resolvingSymlinksInPath()
        guard url.path.hasPrefix(root.path + "/") else { throw EDAError.invalid("路径越界：\(path)") }
        return url
    }
    public func saveManifest() throws {
        try JSONFile.write(manifest, to: root.appendingPathComponent("eda-project.json"))
    }
    public static func create(at root: URL, name: String, template: URL) throws -> EDAProject {
        guard !FileManager.default.fileExists(atPath: root.path) else { throw EDAError.invalid("目标目录已存在，拒绝覆盖") }
        try FileManager.default.copyItem(at: template, to: root)
        do {
            var project = try EDAProject(root: root)
            project.manifest.name = name
            try project.saveManifest()
            return project
        } catch {
            try? FileManager.default.removeItem(at: root)
            throw error
        }
    }
}

public struct Component: Codable, Identifiable, Equatable {
    public var reference: String
    public var value: String
    public var footprint: String
    public var mpn: String
    public var manufacturer: String
    public var unitPrice: Double
    public var dnp: Bool
    public var id: String { reference }
    public init(reference: String, value: String, footprint: String, mpn: String = "", manufacturer: String = "", unitPrice: Double = 0, dnp: Bool = false) {
        self.reference = reference; self.value = value; self.footprint = footprint
        self.mpn = mpn; self.manufacturer = manufacturer; self.unitPrice = unitPrice; self.dnp = dnp
    }
    public func validate() throws {
        guard reference.range(of: "^[A-Za-z]+[0-9]+$", options: .regularExpression) != nil else {
            throw EDAError.invalid("无效位号：\(reference)")
        }
        guard unitPrice.isFinite && unitPrice >= 0 else { throw EDAError.invalid("单价必须是非负有限数") }
    }
}

public struct BOMRow: Identifiable {
    public var references: [String]
    public var component: Component
    public var id: String { references.joined(separator: ",") }
    public var quantity: Int { references.count }
    public var extendedPrice: Double { component.unitPrice * Double(quantity) }
}

public enum BOM {
    public static func validate(_ parts: [Component]) throws {
        var refs = Set<String>()
        for part in parts {
            try part.validate()
            guard refs.insert(part.reference.uppercased()).inserted else { throw EDAError.invalid("重复位号：\(part.reference)") }
        }
    }
    public static func grouped(_ parts: [Component], includeDNP: Bool = false) throws -> [BOMRow] {
        try validate(parts)
        let filtered = parts.filter { includeDNP || !$0.dnp }
        let groups = Dictionary(grouping: filtered) { p in
            // Structured JSON key avoids delimiter collisions and mixes neither DNP nor prices.
            try! JSONEncoder().encode([p.value, p.footprint, p.mpn, p.manufacturer, String(p.unitPrice), String(p.dnp)])
        }
        return groups.values.map { group in
            BOMRow(references: group.map(\.reference).sorted { $0.localizedStandardCompare($1) == .orderedAscending }, component: group[0])
        }.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }
    public static func csv(_ parts: [Component], includeDNP: Bool = false) throws -> String {
        let rows = try grouped(parts, includeDNP: includeDNP)
        return CSV.encode([["References", "Quantity", "Value", "Footprint", "MPN", "Manufacturer", "UnitPrice", "ExtendedPrice", "DNP"]] + rows.map { row in
            [row.id, String(row.quantity), row.component.value, row.component.footprint, row.component.mpn,
             row.component.manufacturer, String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), row.component.unitPrice),
             String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), row.extendedPrice), row.component.dnp ? "true" : "false"]
        })
    }
}

public enum CSV {
    public static func encode(_ rows: [[String]]) -> String {
        rows.map { row in row.map { field in
            // Neutralize spreadsheet formulas in exported user-controlled text.
            let protected = ["=", "+", "-", "@", "\t", "\r"].contains(where: { field.hasPrefix($0) }) ? "'" + field : field
            return "\"" + protected.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }.joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }
}
