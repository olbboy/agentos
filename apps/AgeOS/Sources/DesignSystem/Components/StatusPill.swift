import SwiftUI

/// Sắc thái của một chip trạng thái. Đặt tên theo **vai trò** chứ không theo màu,
/// để đổi palette không phải sửa call site.
enum PillTone {
    case neutral, success, warning, danger, info

    var foreground: Color {
        switch self {
        case .neutral: .ageTextSecondary
        case .success: .ageStatusSuccess
        case .warning: .ageStatusWarning
        case .danger:  .ageStatusDanger
        case .info:    .ageStatusInfo
        }
    }

    /// Nền chip. Dùng `.quinary` của chính màu chữ thay vì `.opacity()`:
    /// opacity làm hỏng contrast đã đo, còn shade hệ thống thì không.
    var background: Color {
        switch self {
        case .neutral: .ageSurface
        case .success: .ageStatusSuccess
        case .warning: .ageStatusWarning
        case .danger:  .ageStatusDanger
        case .info:    .ageStatusInfo
        }
    }
}

/// Chip trạng thái nhỏ: icon tuỳ chọn + chữ.
///
/// Chữ luôn có mặt — chip không bao giờ chỉ dùng màu để truyền tin, vì màu không
/// tới được người dùng VoiceOver và người mù màu.
struct StatusPill: View {
    private let label: Text
    private let spoken: Text
    let tone: PillTone
    var icon: String? = nil

    /// Chữ là VĂN XUÔI cần dịch. Nhận `LocalizedStringKey` chứ không nhận `String`:
    /// một `String` đi qua property luôn resolve vào overload verbatim của `Text`,
    /// nên chuỗi sẽ KHÔNG BAO GIỜ được trích vào String Catalog — không lỗi, không
    /// cảnh báo, chỉ âm thầm vắng mặt lúc ai đó ngồi dịch.
    init(_ text: LocalizedStringKey, tone: PillTone, icon: String? = nil) {
        self.label = Text(text)
        self.spoken = Text(text)
        self.tone = tone
        self.icon = icon
    }

    /// Chữ là DỮ LIỆU (id, path, thông điệp lỗi từ core, chuỗi đã localize sẵn).
    /// Không đưa vào catalog — dịch một skill id là vô nghĩa.
    init(verbatim text: String, tone: PillTone, icon: String? = nil) {
        self.label = Text(verbatim: text)
        self.spoken = Text(verbatim: text)
        self.tone = tone
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: Space.xs) {
            if let icon {
                Image(systemName: icon)
                    .font(.ageCaption)
            }
            label
                .font(.ageCaption)
                .lineLimit(1)
        }
        .padding(.horizontal, Space.sm)
        .padding(.vertical, Space.xs / 2)
        .foregroundStyle(tone.foreground)
        .background(tone.background.quinary, in: Capsule())
        .overlay(Capsule().strokeBorder(tone.foreground.quaternary, lineWidth: Stroke.hairline))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spoken)
    }
}

#Preview("Tones") {
    VStack(alignment: .leading, spacing: Space.sm) {
        StatusPill("Fixable", tone: .success, icon: "wrench")
        StatusPill("Action required", tone: .warning, icon: "exclamationmark.triangle")
        StatusPill("Broken", tone: .danger, icon: "xmark.octagon")
        StatusPill("No automatic fix", tone: .neutral)
        StatusPill(verbatim: "symlink", tone: .info)
        // Trạng thái biên: chữ rất dài phải cắt gọn, không đẩy vỡ bố cục.
        StatusPill("a very long status label that should truncate cleanly", tone: .warning)
    }
    .padding(Space.lg)
    .background(Color.ageSurface)
}

#Preview("Dark") {
    VStack(alignment: .leading, spacing: Space.sm) {
        StatusPill("Fixable", tone: .success, icon: "wrench")
        StatusPill("Broken", tone: .danger, icon: "xmark.octagon")
        StatusPill("No automatic fix", tone: .neutral)
    }
    .padding(Space.lg)
    .background(Color.ageSurface)
    .preferredColorScheme(.dark)
}
