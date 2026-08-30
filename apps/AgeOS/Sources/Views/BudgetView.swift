import SwiftUI
import AgeOSCore

/// Per-agent budget detail. The cross-agent COMPARISON belongs to Overview — this
/// screen answers "what is this agent spending its tokens on".
///
/// The ±20% disclaimer moved from the TOP to the BOTTOM: at the top it blocks the
/// content, at the bottom it answers exactly when the user starts asking whether to
/// trust the number.
struct BudgetView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                ForEach(model.budgets, id: \.adapterId) { report in
                    agentCard(report)
                }

                if model.budgets.isEmpty {
                    EmptyState(icon: "gauge.with.needle",
                               title: "Not measured yet",
                               message: "Press Measure budget to run it.")
                } else {
                    methodNote
                }
            }
            .padding(Space.xxl)
        }
        .background(Color.ageSurface)
        .navigationTitle("Context Budget")
        .toolbar {
            Button {
                Task { await model.runBudget() }
            } label: {
                Label("Measure budget", systemImage: "arrow.clockwise")
            }
            .disabled(model.busy)
            .accessibilityLabel("Measure the budget again")
        }
        .task {
            if model.budgets.isEmpty { await model.runBudget() }
        }
    }

    private func agentCard(_ report: BudgetMeter.Report) -> some View {
        SectionCard(verbatimTitle: report.adapterId) {
            VStack(alignment: .leading, spacing: Space.lg) {
                RatioMeter(value: report.totalTokens,
                           threshold: report.warnThreshold,
                           scaleMax: model.budgetScaleMax,
                           label: report.adapterId)

                HStack(spacing: Space.xl) {
                    StatusPill("\(report.skillCount) skills ≈\(report.skillTokens) tk",
                               tone: .neutral, icon: "books.vertical")
                    StatusPill("\(report.mcpCount) MCP ≈\(report.mcpTokens) tk",
                               tone: .neutral, icon: "server.rack")
                    if !report.mcpUnknownHealth.isEmpty {
                        StatusPill("\(report.mcpUnknownHealth.count) not measured",
                                   tone: .warning, icon: "questionmark.circle")
                    }
                }

                if !report.topSkills.isEmpty {
                    topSkills(report)
                }

                ForEach(report.warnings, id: \.self) { warning in
                    FindingRow(severity: .warning, message: warning,
                               status: "Action required")
                }
            }
        }
    }

    /// An itemized receipt: every line carries its share of the total.
    ///
    /// An absolute number alone cannot tell you what is worth cutting — "≈420" only
    /// means something once you know whether it is 3% or 40% of the total.
    private func topSkills(_ report: BudgetMeter.Report) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text("Top consumers")
                .font(.ageCallout)
                .foregroundStyle(Color.ageTextSecondary)

            ForEach(report.topSkills.prefix(5), id: \.name) { entry in
                let share = report.totalTokens > 0
                    ? Double(entry.tokens) / Double(report.totalTokens) * 100
                    : 0
                HStack(spacing: Space.sm) {
                    Text(verbatim: entry.name)
                        .font(.ageBody)
                        .foregroundStyle(Color.ageTextPrimary)
                        .lineLimit(1)
                    Spacer()
                    Text(verbatim: String(format: "%.1f%%", share))
                        .font(.ageNumericS)
                        .foregroundStyle(Color.ageTextSecondary)
                    Text(verbatim: "≈\(entry.tokens)")
                        .font(.ageNumericS)
                        .foregroundStyle(Color.ageTextPrimary)
                        .frame(minWidth: 60, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text(verbatim: entry.name))
                .accessibilityValue(String(format: "about %d tokens, %.1f percent of this agent's catalog",
                                           entry.tokens, share))
            }
        }
    }

    private var methodNote: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text("How these numbers are produced")
                .font(.ageCallout)
                .foregroundStyle(Color.ageTextPrimary)
            Text("Each skill costs its name plus its description (truncated the way that agent truncates it) plus about 30 characters of surrounding format, divided by 4 bytes per token. That puts the estimate within roughly ±20%. To check it yourself: toggle a skill on and off, then compare /context in that agent.")
                .font(.ageCaption)
                .foregroundStyle(Color.ageTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
