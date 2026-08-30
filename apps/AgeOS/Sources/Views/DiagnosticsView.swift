import SwiftUI
import AppKit
import AgeOSCore

/// Một màn duy nhất trả lời "có gì sai không", phân theo mức nghiêm trọng.
///
/// `doctor --fix` KHÔNG nằm trên toolbar. Nó là hành động phá huỷ duy nhất trong
/// app — đặt cạnh Scan và Rerun trên thanh công cụ là mời người ta bấm nhầm.
struct DiagnosticsView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmFix = false

    private func items(_ all: [DiagnosticItem], _ severity: DiagnosticSeverity) -> [DiagnosticItem] {
        all.filter { $0.severity == severity }
    }

    /// Số việc `doctor --fix` thực sự sẽ làm. Dùng cho cả nhãn nút lẫn confirm —
    /// một nguồn, nên hai chỗ không thể lệch nhau.
    private var fixableFindings: [Doctor.Finding] {
        model.doctorFindings.filter { $0.fixable && !$0.fixed }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                if model.hasRunDiagnostics {
                    // Đọc MỘT lần cho cả lần render. `diagnostics` với library ~100
                    // skill dễ lên 150-250 phần tử, và `body` chạy lại mỗi khi
                    // `busy` đổi — gọi lại property ở từng nhóm là phí thuần tuý.
                    let all = model.diagnostics
                    summaryBar
                    ForEach(DiagnosticSeverity.allCases, id: \.self) { severity in
                        group(severity, all)
                    }
                    methodNote
                    destructiveZone
                } else {
                    notCheckedYet
                }
            }
            .padding(Space.xxl)
        }
        .background(Color.ageSurface)
        .navigationTitle("Diagnostics")
        .confirmationDialog(fixDialogTitle, isPresented: $confirmFix, titleVisibility: .visible) {
            Button("Repair \(fixableFindings.count) findings", role: .destructive) {
                Task { await model.runDoctor(fix: true) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(verbatim: fixDialogDetail)
        }
    }

    // MARK: - Ba trạng thái tách bạch

    /// "Chưa quét" khác hẳn "quét rồi và sạch". Gộp hai cái thành một màn trống là
    /// bỏ mất thông tin người dùng cần.
    private var notCheckedYet: some View {
        SectionCard(title: "Not checked yet",
                    subtitle: "Diagnostics compares the lockfile against what is actually on disk, and scans every loaded skill for duplicates, deprecation and description problems.") {
            Button("Run diagnostics") {
                Task {
                    await model.runScan()
                    await model.runDoctor(fix: false)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.busy)
        }
    }

    private var summaryBar: some View {
        let s = model.attentionSummary
        return HStack(spacing: Space.md) {
            if s.errors + s.warnings + s.info == 0 {
                StatusPill("Everything healthy", tone: .success, icon: "checkmark.circle.fill")
            } else {
                StatusPill("\(s.errors) errors", tone: s.errors == 0 ? .neutral : .danger)
                StatusPill("\(s.warnings) warnings", tone: s.warnings == 0 ? .neutral : .warning)
                StatusPill("\(s.info) info", tone: s.info == 0 ? .neutral : .info)
            }
            Spacer()
            Button("Rerun scan") {
                Task {
                    await model.runScan()
                    await model.runDoctor(fix: false)
                }
            }
            .disabled(model.busy)
        }
    }

    // MARK: - Nhóm theo severity

    private func group(_ severity: DiagnosticSeverity, _ all: [DiagnosticItem]) -> some View {
        let rows = items(all, severity)
        return SectionCard(title: severity.title, count: rows.count) {
            if rows.isEmpty {
                // Thu gọn, KHÔNG ẩn: người dùng cần biết là đã kiểm và sạch.
                Text(severity.emptyMessage)
                    .font(.ageCallout)
                    .foregroundStyle(Color.ageTextSecondary)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { Divider().overlay(Color.ageBorderSubtle) }
                        FindingRow(severity: severity.tone,
                                   message: item.message,
                                   status: item.status,
                                   action: action(for: item),
                                   detail: item.detail)
                    }
                }
            }
        }
    }

    /// Hành động cho từng loại finding.
    ///
    /// Chỉ MỘT loại thực sự đổi trạng thái ở cấp dòng: "Disable everywhere" cho
    /// deprecated, vì `model.toggle` lọc được theo skill. Mọi thứ còn lại là điều
    /// hướng (Reveal, Compare) hoặc dồn vào CTA cuối màn — `Doctor.run(fix:)` là
    /// all-or-nothing, không nhận filter, nên một nút "Repair" cho riêng một dòng
    /// sẽ là lời nói dối.
    private func action(for item: DiagnosticItem) -> (title: LocalizedStringKey, run: () -> Void)? {
        switch item.source {
        case .doctor(let finding):
            guard !finding.path.isEmpty else { return nil }
            return ("Reveal in Finder", { reveal(finding.path) })

        case .exactDupe(let pair), .nearDupe(let pair):
            return ("Compare", { reveal(pair.a); reveal(pair.b) })

        case .deprecated(let deprecated):
            return ("Disable everywhere", {
                // Chặn bấm lần hai khi lần một chưa xong. Không có guard này, Task
                // thứ hai đọc `isEnabled` còn cũ, gọi disable cho adapter đã gỡ, và
                // `LinkEngine.disable` throw `.notFound` → banner báo lỗi giả cho
                // một thao tác thực chất đã thành công.
                guard !model.busy else { return }
                Task {
                    for adapter in model.matrixAdapters
                    where model.isEnabled(skillId: deprecated.id, adapterId: adapter.id) {
                        await model.toggle(skillId: deprecated.id,
                                           adapterId: adapter.id, enabled: false)
                    }
                }
            })

        case .duplicatePath(_, _, let paths):
            return ("Reveal in Finder", { paths.forEach(reveal) })

        // Máy không viết hộ được description — nói thẳng thay vì gắn nút giả.
        case .lint:
            return nil

        // Không phải một vấn đề để sửa, mà là một phép kiểm KHÔNG chạy được.
        case .scanNote:
            return nil
        }
    }

    private func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting(
            [URL(fileURLWithPath: (path as NSString).expandingTildeInPath)])
    }

    // MARK: - Ghi chú và vùng phá huỷ

    private var methodNote: some View {
        Text("Errors mean distribution is actually broken. Warnings mean state has drifted and will surprise you later. Info is description quality — it never affects whether a skill loads.")
            .font(.ageCaption)
            .foregroundStyle(Color.ageTextSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var destructiveZone: some View {
        SectionCard(title: "Repair",
                    subtitle: "Runs doctor --fix. It re-links, re-copies and cleans orphans across every target at once — it cannot be limited to one finding.") {
            HStack(spacing: Space.md) {
                Button("Repair all fixable (\(fixableFindings.count))") { confirmFix = true }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.ageStatusDanger)
                    .disabled(model.busy || fixableFindings.isEmpty)
                if fixableFindings.isEmpty {
                    Text("Nothing here can be repaired automatically.")
                        .font(.ageCallout)
                        .foregroundStyle(Color.ageTextSecondary)
                }
            }
        }
    }

    private var fixDialogTitle: String {
        "Repair \(fixableFindings.count) findings?"
    }

    /// Liệt kê CỤ THỂ từng việc, và tách riêng dòng `copy_drift` — đó là loại duy
    /// nhất ĐÈ lên chỉnh sửa tay của người dùng.
    private var fixDialogDetail: String {
        let drift = fixableFindings.filter { $0.kind == .copyDrift }
        var lines = fixableFindings.map { "• [\($0.kind.rawValue)] \($0.path)" }
        if !drift.isEmpty {
            lines.append("")
            lines.append("\(drift.count) of these are copy drift — repairing them OVERWRITES manual edits you made to those copies. This cannot be undone from inside AgeOS.")
        }
        return lines.joined(separator: "\n")
    }
}
