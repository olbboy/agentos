import Testing
@testable import AgeOS

/// Test cho phần logic THUẦN của design system. Việc vẽ không test ở đây —
/// `#Preview` lo phần nhìn, còn UI test lo phần a11y. Cái đáng khoá bằng test
/// đơn vị là số học, vì đó là chỗ lỗi im lặng.
@Suite("RatioMeter geometry")
struct RatioMeterGeometryTests {

    @Test("Tỉ lệ bình thường tính đúng theo thang chung")
    func normalFill() {
        let g = RatioMeter.Geometry(value: 5000, threshold: 10000, scaleMax: 20000)
        #expect(g.fill == 0.25)
        #expect(g.thresholdMark == 0.5)
        #expect(g.isOver == false)
    }

    @Test("Giá trị vượt scaleMax bị clamp về 1, không vẽ tràn khung")
    func clampsOverflow() {
        let g = RatioMeter.Geometry(value: 99_999, threshold: 10000, scaleMax: 20000)
        #expect(g.fill == 1.0)
        #expect(g.isOver == true)
    }

    @Test("Giá trị âm bị clamp về 0 thay vì vẽ ngược")
    func clampsNegative() {
        let g = RatioMeter.Geometry(value: -500, threshold: 10000, scaleMax: 20000)
        #expect(g.fill == 0.0)
        #expect(g.isOver == false)
    }

    @Test("scaleMax = 0 không sinh NaN — xảy ra khi mọi agent đều 0 token")
    func zeroScaleIsSafe() {
        let g = RatioMeter.Geometry(value: 0, threshold: nil, scaleMax: 0)
        #expect(g.fill == 0.0)
        #expect(g.fill.isNaN == false)
        #expect(g.thresholdMark == nil)
    }

    @Test("scaleMax = 0 với giá trị dương vẫn cho ra tỉ lệ hợp lệ")
    func zeroScaleWithValue() {
        let g = RatioMeter.Geometry(value: 42, threshold: nil, scaleMax: 0)
        #expect(g.fill == 1.0)
        #expect(g.fill.isFinite)
    }

    @Test("Không có ngưỡng thì không có vạch ngưỡng và không bao giờ báo vượt")
    func noThreshold() {
        let g = RatioMeter.Geometry(value: 18_000, threshold: nil, scaleMax: 20000)
        #expect(g.thresholdMark == nil)
        #expect(g.isOver == false)
        #expect(g.fill == 0.9)
    }

    @Test("Vạch ngưỡng vượt thang cũng bị clamp, không trôi khỏi khung")
    func thresholdBeyondScaleIsClamped() {
        let g = RatioMeter.Geometry(value: 100, threshold: 50_000, scaleMax: 20000)
        #expect(g.thresholdMark == 1.0)
    }

    @Test("Bằng đúng ngưỡng thì CHƯA vượt — ngưỡng là mức cảnh báo, không phải mức cấm")
    func equalToThresholdIsNotOver() {
        let g = RatioMeter.Geometry(value: 10_000, threshold: 10_000, scaleMax: 20000)
        #expect(g.isOver == false)
    }

    /// Threshold âm chỉ đến được đây nếu upstream có bug, nhưng khi đó UI phải nói
    /// một chuyện nhất quán. Trước đây vạch dùng giá trị đã clamp còn `isOver` dùng
    /// giá trị gốc, nên thanh vẽ RỖNG 0% mà vẫn gắn chip đỏ "over threshold".
    @Test("Threshold âm không tạo ra thanh rỗng mà vẫn báo vượt ngưỡng")
    func negativeThresholdIsConsistent() {
        let g = RatioMeter.Geometry(value: 0, threshold: -50, scaleMax: 20000)
        #expect(g.fill == 0.0)
        #expect(g.thresholdMark == 0.0)
        #expect(g.isOver == false, "0 trên thang mà báo vượt ngưỡng là tự mâu thuẫn")
    }

    @Test("Giá trị dương với threshold âm thì vượt thật, và nói đúng như vậy")
    func positiveValueOverNegativeThreshold() {
        let g = RatioMeter.Geometry(value: 5, threshold: -50, scaleMax: 20000)
        #expect(g.isOver == true)
    }
}

@Suite("PillTone mapping")
struct PillToneTests {

    /// CHÍNH XÁC test này kiểm cái gì: `Color` so sánh theo (tên asset, bundle),
    /// KHÔNG resolve RGBA thật trong Asset Catalog. Nên nó bắt được lỗi map sai
    /// case trong `switch` (ví dụ `.warning: .ageStatusSuccess`), nhưng KHÔNG bắt
    /// được việc hai colorset khai cùng một giá trị hex.
    ///
    /// Việc hex phải khác nhau được `docs/design-guidelines.md` và script đo
    /// contrast bảo vệ, không phải test này. Ghi rõ ra để không ai đọc tên test rồi
    /// tưởng nó bảo đảm nhiều hơn thực tế.
    @Test("Mỗi tone trỏ tới một asset màu KHÁC NHAU (không kiểm giá trị hex)")
    func tonesPointAtDistinctAssets() {
        let tones: [PillTone] = [.neutral, .success, .warning, .danger, .info]
        let colors = tones.map(\.foreground)
        for i in colors.indices {
            for j in colors.indices where i < j {
                #expect(colors[i] != colors[j])
            }
        }
    }
}

@Suite("FindingRow status default")
struct FindingRowStatusTests {

    @Test("Không có hành động thì nói thẳng là không sửa tự động được")
    func noActionSaysSo() {
        let row = FindingRow(severity: .info, message: "Description is too short")
        #expect(row.effectiveStatus == "No automatic fix")
    }

    @Test("Có hành động thì mặc định là Fixable")
    func actionDefaultsToFixable() {
        let row = FindingRow(severity: .danger, message: "Broken symlink",
                             action: ("Reveal in Finder", {}))
        #expect(row.effectiveStatus == "Fixable")
    }

    @Test("Status truyền tay luôn thắng mặc định")
    func explicitStatusWins() {
        let row = FindingRow(severity: .warning, message: "Marked deprecated",
                             status: "Action required",
                             action: ("Disable everywhere", {}))
        #expect(row.effectiveStatus == "Action required")
    }
}
