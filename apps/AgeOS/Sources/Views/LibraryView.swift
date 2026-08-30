import SwiftUI
import AgeOSCore

/// Library browser: search and filter, add a source, sync.
///
/// Every row has to carry enough to DECIDE whether to enable a skill. Id, version and
/// description are not enough — they say nothing about where it came from, what it
/// costs in tokens, or how many agents already load it.
struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var newSource = ""
    @State private var filter = Filter()

    /// Three filter dimensions folded into one `Menu` rather than three separate
    /// toolbar controls — less ink, and for exactly three facets a dropdown beats a
    /// permanent sidebar.
    struct Filter {
        var sourceId: String? = nil
        var deprecatedOnly = false
        var enabledAnywhereOnly = false

        var isActive: Bool { sourceId != nil || deprecatedOnly || enabledAnywhereOnly }
    }

    var filtered: [IndexDB.SkillRow] {
        model.skills.filter { skill in
            if filter.deprecatedOnly && !skill.deprecated { return false }
            if let sourceId = filter.sourceId, skill.sourceId != sourceId { return false }
            if filter.enabledAnywhereOnly && model.enabledAdapterCount(skillId: skill.id) == 0 {
                return false
            }
            guard !query.isEmpty else { return true }
            return skill.id.localizedCaseInsensitiveContains(query)
                || skill.description.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            addSourceBar

            List(filtered, id: \.id) { skill in
                row(skill)
            }
            .searchable(text: $query, placement: .automatic, prompt: "Search skills")
            .overlay {
                if model.skills.isEmpty {
                    EmptyState(icon: "books.vertical",
                               title: "Library is empty",
                               message: "Add a GitHub source or a local folder to get started.")
                } else if filtered.isEmpty {
                    EmptyState(icon: "line.3.horizontal.decrease.circle",
                               title: "Nothing matches",
                               message: "Clear the search or the filters to see the whole library.")
                }
            }
        }
        .background(Color.ageSurface)
        .navigationTitle("Library (\(filtered.count))")
        .toolbar { filterMenu }
    }

    // MARK: - Add source

    private var addSourceBar: some View {
        HStack(spacing: Space.sm) {
            TextField("Add a source: https://github.com/owner/repo, or a local path", text: $newSource)
                .textFieldStyle(.roundedBorder)
                .onSubmit { addSource() }
                .accessibilityLabel("Source URL or local path")
            Button("Add & Sync") { addSource() }
                .disabled(newSource.isEmpty || model.busy)
                .accessibilityLabel("Add the source and sync it")
            Button {
                Task { await model.syncAll() }
            } label: {
                Label("Sync", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(model.busy)
            .accessibilityLabel("Sync every source")
        }
        .padding(Space.lg)
    }

    // MARK: - Filter

    private var filterMenu: some View {
        Menu {
            Toggle("Deprecated only", isOn: $filter.deprecatedOnly)
            Toggle("Enabled somewhere", isOn: $filter.enabledAnywhereOnly)
            Divider()
            Picker("Source", selection: $filter.sourceId) {
                Text("All sources").tag(String?.none)
                ForEach(model.sources, id: \.id) { source in
                    Text(verbatim: source.id).tag(String?.some(source.id))
                }
            }
        } label: {
            Label("Filter", systemImage: filter.isActive
                  ? "line.3.horizontal.decrease.circle.fill"
                  : "line.3.horizontal.decrease.circle")
        }
        .accessibilityIdentifier("library.filterMenu")
        .accessibilityLabel("Filter skills")
        .accessibilityValue(filter.isActive ? "filters active" : "no filters")
        // The `.action` audit reports that this MenuButton exposes no action. Say what
        // it opens instead of leaving VoiceOver to read only "menu button".
        .accessibilityHint("Opens filter options for source, deprecation and enabled state")
    }

    // MARK: - Row

    private func row(_ skill: IndexDB.SkillRow) -> some View {
        let enabledCount = model.enabledAdapterCount(skillId: skill.id)
        // Look it up in the precomputed table rather than recomputing per render — see
        // AppModel.skillTokenEstimates.
        // AppModel.skillTokenEstimates.
        let tokens = model.skillTokenEstimates[skill.id]

        return VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.sm) {
                Text(verbatim: skill.id)
                    .font(.ageHeadline)
                    .foregroundStyle(Color.ageTextPrimary)
                if skill.deprecated {
                    StatusPill("deprecated", tone: .warning, icon: "xmark.seal")
                }
                Spacer()
                Text(verbatim: skill.version)
                    .font(.ageNumericS)
                    .foregroundStyle(Color.ageTextSecondary)
            }

            Text(verbatim: skill.description)
                .font(.ageCallout)
                .foregroundStyle(Color.ageTextSecondary)
                .lineLimit(2)

            HStack(spacing: Space.sm) {
                StatusPill(verbatim: skill.sourceId, tone: .neutral, icon: "shippingbox")
                if let tokens {
                    StatusPill(verbatim: "≈\(tokens) tk", tone: .neutral, icon: "number")
                }
                StatusPill(enabledCount == 0 ? "not enabled" : "\(enabledCount) agents",
                           tone: enabledCount == 0 ? .neutral : .success,
                           icon: "switch.2")
            }
        }
        .padding(.vertical, Space.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: skill.id))
        .accessibilityValue(spokenRow(skill, tokens: tokens, enabledCount: enabledCount))
    }

    /// Everything those three chips say visually has to be said again in words — a
    /// VoiceOver user sees neither the color nor the icon.
    private func spokenRow(_ skill: IndexDB.SkillRow,
                           tokens: Int?, enabledCount: Int) -> String {
        var parts = [String(localized: "from \(skill.sourceId)"),
                     String(localized: "version \(skill.version)")]
        if let tokens { parts.append(String(localized: "about \(tokens) tokens")) }
        parts.append(enabledCount == 0
                     ? String(localized: "not enabled anywhere")
                     : String(localized: "enabled in \(enabledCount) agents"))
        if skill.deprecated { parts.append(String(localized: "deprecated")) }
        return parts.joined(separator: ", ")
    }

    private func addSource() {
        let value = newSource.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return }
        newSource = ""
        Task { await model.addSource(value) }
    }
}
