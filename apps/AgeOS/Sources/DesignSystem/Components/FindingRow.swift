import SwiftUI

/// One diagnostic row: severity icon, status chip, message, action.
///
/// `action == nil` does NOT leave the button slot empty — it shows "No automatic
/// fix". A blank reads as an omission; a sentence reads as a conclusion.
struct FindingRow: View {
    let severity: PillTone
    let message: String
    /// The status label. Left out, it is inferred from whether there is an action.
    ///
    /// It has to stay separate from `action` because the two are NOT one-to-one: a
    /// finding can be "Fixable" (by the screen-level CTA) while its row action is only
    /// "Reveal in Finder". Merging them would lie about what the button does.
    var status: LocalizedStringKey? = nil
    /// `nil` = no automatic action for this row.
    var action: (title: LocalizedStringKey, run: () -> Void)? = nil
    /// The secondary line showing a path or id — data, not prose.
    var detail: String? = nil

    /// By default, say plainly that nothing can be fixed automatically rather than
    /// leaving the chip blank.
    var effectiveStatus: LocalizedStringKey {
        status ?? (action == nil ? "No automatic fix" : "Fixable")
    }

    private var icon: String {
        switch severity {
        case .danger:  "xmark.octagon.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .info:    "info.circle.fill"
        case .success: "checkmark.circle.fill"
        case .neutral: "circle"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: Space.md) {
            Image(systemName: icon)
                .font(.ageBody)
                .foregroundStyle(severity.foreground)
                .accessibilityHidden(true)   // severity is already in accessibilityLabel

            VStack(alignment: .leading, spacing: Space.xs) {
                Text(verbatim: message)
                    .font(.ageBody)
                    .foregroundStyle(Color.ageTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(verbatim: detail)
                        .font(.ageCaption)
                        .foregroundStyle(Color.ageTextSecondary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
            }
            // Combine ONLY the text, not the whole row: combining the row swallows the
            // action button's own label and drops `detail` — two findings with different
            // paths would then read out identically.
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(verbatim: "\(severityWord): \(message)"))
            .accessibilityValue(Text(verbatim: detail ?? ""))

            Spacer(minLength: Space.sm)

            StatusPill(effectiveStatus, tone: action == nil ? .neutral : severity)

            if let action {
                Button(action.title, action: action.run)
                    .font(.ageCallout)
            }
        }
        .padding(.vertical, Space.sm)
    }

    private var severityWord: String {
        switch severity {
        case .danger:  String(localized: "Error")
        case .warning: String(localized: "Warning")
        case .info:    String(localized: "Info")
        case .success: String(localized: "Healthy")
        case .neutral: String(localized: "Note")
        }
    }
}

#Preview("Severities") {
    VStack(alignment: .leading, spacing: 0) {
        FindingRow(severity: .danger,
                   message: "Broken symlink (destination does not exist)",
                   status: "Fixable",
                   action: ("Reveal in Finder", {}),
                   detail: "~/.claude/skills/canvas-design")
        Divider().overlay(Color.ageBorderSubtle)
        FindingRow(severity: .warning,
                   message: "Copy drifted from its manifest (3 changed, 1 added, 0 missing files)",
                   status: "Fixable",
                   action: ("Reveal in Finder", {}),
                   detail: "~/.codex/skills/pdf")
        Divider().overlay(Color.ageBorderSubtle)
        // Edge case: no action -> it must say so, not leave a blank.
        FindingRow(severity: .info,
                   // No status passed: the view infers "No automatic fix".
                   message: "Description is 24 characters — too short for an agent to tell when to use it")
        Divider().overlay(Color.ageBorderSubtle)
        // Edge case: a very long message must wrap, not truncate.
        FindingRow(severity: .warning,
                   message: "A deliberately long finding message that has to wrap across several lines so we can confirm the row grows downward instead of truncating the explanation the user actually needs to read",
                   status: "Action required",
                   action: ("Disable everywhere", {}))
    }
    .padding(Space.lg)
    .frame(width: 640)
    .background(Color.ageSurfaceRaised)
}

#Preview("Dark") {
    VStack(alignment: .leading, spacing: 0) {
        FindingRow(severity: .danger,
                   message: "Broken symlink (destination does not exist)",
                   status: "Fixable",
                   action: ("Reveal in Finder", {}),
                   detail: "~/.claude/skills/canvas-design")
        Divider().overlay(Color.ageBorderSubtle)
        FindingRow(severity: .info,
                   message: "Description is entirely generic wording")
    }
    .padding(Space.lg)
    .frame(width: 640)
    .background(Color.ageSurfaceRaised)
    .preferredColorScheme(.dark)
}
