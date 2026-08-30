import SwiftUI

/// Thanh ngang so sánh một giá trị trên **thang dùng chung**.
///
/// `scaleMax` do view cha tính MỘT LẦN cho cả nhóm, không phải mỗi meter tự chuẩn
/// hoá theo ngưỡng riêng. Nếu mỗi thanh có trục riêng thì hai thanh dài bằng nhau
/// lại mang giá trị khác nhau — đúng cái lỗi mà bản redesign này đi sửa.
struct RatioMeter: View {
    let value: Int
    /// `nil` = adapter không khai báo ngưỡng cảnh báo.
    let threshold: Int?
    /// Trục chung của cả nhóm. KHÔNG phải ngưỡng riêng của dòng này.
    let scaleMax: Int
    /// Đơn vị đọc thành lời cho VoiceOver ("tokens").
    var unit: String = "tokens"
    /// Thanh này đo cái gì. Bắt buộc về mặt accessibility: component tự cô lập bằng
    /// `.accessibilityElement(children: .ignore)`, nên nếu không có nhãn thì VoiceOver
    /// đọc "4200 of 10000 tokens" mà không biết đó là của agent nào.
    var label: String? = nil

    /// Toàn bộ phần tính toán, tách khỏi view để test được mà không cần render.
    struct Geometry: Equatable {
        /// Tỉ lệ lấp đầy, luôn nằm trong 0...1.
        let fill: Double
        /// Vị trí vạch ngưỡng trên trục, `nil` khi không có ngưỡng.
        let thresholdMark: Double?
        /// Đã vượt ngưỡng chưa.
        let isOver: Bool

        init(value: Int, threshold: Int?, scaleMax: Int) {
            // scaleMax <= 0 xảy ra khi mọi agent đều 0 token. Chia cho 0 sẽ ra
            // inf/NaN và SwiftUI vẽ ra khung hình vô nghĩa, nên chặn ở đây.
            let safeMax = max(scaleMax, 1)
            // Clamp threshold MỘT LẦN rồi dùng cho cả vạch lẫn phán quyết vượt
            // ngưỡng. Trước đây vạch dùng giá trị đã clamp còn `isOver` dùng giá
            // trị gốc, nên threshold âm cho ra thanh rỗng 0% mà vẫn gắn chip đỏ
            // "over threshold" — hai thứ nói ngược nhau trên cùng một dòng.
            let safeThreshold = threshold.map { max($0, 0) }
            fill = Self.clamped(Double(max(value, 0)) / Double(safeMax))
            thresholdMark = safeThreshold.map { Self.clamped(Double($0) / Double(safeMax)) }
            isOver = safeThreshold.map { max(value, 0) > $0 } ?? false
        }

        private static func clamped(_ x: Double) -> Double {
            min(max(x, 0), 1)
        }
    }

    private var geometry: Geometry {
        Geometry(value: value, threshold: threshold, scaleMax: scaleMax)
    }

    private var tone: PillTone { geometry.isOver ? .danger : .success }

    /// Trạng thái đọc thành lời. Màu và độ dài thanh không tới được người dùng
    /// VoiceOver, nên mọi thứ thanh này nói bằng hình phải nói lại bằng chữ.
    private var spokenValue: String {
        let pct = Int((geometry.fill * 100).rounded())
        guard let threshold else {
            return "\(value) \(unit), \(pct)% of the scale, no threshold set"
        }
        let verdict = geometry.isOver ? "over the threshold" : "under the threshold"
        return "\(value) of \(threshold) \(unit), \(pct)% of the scale, \(verdict)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.ageBorderSubtle)
                    Capsule()
                        .fill(tone.foreground)
                        .frame(width: proxy.size.width * geometry.fill)
                    if let mark = geometry.thresholdMark {
                        Rectangle()
                            .fill(Color.ageTextSecondary)
                            .frame(width: Stroke.emphasis)
                            .offset(x: proxy.size.width * mark - Stroke.emphasis / 2)
                    }
                }
            }
            .frame(height: Space.sm)

            HStack(spacing: Space.sm) {
                Text(verbatim: "\(value)")
                    .font(.ageNumericS)
                    .foregroundStyle(Color.ageTextPrimary)
                if let threshold {
                    Text(verbatim: "/ \(threshold)")
                        .font(.ageNumericS)
                        .foregroundStyle(Color.ageTextSecondary)
                } else {
                    // Nói thẳng là chưa đặt ngưỡng, thay vì để trống — trống đọc
                    // như "thiếu dữ liệu", còn đây là một kết luận.
                    Text("no threshold set")
                        .font(.ageCaption)
                        .foregroundStyle(Color.ageTextSecondary)
                }
                if geometry.isOver {
                    StatusPill("over threshold", tone: .danger,
                               icon: "exclamationmark.triangle.fill")
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: label ?? ""))
        .accessibilityValue(spokenValue)
    }
}

#Preview("States") {
    VStack(alignment: .leading, spacing: Space.xl) {
        RatioMeter(value: 4200, threshold: 10000, scaleMax: 20000)
        RatioMeter(value: 16800, threshold: 10000, scaleMax: 20000)   // vượt ngưỡng
        RatioMeter(value: 0, threshold: 10000, scaleMax: 20000)       // biên: rỗng
        RatioMeter(value: 7300, threshold: nil, scaleMax: 20000)      // không có ngưỡng
        RatioMeter(value: 99999, threshold: 10000, scaleMax: 20000)   // biên: tràn -> clamp
        RatioMeter(value: 0, threshold: nil, scaleMax: 0)             // biên: thang rỗng
    }
    .padding(Space.lg)
    .frame(width: 420)
    .background(Color.ageSurface)
}

#Preview("Dark") {
    VStack(alignment: .leading, spacing: Space.xl) {
        RatioMeter(value: 4200, threshold: 10000, scaleMax: 20000)
        RatioMeter(value: 16800, threshold: 10000, scaleMax: 20000)
        RatioMeter(value: 7300, threshold: nil, scaleMax: 20000)
    }
    .padding(Space.lg)
    .frame(width: 420)
    .background(Color.ageSurface)
    .preferredColorScheme(.dark)
}
