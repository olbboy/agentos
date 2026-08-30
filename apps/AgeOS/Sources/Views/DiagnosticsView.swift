import SwiftUI
import AppKit
import AgeOSCore

/// One screen that answers "is anything wrong", ordered by how serious it is.
///
/// `doctor --fix` is NOT on the toolbar. It is the only destructive action in the
/// app, and sitting next to Scan and Rerun invites a misclick.
struct DiagnosticsView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmFix = false

    private func items(_ all: [DiagnosticItem], _ severity: DiagnosticSeverity) -> [DiagnosticItem] {
        all.filter { $0.severity == severity }
    }

    /// How many things `doctor --fix` will actually do. Used for both the button label
    /// and the confirmation — one source, so the two cannot disagree.
    private var fixableFindings: [Doctor.Finding] {
        model.doctorFindings.filter { $0.fixable && !$0.fixed }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                if model.hasRunDiagnostics {
                    // Read it ONCE for the whole render. With a library of ~100 skills
                    // `diagnostics` easily reaches 150-250 entries, and `body` runs again
                    // on every change to `busy` — re-reading it per group is pure waste.
                    let all = model.diagnostics
                    summaryBar
                    ForEach(DiagnosticSeverity.allCases, id: \.self) { severity in
                        group(severity, all)
                    }
                    methodNote
                    destructiveZone
                } else {
                    notCheckedYet
                }
            }
            .padding(Space.xxl)
        }
        .background(Color.ageSurface)
        .navigationTitle("Diagnostics")
        .confirmationDialog(fixDialogTitle, isPresented: $confirmFix, titleVisibility: .visible) {
            Button("Repair \(fixableFindings.count) findings", role: .destructive) {
                Task { await model.runDoctor(fix: true) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(verbatim: fixDialogDetail)
        }
    }

    // MARK: - Three states kept apart

    /// "Not checked" is very different from "checked and clean". Collapsing them into
    /// one blank screen throws away something the user needs.
    private var notCheckedYet: some View {
        SectionCard(title: "Not checked yet",
                    subtitle: "Diagnostics compares the lockfile against what is actually on disk, and scans every loaded skill for duplicates, deprecation and description problems.") {
            Button("Run diagnostics") {
                Task {
                    await model.runScan()
                    await model.runDoctor(fix: false)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.busy)
        }
    }

    private var summaryBar: some View {
        let s = model.attentionSummary
        return HStack(spacing: Space.md) {
            if s.errors + s.warnings + s.info == 0 {
                StatusPill("Everything healthy", tone: .success, icon: "checkmark.circle.fill")
            } else {
                StatusPill("\(s.errors) errors", tone: s.errors == 0 ? .neutral : .danger)
                StatusPill("\(s.warnings) warnings", tone: s.warnings == 0 ? .neutral : .warning)
                StatusPill("\(s.info) info", tone: s.info == 0 ? .neutral : .info)
            }
            Spacer()
            Button("Rerun scan") {
                Task {
                    await model.runScan()
                    await model.runDoctor(fix: false)
                }
            }
            .disabled(model.busy)
        }
    }

    // MARK: - Grouped by severity

    private func group(_ severity: DiagnosticSeverity, _ all: [DiagnosticItem]) -> some View {
        let rows = items(all, severity)
        return SectionCard(title: severity.title, count: rows.count) {
            if rows.isEmpty {
                // Collapsed, NOT hidden: the user needs to know it was checked and is clean.
                Text(severity.emptyMessage)
                    .font(.ageCallout)
                    .foregroundStyle(Color.ageTextSecondary)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { Divider().overlay(Color.ageBorderSubtle) }
                        FindingRow(severity: severity.tone,
                                   message: item.message,
                                   status: item.status,
                                   action: action(for: item),
                                   detail: item.detail)
                    }
                }
            }
        }
    }

    /// The action for each kind of finding.
    ///
    /// Only ONE actually changes state at row level: "Disable everywhere" for a
    /// deprecated skill, because `model.toggle` can filter by skill. Everything else is
    /// navigation (Reveal, Compare) or belongs to the screen-level CTA — `Doctor.run(fix:)`
    /// is all-or-nothing and takes no filter, so a "Repair" button on a single row
    /// would be a lie.
    private func action(for item: DiagnosticItem) -> (title: LocalizedStringKey, run: () -> Void)? {
        switch item.source {
        case .doctor(let finding):
            guard !finding.path.isEmpty else { return nil }
            return ("Reveal in Finder", { reveal(finding.path) })

        case .exactDupe(let pair), .nearDupe(let pair):
            return ("Compare", { reveal(pair.a); reveal(pair.b) })

        case .deprecated(let deprecated):
            return ("Disable everywhere", {
                // Block a second press while the first is still running. Without this
                // guard the second Task reads a stale `isEnabled`, calls disable on an
                // adapter already removed, and `LinkEngine.disable` throws `.notFound` →
                // a false error banner for an operation that actually succeeded.
                guard !model.busy else { return }
                Task {
                    for adapter in model.matrixAdapters
                    where model.isEnabled(skillId: deprecated.id, adapterId: adapter.id) {
                        await model.toggle(skillId: deprecated.id,
                                           adapterId: adapter.id, enabled: false)
                    }
                }
            })

        case .duplicatePath(_, _, let paths):
            return ("Reveal in Finder", { paths.forEach(reveal) })

        // No machine writes a description for you — say so rather than fake a button.
        case .lint:
            return nil

        // Not a problem to fix, but a check that could NOT run.
        case .scanNote:
            return nil
        }
    }

    private func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting(
            [URL(fileURLWithPath: (path as NSString).expandingTildeInPath)])
    }

    // MARK: - Method note and the destructive zone

    private var methodNote: some View {
        Text("Errors mean distribution is actually broken. Warnings mean state has drifted and will surprise you later. Info is description quality — it never affects whether a skill loads.")
            .font(.ageCaption)
            .foregroundStyle(Color.ageTextSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var destructiveZone: some View {
        SectionCard(title: "Repair",
                    subtitle: "Runs doctor --fix. It re-links, re-copies and cleans orphans across every target at once — it cannot be limited to one finding.") {
            HStack(spacing: Space.md) {
                Button("Repair all fixable (\(fixableFindings.count))") { confirmFix = true }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.ageStatusDanger)
                    .disabled(model.busy || fixableFindings.isEmpty)
                if fixableFindings.isEmpty {
                    Text("Nothing here can be repaired automatically.")
                        .font(.ageCallout)
                        .foregroundStyle(Color.ageTextSecondary)
                }
            }
        }
    }

    private var fixDialogTitle: String {
        "Repair \(fixableFindings.count) findings?"
    }

    /// Lists each item SPECIFICALLY, and calls out `copy_drift` separately — it is the
    /// only kind that OVERWRITES edits the user made by hand.
    private var fixDialogDetail: String {
        let drift = fixableFindings.filter { $0.kind == .copyDrift }
        var lines = fixableFindings.map { "• [\($0.kind.rawValue)] \($0.path)" }
        if !drift.isEmpty {
            lines.append("")
            lines.append("\(drift.count) of these are copy drift — repairing them OVERWRITES manual edits you made to those copies. This cannot be undone from inside AgeOS.")
        }
        return lines.joined(separator: "\n")
    }
}
