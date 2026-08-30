import SwiftUI
import AgeOSCore

/// The screen the app opens on. It answers the first question a user has — "what
/// does my machine look like" — from a real scan, even when the library is empty.
///
/// Every tile here has to lead somewhere or do something. A tile that only shows a
/// number and cannot be clicked was dropped: better few tiles that each go somewhere.
struct OverviewView: View {
    @Environment(AppModel.self) private var model
    @Binding var selection: Destination

    @State private var confirmImport = false
    /// The most recent import result. It MUST be kept: `adoptImport` catches per-skill
    /// failures into `AdoptReport.errors` and does NOT throw, so discarding the report
    /// means a copy failure never reaches `lastError` or the ErrorBanner — the user
    /// believes everything imported while some skills silently failed.
    @State private var adoptResult: EffectiveLoadScanner.AdoptReport?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                if model.lock.skills.isEmpty { coldStartHero }

                if let result = adoptResult { importResult(result) }

                metricStrip
                attentionSplit
                budgetRow
                footer
            }
            .padding(Space.xxl)
        }
        .background(Color.ageSurface)
        .navigationTitle("Overview")
        .confirmationDialog(
            "Copy every skill you installed yourself into the local/adopted source? The originals are left untouched.",
            isPresented: $confirmImport, titleVisibility: .visible
        ) {
            Button("Import") {
                Task { adoptResult = await model.runAdopt(importSkills: true) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Cold start

    /// Shown only when the library is empty. The numbers come from `inventory`, which
    /// `AppModel.start()` already scanned — so this screen has real content on the very
    /// first launch, rather than an empty frame waiting for the user to do something.
    private var coldStartHero: some View {
        SectionCard(title: "Start here",
                    subtitle: "AgeOS found skills already installed on this Mac. Import them to manage every agent from one library.") {
            VStack(alignment: .leading, spacing: Space.lg) {
                if let inventory = model.inventory {
                    Text(verbatim: "Found \(inventory.totalDistinctSkills) skills across \(inventory.agents.count) agents on this Mac")
                        .font(.ageTitleL)
                        .foregroundStyle(Color.ageTextPrimary)
                } else {
                    Text("Scanning this Mac…")
                        .font(.ageTitleL)
                        .foregroundStyle(Color.ageTextSecondary)
                }
                HStack(spacing: Space.md) {
                    Button("Import into library") { confirmImport = true }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.busy || model.inventory == nil)
                    Button("Add a source") { selection = .library }
                }
            }
        }
    }

    /// The import result, including the PER-SKILL ERROR LIST. The old AdoptView had
    /// this; dropping it removes the only way to learn which skill did not make it.
    private func importResult(_ result: EffectiveLoadScanner.AdoptReport) -> some View {
        SectionCard(title: "Import result",
                    accessory: AnyView(Button("Dismiss") { adoptResult = nil })) {
            VStack(alignment: .leading, spacing: Space.sm) {
                StatusPill("\(result.imported.count) imported",
                           tone: result.imported.isEmpty ? .neutral : .success,
                           icon: "checkmark.circle.fill")
                if !result.imported.isEmpty {
                    Text(verbatim: result.imported.joined(separator: ", "))
                        .font(.ageCaption)
                        .foregroundStyle(Color.ageTextSecondary)
                        .textSelection(.enabled)
                }
                if result.skippedManaged > 0 {
                    Text(verbatim: "\(result.skippedManaged) already managed by AgeOS, skipped")
                        .font(.ageCaption)
                        .foregroundStyle(Color.ageTextSecondary)
                }
                ForEach(result.errors, id: \.self) { error in
                    FindingRow(severity: .danger, message: error, status: "Import failed")
                }
            }
        }
    }

    // MARK: - Metrics

    private var metricStrip: some View {
        HStack(spacing: Space.md) {
            StatTile(value: "\(model.inventory?.totalDistinctSkills ?? 0)",
                     label: "distinct skills",
                     action: { selection = .library })
            StatTile(value: "\(model.inventory?.agents.count ?? 0)",
                     label: "agents detected",
                     action: { selection = .matrix })
            StatTile(value: "\(model.lock.skills.count)",
                     label: "managed by AgeOS",
                     outOf: "\(model.inventory?.totalDistinctSkills ?? 0)",
                     action: { selection = .matrix })
            StatTile(value: "\(multiAgentCount)",
                     label: "loaded in 2+ agents",
                     action: { selection = .diagnostics })
        }
    }

    private var multiAgentCount: Int {
        model.inventory?.byName.filter { $0.value.count >= 2 }.count ?? 0
    }

    // MARK: - Healthy / Needs attention

    private var attentionSplit: some View {
        let summary = model.attentionSummary
        let total = summary.errors + summary.warnings + summary.info
        return HStack(alignment: .top, spacing: Space.md) {
            SectionCard(title: "Health",
                        accessory: AnyView(
                            Button(model.hasRunDiagnostics ? "Rerun" : "Run diagnostics") {
                                Task {
                                    await model.runScan()
                                    await model.runDoctor(fix: false)
                                }
                            }
                            .disabled(model.busy))) {
                if !model.hasRunDiagnostics {
                    Text("Not checked yet. Run diagnostics to look for broken links, duplicates and drift.")
                        .font(.ageCallout)
                        .foregroundStyle(Color.ageTextSecondary)
                } else if total == 0 {
                    HStack(spacing: Space.sm) {
                        StatusPill("Everything healthy", tone: .success,
                                   icon: "checkmark.circle.fill")
                    }
                } else {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        attentionRow("Errors", summary.errors, .danger)
                        attentionRow("Warnings", summary.warnings, .warning)
                        attentionRow("Info", summary.info, .info)
                    }
                }
            }

            SectionCard(title: "Distribution") {
                VStack(alignment: .leading, spacing: Space.sm) {
                    LabeledContent("Sources") {
                        Text(verbatim: "\(model.sources.count)")
                            .font(.ageNumericS)
                    }
                    LabeledContent("MCP servers") {
                        Text(verbatim: "\(model.mcpServers.count)")
                            .font(.ageNumericS)
                    }
                    LabeledContent("Load entries") {
                        Text(verbatim: "\(model.inventory?.totalLoadEntries ?? 0)")
                            .font(.ageNumericS)
                    }
                }
                .font(.ageBody)
                .foregroundStyle(Color.ageTextPrimary)
            }
        }
    }

    /// Each row is a deep link into Diagnostics — not a dead number.
    private func attentionRow(_ label: String, _ count: Int, _ tone: PillTone) -> some View {
        Button { selection = .diagnostics } label: {
            HStack(spacing: Space.sm) {
                StatusPill(verbatim: "\(count)", tone: count == 0 ? .neutral : tone)
                Text(label)
                    .font(.ageBody)
                    .foregroundStyle(Color.ageTextPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.ageCaption)
                    .foregroundStyle(Color.ageTextSecondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue("\(count)")
        .accessibilityHint("Opens Diagnostics")
    }

    // MARK: - Budget cross-agent

    private var budgetRow: some View {
        SectionCard(title: "Context budget",
                    subtitle: "Always-loaded catalog tokens per agent, on one shared scale.",
                    accessory: AnyView(
                        Button(model.budgets.isEmpty ? "Measure" : "Re-measure") {
                            Task { await model.runBudget() }
                        }
                        .disabled(model.busy))) {
            if model.budgets.isEmpty {
                Text("Not measured yet. Measuring reads each agent's catalog and estimates its token cost.")
                    .font(.ageCallout)
                    .foregroundStyle(Color.ageTextSecondary)
            } else {
                VStack(alignment: .leading, spacing: Space.lg) {
                    ForEach(model.budgets, id: \.adapterId) { report in
                        VStack(alignment: .leading, spacing: Space.xs) {
                            Button { selection = .budget } label: {
                                HStack {
                                    Text(verbatim: report.adapterId)
                                        .font(.ageHeadline)
                                        .foregroundStyle(Color.ageTextPrimary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.ageCaption)
                                        .foregroundStyle(Color.ageTextSecondary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(verbatim: report.adapterId))
                            .accessibilityHint("Opens Context Budget")

                            RatioMeter(value: report.totalTokens,
                                       threshold: report.warnThreshold,
                                       scaleMax: model.budgetScaleMax,
                                       label: report.adapterId)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: Space.md) {
            if let sync = model.lastSyncAt {
                Text(verbatim: "Last sync \(sync.formatted(date: .omitted, time: .shortened))")
                    .font(.ageCaption)
                    .foregroundStyle(Color.ageTextSecondary)
            } else {
                Text("Never synced")
                    .font(.ageCaption)
                    .foregroundStyle(Color.ageTextSecondary)
            }
            Spacer()
            // Rescan the inventory WITHOUT importing. The old screen had this button;
            // without it the only way to refresh the inventory is "Sync all sources",
            // which is far heavier and touches the network. It is also the way out when
            // the scan at launch failed.
            Button("Rescan this Mac") {
                Task { _ = await model.runAdopt(importSkills: false) }
            }
            .disabled(model.busy)
            // Import stays available, not just at cold start — someone who installs a
            // skill by hand later still needs to gather it in.
            Button("Import unmanaged skills") { confirmImport = true }
                .disabled(model.busy || model.inventory == nil)
            Button("Sync all sources") { Task { await model.syncAll() } }
                .disabled(model.busy)
        }
    }
}
