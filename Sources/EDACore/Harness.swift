import Foundation

public struct Connector: Codable, Equatable, Identifiable {
    public var id: String
    public var pins: Int
    public var partNumber: String
    public init(id: String, pins: Int, partNumber: String = "") { self.id = id; self.pins = pins; self.partNumber = partNumber }
}
public struct HarnessEndpoint: Codable, Equatable, Hashable {
    public var connector: String
    public var pin: Int
    public init(_ connector: String, _ pin: Int) { self.connector = connector; self.pin = pin }
    public var label: String { "\(connector):\(pin)" }
}
public struct HarnessWire: Codable, Equatable, Identifiable {
    public var id: String
    public var from: HarnessEndpoint
    public var to: HarnessEndpoint
    public var net: String
    public var lengthMM: Double
    public var awg: Int
    public var color: String
    public init(id: String, from: HarnessEndpoint, to: HarnessEndpoint, net: String, lengthMM: Double, awg: Int = 24, color: String = "black") {
        self.id = id; self.from = from; self.to = to; self.net = net; self.lengthMM = lengthMM; self.awg = awg; self.color = color
    }
}
public struct Harness: Codable, Equatable {
    public var schemaVersion: Int
    public var connectors: [Connector]
    public var wires: [HarnessWire]
    public init(connectors: [Connector], wires: [HarnessWire]) { schemaVersion = 1; self.connectors = connectors; self.wires = wires }
    public func validate() -> [String] {
        var issues = [String](), map = [String: Connector](), used = Set<HarnessEndpoint>(), ids = Set<String>()
        if schemaVersion != 1 { issues.append("不支持的线束格式版本") }
        for connector in connectors {
            if connector.id.isEmpty || connector.pins < 1 || map[connector.id] != nil { issues.append("无效或重复连接器：\(connector.id)") }
            map[connector.id] = connector
        }
        for wire in wires {
            if wire.id.isEmpty || !ids.insert(wire.id).inserted { issues.append("重复或空导线 ID：\(wire.id)") }
            if wire.net.isEmpty { issues.append("\(wire.id)：网络名称为空") }
            if !wire.lengthMM.isFinite || wire.lengthMM <= 0 || !(0...40).contains(wire.awg) { issues.append("\(wire.id)：长度或 AWG 无效") }
            if wire.from == wire.to { issues.append("\(wire.id)：导线两端相同") }
            for endpoint in [wire.from, wire.to] {
                if let connector = map[endpoint.connector] {
                    if !(1...max(1, connector.pins)).contains(endpoint.pin) { issues.append("\(wire.id)：引脚越界 \(endpoint.label)") }
                } else { issues.append("\(wire.id)：未知连接器 \(endpoint.connector)") }
                if !used.insert(endpoint).inserted { issues.append("\(wire.id)：引脚重复占用 \(endpoint.label)，v1 不支持分支压接") }
            }
        }
        return issues
    }
    public func cutListCSV() throws -> String {
        let issues = validate()
        guard issues.isEmpty else { throw EDAError.invalid(issues.joined(separator: "\n")) }
        return CSV.encode([["Wire", "Net", "From", "To", "LengthMM", "AWG", "Color"]] + wires.map {
            [$0.id, $0.net, $0.from.label, $0.to.label, String($0.lengthMM), String($0.awg), $0.color]
        })
    }
}

public enum Engineering {
    /// Thin-conductor microstrip, quasi-static approximation; no soldermask or copper correction.
    public static func microstrip(widthMM: Double, heightMM: Double, er: Double) throws -> Double {
        guard widthMM.isFinite, heightMM.isFinite, er.isFinite, widthMM > 0, heightMM > 0, er >= 1 else {
            throw EDAError.invalid("线宽、介质厚度必须大于零，介电常数必须 ≥ 1")
        }
        let u = widthMM / heightMM
        let correction = u < 1 ? 0.04 * pow(1 - u, 2) : 0
        let effective = (er + 1) / 2 + (er - 1) / 2 * (1 / sqrt(1 + 12 / u) + correction)
        if u <= 1 { return 60 / sqrt(effective) * log(8 / u + u / 4) }
        return 120 * Double.pi / (sqrt(effective) * (u + 1.393 + 0.667 * log(u + 1.444)))
    }
}
