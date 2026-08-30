import SwiftUI

/// One large number plus a label, with an optional denominator.
///
/// `outOf` exists because "12" on its own says nothing while "12 / 20" does. When
/// there is no natural denominator, leave it out rather than inventing one.
struct StatTile: View {
    let value: String
    /// The label is prose that needs translating — see the note in StatusPill for why
    /// NOT to use `String` here.
    let label: LocalizedStringKey
    /// Optional denominator — rendered as "value / outOf".
    var outOf: String? = nil
    /// Whether this deep-links anywhere. `nil` = the tile is read-only.
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
                // verbatim: this is pre-formatted data, not a string to translate.
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
        // Edge cases: 0 and a very large number both have to fit.
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
