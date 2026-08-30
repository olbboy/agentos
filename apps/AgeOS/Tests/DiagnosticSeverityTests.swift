import Foundation
import Testing
import AgeOSCore
@testable import AgeOS

/// Fixtures are decoded from JSON rather than built with an initializer.
///
/// The reason: a `public struct` in Swift gets no public memberwise init — only an
/// internal one. From the app module the only visible initializer is the `init(from:)`
/// Codable synthesizes. Adding a public init to core would widen its API surface, and
/// the plan allows exactly one such exception (`BudgetMeter.skillTokens`). Decoding
/// respects that boundary and, as a bonus, pins the `--json` shape — these tests fail
/// if a key is renamed.
private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
    try JSONDecoder().decode(T.self, from: Data(json.utf8))
}

private func doctorFinding(kind: String, fixable: Bool = true,
                           fixed: Bool = false, path: String = "/tmp/thing") throws -> Doctor.Finding {
    try decode(Doctor.Finding.self, """
    {"kind":"\(kind)","skillId":"acme/repo/thing","targetKey":"claude-code@global",
     "path":"\(path)","message":"something happened","fixable":\(fixable),"fixed":\(fixed)}
    """)
}

@Suite("Diagnostic severity mapping")
struct DiagnosticSeverityMappingTests {

    @Test("Four kinds mean distribution is genuinely broken → Error")
    func brokenDistributionIsError() {
        for kind: Doctor.Finding.Kind in [.brokenLink, .missingTarget, .storeMissing, .adapterUnknown] {
            #expect(DiagnosticSeverity.of(kind) == .error, "\(kind.rawValue) should be an error")
        }
    }

    @Test("Four kinds mean state has drifted → Warning")
    func driftIsWarning() {
        for kind: Doctor.Finding.Kind in [.copyDrift, .orphanFile, .agentPathMissing, .userShadow] {
            #expect(DiagnosticSeverity.of(kind) == .warning, "\(kind.rawValue) should be a warning")
        }
    }

    /// The `switch` in `DiagnosticSeverity.of` has no `default`, so a new kind in core
    /// stops the compiler first. This test is the second fence: it catches someone
    /// "fixing the build" by reaching for a `default`.
    @Test("Exactly 8 kinds, each mapping to a definite severity")
    func everyKindIsMapped() {
        let all: [Doctor.Finding.Kind] = [
            .brokenLink, .missingTarget, .copyDrift, .orphanFile,
            .agentPathMissing, .userShadow, .storeMissing, .adapterUnknown,
        ]
        #expect(all.count == 8, "Core changed the number of kinds — update the severity table")
        for kind in all {
            let severity = DiagnosticSeverity.of(kind)
            #expect(severity == .error || severity == .warning)
        }
    }
}

@Suite("Diagnostics builder")
struct DiagnosticsBuilderTests {

    private var fullScanReport: String {
        """
        {"scannedSkills":3,
         "exactDupes":[{"kind":"exact","a":"a","b":"b","score":1.0}],
         "nearDupes":[{"kind":"near","a":"c","b":"d","score":0.81}],
         "nearDupeAvailable":true,
         "deprecated":[{"id":"acme/repo/old","reason":"source archived"}],
         "lintFindings":[{"id":"acme/repo/thing",
                          "findings":[{"rule":"too_short","message":"too short"}]}],
         "notes":[]}
        """
    }

    @Test("No sources produce no findings")
    func emptyInputsProduceNothing() {
        let items = DiagnosticsBuilder.build(doctorFindings: [], scanReport: nil, inventory: nil)
        #expect(items.isEmpty)
    }

    @Test("Exact duplicates are Errors, near duplicates and deprecation are Warnings, lint is Info")
    func scanSourcesLandInTheRightGroups() throws {
        let report = try decode(ScanEngine.ScanReport.self, fullScanReport)
        let items = DiagnosticsBuilder.build(doctorFindings: [], scanReport: report, inventory: nil)

        #expect(items.filter { $0.severity == .error }.count == 1)
        #expect(items.filter { $0.severity == .warning }.count == 2)
        #expect(items.filter { $0.severity == .info }.count == 1)
    }

    @Test("An already-repaired finding reads Fixed, not Fixable")
    func fixedFindingsSaySo() throws {
        let items = DiagnosticsBuilder.build(
            doctorFindings: [try doctorFinding(kind: "broken_link", fixable: true, fixed: true)],
            scanReport: nil, inventory: nil)
        #expect(items.count == 1)
        #expect(items[0].status == "Fixed")
    }

    @Test("A finding with no automatic fix says so rather than leaving a blank")
    func unfixableSaysSo() throws {
        let items = DiagnosticsBuilder.build(
            doctorFindings: [try doctorFinding(kind: "user_shadow", fixable: false)],
            scanReport: nil, inventory: nil)
        #expect(items[0].status == "No automatic fix")
    }

    @Test("Every id is unique — duplicates make ForEach build the wrong list")
    func idsAreUnique() throws {
        let report = try decode(ScanEngine.ScanReport.self, """
        {"scannedSkills":2,
         "exactDupes":[{"kind":"exact","a":"a","b":"b","score":1.0},
                       {"kind":"exact","a":"c","b":"d","score":1.0}],
         "nearDupes":[],"nearDupeAvailable":true,"deprecated":[],
         "lintFindings":[{"id":"x","findings":[{"rule":"too_short","message":"m1"},
                                               {"rule":"too_long","message":"m2"}]}],
         "notes":[]}
        """)
        let items = DiagnosticsBuilder.build(
            doctorFindings: [try doctorFinding(kind: "broken_link", path: "/a"),
                             try doctorFinding(kind: "copy_drift", path: "/b")],
            scanReport: report, inventory: nil)

        #expect(Set(items.map(\.id)).count == items.count)
    }

    @Test("Duplicate load paths from the inventory land in Warning")
    func duplicatePathsAreWarnings() throws {
        let inventory = try decode(EffectiveLoadScanner.Inventory.self, """
        {"agents":[{"adapterId":"claude-code","entries":[],
                    "duplicated":{"pdf":["/a/pdf","/b/pdf"]}}],
         "byName":{},"totalDistinctSkills":1,"totalLoadEntries":2}
        """)
        let items = DiagnosticsBuilder.build(doctorFindings: [], scanReport: nil,
                                             inventory: inventory)
        #expect(items.count == 1)
        #expect(items[0].severity == .warning)
        #expect(items[0].message.contains("2 paths"))
    }

    @Test("All three sources at once: the totals add up and nothing is swallowed")
    func allSourcesCombine() throws {
        let report = try decode(ScanEngine.ScanReport.self, fullScanReport)
        let inventory = try decode(EffectiveLoadScanner.Inventory.self, """
        {"agents":[{"adapterId":"codex","entries":[],
                    "duplicated":{"pdf":["/a/pdf","/b/pdf"]}}],
         "byName":{},"totalDistinctSkills":1,"totalLoadEntries":2}
        """)
        let items = DiagnosticsBuilder.build(
            doctorFindings: [try doctorFinding(kind: "broken_link"),
                             try doctorFinding(kind: "copy_drift", path: "/other")],
            scanReport: report, inventory: inventory)

        // 1 doctor error + 1 exact dupe
        #expect(items.filter { $0.severity == .error }.count == 2)
        // 1 doctor drift + 1 near dupe + 1 deprecated + 1 duplicate path
        #expect(items.filter { $0.severity == .warning }.count == 4)
        #expect(items.filter { $0.severity == .info }.count == 1)
        #expect(items.count == 7)
    }
}
