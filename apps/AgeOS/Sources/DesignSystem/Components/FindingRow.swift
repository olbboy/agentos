import SwiftUI

/// Một dòng chẩn đoán: icon severity + chip trạng thái + thông điệp + hành động.
///
/// `action == nil` KHÔNG để trống chỗ nút — nó hiện "No automatic fix". Ô trống
/// đọc như thiếu sót; một câu nói rõ thì đó là kết luận.
struct FindingRow: View {
    let severity: PillTone
    let message: String
    /// Nhãn trạng thái. Bỏ trống thì suy ra từ việc có hành động hay không.
    ///
    /// Phải tách khỏi `action` vì hai thứ này KHÔNG một-đối-một: một finding có thể
    /// mang trạng thái "Fixable" (do CTA toàn màn lo) mà hành động tại dòng chỉ là
    /// "Reveal in Finder". Gộp lại sẽ nói dối về việc nút đó làm gì.
    var status: LocalizedStringKey? = nil
    /// `nil` = không có hành động tự động cho dòng này.
    var action: (title: LocalizedStringKey, run: () -> Void)? = nil
    /// Dòng phụ hiện path hoặc id — dữ liệu, không phải văn xuôi.
    var detail: String? = nil

    /// Mặc định nói thẳng khi không sửa tự động được, thay vì để chip trống.
    var effectiveStatus: LocalizedStringKey {
        status ?? (action == nil ? "No automatic fix" : "Fixable")
    }

    private var icon: String {
        switch severity {
        case .danger:  "xmark.octagon.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .info:    "info.circle.fill"
        case .success: "checkmark.circle.fill"
        case .neutral: "circle"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: Space.md) {
            Image(systemName: icon)
                .font(.ageBody)
                .foregroundStyle(severity.foreground)
                .accessibilityHidden(true)   // severity đã nằm trong accessibilityLabel

            VStack(alignment: .leading, spacing: Space.xs) {
                Text(verbatim: message)
                    .font(.ageBody)
                    .foregroundStyle(Color.ageTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(verbatim: detail)
                        .font(.ageCaption)
                        .foregroundStyle(Color.ageTextSecondary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
            }
            // Gộp RIÊNG phần chữ, không gộp cả hàng: gộp cả hàng sẽ nuốt mất nhãn
            // riêng của nút hành động, và bỏ rơi `detail` — hai finding khác path
            // sẽ đọc lên giống hệt nhau.
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(verbatim: "\(severityWord): \(message)"))
            .accessibilityValue(Text(verbatim: detail ?? ""))

            Spacer(minLength: Space.sm)

            StatusPill(effectiveStatus, tone: action == nil ? .neutral : severity)

            if let action {
                Button(action.title, action: action.run)
                    .font(.ageCallout)
            }
        }
        .padding(.vertical, Space.sm)
    }

    private var severityWord: String {
        switch severity {
        case .danger:  "Error"
        case .warning: "Warning"
        case .info:    "Info"
        case .success: "Healthy"
        case .neutral: "Note"
        }
    }
}

#Preview("Severities") {
    VStack(alignment: .leading, spacing: 0) {
        FindingRow(severity: .danger,
                   message: "Broken symlink (destination does not exist)",
                   status: "Fixable",
                   action: ("Reveal in Finder", {}),
                   detail: "~/.claude/skills/canvas-design")
        Divider().overlay(Color.ageBorderSubtle)
        FindingRow(severity: .warning,
                   message: "Copy drifted from its manifest (3 changed, 1 added, 0 missing files)",
                   status: "Fixable",
                   action: ("Reveal in Finder", {}),
                   detail: "~/.codex/skills/pdf")
        Divider().overlay(Color.ageBorderSubtle)
        // Biên: không có hành động -> phải nói rõ, không để trống.
        FindingRow(severity: .info,
                   // Không truyền status: view tự suy ra "No automatic fix".
                   message: "Description is 24 characters — too short for an agent to tell when to use it")
        Divider().overlay(Color.ageBorderSubtle)
        // Biên: thông điệp rất dài phải xuống dòng, không cắt cụt.
        FindingRow(severity: .warning,
                   message: "A deliberately long finding message that has to wrap across several lines so we can confirm the row grows downward instead of truncating the explanation the user actually needs to read",
                   status: "Action required",
                   action: ("Disable everywhere", {}))
    }
    .padding(Space.lg)
    .frame(width: 640)
    .background(Color.ageSurfaceRaised)
}

#Preview("Dark") {
    VStack(alignment: .leading, spacing: 0) {
        FindingRow(severity: .danger,
                   message: "Broken symlink (destination does not exist)",
                   status: "Fixable",
                   action: ("Reveal in Finder", {}),
                   detail: "~/.claude/skills/canvas-design")
        Divider().overlay(Color.ageBorderSubtle)
        FindingRow(severity: .info,
                   message: "Description is entirely generic wording")
    }
    .padding(Space.lg)
    .frame(width: 640)
    .background(Color.ageSurfaceRaised)
    .preferredColorScheme(.dark)
}
