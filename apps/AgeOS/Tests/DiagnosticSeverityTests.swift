import Foundation
import Testing
import AgeOSCore
@testable import AgeOS

/// Dựng fixture bằng cách decode JSON thay vì gọi init.
///
/// Lý do: `public struct` trong Swift KHÔNG tự có memberwise init public — chỉ có
/// internal. Từ module app ta chỉ thấy `init(from:)` do Codable sinh ra. Thêm init
/// public vào core sẽ mở rộng API surface, mà ràng buộc của plan chỉ cho đúng một
/// ngoại lệ (`BudgetMeter.skillTokens`). Decode JSON tôn trọng ranh giới đó, và
/// tiện thể khoá luôn hình dạng `--json` — test sẽ đỏ nếu key đổi tên.
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

    @Test("Bốn Kind nghĩa là phân phối đang hỏng → Error")
    func brokenDistributionIsError() {
        for kind: Doctor.Finding.Kind in [.brokenLink, .missingTarget, .storeMissing, .adapterUnknown] {
            #expect(DiagnosticSeverity.of(kind) == .error, "\(kind.rawValue) phải là error")
        }
    }

    @Test("Bốn Kind nghĩa là trạng thái lệch → Warning")
    func driftIsWarning() {
        for kind: Doctor.Finding.Kind in [.copyDrift, .orphanFile, .agentPathMissing, .userShadow] {
            #expect(DiagnosticSeverity.of(kind) == .warning, "\(kind.rawValue) phải là warning")
        }
    }

    /// `switch` trong `DiagnosticSeverity.of` không có `default`, nên nếu core thêm
    /// `Kind` mới thì compiler chặn trước. Test này là hàng rào thứ hai: nó bắt
    /// trường hợp ai đó "sửa lỗi build" bằng cách thêm `default` cho nhanh.
    @Test("Đúng 8 Kind, mỗi cái map ra một severity xác định")
    func everyKindIsMapped() {
        let all: [Doctor.Finding.Kind] = [
            .brokenLink, .missingTarget, .copyDrift, .orphanFile,
            .agentPathMissing, .userShadow, .storeMissing, .adapterUnknown,
        ]
        #expect(all.count == 8, "Core đã đổi số lượng Kind — cập nhật bảng severity")
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

    @Test("Không có nguồn nào thì không sinh finding nào")
    func emptyInputsProduceNothing() {
        let items = DiagnosticsBuilder.build(doctorFindings: [], scanReport: nil, inventory: nil)
        #expect(items.isEmpty)
    }

    @Test("Exact dupe là Error, near dupe và deprecated là Warning, lint là Info")
    func scanSourcesLandInTheRightGroups() throws {
        let report = try decode(ScanEngine.ScanReport.self, fullScanReport)
        let items = DiagnosticsBuilder.build(doctorFindings: [], scanReport: report, inventory: nil)

        #expect(items.filter { $0.severity == .error }.count == 1)
        #expect(items.filter { $0.severity == .warning }.count == 2)
        #expect(items.filter { $0.severity == .info }.count == 1)
    }

    @Test("Finding đã sửa mang trạng thái Fixed, không phải Fixable")
    func fixedFindingsSaySo() throws {
        let items = DiagnosticsBuilder.build(
            doctorFindings: [try doctorFinding(kind: "broken_link", fixable: true, fixed: true)],
            scanReport: nil, inventory: nil)
        #expect(items.count == 1)
        #expect(items[0].status == "Fixed")
    }

    @Test("Finding không sửa tự động được thì nói thẳng, không để trống")
    func unfixableSaysSo() throws {
        let items = DiagnosticsBuilder.build(
            doctorFindings: [try doctorFinding(kind: "user_shadow", fixable: false)],
            scanReport: nil, inventory: nil)
        #expect(items[0].status == "No automatic fix")
    }

    @Test("Mỗi id là duy nhất — id trùng làm ForEach dựng sai danh sách")
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

    @Test("Duplicate load path từ inventory rơi vào Warning")
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

    @Test("Ba nguồn cùng lúc: tổng đếm khớp, không nguồn nào bị nuốt")
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
