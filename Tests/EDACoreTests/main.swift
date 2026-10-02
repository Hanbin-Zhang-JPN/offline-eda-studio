import Foundation
import EDACore

var assertionFailures = [String]()
func failure(_ message: String, _ file: StaticString, _ line: UInt) { assertionFailures.append("\(file):\(line): \(message)") }
func expectTrue(_ value: Bool, file: StaticString = #fileID, line: UInt = #line) { if !value { failure("Expected true", file, line) } }
func expectFalse(_ value: Bool, file: StaticString = #fileID, line: UInt = #line) { if value { failure("Expected false", file, line) } }
func expectEqual<T: Equatable>(_ actual: T, _ expected: T, file: StaticString = #fileID, line: UInt = #line) { if actual != expected { failure("Expected \(expected), got \(actual)", file, line) } }
func expectEqual(_ actual: Double, _ expected: Double, accuracy: Double, file: StaticString = #fileID, line: UInt = #line) { if abs(actual - expected) > accuracy { failure("Expected \(expected), got \(actual)", file, line) } }
func expectNil<T>(_ value: T?, file: StaticString = #fileID, line: UInt = #line) { if value != nil { failure("Expected nil", file, line) } }
func expectThrows<T>(_ action: @autoclosure () throws -> T, file: StaticString = #fileID, line: UInt = #line) { do { _ = try action(); failure("Expected error", file, line) } catch {} }

let tests = CoreTests()
let cases: [(String, () throws -> Void)] = [
    ("testPathTraversalRejected", tests.testPathTraversalRejected),
    ("testSymlinkEscapeRejected", tests.testSymlinkEscapeRejected),
    ("testUnsupportedManifestRejected", tests.testUnsupportedManifestRejected),
    ("testCreateNeverOverwritesDirectory", tests.testCreateNeverOverwritesDirectory),
    ("testSnapshotDetectsTampering", tests.testSnapshotDetectsTampering),
    ("testSnapshotsExcludeOutputsAndPreviousSnapshots", tests.testSnapshotsExcludeOutputsAndPreviousSnapshots),
    ("testBOMGroupIdentityAndDNP", tests.testBOMGroupIdentityAndDNP),
    ("testBOMDuplicateAndInvalidPriceRejected", tests.testBOMDuplicateAndInvalidPriceRejected),
    ("testCSVEscapesQuotesAndNeutralizesFormula", tests.testCSVEscapesQuotesAndNeutralizesFormula),
    ("testHarnessChecksUnknownAndDuplicatePins", tests.testHarnessChecksUnknownAndDuplicatePins),
    ("testHarnessGoodCutList", tests.testHarnessGoodCutList),
    ("testMicrostripReferenceAndInputs", tests.testMicrostripReferenceAndInputs),
    ("testSExpressionEscapesAndMalformedInput", tests.testSExpressionEscapesAndMalformedInput),
    ("testPreviewUsesActualGeometry", tests.testPreviewUsesActualGeometry),
    ("testProcessCapturesLargeOutputWithoutDeadlock", tests.testProcessCapturesLargeOutputWithoutDeadlock),
    ("testProcessTimeout", tests.testProcessTimeout),
    ("testExplicitMissingEngineNeverFallsBack", tests.testExplicitMissingEngineNeverFallsBack),
    ("testReportsRejectFalseSuccess", tests.testReportsRejectFalseSuccess)
]
var results = [[String: Any]]()
for (name, action) in cases {
    let before = assertionFailures.count
    do { try tests.setUpWithError(); try action() } catch { assertionFailures.append("\(name): \(error)") }
    do { try tests.tearDownWithError() } catch { assertionFailures.append("Cleanup: \(error)") }
    let passed = assertionFailures.count == before
    print("\(passed ? "PASS" : "FAIL") \(name)")
    results.append(["name": name, "passed": passed])
}
let report: [String: Any] = ["schemaVersion": 1, "passed": assertionFailures.isEmpty, "tests": results, "failures": assertionFailures]
if let path = ProcessInfo.processInfo.environment["EDA_TEST_REPORT"] { try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: path), options: .atomic) }
for message in assertionFailures { print(message) }
print("\(cases.count) tests; \(assertionFailures.count) failures")
exit(assertionFailures.isEmpty ? 0 : 1)
