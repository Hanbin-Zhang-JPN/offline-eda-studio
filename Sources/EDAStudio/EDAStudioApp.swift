import SwiftUI
import EDACore

@main struct EDAStudioApp: App {
    @StateObject private var model = AppModel()
    var body: some Scene {
        WindowGroup("Offline EDA Studio") {
            StudioView().environmentObject(model).frame(minWidth: 1060, minHeight: 720).preferredColorScheme(.dark)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新建示例项目…") { model.createDemo() }.keyboardShortcut("n")
                Button("打开项目…") { model.importProject() }.keyboardShortcut("o")
            }
        }
    }
}

struct StudioView: View {
    @EnvironmentObject var model: AppModel
    private let sections: [(String, String, String)] = [
        ("overview", "项目总览", "square.grid.2x2"), ("board", "PCB 预览", "cpu"),
        ("parts", "元件与 BOM", "shippingbox"), ("jobs", "检查与制造", "checkmark.shield"),
        ("harness", "线束连接", "point.3.connected.trianglepath.dotted"), ("calculator", "工程计算", "function"),
        ("coverage", "功能与验收", "list.bullet.rectangle"), ("help", "本地帮助", "book.closed")]
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 8) {
                HStack { Image(systemName: "cpu.fill").font(.title).foregroundStyle(.mint); VStack(alignment: .leading) { Text("OFFLINE EDA").font(.headline); Text("STUDIO  /  0.1.1").font(.caption).foregroundStyle(.secondary) } }.padding(16)
                List(selection: $model.section) {
                    Section("工作台") { ForEach(sections, id: \.0) { item in Label(item.1, systemImage: item.2).tag(item.0) } }
                    Section("本地项目") {
                        ForEach(model.projects) { project in
                            Button { model.selectedID = project.id; model.reload(); model.section = "overview" } label: {
                                Label(project.manifest.name, systemImage: model.selectedID == project.id ? "folder.fill" : "folder")
                            }.buttonStyle(.plain).foregroundStyle(model.selectedID == project.id ? Color.mint : .primary)
                        }
                    }
                }.listStyle(.sidebar)
                VStack(alignment: .leading, spacing: 8) {
                    Label("本地运行 · 无云账户", systemImage: "externaldrive.fill").foregroundStyle(.mint)
                    Text("KiCad: \(model.engineVersion)").font(.caption).foregroundStyle(.secondary).lineLimit(3)
                    Button("选择 EDA 引擎…") { model.selectEngine() }.font(.caption)
                }.padding(16)
            }.navigationSplitViewColumnWidth(240)
        } detail: {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(sections.first { $0.0 == model.section }?.1 ?? "工作台").font(.title2.bold())
                        Text(model.project?.manifest.name ?? "选择或创建一个本地项目").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if model.busy { ProgressView().controlSize(.small) }
                    Button { model.importProject() } label: { Label("打开", systemImage: "folder") }
                    Button { model.createDemo() } label: { Label("新建示例", systemImage: "plus") }.buttonStyle(.borderedProminent).tint(.mint)
                }.padding(24)
                Divider()
                ScrollView {
                    Group {
                        switch model.section {
                        case "board": BoardView()
                        case "parts": PartsView()
                        case "jobs": JobsView()
                        case "harness": HarnessView()
                        case "calculator": CalculatorView()
                        case "coverage": CoverageView()
                        case "help": HelpView()
                        default: OverviewView()
                        }
                    }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
                }
                if !model.message.isEmpty {
                    Divider(); Text(model.message).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(5).padding(16)
                }
            }
        }
        .disabled(model.busy)
        .alert("操作未完成", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("知道了") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }
}

struct Panel<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.headline); content
        }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
         .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
         .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.07)))
    }
}

struct OverviewView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("从电路到制造，留在你的 Mac 上。").font(.system(size: 30, weight: .semibold))
            Text("原理图与布线使用 KiCad 原生编辑器。工作台负责项目、采购计划、快照和制造作业。首次准备好引擎、元件库和模型后，可以断网使用。").foregroundStyle(.secondary)
            HStack(spacing: 16) {
                stat("铜层", model.preview.map { String($0.copperLayers.count) } ?? "—", "square.3.layers.3d")
                stat("板上元件", model.preview.map { String($0.references.count) } ?? "—", "cpu")
                stat("采购计划", String(model.parts.count), "shippingbox")
            }
            Panel(title: "设计工具") {
                HStack(spacing: 12) {
                    Button("打开原理图编辑器") { model.openEditor(schematic: true) }
                    Button("打开 PCB 编辑器 / 3D") { model.openEditor(schematic: false) }
                    Button("刷新项目") { model.reload() }
                }.disabled(model.project == nil)
                Text("在 PCB 编辑器中使用 3D Viewer、推挤布线和差分对工具；在原理图编辑器中使用 SPICE 仿真。").font(.caption).foregroundStyle(.secondary)
            }
            Panel(title: "项目与版本") {
                Text(model.project?.root.path ?? "还没有打开项目。点击“新建示例”可创建带原理图与 PCB 的演示项目。").font(.callout.monospaced()).textSelection(.enabled)
                HStack {
                    Button("建立 SHA-256 快照") { model.snapshot() }
                    Button("在 Finder 中显示") { if let root = model.project?.root { model.reveal(root) } }
                }.disabled(model.project == nil)
            }
            Panel(title: "开发状态") {
                Text("v0.1 是可运行的基础工作台，尚未达到 Altium Designer 90% 功能。功能矩阵记录了完整目标、验收条件和证据；高级刚柔结合、多板装配、SI/PI 求解等仍需开发。")
                Button("查看功能与验收") { model.section = "coverage" }
            }
        }
    }
    func stat(_ title: String, _ value: String, _ icon: String) -> some View {
        Panel(title: title) { HStack { Text(value).font(.system(size: 34, weight: .medium, design: .rounded)); Spacer(); Image(systemName: icon).font(.title).foregroundStyle(.mint) } }
    }
}

struct BoardView: View {
    @EnvironmentObject var model: AppModel
    @SwiftUI.State<Bool> private var front = true
    @SwiftUI.State<Bool> private var back = true
    @SwiftUI.State<Bool> private var showPads = true
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Toggle("F.Cu", isOn: $front); Toggle("B.Cu", isOn: $back); Toggle("焊盘", isOn: $showPads); Spacer(); Button("打开 PCB 编辑器") { model.openEditor(schematic: false) }.disabled(model.project == nil) }
            if let board = model.preview {
                Canvas { context, size in
                    let points = board.lines.flatMap { [$0.start, $0.end] } + board.pads.map(\.center)
                    let minX = (points.map(\.x).min() ?? 0) - 4, maxX = (points.map(\.x).max() ?? 60) + 4
                    let minY = (points.map(\.y).min() ?? 0) - 4, maxY = (points.map(\.y).max() ?? 40) + 4
                    let scale: Double = min(Double(size.width) / max(1, maxX - minX), Double(size.height) / max(1, maxY - minY))
                    let ox = (Double(size.width) - (maxX - minX) * scale) / 2, oy = (Double(size.height) - (maxY - minY) * scale) / 2
                    func point(_ p: BoardPoint) -> CGPoint { .init(x: CGFloat(ox + (p.x - minX) * scale), y: CGFloat(oy + (p.y - minY) * scale)) }
                    for x in stride(from: 0.0, through: size.width, by: 20) { for y in stride(from: 0.0, through: size.height, by: 20) {
                        context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1, height: 1)), with: .color(.white.opacity(0.12)))
                    } }
                    for line in board.lines where (line.layer != "F.Cu" || front) && (line.layer != "B.Cu" || back) {
                        var path = Path(); path.move(to: point(line.start)); path.addLine(to: point(line.end))
                        let color: Color = line.layer == "F.Cu" ? .orange : line.layer == "B.Cu" ? .cyan : .mint
                        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: CGFloat(max(1, line.width * scale)), lineCap: .round))
                    }
                    if showPads { for pad in board.pads {
                        let p = point(pad.center)
                        var transformed = context; transformed.translateBy(x: p.x, y: p.y); transformed.rotate(by: .degrees(-pad.angle))
                        let pw = CGFloat(pad.width * scale), ph = CGFloat(pad.height * scale)
                        transformed.fill(Path(roundedRect: CGRect(x: -pw / 2, y: -ph / 2, width: pw, height: ph), cornerRadius: 3), with: .color(.yellow))
                    } }
                }.frame(height: 420).background(Color(red: 0.025, green: 0.055, blue: 0.08), in: RoundedRectangle(cornerRadius: 14))
                Text("\(board.references.joined(separator: " · "))").font(.caption.monospaced()).foregroundStyle(.secondary)
                Text("简化只读预览：显示直线、走线和矩形焊盘。圆弧、覆铜、过孔形状、背面封装与自定义焊盘请在 KiCad 中查看；不可用此预览审核制造。").font(.caption).foregroundStyle(.secondary)
            } else { ContentUnavailableView("没有 PCB 预览", systemImage: "cpu", description: Text("先打开或创建一个项目")) }
        }
    }
}

struct PartsView: View {
    @EnvironmentObject var model: AppModel
    @SwiftUI.State<String> private var search = ""
    @SwiftUI.State<String> private var reference = ""
@SwiftUI.State<String> private var value = ""
@SwiftUI.State<String> private var footprint = ""
@SwiftUI.State<String> private var mpn = ""
@SwiftUI.State<String> private var manufacturer = ""
@SwiftUI.State<String> private var price = "0"
    var filtered: [Component] { model.parts.filter { search.isEmpty || [$0.reference, $0.value, $0.mpn, $0.footprint].joined(separator: " ").localizedCaseInsensitiveContains(search) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("本地采购计划独立于原理图；生产使用“原理图 BOM”作业导出的设计 BOM。单价为手工输入，不代表实时价格。").foregroundStyle(.secondary)
            HStack { TextField("搜索位号、MPN、封装…", text: $search); Button("导出采购 BOM") { model.exportBOM() }.disabled(model.project == nil) }
            ForEach(filtered) { part in
                HStack {
                    Text(part.reference).font(.headline.monospaced()).frame(width: 50, alignment: .leading)
                    VStack(alignment: .leading) { Text(part.value); Text("\(part.footprint) · \(part.mpn)").font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    Toggle("DNP", isOn: Binding(get: { part.dnp }, set: { dnp in var parts = model.parts; if let index = parts.firstIndex(where: { $0.id == part.id }) { parts[index].dnp = dnp }; model.saveParts(parts) })).toggleStyle(.checkbox)
                    Button("删除") { model.saveParts(model.parts.filter { $0.id != part.id }) }
                }.padding(12).background(.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))
            }
            Panel(title: "添加采购元件") {
                HStack { TextField("位号 R2", text: $reference); TextField("值 10k", text: $value); TextField("封装", text: $footprint) }
                HStack { TextField("MPN", text: $mpn); TextField("厂商", text: $manufacturer); TextField("单价", text: $price) }
                Button("保存到本地计划") {
                    guard let amount = Double(price) else { model.error = "单价必须是数字"; return }
                    let part = Component(reference: reference, value: value, footprint: footprint, mpn: mpn, manufacturer: manufacturer, unitPrice: amount)
                    let count = model.parts.count; model.saveParts(model.parts + [part])
                    if model.parts.count > count { reference = ""; value = ""; footprint = ""; mpn = ""; manufacturer = ""; price = "0" }
                }.disabled(model.project == nil)
            }
        }.textFieldStyle(.roundedBorder)
    }
}

struct JobsView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Panel(title: "双层板制造发布") {
                Text("冻结源文件 → ERC → DRC / 原理图一致性 → Gerber / 钻孔 / 坐标 / BOM / PDF → SHA-256 清单。任一步失败会保留 failed 目录和诊断，不生成 release 目录。")
                Button("检查并生成制造发布") { model.run() }.buttonStyle(.borderedProminent).tint(.mint)
                Text("v0.1 仅支持双层板；正式生产还需人工 DFM、叠层、装配及电气复核。").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(EngineJob.allCases) { job in
                HStack { Label(job.title, systemImage: job == .drc || job == .erc ? "checkmark.shield" : "square.and.arrow.down"); Spacer(); Button("执行") { model.run(job: job) } }.padding(12).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
            }
            Text("单项作业输出位于 outputs/job-*，它们不代表已通过制造发布检查。引擎命令和退出码保存在 command.json 中。").font(.caption).foregroundStyle(.secondary)
        }.disabled(model.project == nil)
    }
}

struct HarnessView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("点对点线束校验与裁线表。编辑项目中的 harness.json 后点击刷新；当前不包含图形化线束编辑、分支压接或多板 3D 装配。").foregroundStyle(.secondary)
            HStack { Button("刷新") { model.reload() }; Button("导出裁线 CSV") { model.exportHarness() }; Button("显示数据文件") { if let project = model.project, let url = try? project.file(project.manifest.harnessFile) { model.reveal(url) } } }.disabled(model.project == nil)
            if let harness = model.harness {
                let issues = harness.validate()
                Panel(title: issues.isEmpty ? "连接检查通过" : "连接问题") {
                    if issues.isEmpty { Text("\(harness.connectors.count) 个连接器 · \(harness.wires.count) 根导线").foregroundStyle(.mint) }
                    else { ForEach(issues, id: \.self) { Text($0).foregroundStyle(.orange) } }
                }
                ForEach(harness.wires) { wire in
                    HStack { Text(wire.id).font(.headline.monospaced()); Text(wire.from.label); Image(systemName: "arrow.right").foregroundStyle(.mint); Text(wire.to.label); Spacer(); Text(wire.net); Text("\(String(format: "%.1f", wire.lengthMM)) mm · AWG \(wire.awg)").foregroundStyle(.secondary) }.padding(12)
                }
            }
        }
    }
}

struct CalculatorView: View {
    @SwiftUI.State<String> private var width = "0.30"
@SwiftUI.State<String> private var height = "0.18"
@SwiftUI.State<String> private var er = "4.2"
    var result: String {
        guard let w = Double(width), let h = Double(height), let e = Double(er), let z = try? Engineering.microstrip(widthMM: w, heightMM: h, er: e) else { return "请输入有效正数；εr ≥ 1" }
        return String(format: "%.2f Ω", z)
    }
    var body: some View {
        Panel(title: "微带阻抗估算") {
            Text("\(result)").font(.system(size: 48, weight: .medium, design: .rounded)).foregroundStyle(.mint)
            HStack { VStack { Text("线宽 mm"); TextField("0.30", text: $width) }; VStack { Text("介质厚度 mm"); TextField("0.18", text: $height) }; VStack { Text("介电常数 εr"); TextField("4.2", text: $er) } }.textFieldStyle(.roundedBorder)
            Text("准静态薄导体近似，不计铜厚、阻焊、损耗与频散。仅作工程初估；不作为受控阻抗制造或 SI/PI 验收结果。").foregroundStyle(.secondary)
        }
    }
}

struct CoverageView: View {
    @EnvironmentObject var model: AppModel
    @SwiftUI.State<String> private var query = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Panel(title: "90% 是验收目标") {
                Text("分母是仓库定义的功能矩阵，并非 Altium 官方认证。仅有验收证据的项目计入覆盖率；继承自 KiCad 的能力需要逐项集成验收。高级能力不会通过增加简单功能的数量来冲抵。")
                Text("\(model.features.count) 项功能规格 · 详见 docs/FEATURE_MATRIX.md").foregroundStyle(.mint)
            }
            TextField("搜索功能、阶段或状态…", text: $query).textFieldStyle(.roundedBorder)
            ForEach(model.features.filter { query.isEmpty || [$0.name, $0.category, $0.status, $0.phase].joined(separator: " ").localizedCaseInsensitiveContains(query) }) { feature in
                VStack(alignment: .leading, spacing: 6) {
                    HStack { Text(feature.id).font(.caption.monospaced()).foregroundStyle(.secondary); Text(feature.name).font(.headline); Spacer(); Text(feature.status).font(.caption).foregroundStyle(feature.status == "verified" ? .mint : .orange) }
                    Text("\(feature.category) · \(feature.phase) · 权重 \(feature.weight)").font(.caption).foregroundStyle(.secondary)
                    Text(feature.acceptance).font(.callout)
                    if !feature.evidence.isEmpty { Text(feature.evidence).font(.caption.monospaced()).foregroundStyle(.secondary) }
                }.padding(14).background(.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }
}

struct HelpView: View {
    @EnvironmentObject var model: AppModel
    let content = """
    1. 从官方安装包安装 KiCad 10，包含符号、封装、3D 模型。
    2. 在工作台中创建示例项目，或打开含 eda-project.json 的项目目录。
    3. 使用原理图 / PCB 按钮打开 KiCad 原生编辑器，保存后回到工作台刷新。
    4. 在检查与制造中运行 ERC、DRC 或制造发布，查看报告后审阅输出。
    5. 编辑 parts.json 管理采购计划；编辑 harness.json 管理点对点线束。
    6. 快照保留源文件和哈希，CLI 可核对快照。恢复时复制到新目录，避免覆盖设计。

    无网络依赖的范围：工作台、KiCad 本地编辑、提前准备的元件库和模型、SPICE 模型、文件导出。GitHub 推送、下载、供应链实时数据需要网络；程序不会自动联网。

    当前边界：工作台不自行实现原理图/PCB 编辑内核；采购 DNP 不会修改 KiCad 装配变体；预览不是制造校核；制造发布仅支持双层板。
    """
    var body: some View { Panel(title: "离线使用指南") { Text(content).textSelection(.enabled); Button("显示完整本地文档") { model.reveal(model.resources.appendingPathComponent("docs")) } } }
}
