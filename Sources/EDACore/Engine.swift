import Foundation
import Darwin

public struct CommandResult: Codable {
    public let arguments: [String]
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
    public let durationSeconds: Double
}

public struct KiCadEngine {
    public let executable: URL
    public let timeout: TimeInterval
    public init(executable: URL, timeout: TimeInterval = 180) { self.executable = executable; self.timeout = timeout }
    public static func discover(explicit: String? = nil) -> KiCadEngine? {
        let env = ProcessInfo.processInfo.environment
        if let specified = explicit ?? env["KICAD_CLI"], !specified.isEmpty {
            let url = URL(fileURLWithPath: specified)
            return FileManager.default.isExecutableFile(atPath: url.path) ? KiCadEngine(executable: url) : nil
        }
        let candidates = ["/Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli",
                          "/Applications/KiCad.app/Contents/MacOS/kicad-cli",
                          NSHomeDirectory() + "/Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli"]
            + (env["PATH"] ?? "").split(separator: ":").map { String($0) + "/kicad-cli" }
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }).map { KiCadEngine(executable: URL(fileURLWithPath: $0)) }
    }
    public func run(_ arguments: [String], directory: URL? = nil) throws -> CommandResult {
        // Files rather than pipes avoid deadlock when an engine prints more than the pipe buffer.
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("eda-process-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let stdoutURL = scratch.appendingPathComponent("stdout"), stderrURL = scratch.appendingPathComponent("stderr")
        FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
        FileManager.default.createFile(atPath: stderrURL.path, contents: nil)
        let stdout = try FileHandle(forWritingTo: stdoutURL), stderr = try FileHandle(forWritingTo: stderrURL)
        defer { try? stdout.close(); try? stderr.close() }
        let process = Process()
        process.executableURL = executable; process.arguments = arguments
        process.currentDirectoryURL = directory; process.standardOutput = stdout; process.standardError = stderr
        let started = Date()
        try process.run()
        while process.isRunning {
            if Date().timeIntervalSince(started) > timeout {
                process.terminate()
                let stopDeadline = Date().addingTimeInterval(2)
                while process.isRunning && Date() < stopDeadline { usleep(20_000) }
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                process.waitUntilExit()
                throw EDAError.command("KiCad 命令超时：\(arguments.joined(separator: " "))")
            }
            usleep(20_000)
        }
        process.waitUntilExit()
        let output = (try? String(contentsOf: stdoutURL, encoding: .utf8)) ?? ""
        let errors = (try? String(contentsOf: stderrURL, encoding: .utf8)) ?? ""
        return CommandResult(arguments: arguments, exitCode: process.terminationStatus, stdout: output, stderr: errors, durationSeconds: Date().timeIntervalSince(started))
    }
    public func version() throws -> String {
        let result = try run(["version"])
        guard result.exitCode == 0 else { throw EDAError.command(result.stderr) }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    public func requireSupported() throws -> String {
        let version = try version()
        guard version.split(separator: ".").first == "10" else { throw EDAError.invalid("当前引擎 \(version)，本版本仅支持 KiCad 10.x；尚未验证其他版本") }
        return version
    }
}

public enum EngineJob: String, CaseIterable, Codable, Identifiable {
    case drc, erc, gerbers, drill, positions, step, boardSVG, schematicPDF, netlist, schematicBOM, ipc2581, odb
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .drc: return "PCB 设计规则检查"
        case .erc: return "原理图电气规则检查"
        case .gerbers: return "Gerber 制造文件"
        case .drill: return "Excellon 钻孔文件"
        case .positions: return "贴片坐标 CSV"
        case .step: return "STEP 三维模型"
        case .boardSVG: return "PCB SVG 预览"
        case .schematicPDF: return "原理图 PDF"
        case .netlist: return "网表"
        case .schematicBOM: return "原理图 BOM"
        case .ipc2581: return "IPC-2581"
        case .odb: return "ODB++"
        }
    }
    public func arguments(project: EDAProject, output: URL) throws -> [String] {
        let pcb = try project.file(project.manifest.boardFile).path
        let sch = try project.file(project.manifest.schematicFile).path
        switch self {
        case .drc: return ["pcb", "drc", "--format", "json", "--severity-all", "--schematic-parity", "--exit-code-violations", "--output", output.appendingPathComponent("drc.json").path, pcb]
        case .erc: return ["sch", "erc", "--format", "json", "--severity-all", "--exit-code-violations", "--output", output.appendingPathComponent("erc.json").path, sch]
        case .gerbers: return ["pcb", "export", "gerbers", "--layers", "F.Cu,B.Cu,F.Paste,B.Paste,F.SilkS,B.SilkS,F.Mask,B.Mask,Edge.Cuts", "--output", output.appendingPathComponent("gerbers").path + "/", pcb]
        case .drill: return ["pcb", "export", "drill", "--format", "excellon", "--output", output.appendingPathComponent("drill").path + "/", pcb]
        case .positions: return ["pcb", "export", "pos", "--format", "csv", "--units", "mm", "--output", output.appendingPathComponent("positions.csv").path, pcb]
        case .step: return ["pcb", "export", "step", "--output", output.appendingPathComponent("board.step").path, pcb]
        case .boardSVG: return ["pcb", "export", "svg", "--layers", "F.Cu,B.Cu,F.SilkS,Edge.Cuts", "--mode-single", "--output", output.appendingPathComponent("board.svg").path, pcb]
        case .schematicPDF: return ["sch", "export", "pdf", "--output", output.appendingPathComponent("schematic.pdf").path, sch]
        case .netlist: return ["sch", "export", "netlist", "--output", output.appendingPathComponent("netlist.net").path, sch]
        case .schematicBOM: return ["sch", "export", "bom", "--output", output.appendingPathComponent("schematic-bom.csv").path, sch]
        case .ipc2581: return ["pcb", "export", "ipc2581", "--output", output.appendingPathComponent("board.xml").path, pcb]
        case .odb: return ["pcb", "export", "odb", "--output", output.appendingPathComponent("board-odb.zip").path, pcb]
        }
    }
    public func execute(project: EDAProject, engine: KiCadEngine, output: URL) throws -> CommandResult {
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        return try engine.run(arguments(project: project, output: output), directory: project.root)
    }
}

public struct ReleaseManifest: Codable {
    public var schemaVersion = 1
    public let id: String
    public let createdAt: String
    public let engineVersion: String
    public let source: [FileDigest]
    public let artifacts: [FileDigest]
    public let commands: [CommandResult]
    public let status: String
    public let note: String
}

public enum Manufacturing {
    public static func release(_ project: EDAProject, engine: KiCadEngine, includeSTEP: Bool = false) throws -> URL {
        let version = try engine.requireSupported()
        let id = UUID().uuidString.lowercased()
        let outputs = try project.file("outputs")
        let pending = outputs.appendingPathComponent(".pending-" + id)
        let source = pending.appendingPathComponent("source")
        let artifacts = pending.appendingPathComponent("artifacts")
        var commands = [CommandResult]()
        var sourceDigests = [FileDigest]()
        do {
            sourceDigests = try ProjectFiles.copyVerified(from: project.root, to: source)
            let frozen = try EDAProject(root: source)
            let preview = try BoardPreview(contents: String(contentsOf: frozen.file(frozen.manifest.boardFile), encoding: .utf8))
            guard Set(preview.copperLayers) == Set(["F.Cu", "B.Cu"]) else {
                throw EDAError.invalid("v0.1 制造发布仅支持双层板；多层板请在 KiCad 中导出并审核完整铜层")
            }
            // Run against immutable copy, including ERC and all DRC severities. No waive switch.
            let jobs: [EngineJob] = [.erc, .drc, .gerbers, .drill, .positions, .schematicBOM, .schematicPDF] + (includeSTEP ? [.step] : [])
            for job in jobs {
                let result = try job.execute(project: frozen, engine: engine, output: artifacts)
                commands.append(result)
                guard result.exitCode == 0 else {
                    throw EDAError.command("\(job.title)失败（\(result.exitCode)）：\(result.stdout)\n\(result.stderr)")
                }
                if job == .erc || job == .drc {
                    let report = artifacts.appendingPathComponent(job.rawValue + ".json")
                    guard FileManager.default.fileExists(atPath: report.path) else { throw EDAError.command("检查报告缺失，拒绝发布") }
                    try CheckReport.requireClean(Data(contentsOf: report), job: job)
                }
            }
            let partsURL = try frozen.file(frozen.manifest.partsFile)
            if FileManager.default.fileExists(atPath: partsURL.path) {
                let parts = try JSONFile.read([Component].self, from: partsURL)
                try BOM.csv(parts).write(to: artifacts.appendingPathComponent("planning-bom.csv"), atomically: true, encoding: .utf8)
            }
            guard try ProjectFiles.digests(in: source) == sourceDigests else { throw EDAError.invalid("引擎修改了源文件，拒绝发布") }
            let hashes = try ProjectFiles.digests(in: artifacts)
            guard hashes.contains(where: { $0.path.hasPrefix("gerbers/") && $0.bytes > 0 }),
                  hashes.contains(where: { $0.path.hasPrefix("drill/") && $0.bytes > 0 }),
                  hashes.contains(where: { $0.path == "positions.csv" && $0.bytes > 0 }),
                  hashes.contains(where: { $0.path == "schematic-bom.csv" && $0.bytes > 0 }) else {
                throw EDAError.command("制造输出缺失，拒绝发布")
            }
            let manifest = ReleaseManifest(id: id, createdAt: ISO8601DateFormatter().string(from: Date()), engineVersion: version,
                source: sourceDigests, artifacts: hashes, commands: commands, status: "passed",
                note: "启用的 ERC/DRC 规则与原理图一致性检查通过；禁用规则见报告 ignored_checks。planning-bom 为手工采购计划，schematic-bom 为设计导出。此检查不构成完整 DFM 或电气性能认证；本发布仅支持双层板。")
            try JSONFile.write(manifest, to: pending.appendingPathComponent("release.json"))
            let destination = outputs.appendingPathComponent("release-" + id)
            try FileManager.default.moveItem(at: pending, to: destination)
            return destination
        } catch {
            if FileManager.default.fileExists(atPath: pending.path) {
                let failure = ReleaseManifest(id: id, createdAt: ISO8601DateFormatter().string(from: Date()), engineVersion: version,
                    source: sourceDigests, artifacts: (try? ProjectFiles.digests(in: artifacts)) ?? [], commands: commands, status: "failed", note: error.localizedDescription)
                try? JSONFile.write(failure, to: pending.appendingPathComponent("release.json"))
                try? FileManager.default.moveItem(at: pending, to: outputs.appendingPathComponent("failed-" + id))
            }
            throw error
        }
    }
}

public enum CheckReport {
    public static func requireClean(_ data: Data, job: EngineJob) throws {
        guard let report = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let schema = report["$schema"] as? String, schema.hasSuffix("/\(job.rawValue).v1.json"),
              let version = report["kicad_version"] as? String, version.hasPrefix("10.") else {
            throw EDAError.command("检查报告格式或版本无效，拒绝发布")
        }
        if job == .drc {
            for key in ["violations", "unconnected_items", "schematic_parity"] {
                guard let entries = report[key] as? [Any], entries.isEmpty else {
                    throw EDAError.command("DRC 报告存在 \(key) 或缺失该字段，拒绝发布")
                }
            }
        } else if job == .erc {
            guard let sheets = report["sheets"] as? [[String: Any]], !sheets.isEmpty else { throw EDAError.command("ERC 报告缺少电路页") }
            for sheet in sheets {
                guard let violations = sheet["violations"] as? [Any], violations.isEmpty else { throw EDAError.command("ERC 报告包含违规或字段缺失，拒绝发布") }
            }
        } else { throw EDAError.invalid("只有 ERC/DRC 报告可用于发布检查") }
    }
}
