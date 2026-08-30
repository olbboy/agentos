import SwiftUI

/// The AgeOS type ramp. Brand identity comes from here and from `Space`,
/// not from saturation — see `docs/design-guidelines.md`.
extension Font {
    /// The single largest number on Overview. Used once per screen.
    static let ageDisplayL = Font.system(size: 28, weight: .semibold)
    static let ageTitleL   = Font.system(size: 20, weight: .semibold)
    static let ageHeadline = Font.system(size: 15, weight: .medium)
    static let ageBody     = Font.system(size: 13)
    static let ageCallout  = Font.system(size: 12)
    static let ageCaption  = Font.system(size: 11)

    /// For any number that changes over time (token counts, ratios, tallies).
    /// `monospacedDigit` keeps every digit the same width, so a column of numbers
    /// does not shift sideways when a value changes — very visible on a live meter.
    static let ageNumeric  = Font.system(size: 15, weight: .medium).monospacedDigit()

    /// The small variant of `ageNumeric`, for secondary numbers inside a list row.
    static let ageNumericS = Font.system(size: 12, weight: .regular).monospacedDigit()
}
