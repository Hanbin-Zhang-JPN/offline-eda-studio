import Foundation
import EDACore

func usage() {
    print("""
    Offline EDA Studio 0.1.0 · 本地离线 EDA 工作台
    eda doctor
    eda inspect PROJECT_DIRECTORY
    eda create NEW_DIRECTORY NAME TEMPLATE_DIRECTORY
    eda snapshot PROJECT_DIRECTORY LABEL
    eda verify-snapshot SNAPSHOT_DIRECTORY
    eda bom PROJECT_DIRECTORY OUTPUT_CSV
    eda harness PROJECT_DIRECTORY OUTPUT_CSV
    eda job PROJECT_DIRECTORY JOB OUTPUT_DIRECTORY
    eda release PROJECT_DIRECTORY [--step]
    eda impedance WIDTH_MM HEIGHT_MM ER
    JOB: \(EngineJob.allCases.map(\.rawValue).joined(separator: ", "))
    引擎路径：KICAD_CLI=/path/to/kicad-cli
    """)
}

do {
    let args = Array(CommandLine.arguments.dropFirst())
    guard let command = args.first else { usage(); exit(0) }
    func require(_ count: Int) throws {
        guard args.count >= count else { throw EDAError.invalid("参数不足；运行 eda help 查看用法") }
    }
    func engine() throws -> KiCadEngine {
        guard let engine = KiCadEngine.discover() else { throw EDAError.engineMissing }
        _ = try engine.requireSupported()
        return engine
    }
    switch command {
    case "help", "--help", "-h": usage()
    case "doctor":
        let engine = try engine()
        print("KiCad: \(try engine.version())\nCLI: \(engine.executable.path)\nOffline: 本程序无网络客户端；库和模型需要提前安装到本地")
    case "create":
        try require(4)
        let project = try EDAProject.create(at: URL(fileURLWithPath: args[1]), name: args[2], template: URL(fileURLWithPath: args[3]))
        print(project.root.path)
    case "impedance":
        try require(4)
        guard let w = Double(args[1]), let h = Double(args[2]), let er = Double(args[3]) else { throw EDAError.invalid("请输入数值") }
        print(String(format: "%.2f Ω（准静态薄导体微带近似，不是场求解器）", try Engineering.microstrip(widthMM: w, heightMM: h, er: er)))
    case "verify-snapshot":
        try require(2)
        guard try ProjectFiles.verifySnapshot(at: URL(fileURLWithPath: args[1])) else { throw EDAError.invalid("快照内容与清单不一致") }
        print("SHA-256 校验通过")
    case "inspect", "snapshot", "bom", "harness", "job", "release":
        try require(2)
        let project = try EDAProject(root: URL(fileURLWithPath: args[1]))
        switch command {
        case "inspect": print("\(project.manifest.name)\n\(project.root.path)\n\(try ProjectFiles.digests(in: project.root).count) 个源文件")
        case "snapshot":
            try require(3); print(try ProjectFiles.snapshot(project, label: args[2]).path)
        case "bom":
            try require(3)
            let parts = try JSONFile.read([Component].self, from: project.file(project.manifest.partsFile))
            try BOM.csv(parts).write(toFile: args[2], atomically: true, encoding: .utf8)
            print("采购计划 BOM 已保存（不自动同步原理图）")
        case "harness":
            try require(3)
            let harness = try JSONFile.read(Harness.self, from: project.file(project.manifest.harnessFile))
            try harness.cutListCSV().write(toFile: args[2], atomically: true, encoding: .utf8)
            print("点对点线束裁线表已保存")
        case "job":
            try require(4)
            guard let job = EngineJob(rawValue: args[2]) else { throw EDAError.invalid("未知作业") }
            let result = try job.execute(project: project, engine: engine(), output: URL(fileURLWithPath: args[3]))
            print(result.stdout)
            if result.exitCode != 0 { throw EDAError.command("作业失败（\(result.exitCode)）：\(result.stderr)") }
        case "release": print(try Manufacturing.release(project, engine: engine(), includeSTEP: args.contains("--step")).path)
        default: break
        }
    default: throw EDAError.invalid("未知命令：\(command)")
    }
} catch {
    FileHandle.standardError.write(Data(("错误：" + error.localizedDescription + "\n").utf8))
    exit(1)
}
