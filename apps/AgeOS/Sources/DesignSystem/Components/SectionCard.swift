import SwiftUI

/// A titled block of content, replacing a bare `GroupBox`.
///
/// It takes an optional action in the corner because most sections in AgeOS carry
/// something you can do right there (Rerun scan, Sync, Measure). Putting that button
/// on the toolbar would separate the action from what it acts on.
struct SectionCard<Content: View>: View {
    private let titleText: Text
    private let subtitleText: Text?
    var count: Int? = nil
    var accessory: AnyView? = nil
    @ViewBuilder var content: Content

    /// The title is prose that needs translating — see the note in StatusPill.
    init(title: LocalizedStringKey, subtitle: LocalizedStringKey? = nil,
         count: Int? = nil, accessory: AnyView? = nil,
         @ViewBuilder content: () -> Content) {
        self.titleText = Text(title)
        self.subtitleText = subtitle.map { Text($0) }
        self.count = count
        self.accessory = accessory
        self.content = content()
    }

    /// The title is DATA (an adapter id) or a string already localized elsewhere.
    init(verbatimTitle: String, count: Int? = nil, accessory: AnyView? = nil,
         @ViewBuilder content: () -> Content) {
        self.titleText = Text(verbatim: verbatimTitle)
        self.subtitleText = nil
        self.count = count
        self.accessory = accessory
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                titleText
                    .font(.ageHeadline)
                    .foregroundStyle(Color.ageTextPrimary)
                if let count {
                    Text(verbatim: "\(count)")
                        .font(.ageNumericS)
                        .foregroundStyle(Color.ageTextSecondary)
                        .padding(.horizontal, Space.sm)
                        .background(Color.ageSurface.quinary, in: Capsule())
                }
                Spacer(minLength: Space.sm)
                if let accessory { accessory }
            }

            if let subtitleText {
                subtitleText
                    .font(.ageCallout)
                    .foregroundStyle(Color.ageTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            content
        }
        .padding(Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.ageSurfaceRaised, in: RoundedRectangle(cornerRadius: Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .strokeBorder(Color.ageBorderSubtle, lineWidth: Stroke.hairline)
        )
    }
}

#Preview("Variants") {
    VStack(spacing: Space.lg) {
        SectionCard(title: "Errors", count: 3) {
            Text("Three things are actually broken.")
                .font(.ageBody)
                .foregroundStyle(Color.ageTextPrimary)
        }
        SectionCard(title: "Context budget",
                    subtitle: "Always-loaded catalog tokens, per agent.",
                    accessory: AnyView(Button("Measure") {})) {
            RatioMeter(value: 4200, threshold: 10000, scaleMax: 20000)
        }
        // Edge case: no content, and a very long title.
        SectionCard(title: "A section title long enough to test how the header wraps",
                    count: 0) {
            Text("No errors")
                .font(.ageCallout)
                .foregroundStyle(Color.ageTextSecondary)
        }
    }
    .padding(Space.lg)
    .frame(width: 520)
    .background(Color.ageSurface)
}

#Preview("Dark") {
    SectionCard(title: "Warnings", count: 7,
                accessory: AnyView(Button("Rerun scan") {})) {
        Text("Nothing is broken yet, but it will surprise you.")
            .font(.ageBody)
            .foregroundStyle(Color.ageTextPrimary)
    }
    .padding(Space.lg)
    .frame(width: 520)
    .background(Color.ageSurface)
    .preferredColorScheme(.dark)
}
