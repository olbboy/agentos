import Foundation
import SwiftUI
import AgeOSCore

/// Mức nghiêm trọng của một finding. Thứ tự khai báo = thứ tự ưu tiên hiển thị.
enum DiagnosticSeverity: Int, CaseIterable, Comparable {
    case error = 0, warning = 1, info = 2

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .error:   "Errors"
        case .warning: "Warnings"
        case .info:    "Info"
        }
    }

    /// Câu hiện khi nhóm rỗng. Nói "đã kiểm và sạch", khác hẳn với "chưa kiểm".
    var emptyMessage: LocalizedStringKey {
        switch self {
        case .error:   "No errors"
        case .warning: "No warnings"
        case .info:    "No suggestions"
        }
    }

    var tone: PillTone {
        switch self {
        case .error:   .danger
        case .warning: .warning
        case .info:    .info
        }
    }
}

/// Một finding đã chuẩn hoá từ mọi nguồn (Doctor, ScanEngine, inventory) về cùng
/// một hình dạng.
///
/// Vì sao gom lại: với người dùng, "có gì sai không" là MỘT câu hỏi. Giữ Doctor và
/// Scan làm hai mô hình riêng bắt họ tự nhớ cái nào tìm được cái gì.
struct DiagnosticItem: Identifiable {
    /// Cái gì sinh ra finding này. View đọc `source` để quyết định gắn action nào —
    /// closure không sống được trong model thuần, nên model chỉ mang dữ liệu.
    enum Source {
        case doctor(Doctor.Finding)
        case exactDupe(DedupeEngine.DupePair)
        case nearDupe(DedupeEngine.DupePair)
        case deprecated(ScanEngine.ScanReport.DeprecatedItem)
        case lint(skillId: String, finding: DescriptionLinter.Finding)
        case duplicatePath(adapterId: String, name: String, paths: [String])
        /// Một phần của lần quét KHÔNG chạy được (ví dụ máy thiếu embedding assets).
        /// Phải nói ra, vì "không kiểm được" khác hẳn "kiểm rồi và sạch".
        case scanNote(String)
    }

    let id: String
    let severity: DiagnosticSeverity
    let message: String
    /// Dòng phụ: path hoặc id. Dữ liệu, không phải văn xuôi.
    let detail: String?
    let status: LocalizedStringKey
    let source: Source
}

extension DiagnosticSeverity {
    /// Ánh xạ `Doctor.Kind` sang severity.
    ///
    /// KHÔNG có `default` — có chủ ý. Nếu core thêm một `Kind` mới, compiler bắt
    /// ngay tại đây; với `default` thì finding mới sẽ âm thầm rơi vào một nhóm sai.
    /// Đây là hàng rào rẻ nhất có thể dựng.
    static func of(_ kind: Doctor.Finding.Kind) -> DiagnosticSeverity {
        switch kind {
        // Phân phối đang hỏng thật — agent không load được skill.
        case .brokenLink, .missingTarget, .storeMissing, .adapterUnknown:
            .error
        // Lệch trạng thái: chưa hỏng, nhưng sẽ gây bất ngờ.
        case .copyDrift, .orphanFile, .agentPathMissing, .userShadow:
            .warning
        }
    }
}

/// Gom mọi nguồn finding thành một danh sách đã phân loại.
///
/// Là hàm thuần (không đọc `AppModel`) để test được, và để Overview với Diagnostics
/// dùng chung đúng một phép đếm — hai màn tự tổng hợp riêng là cách chắc chắn nhất
/// để chúng báo hai con số khác nhau.
enum DiagnosticsBuilder {

    /// RANH GIỚI dịch thuật ở đây:
    ///
    /// - Thông điệp do **app** viết → `String(localized:)`, vào String Catalog.
    /// - Thông điệp do **core** phát (`Doctor.Finding.message`, lint message,
    ///   `ScanReport.notes`) → đi thẳng, KHÔNG bọc. Chúng là dữ liệu chạy qua, và
    ///   core không có hạ tầng i18n; bọc chúng chỉ tạo ra hàng trăm key rác trong
    ///   catalog mà không key nào dịch được vì nội dung sinh lúc chạy.
    static func build(doctorFindings: [Doctor.Finding],
                      scanReport: ScanEngine.ScanReport?,
                      inventory: EffectiveLoadScanner.Inventory?) -> [DiagnosticItem] {
        var items: [DiagnosticItem] = []

        for (i, f) in doctorFindings.enumerated() {
            items.append(DiagnosticItem(
                id: "doctor-\(i)-\(f.kind.rawValue)",
                severity: .of(f.kind),
                message: f.message,
                detail: f.path.isEmpty ? f.skillId : f.path,
                // "Fixable" nghĩa là CTA toàn màn sửa được, KHÔNG phải nút của dòng này.
                status: f.fixed ? "Fixed" : (f.fixable ? "Fixable" : "No automatic fix"),
                source: .doctor(f)))
        }

        if let report = scanReport {
            for (i, p) in report.exactDupes.enumerated() {
                items.append(DiagnosticItem(
                    id: "exact-\(i)",
                    // Hai bản y hệt nhau thì chắc chắn đang lãng phí, không phải "có thể".
                    severity: .error,
                    message: String(localized: "Exact duplicate: the same skill exists twice"),
                    detail: "\(p.a)  ·  \(p.b)",
                    status: "No automatic fix",
                    source: .exactDupe(p)))
            }
            for (i, p) in report.nearDupes.enumerated() {
                let score = String(format: "%.2f", p.score)
                items.append(DiagnosticItem(
                    id: "near-\(i)",
                    severity: .warning,
                    message: String(localized: "Near duplicate (cosine \(score))"),
                    detail: "\(p.a)  ·  \(p.b)",
                    status: "No automatic fix",
                    source: .nearDupe(p)))
            }
            for item in report.deprecated {
                items.append(DiagnosticItem(
                    id: "deprecated-\(item.id)",
                    severity: .warning,
                    message: String(localized: "Marked deprecated: \(item.reason)"),
                    detail: item.id,
                    status: "Action required",
                    source: .deprecated(item)))
            }
            for lint in report.lintFindings {
                for f in lint.findings {
                    items.append(DiagnosticItem(
                        id: "lint-\(lint.id)-\(f.rule.rawValue)",
                        // Gợi ý chất lượng mô tả — không ảnh hưởng vận hành.
                        severity: .info,
                        message: f.message,
                        detail: lint.id,
                        status: "No automatic fix",
                        source: .lint(skillId: lint.id, finding: f)))
                }
            }
        }

        // Ghi chú của lần quét — thường là "phần này không chạy được trên máy bạn".
        // KHÔNG được bỏ qua: nếu near-dupe không chạy mà màn hình vẫn báo "No
        // warnings" thì người dùng tin là đã kiểm sạch, trong khi phép kiểm chưa
        // từng chạy. Đó là nói dối bằng cách im lặng.
        if let report = scanReport {
            for (i, note) in report.notes.enumerated() {
                items.append(DiagnosticItem(
                    id: "note-\(i)",
                    severity: .warning,
                    message: note,
                    detail: nil,
                    status: "Not checked",
                    source: .scanNote(note)))
            }
            if !report.nearDupeAvailable && report.notes.isEmpty {
                items.append(DiagnosticItem(
                    id: "note-neardupe",
                    severity: .warning,
                    message: String(localized: "Near-duplicate detection did not run on this machine — only exact duplicates were checked"),
                    detail: nil,
                    status: "Not checked",
                    source: .scanNote("nearDupeUnavailable")))
            }
        }

        if let inventory {
            for agent in inventory.agents {
                for (name, paths) in agent.duplicated.sorted(by: { $0.key < $1.key }) {
                    items.append(DiagnosticItem(
                        id: "duppath-\(agent.adapterId)-\(name)",
                        severity: .warning,
                        message: String(localized: "'\(name)' is loaded from \(paths.count) paths in \(agent.adapterId)"),
                        detail: paths.joined(separator: "  ·  "),
                        status: "Action required",
                        source: .duplicatePath(adapterId: agent.adapterId,
                                               name: name, paths: paths)))
                }
            }
        }

        return items
    }
}
