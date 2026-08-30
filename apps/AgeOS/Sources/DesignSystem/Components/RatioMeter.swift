import SwiftUI

/// A horizontal bar comparing a value on a **shared scale**.
///
/// The parent computes `scaleMax` ONCE for the whole group; a meter never
/// normalizes against its own threshold. If each bar had its own axis, two bars of
/// equal length would mean different things — the very bug this redesign fixes.
struct RatioMeter: View {
    let value: Int
    /// `nil` = the adapter declares no warning threshold.
    let threshold: Int?
    /// The group's shared axis. NOT this row's own threshold.
    let scaleMax: Int
    /// The unit spoken aloud for VoiceOver ("tokens").
    var unit: String = "tokens"
    /// What this bar measures. Required for accessibility: the component isolates
    /// itself with `.accessibilityElement(children: .ignore)`, so without a label
    /// VoiceOver reads "4200 of 10000 tokens" without saying which agent.
    var label: String? = nil

    /// All the arithmetic, kept out of the view so it is testable without rendering.
    struct Geometry: Equatable {
        /// The fill ratio, always within 0...1.
        let fill: Double
        /// Where the threshold mark sits on the axis; `nil` when there is no threshold.
        let thresholdMark: Double?
        /// Whether the value is over the threshold.
        let isOver: Bool

        init(value: Int, threshold: Int?, scaleMax: Int) {
            // scaleMax <= 0 happens when every agent is at 0 tokens. Dividing by zero
            // gives inf/NaN and SwiftUI draws nonsense, so it is stopped here.
            let safeMax = max(scaleMax, 1)
            // Clamp the threshold ONCE and use it for both the mark and the verdict.
            // The mark used to use the clamped value while `isOver` used the raw one, so
            // a negative threshold drew an empty 0% bar that still carried a red
            // "over threshold" chip — two contradictory claims on one row.
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

    /// The state spoken aloud. Color and bar length never reach a VoiceOver user, so
    /// everything this bar says visually has to be said again in words.
    private var spokenValue: String {
        let pct = Int((geometry.fill * 100).rounded())
        guard let threshold else {
            return String(localized: "\(value) \(unit), \(pct)% of the scale, no threshold set")
        }
        let verdict = geometry.isOver
            ? String(localized: "over the threshold")
            : String(localized: "under the threshold")
        return String(localized: "\(value) of \(threshold) \(unit), \(pct)% of the scale, \(verdict)")
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
                    // Say plainly that no threshold is set rather than leaving a blank —
                    // a blank reads as missing data, this is a conclusion.
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
        RatioMeter(value: 16800, threshold: 10000, scaleMax: 20000)   // over threshold
        RatioMeter(value: 0, threshold: 10000, scaleMax: 20000)       // edge: empty
        RatioMeter(value: 7300, threshold: nil, scaleMax: 20000)      // no threshold
        RatioMeter(value: 99999, threshold: 10000, scaleMax: 20000)   // edge: overflow -> clamp
        RatioMeter(value: 0, threshold: nil, scaleMax: 0)             // edge: empty scale
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
