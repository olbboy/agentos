import SwiftUI
import AgeOSCore

/// Adopt wizard: "tìm thấy N skill / M agent, K trùng" → import 1 nút.
struct AdoptView: View {
    @Environment(AppModel.self) private var model
    @State private var adoptResult: EffectiveLoadScanner.AdoptReport?
    @State private var confirmImport = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let inventory = model.inventory {
                    GroupBox {
                        HStack(spacing: 24) {
                            stat("\(inventory.totalDistinctSkills)", "skill distinct")
                            stat("\(inventory.agents.count)", "agent")
                            stat("\(inventory.totalLoadEntries)", "load entries")
                            stat("\(inventory.byName.filter { $0.value.count >= 2 }.count)", "skill ≥2 agent")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(8)
                    }

                    ForEach(inventory.agents, id: \.adapterId) { agent in
                        GroupBox("\(agent.adapterId) — \(agent.entries.count) skill (\(agent.entries.filter(\.managed).count) managed)") {
                            if agent.duplicated.isEmpty {
                                Text("Không có skill bị load trùng path")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                ForEach(agent.duplicated.sorted(by: { $0.key < $1.key }), id: \.key) { name, paths in
                                    VStack(alignment: .leading, spacing: 1) {
                                        Label("\(name) — \(paths.count) path", systemImage: "doc.on.doc")
                                            .font(.caption.weight(.medium))
                                        ForEach(paths, id: \.self) { path in
                                            Text(path).font(.caption2).foregroundStyle(.secondary)
                                                .padding(.leading, 20)
                                        }
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }
                    }

                    if let result = adoptResult {
                        GroupBox("Kết quả import") {
                            VStack(alignment: .leading) {
                                Label("Đã import \(result.imported.count) skill vào nguồn local/adopted",
                                      systemImage: "checkmark.circle.fill")
                                Text(result.imported.joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                ForEach(result.errors, id: \.self) { e in
                                    Label(e, systemImage: "xmark.circle").font(.caption).foregroundStyle(.red)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                } else {
                    ContentUnavailableView("Đang quét hiện trạng…", systemImage: "square.and.arrow.down.on.square")
                }
            }
            .padding()
        }
        .navigationTitle("Adopt")
        .toolbar {
            Button {
                Task { _ = await model.runAdopt(importSkills: false) }
            } label: {
                Label("Quét lại", systemImage: "arrow.clockwise")
            }
            .disabled(model.busy)
            .accessibilityLabel("Quét lại hiện trạng")

            Button {
                confirmImport = true
            } label: {
                Label("Import vào library", systemImage: "square.and.arrow.down")
            }
            .disabled(model.busy)
            .accessibilityLabel("Import skill user vào library")
        }
        .confirmationDialog("Copy mọi skill user tự cài (không đụng bản gốc) vào library nguồn local/adopted?",
                            isPresented: $confirmImport, titleVisibility: .visible) {
            Button("Import") {
                Task { adoptResult = await model.runAdopt(importSkills: true) }
            }
            Button("Hủy", role: .cancel) {}
        }
    }

    func stat(_ value: String, _ label: String) -> some View {
        VStack {
            Text(value).font(.title2.monospacedDigit().weight(.semibold))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}
