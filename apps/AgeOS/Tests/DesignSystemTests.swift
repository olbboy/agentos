import Testing
@testable import AgeOS

/// Tests for the PURE logic of the design system. Drawing is not tested here —
/// `#Preview` covers how it looks and the UI tests cover accessibility. What earns a
/// unit test is the arithmetic, because that is where a bug stays silent.
@Suite("RatioMeter geometry")
struct RatioMeterGeometryTests {

    @Test("A normal ratio is computed against the shared scale")
    func normalFill() {
        let g = RatioMeter.Geometry(value: 5000, threshold: 10000, scaleMax: 20000)
        #expect(g.fill == 0.25)
        #expect(g.thresholdMark == 0.5)
        #expect(g.isOver == false)
    }

    @Test("A value past scaleMax clamps to 1 and never draws outside the frame")
    func clampsOverflow() {
        let g = RatioMeter.Geometry(value: 99_999, threshold: 10000, scaleMax: 20000)
        #expect(g.fill == 1.0)
        #expect(g.isOver == true)
    }

    @Test("A negative value clamps to 0 rather than drawing backwards")
    func clampsNegative() {
        let g = RatioMeter.Geometry(value: -500, threshold: 10000, scaleMax: 20000)
        #expect(g.fill == 0.0)
        #expect(g.isOver == false)
    }

    @Test("scaleMax = 0 produces no NaN — it happens when every agent is at 0 tokens")
    func zeroScaleIsSafe() {
        let g = RatioMeter.Geometry(value: 0, threshold: nil, scaleMax: 0)
        #expect(g.fill == 0.0)
        #expect(g.fill.isNaN == false)
        #expect(g.thresholdMark == nil)
    }

    @Test("scaleMax = 0 with a positive value still yields a valid ratio")
    func zeroScaleWithValue() {
        let g = RatioMeter.Geometry(value: 42, threshold: nil, scaleMax: 0)
        #expect(g.fill == 1.0)
        #expect(g.fill.isFinite)
    }

    @Test("With no threshold there is no mark, and it never reports being over")
    func noThreshold() {
        let g = RatioMeter.Geometry(value: 18_000, threshold: nil, scaleMax: 20000)
        #expect(g.thresholdMark == nil)
        #expect(g.isOver == false)
        #expect(g.fill == 0.9)
    }

    @Test("A threshold past the scale clamps too, instead of drifting off the frame")
    func thresholdBeyondScaleIsClamped() {
        let g = RatioMeter.Geometry(value: 100, threshold: 50_000, scaleMax: 20000)
        #expect(g.thresholdMark == 1.0)
    }

    @Test("Exactly at the threshold is NOT over — a threshold warns, it does not forbid")
    func equalToThresholdIsNotOver() {
        let g = RatioMeter.Geometry(value: 10_000, threshold: 10_000, scaleMax: 20000)
        #expect(g.isOver == false)
    }

    /// A negative threshold only reaches here if something upstream is buggy, but even
    /// then the UI has to say one consistent thing. The mark used to use the clamped
    /// value while `isOver` used the raw one, so the bar drew EMPTY at 0% and still
    /// carried a red "over threshold" chip.
    @Test("A negative threshold does not produce an empty bar that claims to be over")
    func negativeThresholdIsConsistent() {
        let g = RatioMeter.Geometry(value: 0, threshold: -50, scaleMax: 20000)
        #expect(g.fill == 0.0)
        #expect(g.thresholdMark == 0.0)
        #expect(g.isOver == false, "0 on the scale while reporting over-threshold is self-contradictory")
    }

    @Test("A positive value against a negative threshold really is over, and says so")
    func positiveValueOverNegativeThreshold() {
        let g = RatioMeter.Geometry(value: 5, threshold: -50, scaleMax: 20000)
        #expect(g.isOver == true)
    }
}

@Suite("PillTone mapping")
struct PillToneTests {

    /// EXACTLY what this test checks: `Color` compares by (asset name, bundle) and does
    /// NOT resolve the real RGBA from the Asset Catalog. So it catches a miswired case
    /// in the `switch` (for example `.warning: .ageStatusSuccess`), but it does NOT
    /// catch two colorsets declaring the same hex value.
    ///
    /// That the hex values differ is guarded by `docs/design-guidelines.md` and the
    /// contrast script, not by this test. Spelled out so nobody reads the name and
    /// assumes it guarantees more than it does.
    @Test("Each tone points at a DIFFERENT color asset (hex values not checked)")
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

    @Test("With no action it says plainly that nothing can be fixed automatically")
    func noActionSaysSo() {
        let row = FindingRow(severity: .info, message: "Description is too short")
        #expect(row.effectiveStatus == "No automatic fix")
    }

    @Test("With an action the default is Fixable")
    func actionDefaultsToFixable() {
        let row = FindingRow(severity: .danger, message: "Broken symlink",
                             action: ("Reveal in Finder", {}))
        #expect(row.effectiveStatus == "Fixable")
    }

    @Test("An explicit status always beats the default")
    func explicitStatusWins() {
        let row = FindingRow(severity: .warning, message: "Marked deprecated",
                             status: "Action required",
                             action: ("Disable everywhere", {}))
        #expect(row.effectiveStatus == "Action required")
    }
}
