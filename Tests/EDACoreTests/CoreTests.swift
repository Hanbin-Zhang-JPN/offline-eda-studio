import Foundation
import EDACore

final class CoreTests {
    var scratch: URL!
    func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory.appendingPathComponent("eda-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }
    func tearDownWithError() throws { try FileManager.default.removeItem(at: scratch) }
    func project() throws -> EDAProject {
        try JSONFile.write(ProjectManifest(name: "Fixture"), to: scratch.appendingPathComponent("eda-project.json"))
        try Data("original".utf8).write(to: scratch.appendingPathComponent("design.kicad_pcb"))
        return try EDAProject(root: scratch)
    }
    func testPathTraversalRejected() throws {
        let project = try project()
        expectThrows(try project.file("../outside"))
        expectThrows(try project.file("/private/tmp/outside"))
        expectEqual(try project.file("sub/data.json").path, scratch.appendingPathComponent("sub/data.json").path)
    }
    func testSymlinkEscapeRejected() throws {
        let project = try project()
        try FileManager.default.createSymbolicLink(at: scratch.appendingPathComponent("link"), withDestinationURL: URL(fileURLWithPath: "/private/tmp"))
        expectThrows(try project.file("link/escape"))
        expectThrows(try ProjectFiles.snapshot(project, label: "Unsafe"))
    }
    func testUnsupportedManifestRejected() throws {
        var manifest = ProjectManifest(name: "test"); manifest.schemaVersion = 99
        try JSONFile.write(manifest, to: scratch.appendingPathComponent("eda-project.json"))
        expectThrows(try EDAProject(root: scratch))
    }
    func testCreateNeverOverwritesDirectory() throws {
        expectThrows(try EDAProject.create(at: scratch, name: "test", template: scratch))
    }
    func testSnapshotDetectsTampering() throws {
        let project = try project()
        let url = try ProjectFiles.snapshot(project, label: "Original")
        expectTrue(try ProjectFiles.verifySnapshot(at: url))
        try Data("modified".utf8).write(to: url.appendingPathComponent("source/design.kicad_pcb"))
        expectFalse(try ProjectFiles.verifySnapshot(at: url))
        expectEqual(try String(contentsOf: project.file("design.kicad_pcb")), "original")
    }
    func testSnapshotsExcludeOutputsAndPreviousSnapshots() throws {
        let project = try project()
        try FileManager.default.createDirectory(at: scratch.appendingPathComponent("outputs"), withIntermediateDirectories: true)
        try Data("generated".utf8).write(to: scratch.appendingPathComponent("outputs/foo"))
        _ = try ProjectFiles.snapshot(project, label: "One")
        let second = try ProjectFiles.snapshot(project, label: "Two")
        let files = try ProjectFiles.digests(in: second.appendingPathComponent("source"))
        expectEqual(files.count, 2)
        expectFalse(files.contains { $0.path.hasPrefix("outputs") || $0.path.contains(".eda-snapshots") })
    }
    func testBOMGroupIdentityAndDNP() throws {
        let parts = [Component(reference: "R10", value: "10k", footprint: "0603", unitPrice: 0.01),
                     Component(reference: "R2", value: "10k", footprint: "0603", unitPrice: 0.01),
                     Component(reference: "R3", value: "10k", footprint: "0603", unitPrice: 0.02),
                     Component(reference: "R4", value: "10k", footprint: "0603", unitPrice: 0.01, dnp: true)]
        let rows = try BOM.grouped(parts)
        expectEqual(rows.count, 2); expectEqual(rows[0].references, ["R2", "R10"])
        expectEqual(rows[0].extendedPrice, 0.02, accuracy: 0.0001)
        expectEqual(try BOM.grouped(parts, includeDNP: true).count, 3)
    }
    func testBOMDuplicateAndInvalidPriceRejected() {
        expectThrows(try BOM.validate([Component(reference: "R1", value: "", footprint: ""), Component(reference: "r1", value: "", footprint: "")]))
        expectThrows(try BOM.validate([Component(reference: "R1", value: "", footprint: "", unitPrice: -.infinity)]))
        expectThrows(try BOM.validate([Component(reference: "wrong", value: "", footprint: "")]))
    }
    func testCSVEscapesQuotesAndNeutralizesFormula() {
        let csv = CSV.encode([["comma,field", "quote\"field", "two\nlines", "=1+2"]])
        expectEqual(csv, "\"comma,field\",\"quote\"\"field\",\"two\nlines\",\"'=1+2\"\r\n")
    }
    func testHarnessChecksUnknownAndDuplicatePins() {
        let h = Harness(connectors: [Connector(id: "J1", pins: 2), Connector(id: "J2", pins: 2)], wires: [
            HarnessWire(id: "W1", from: .init("J1", 1), to: .init("J2", 1), net: "VCC", lengthMM: 100),
            HarnessWire(id: "W2", from: .init("J1", 1), to: .init("unknown", 9), net: "GND", lengthMM: -1)])
        let issues = h.validate()
        expectTrue(issues.contains { $0.contains("重复占用") })
        expectTrue(issues.contains { $0.contains("未知连接器") })
        expectTrue(issues.contains { $0.contains("长度") })
        expectThrows(try h.cutListCSV())
    }
    func testHarnessGoodCutList() throws {
        let h = Harness(connectors: [Connector(id: "J1", pins: 2), Connector(id: "J2", pins: 2)], wires: [HarnessWire(id: "W1", from: .init("J1", 2), to: .init("J2", 2), net: "GND", lengthMM: 150)])
        expectTrue(h.validate().isEmpty)
        expectTrue(try h.cutListCSV().contains("J1:2"))
    }
    func testMicrostripReferenceAndInputs() throws {
        expectEqual(try Engineering.microstrip(widthMM: 0.18, heightMM: 0.18, er: 4.2), 72.572548, accuracy: 0.01)
        expectThrows(try Engineering.microstrip(widthMM: 0, heightMM: 0.18, er: 4.2))
        expectThrows(try Engineering.microstrip(widthMM: 0.18, heightMM: .nan, er: 4.2))
    }
    func testSExpressionEscapesAndMalformedInput() throws {
        expectEqual(try SExpression.parse("(root (name \"a\\\"b\"))").child("name")?.value(), "a\"b")
        expectThrows(try SExpression.parse("(root (missing)"))
        expectThrows(try SExpression.parse("(root) trailing"))
        expectThrows(try SExpression.parse(String(repeating: "(", count: 130) + "x" + String(repeating: ")", count: 130)))
    }
    func testPreviewUsesActualGeometry() throws {
        let board = try BoardPreview(contents: "(kicad_pcb (layers (0 \"F.Cu\" signal) (2 \"B.Cu\" signal)) (segment (start 1 2) (end 3 4) (width 0.4) (layer \"F.Cu\")))")
        expectEqual(board.copperLayers, ["F.Cu", "B.Cu"])
        expectEqual(board.lines[0].end.x, 3)
        expectThrows(try BoardPreview(contents: "(kicad_pcb (segment (start nan 2) (end 3 4) (width 0.4) (layer \"F.Cu\")))"))
    }
    func testProcessCapturesLargeOutputWithoutDeadlock() throws {
        let engine = KiCadEngine(executable: URL(fileURLWithPath: "/usr/bin/perl"), timeout: 5)
        let result = try engine.run(["-e", "print 'x' x 200000; print STDERR 'bad'; exit 3;"])
        expectEqual(result.stdout.count, 200000); expectEqual(result.stderr, "bad"); expectEqual(result.exitCode, 3)
    }
    func testProcessTimeout() {
        let engine = KiCadEngine(executable: URL(fileURLWithPath: "/bin/sleep"), timeout: 0.05)
        expectThrows(try engine.run(["2"]))
    }
    func testExplicitMissingEngineNeverFallsBack() {
        expectNil(KiCadEngine.discover(explicit: "/does/not/exist"))
    }
    func testReportsRejectFalseSuccess() throws {
        expectThrows(try CheckReport.requireClean(Data("{}".utf8), job: .drc))
        let base: [String: Any] = ["$schema": "https://schemas.kicad.org/drc.v1.json", "kicad_version": "10.0.6", "violations": [], "unconnected_items": [], "schematic_parity": []]
        try CheckReport.requireClean(JSONSerialization.data(withJSONObject: base), job: .drc)
        var bad = base; bad["unconnected_items"] = [["type": "unconnected"]]
        expectThrows(try CheckReport.requireClean(JSONSerialization.data(withJSONObject: bad), job: .drc))
    }
}
