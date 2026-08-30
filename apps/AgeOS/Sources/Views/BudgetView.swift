import SwiftUI
import AgeOSCore

/// Chi tiết budget từng agent. Phần SO SÁNH cross-agent thuộc về Overview —
/// màn này trả lời "agent này tốn token vào những gì".
///
/// Disclaimer ±20% chuyển từ ĐẦU xuống CUỐI màn: ở đầu nó chặn nội dung, ở cuối nó
/// trả lời đúng lúc người dùng bắt đầu hỏi "số này đáng tin không".
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

    /// Dạng hoá đơn: mỗi dòng kèm % của tổng.
    ///
    /// Con số tuyệt đối một mình không nói được cái gì đáng cắt — "≈420" chỉ có
    /// nghĩa khi biết nó là 3% hay 40% của tổng.
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
