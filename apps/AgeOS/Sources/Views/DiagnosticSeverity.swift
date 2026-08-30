import Foundation
import SwiftUI
import AgeOSCore

/// How serious a finding is. Declaration order is display priority.
enum DiagnosticSeverity: Int, CaseIterable, Comparable {
    case error = 0, warning = 1, info = 2

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .error:   "Errors"
        case .warning: "Warnings"
        case .info:    "Info"
        }
    }

    /// What an empty group says. "Checked and clean" reads very differently from "not checked".
    var emptyMessage: LocalizedStringKey {
        switch self {
        case .error:   "No errors"
        case .warning: "No warnings"
        case .info:    "No suggestions"
        }
    }

    var tone: PillTone {
        switch self {
        case .error:   .danger
        case .warning: .warning
        case .info:    .info
        }
    }
}

/// One finding, normalized from every source (Doctor, ScanEngine, the inventory) into
/// a single shape.
///
/// Why fold them together: to a user, "is anything wrong" is ONE question. Keeping
/// Doctor and Scan as separate models forces them to remember which finds what.
struct DiagnosticItem: Identifiable {
    /// What produced this finding. The view reads `source` to decide which action to
    /// attach — a closure cannot live in a plain model, so the model carries data only.
    enum Source {
        case doctor(Doctor.Finding)
        case exactDupe(DedupeEngine.DupePair)
        case nearDupe(DedupeEngine.DupePair)
        case deprecated(ScanEngine.ScanReport.DeprecatedItem)
        case lint(skillId: String, finding: DescriptionLinter.Finding)
        case duplicatePath(adapterId: String, name: String, paths: [String])
        /// Part of the scan that could NOT run (for example, no embedding assets here).
        /// It has to be said, because "could not check" differs from "checked and clean".
        case scanNote(String)
    }

    let id: String
    let severity: DiagnosticSeverity
    let message: String
    /// The secondary line: a path or an id. Data, not prose.
    let detail: String?
    let status: LocalizedStringKey
    let source: Source
}

extension DiagnosticSeverity {
    /// Maps a `Doctor.Kind` to a severity.
    ///
    /// There is deliberately NO `default`. If core adds a kind, the compiler stops here;
    /// with a `default` the new finding would silently land in the wrong group.
    /// This is the cheapest fence available.
    static func of(_ kind: Doctor.Finding.Kind) -> DiagnosticSeverity {
        switch kind {
        // Distribution is genuinely broken — the agent cannot load the skill.
        case .brokenLink, .missingTarget, .storeMissing, .adapterUnknown:
            .error
        // State has drifted: not broken yet, but it will surprise you.
        case .copyDrift, .orphanFile, .agentPathMissing, .userShadow:
            .warning
        }
    }
}

/// Folds every finding source into one classified list.
///
/// A pure function (it never reads `AppModel`) so it is testable, and so Overview and
/// Diagnostics share exactly one count — each screen aggregating for itself is the
/// surest way to have them report two different numbers.
enum DiagnosticsBuilder {

    /// THE TRANSLATION BOUNDARY:
    ///
    /// - Messages the **app** writes → `String(localized:)`, into the String Catalog.
    /// - Messages **core** emits (`Doctor.Finding.message`, lint messages,
    ///   `ScanReport.notes`) → passed through, NOT wrapped. They are data flowing
    ///   through, and core has no i18n layer; wrapping them would only fill the catalog
    ///   with hundreds of keys nobody can translate, since the content is built at runtime.
    static func build(doctorFindings: [Doctor.Finding],
                      scanReport: ScanEngine.ScanReport?,
                      inventory: EffectiveLoadScanner.Inventory?) -> [DiagnosticItem] {
        var items: [DiagnosticItem] = []

        for (i, f) in doctorFindings.enumerated() {
            items.append(DiagnosticItem(
                id: "doctor-\(i)-\(f.kind.rawValue)",
                severity: .of(f.kind),
                message: f.message,
                detail: f.path.isEmpty ? f.skillId : f.path,
                // "Fixable" means the screen-level CTA can fix it, NOT this row's button.
                status: f.fixed ? "Fixed" : (f.fixable ? "Fixable" : "No automatic fix"),
                source: .doctor(f)))
        }

        if let report = scanReport {
            for (i, p) in report.exactDupes.enumerated() {
                items.append(DiagnosticItem(
                    id: "exact-\(i)",
                    // Two identical copies are definitely waste, not "possibly".
                    severity: .error,
                    message: String(localized: "Exact duplicate: the same skill exists twice"),
                    detail: "\(p.a)  ·  \(p.b)",
                    status: "No automatic fix",
                    source: .exactDupe(p)))
            }
            for (i, p) in report.nearDupes.enumerated() {
                let score = String(format: "%.2f", p.score)
                items.append(DiagnosticItem(
                    id: "near-\(i)",
                    severity: .warning,
                    message: String(localized: "Near duplicate (cosine \(score))"),
                    detail: "\(p.a)  ·  \(p.b)",
                    status: "No automatic fix",
                    source: .nearDupe(p)))
            }
            for item in report.deprecated {
                items.append(DiagnosticItem(
                    id: "deprecated-\(item.id)",
                    severity: .warning,
                    message: String(localized: "Marked deprecated: \(item.reason)"),
                    detail: item.id,
                    status: "Action required",
                    source: .deprecated(item)))
            }
            for lint in report.lintFindings {
                for f in lint.findings {
                    items.append(DiagnosticItem(
                        id: "lint-\(lint.id)-\(f.rule.rawValue)",
                        // Description quality — never affects whether anything loads.
                        severity: .info,
                        message: f.message,
                        detail: lint.id,
                        status: "No automatic fix",
                        source: .lint(skillId: lint.id, finding: f)))
                }
            }
        }

        // Scan notes — usually "this part could not run on your machine".
        // They must NOT be dropped: if near-duplicate detection never ran and the screen
        // still reports "No warnings", the user believes it was checked and came back
        // clean. That is lying by omission.
        if let report = scanReport {
            for (i, note) in report.notes.enumerated() {
                items.append(DiagnosticItem(
                    id: "note-\(i)",
                    severity: .warning,
                    message: note,
                    detail: nil,
                    status: "Not checked",
                    source: .scanNote(note)))
            }
            if !report.nearDupeAvailable && report.notes.isEmpty {
                items.append(DiagnosticItem(
                    id: "note-neardupe",
                    severity: .warning,
                    message: String(localized: "Near-duplicate detection did not run on this machine — only exact duplicates were checked"),
                    detail: nil,
                    status: "Not checked",
                    source: .scanNote("nearDupeUnavailable")))
            }
        }

        if let inventory {
            for agent in inventory.agents {
                for (name, paths) in agent.duplicated.sorted(by: { $0.key < $1.key }) {
                    items.append(DiagnosticItem(
                        id: "duppath-\(agent.adapterId)-\(name)",
                        severity: .warning,
                        message: String(localized: "'\(name)' is loaded from \(paths.count) paths in \(agent.adapterId)"),
                        detail: paths.joined(separator: "  ·  "),
                        status: "Action required",
                        source: .duplicatePath(adapterId: agent.adapterId,
                                               name: name, paths: paths)))
                }
            }
        }

        return items
    }
}
