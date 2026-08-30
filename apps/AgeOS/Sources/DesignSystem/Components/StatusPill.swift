import SwiftUI

/// The tone of a status chip. Named after the **role**, not the color, so changing
/// the palette does not mean editing call sites.
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

    /// The chip background. Uses `.quinary` of the foreground rather than `.opacity()`:
    /// opacity breaks the measured contrast, a system shade does not.
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

/// A small status chip: optional icon plus text.
///
/// The text is always present — a chip never uses color alone to carry meaning, since
/// color reaches neither VoiceOver users nor color-blind users.
struct StatusPill: View {
    private let label: Text
    private let spoken: Text
    let tone: PillTone
    var icon: String? = nil

    /// The text is PROSE that needs translating. It takes `LocalizedStringKey` rather
    /// than `String`: a `String` passed through a property always resolves to `Text`'s
    /// verbatim overload, so the string would NEVER be extracted into the String
    /// Catalog — no error, no warning, just silently absent when someone translates.
    init(_ text: LocalizedStringKey, tone: PillTone, icon: String? = nil) {
        self.label = Text(text)
        self.spoken = Text(text)
        self.tone = tone
        self.icon = icon
    }

    /// The text is DATA (an id, a path, an error from core, an already-localized string).
    /// Kept out of the catalog — translating a skill id is meaningless.
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
        // Edge case: very long text must truncate without breaking the layout.
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
