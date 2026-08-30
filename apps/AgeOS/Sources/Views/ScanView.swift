import SwiftUI
import AgeOSCore

/// Kết quả scan: dupe/deprecated/lint + hành động doctor.
struct ScanView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmDoctorFix = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let report = model.scanReport {
                    GroupBox("Exact dupe (\(report.exactDupes.count) cặp)") {
                        dupeList(report.exactDupes)
                    }
                    GroupBox("Near dupe (\(report.nearDupes.count) cặp)") {
                        if report.nearDupeAvailable {
                            dupeList(report.nearDupes)
                        } else {
                            Text("Embedding assets không khả dụng trên máy này — chỉ quét exact.")
                                .foregroundStyle(.secondary)
                        }
                    }
                    GroupBox("Deprecated (\(report.deprecated.count))") {
                        if report.deprecated.isEmpty {
                            Text("Không có").foregroundStyle(.secondary)
                        } else {
                            ForEach(report.deprecated, id: \.id) { item in
                                Label("\(item.id) — \(item.reason)", systemImage: "xmark.seal")
                            }
                        }
                    }
                    GroupBox("Description lint (\(report.lintFindings.count) skill)") {
                        ForEach(report.lintFindings.prefix(20), id: \.id) { item in
                            VStack(alignment: .leading) {
                                Text(item.id).font(.caption.weight(.medium))
                                ForEach(item.findings, id: \.message) { finding in
                                    Text("• \(finding.message)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                } else {
                    ContentUnavailableView("Chưa quét",
                                           systemImage: "magnifyingglass.circle",
                                           description: Text("Bấm Quét để tìm dupe, deprecated và lint."))
                }

                if !model.doctorFindings.isEmpty {
                    GroupBox("Doctor (\(model.doctorFindings.count) finding)") {
                        ForEach(Array(model.doctorFindings.enumerated()), id: \.offset) { _, finding in
                            Label {
                                Text("[\(finding.kind.rawValue)] \(finding.message)")
                                    .font(.caption)
                            } icon: {
                                Image(systemName: finding.fixed ? "checkmark.circle.fill"
                                    : (finding.fixable ? "wrench" : "exclamationmark.triangle"))
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Scan")
        .toolbar {
            Button {
                Task { await model.runScan() }
            } label: {
                Label("Quét", systemImage: "magnifyingglass")
            }
            .disabled(model.busy)
            .accessibilityLabel("Quét library")

            Button {
                Task { await model.runDoctor(fix: false) }
            } label: {
                Label("Doctor", systemImage: "stethoscope")
            }
            .disabled(model.busy)
            .accessibilityLabel("Chạy doctor kiểm tra")

            Button(role: .destructive) {
                confirmDoctorFix = true
            } label: {
                Label("Doctor --fix", systemImage: "wrench.and.screwdriver")
            }
            .disabled(model.busy)
            .accessibilityLabel("Doctor tự sửa")
        }
        .confirmationDialog("Doctor --fix sẽ re-link, re-copy (ĐÈ chỉnh sửa tay trên bản copy drift) và dọn orphan. Tiếp tục?",
                            isPresented: $confirmDoctorFix, titleVisibility: .visible) {
            Button("Sửa tất cả", role: .destructive) {
                Task { await model.runDoctor(fix: true) }
            }
            Button("Hủy", role: .cancel) {}
        }
    }

    @ViewBuilder
    func dupeList(_ pairs: [DedupeEngine.DupePair]) -> some View {
        if pairs.isEmpty {
            Text("Không có").foregroundStyle(.secondary)
        } else {
            ForEach(Array(pairs.prefix(30).enumerated()), id: \.offset) { _, pair in
                VStack(alignment: .leading, spacing: 1) {
                    HStack {
                        Text(pair.kind == .exact ? "=" : "≈ \(String(format: "%.3f", pair.score))")
                            .font(.caption.monospaced())
                            .foregroundStyle(.orange)
                        Text(pair.a).font(.caption)
                    }
                    Text(pair.b).font(.caption).padding(.leading, 24)
                }
                .padding(.vertical, 2)
            }
        }
    }
}
