import SwiftUI

/// Một con số lớn + nhãn, tuỳ chọn mẫu số.
///
/// Mẫu số (`outOf`) tồn tại vì "12" đứng một mình không nói được gì — "12 / 20"
/// thì có. Khi không có mẫu số tự nhiên thì bỏ trống, đừng bịa ra một cái.
struct StatTile: View {
    let value: String
    /// Nhãn là văn xuôi cần dịch — xem ghi chú trong StatusPill về lý do
    /// KHÔNG dùng `String` ở đây.
    let label: LocalizedStringKey
    /// Mẫu số tuỳ chọn — hiện dạng "value / outOf".
    var outOf: String? = nil
    /// Có deep-link đi đâu không. `nil` = tile chỉ để đọc.
    var action: (() -> Void)? = nil

    private var spokenValue: String {
        outOf.map { String(localized: "\(value) of \($0)") } ?? value
    }

    var body: some View {
        if let action {
            Button(action: action) { content }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(label))
                .accessibilityValue(spokenValue)
                .accessibilityAddTraits(.isButton)
        } else {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(label))
                .accessibilityValue(spokenValue)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                // verbatim: đây là dữ liệu đã định dạng sẵn, không phải chuỗi cần dịch.
                Text(verbatim: value)
                    .font(.ageDisplayL)
                    .foregroundStyle(Color.ageTextPrimary)
                if let outOf {
                    Text(verbatim: "/ \(outOf)")
                        .font(.ageNumericS)
                        .foregroundStyle(Color.ageTextSecondary)
                }
            }
            Text(label)
                .font(.ageCallout)
                .foregroundStyle(Color.ageTextSecondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.lg)
        .background(Color.ageSurfaceRaised, in: RoundedRectangle(cornerRadius: Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .strokeBorder(Color.ageBorderSubtle, lineWidth: Stroke.hairline)
        )
    }
}

#Preview("Row") {
    HStack(spacing: Space.md) {
        StatTile(value: "128", label: "distinct skills")
        StatTile(value: "6", label: "agents detected")
        StatTile(value: "12", label: "managed by AgeOS", outOf: "128")
        // Biên: 0 và một số rất lớn phải cùng nằm gọn.
        StatTile(value: "0", label: "loaded in 2+ agents")
        StatTile(value: "1284093", label: "a deliberately long label that wraps to two lines")
    }
    .padding(Space.lg)
    .background(Color.ageSurface)
}

#Preview("Dark") {
    HStack(spacing: Space.md) {
        StatTile(value: "128", label: "distinct skills")
        StatTile(value: "12", label: "managed by AgeOS", outOf: "128", action: {})
    }
    .padding(Space.lg)
    .background(Color.ageSurface)
    .preferredColorScheme(.dark)
}
