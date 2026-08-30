import SwiftUI
import AgeOSCore

/// Màn đích khi mở app. Trả lời câu hỏi đầu tiên người dùng có — "máy tôi đang ra
/// sao" — bằng dữ liệu quét từ máy thật, kể cả khi library còn rỗng.
///
/// Mọi tile ở đây phải dẫn đi đâu đó hoặc làm được việc gì đó. Tile chỉ hiện số mà
/// không bấm được thì bỏ khỏi màn này — thà ít tile mà mỗi tile có đích đến.
struct OverviewView: View {
    @Environment(AppModel.self) private var model
    @Binding var selection: Destination

    @State private var confirmImport = false
    /// Kết quả lần import gần nhất. PHẢI giữ lại: `adoptImport` bắt lỗi từng skill
    /// vào `AdoptReport.errors` và KHÔNG throw, nên nếu vứt report đi thì lỗi copy
    /// từng skill sẽ không bao giờ tới được `lastError`/ErrorBanner — người dùng
    /// tưởng import xong hết trong khi có skill âm thầm thất bại.
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

    /// Chỉ hiện khi library rỗng. Số liệu lấy từ `inventory`, thứ đã được quét trong
    /// `AppModel.start()` — nên màn này có nội dung thật ngay lần mở đầu tiên, chứ
    /// không phải một khung trống chờ người dùng làm gì đó trước.
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

    /// Kết quả import, kèm DANH SÁCH LỖI từng skill. Bản cũ (AdoptView) có phần
    /// này; bỏ đi là mất đường duy nhất để người dùng biết skill nào không vào được.
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

    /// Mỗi dòng là một deep-link sang Diagnostics — không phải một con số chết.
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
            // Import để thường trực, không chỉ lúc cold-start — người dùng cài thêm
            // skill bằng tay sau này vẫn cần gom về.
            // Quét lại inventory mà KHÔNG import. Bản cũ có nút này; thiếu nó thì
            // cách duy nhất làm mới inventory là "Sync all sources" — nặng hơn nhiều
            // và đụng network. Cũng là đường thoát khi lần quét lúc khởi động hỏng.
            Button("Rescan this Mac") {
                Task { _ = await model.runAdopt(importSkills: false) }
            }
            .disabled(model.busy)
            Button("Import unmanaged skills") { confirmImport = true }
                .disabled(model.busy || model.inventory == nil)
            Button("Sync all sources") { Task { await model.syncAll() } }
                .disabled(model.busy)
        }
    }
}
