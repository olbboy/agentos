import SwiftUI
import AgeOSCore

/// Budget dashboard: token catalog per agent + cảnh báo ngưỡng.
struct BudgetView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Mỗi con số là ƯỚC LƯỢNG ±20% (hệ số 4 bytes/token). Đối chiếu: bật/tắt skill rồi so /context trong agent.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                ForEach(model.budgets, id: \.adapterId) { report in
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(report.adapterId).font(.headline)
                                Spacer()
                                Text("≈\(report.totalTokens) tokens luôn-tải")
                                    .font(.title3.monospacedDigit())
                                    .foregroundStyle(report.warnings.isEmpty ? Color.primary : Color.orange)
                            }
                            if let threshold = report.warnThreshold {
                                ProgressView(value: min(Double(report.totalTokens), Double(threshold)),
                                             total: Double(threshold))
                                    .tint(report.totalTokens > threshold ? .red : .accentColor)
                                    .accessibilityLabel("Mức dùng budget của \(report.adapterId)")
                            }
                            HStack(spacing: 16) {
                                Label("\(report.skillCount) skills ≈\(report.skillTokens)", systemImage: "books.vertical")
                                Label("\(report.mcpCount) MCP ≈\(report.mcpTokens)", systemImage: "server.rack")
                            }
                            .font(.callout)
                            ForEach(report.topSkills.prefix(5), id: \.name) { entry in
                                HStack {
                                    Text(entry.name).font(.caption)
                                    Spacer()
                                    Text("≈\(entry.tokens)").font(.caption.monospacedDigit())
                                }
                                .foregroundStyle(.secondary)
                            }
                            ForEach(report.warnings, id: \.self) { warning in
                                Label(warning, systemImage: "exclamationmark.triangle")
                                    .font(.callout)
                                    .foregroundStyle(.orange)
                            }
                        }
                        .padding(4)
                    }
                }

                if model.budgets.isEmpty {
                    ContentUnavailableView("Chưa có số liệu",
                                           systemImage: "gauge.with.needle",
                                           description: Text("Bấm Tính budget để đo."))
                }
            }
            .padding()
        }
        .navigationTitle("Context Budget")
        .toolbar {
            Button {
                Task { await model.runBudget() }
            } label: {
                Label("Tính budget", systemImage: "arrow.clockwise")
            }
            .disabled(model.busy)
            .accessibilityLabel("Tính lại budget")
        }
        .task {
            if model.budgets.isEmpty { await model.runBudget() }
        }
    }
}
