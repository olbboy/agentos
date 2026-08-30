import SwiftUI
import AgeOSCore

/// THE CENTRAL SCREEN: a skill-by-agent grid with global-scope enable/disable toggles.
/// State is read from the lockfile (the source of truth) — an FSEvents change updates it.
///
/// The old version's problem: a grid of colorless mini switches you could not read at
/// a glance. This one tints rows by state and moves mode and verified status out of the
/// tooltip into the column header — whether an adapter is verified is something you
/// want to know BEFORE enabling it, not after hovering.
struct TargetMatrixView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""

    var rows: [IndexDB.SkillRow] {
        query.isEmpty ? model.skills
            : model.skills.filter { $0.id.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        Table(rows) {
            TableColumn("Skill") { skill in
                skillCell(skill)
            }
            .width(min: 260)

            TableColumnForEach(model.matrixAdapters) { adapter in
                TableColumn(columnTitle(adapter)) { (skill: IndexDB.SkillRow) in
                    MatrixToggle(skillId: skill.id, adapter: adapter)
                }
                .width(130)
            }
        }
        .searchable(text: $query, prompt: "Filter skills")
        .navigationTitle("Target Matrix")
        .overlay {
            if model.skills.isEmpty {
                EmptyState(icon: "switch.2",
                           title: "No skills in the library yet",
                           message: "Go to Library to add a source.")
            }
        }
        .toolbar {
            if model.busy { ProgressView().controlSize(.small) }
        }
    }

    /// The column header carries mode and verified status. `Table` only accepts a
    /// `String` for a column title, so it folds into one line — accepted, rather than
    /// trading it for a more complicated layout.
    private func columnTitle(_ adapter: AdapterSpec) -> String {
        let mode = adapter.effectiveSkillMode.rawValue
        let verified = (adapter.skills?.verified ?? false) ? "" : " ⚠"
        return "\(adapter.displayName) · \(mode)\(verified)"
    }

    private func skillCell(_ skill: IndexDB.SkillRow) -> some View {
        let count = model.enabledAdapterCount(skillId: skill.id)
        return HStack(spacing: Space.sm) {
            // A shape indicator that does NOT depend on color, next to the row tint: a
            // color-blind user and a VoiceOver user can both still tell enabled rows apart.
            Image(systemName: count > 0 ? "largecircle.fill.circle" : "circle")
                .font(.ageCaption)
                .foregroundStyle(count > 0 ? Color.ageAccentBrand : Color.ageBorderSubtle)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: skill.name)
                    .font(.ageHeadline)
                    .foregroundStyle(Color.ageTextPrimary)
                Text(verbatim: skill.id)
                    .font(.ageCaption)
                    .foregroundStyle(Color.ageTextSecondary)
            }
        }
        .padding(.vertical, Space.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        // AnyShapeStyle because `.quinary` returns an opaque type, which is not the same
        // type as Color, so the two branches of `? :` would not match bare.
        .background(count > 0 ? AnyShapeStyle(Color.ageAccentBrand.quinary)
                              : AnyShapeStyle(Color.clear))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: skill.name))
        .accessibilityValue(count == 0 ? "not enabled anywhere"
                                       : "enabled in \(count) agents")
    }
}

struct MatrixToggle: View {
    @Environment(AppModel.self) private var model
    let skillId: String
    let adapter: AdapterSpec

    var body: some View {
        let enabled = model.isEnabled(skillId: skillId, adapterId: adapter.id)
        Toggle(isOn: Binding(
            get: { enabled },
            set: { newValue in
                Task { await model.toggle(skillId: skillId, adapterId: adapter.id, enabled: newValue) }
            }
        )) {
            EmptyView()
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
        .help(helpText)
        .accessibilityLabel("\(skillId) for \(adapter.displayName)")
        .accessibilityValue(enabled ? "on" : "off")
    }

    var helpText: String {
        let mode = adapter.effectiveSkillMode.rawValue
        let verified = (adapter.skills?.verified ?? false)
            ? ""
            : " — adapter not verified on a real machine"
        return "\(adapter.id) [\(mode)]\(verified)"
    }
}
