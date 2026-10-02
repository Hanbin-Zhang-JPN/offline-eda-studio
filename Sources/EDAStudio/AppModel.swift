import SwiftUI
import AppKit
import EDACore

struct Feature: Codable, Identifiable {
    let id: String
    let category: String
    let name: String
    let weight: Int
    let status: String
    let phase: String
    let acceptance: String
    let evidence: String
}

@MainActor final class AppModel: ObservableObject {
    @Published var projects = [EDAProject]()
    @Published var selectedID: String?
    @Published var section = "overview"
    @Published var parts = [Component]()
    @Published var harness: Harness?
    @Published var preview: BoardPreview?
    @Published var engineVersion = "未检测"
    @Published var enginePath = UserDefaults.standard.string(forKey: "enginePath") ?? ""
    @Published var busy = false
    @Published var message = ""
    @Published var error: String?
    @Published var features = [Feature]()
    var project: EDAProject? { projects.first { $0.id == selectedID } }
    var engine: KiCadEngine? { KiCadEngine.discover(explicit: enginePath.isEmpty ? nil : enginePath) }
    var resources: URL { Bundle.module.url(forResource: "Resources", withExtension: nil)! }

    init() {
        for path in UserDefaults.standard.stringArray(forKey: "recentProjects") ?? [] {
            if let project = try? EDAProject(root: URL(fileURLWithPath: path)) { projects.append(project) }
        }
        selectedID = projects.first?.id
        features = (try? JSONFile.read([Feature].self, from: resources.appendingPathComponent("features.json"))) ?? []
        reload(); detectEngine()
    }
    func report(_ error: Error) { self.error = error.localizedDescription }
    func remember(_ project: EDAProject) {
        if !projects.contains(where: { $0.id == project.id }) { projects.append(project) }
        selectedID = project.id
        UserDefaults.standard.set(projects.map { $0.root.path }, forKey: "recentProjects")
        reload()
    }
    func reload() {
        parts = []; harness = nil; preview = nil
        guard let project else { return }
        do {
            parts = try JSONFile.read([Component].self, from: project.file(project.manifest.partsFile))
            try BOM.validate(parts)
            harness = try JSONFile.read(Harness.self, from: project.file(project.manifest.harnessFile))
            preview = try BoardPreview(contents: String(contentsOf: project.file(project.manifest.boardFile), encoding: .utf8))
        } catch { report(error) }
    }
    func importProject() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.message = "选择含 eda-project.json 的项目目录"
        if panel.runModal() == .OK, let root = panel.url {
            do { remember(try EDAProject(root: root)) } catch { report(error) }
        }
    }
    func createDemo() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "LED-Demo"; panel.canCreateDirectories = true
        panel.message = "创建可编辑的双层 LED 示例项目，目标目录必须尚不存在"
        if panel.runModal() == .OK, let root = panel.url {
            do { remember(try EDAProject.create(at: root, name: root.lastPathComponent, template: resources.appendingPathComponent("led-demo"))) }
            catch { report(error) }
        }
    }
    func selectEngine() {
        let panel = NSOpenPanel(); panel.message = "选择 KiCad.app/Contents/MacOS/kicad-cli"
        if panel.runModal() == .OK, let url = panel.url {
            enginePath = url.path; UserDefaults.standard.set(enginePath, forKey: "enginePath"); detectEngine()
        }
    }
    func detectEngine() {
        guard let engine else { engineVersion = "未安装 KiCad 10"; return }
        Task {
            do { engineVersion = try await Task.detached { try engine.requireSupported() }.value }
            catch { engineVersion = error.localizedDescription }
        }
    }
    func openEditor(schematic: Bool) {
        guard let project, let engine else { error = EDAError.engineMissing.localizedDescription; return }
        let manager = engine.executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let name = schematic ? "eeschema" : "pcbnew"
        let candidates = [manager.deletingLastPathComponent().appendingPathComponent(name + ".app"), manager.appendingPathComponent("Contents/Applications/" + name + ".app")]
        guard let app = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            error = "找不到 \(name).app，请从 KiCad 项目管理器打开设计"; return
        }
        do {
            let file = try project.file(schematic ? project.manifest.schematicFile : project.manifest.boardFile)
            let config = NSWorkspace.OpenConfiguration(); config.arguments = [file.path]
            NSWorkspace.shared.openApplication(at: app, configuration: config) { _, launchError in
                if let launchError { Task { @MainActor in self.report(launchError) } }
            }
        } catch { report(error) }
    }
    func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    func saveParts(_ updated: [Component]) {
        guard let project else { return }
        do { try BOM.validate(updated); try JSONFile.write(updated, to: project.file(project.manifest.partsFile)); parts = updated; message = "采购计划已保存；原理图元件请在 KiCad 中编辑" }
        catch { report(error) }
    }
    func exportBOM() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "planning-bom.csv"
        if panel.runModal() == .OK, let url = panel.url {
            do { try BOM.csv(parts).write(to: url, atomically: true, encoding: .utf8); reveal(url) } catch { report(error) }
        }
    }
    func exportHarness() {
        guard let harness else { return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = "wire-cut-list.csv"
        if panel.runModal() == .OK, let url = panel.url {
            do { try harness.cutListCSV().write(to: url, atomically: true, encoding: .utf8); reveal(url) } catch { report(error) }
        }
    }
    func snapshot() {
        guard let project else { return }; busy = true
        Task {
            defer { busy = false }
            do {
                let url = try await Task.detached { try ProjectFiles.snapshot(project, label: "Desktop snapshot") }.value
                message = "快照已保存：\(url.lastPathComponent)"; reveal(url)
            } catch { report(error) }
        }
    }
    func run(job: EngineJob? = nil) {
        guard let project else { return }
        guard let engine else { error = EDAError.engineMissing.localizedDescription; return }
        busy = true; message = "正在执行 \(job?.title ?? "制造发布检查")…"
        Task {
            defer { busy = false }
            do {
                let (url, log): (URL, String) = try await Task.detached {
                    _ = try engine.requireSupported()
                    if let job {
                        let output = try project.file("outputs/job-" + UUID().uuidString.lowercased())
                        let result = try job.execute(project: project, engine: engine, output: output)
                        try JSONFile.write(result, to: output.appendingPathComponent("command.json"))
                        guard result.exitCode == 0 else { throw EDAError.command("退出码 \(result.exitCode)\n\(result.stdout)\n\(result.stderr)\n报告：\(output.path)") }
                        return (output, result.stdout)
                    }
                    return (try Manufacturing.release(project, engine: engine), "ERC、DRC 与原理图一致性检查通过；已输出双层板制造文件")
                }.value
                message = "\(log)\n\(url.path)"; reveal(url)
            } catch { report(error); message = "作业未完成：\(error.localizedDescription)" }
        }
    }
}
