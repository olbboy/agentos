import SwiftUI

/// The bridge from semantic names to the Asset Catalog.
///
/// Names describe a **role** (`statusDanger`), not a color (`red`). Changing the hue
/// later means editing the Asset Catalog, not auditing call sites.
///
/// Each color set declares four variants (light / dark / light+HighContrast /
/// dark+HighContrast). macOS picks the right one for the environment, so no view
/// needs to read `@Environment(\.colorScheme)` or probe for Increase Contrast.
///
/// Hex values and measured contrast ratios: `docs/design-guidelines.md`.
extension Color {
    /// The window background.
    static let ageSurface       = Color("surface")
    /// The background of a card or section raised above `ageSurface`.
    static let ageSurfaceRaised = Color("surfaceRaised")
    /// Separator lines. Purely decorative — never carries state.
    static let ageBorderSubtle  = Color("borderSubtle")
    static let ageTextPrimary   = Color("textPrimary")
    static let ageTextSecondary = Color("textSecondary")

    /// Only for small areas: active state, a left rule, an eyebrow.
    /// Never a large fill — see the rules in design-guidelines.
    static let ageAccentBrand   = Color("accentBrand")

    static let ageStatusSuccess = Color("statusSuccess")
    static let ageStatusWarning = Color("statusWarning")
    static let ageStatusDanger  = Color("statusDanger")
    static let ageStatusInfo    = Color("statusInfo")
}
