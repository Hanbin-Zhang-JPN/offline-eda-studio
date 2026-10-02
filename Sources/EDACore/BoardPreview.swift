import Foundation

public indirect enum SExpression: Equatable {
    case atom(String)
    case list([SExpression])
    public var atom: String? { if case .atom(let text) = self { return text }; return nil }
    public var items: [SExpression] { if case .list(let items) = self { return items }; return [] }
    public var tag: String? { items.first?.atom }
    public func children(_ tag: String) -> [SExpression] { items.filter { $0.tag == tag } }
    public func child(_ tag: String) -> SExpression? { children(tag).first }
    public func value(_ index: Int = 1) -> String? { items.indices.contains(index) ? items[index].atom : nil }
    public func number(_ index: Int = 1) -> Double? { value(index).flatMap(Double.init) }
    public static func parse(_ text: String) throws -> SExpression {
        guard text.utf8.count <= 32 * 1024 * 1024 else { throw EDAError.invalid("预览文件超过 32 MB，请使用 KiCad 编辑器") }
        let chars = Array(text); var index = 0
        func whitespace() { while index < chars.count && chars[index].isWhitespace { index += 1 } }
        func read(_ depth: Int) throws -> SExpression {
            guard depth < 128 else { throw EDAError.invalid("S-expression 嵌套过深") }
            whitespace()
            guard index < chars.count else { throw EDAError.invalid("S-expression 意外结束") }
            if chars[index] == "(" {
                index += 1; var children = [SExpression]()
                while true {
                    whitespace()
                    guard index < chars.count else { throw EDAError.invalid("缺少右括号") }
                    if chars[index] == ")" { index += 1; return .list(children) }
                    children.append(try read(depth + 1))
                }
            }
            if chars[index] == "\"" {
                index += 1; var result = ""
                while index < chars.count {
                    let ch = chars[index]; index += 1
                    if ch == "\"" { return .atom(result) }
                    if ch == "\\" {
                        guard index < chars.count else { throw EDAError.invalid("无效转义") }
                        let next = chars[index]; index += 1
                        result.append(next == "n" ? "\n" : next == "r" ? "\r" : next == "t" ? "\t" : next)
                    } else { result.append(ch) }
                }
                throw EDAError.invalid("字符串未闭合")
            }
            let start = index
            while index < chars.count && !chars[index].isWhitespace && chars[index] != "(" && chars[index] != ")" { index += 1 }
            guard index > start else { throw EDAError.invalid("意外的右括号") }
            return .atom(String(chars[start..<index]))
        }
        let expression = try read(0); whitespace()
        guard index == chars.count else { throw EDAError.invalid("S-expression 存在多余内容") }
        return expression
    }
}

public struct BoardPoint { public var x: Double; public var y: Double }
public struct BoardLine: Identifiable {
    public let id: Int; public let start: BoardPoint; public let end: BoardPoint; public let width: Double; public let layer: String
}
public struct BoardPad: Identifiable {
    public let id: Int; public let center: BoardPoint; public let width: Double; public let height: Double; public let angle: Double; public let label: String
}
public struct BoardPreview {
    public let lines: [BoardLine]
    public let pads: [BoardPad]
    public let copperLayers: [String]
    public let references: [String]
    public init(contents: String) throws {
        let tree = try SExpression.parse(contents)
        guard tree.tag == "kicad_pcb" else { throw EDAError.invalid("不是 KiCad PCB 文件") }
        copperLayers = (tree.child("layers")?.items.dropFirst() ?? []).compactMap { node in
            guard let name = node.value(), name.hasSuffix(".Cu") else { return nil }; return name
        }
        var lines = [BoardLine](), pads = [BoardPad](), references = [String]()
        for node in tree.items where ["segment", "gr_line"].contains(node.tag ?? "") {
            guard let start = node.child("start"), let end = node.child("end"),
                  let x1 = start.number(), let y1 = start.number(2), let x2 = end.number(), let y2 = end.number(2) else { continue }
            lines.append(BoardLine(id: lines.count, start: .init(x: x1, y: y1), end: .init(x: x2, y: y2),
                width: node.child("width")?.number() ?? node.child("stroke")?.child("width")?.number() ?? 0.15,
                layer: node.child("layer")?.value() ?? "F.Cu"))
        }
        for fp in tree.children("footprint") {
            let fx = fp.child("at")?.number() ?? 0, fy = fp.child("at")?.number(2) ?? 0
            let angle = fp.child("at")?.number(3) ?? 0, rad = angle * .pi / 180
            let reference = fp.children("property").first(where: { $0.value() == "Reference" })?.value(2)
                ?? fp.children("fp_text").first(where: { $0.value() == "reference" })?.value(2) ?? "?"
            references.append(reference)
            for pad in fp.children("pad") {
                let x = pad.child("at")?.number() ?? 0, y = pad.child("at")?.number(2) ?? 0
                let width = pad.child("size")?.number() ?? 1, height = pad.child("size")?.number(2) ?? 1
                pads.append(BoardPad(id: pads.count, center: .init(x: fx + x * cos(rad) + y * sin(rad), y: fy - x * sin(rad) + y * cos(rad)),
                    width: width, height: height, angle: angle + (pad.child("at")?.number(3) ?? 0), label: "\(reference).\(pad.value() ?? "")"))
            }
        }
        guard lines.allSatisfy({ [$0.start.x, $0.start.y, $0.end.x, $0.end.y, $0.width].allSatisfy(\.isFinite) && $0.width > 0 }),
              pads.allSatisfy({ [$0.center.x, $0.center.y, $0.width, $0.height, $0.angle].allSatisfy(\.isFinite) && $0.width > 0 && $0.height > 0 }) else {
            throw EDAError.invalid("PCB 预览包含无效或非有限几何数值")
        }
        self.lines = lines; self.pads = pads; self.references = references.sorted()
    }
}
