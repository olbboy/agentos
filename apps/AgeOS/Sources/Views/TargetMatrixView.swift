import SwiftUI
import AgeOSCore

/// MÀN ĐINH: bảng skill × agent, toggle enable/disable global scope.
/// Trạng thái đọc từ lockfile (nguồn chân lý) — FSEvents đổi là bảng tự cập nhật.
struct TargetMatrixView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""

    var rows: [IndexDB.SkillRow] {
        query.isEmpty ? model.skills
            : model.skills.filter { $0.id.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        Table(rows) {
            TableColumn("Skill") { skill in
                VStack(alignment: .leading) {
                    Text(skill.name).fontWeight(.medium)
                    Text(skill.id).font(.caption).foregroundStyle(.secondary)
                }
            }
            .width(min: 220)

            TableColumnForEach(model.matrixAdapters) { adapter in
                TableColumn(adapter.displayName) { (skill: IndexDB.SkillRow) in
                    MatrixToggle(skillId: skill.id, adapter: adapter)
                }
                .width(110)
            }
        }
        .searchable(text: $query, prompt: "Lọc skill")
        .navigationTitle("Target Matrix")
        .overlay {
            if model.skills.isEmpty {
                ContentUnavailableView("Chưa có skill trong library",
                                       systemImage: "switch.2",
                                       description: Text("Sang tab Library để thêm nguồn."))
            }
        }
        .toolbar {
            if model.busy { ProgressView().controlSize(.small) }
        }
    }
}

struct MatrixToggle: View {
    @Environment(AppModel.self) private var model
    let skillId: String
    let adapter: AdapterSpec

    var body: some View {
        let enabled = model.isEnabled(skillId: skillId, adapterId: adapter.id)
        Toggle(isOn: Binding(
            get: { enabled },
            set: { newValue in
                Task { await model.toggle(skillId: skillId, adapterId: adapter.id, enabled: newValue) }
            }
        )) {
            EmptyView()
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
        .help(helpText)
        .accessibilityLabel("\(skillId) cho \(adapter.displayName)")
        .accessibilityValue(enabled ? "đang bật" : "đang tắt")
    }

    var helpText: String {
        let mode = adapter.effectiveSkillMode.rawValue
        let verified = (adapter.skills?.verified ?? false) ? "" : " — adapter chưa verified"
        return "\(adapter.id) [\(mode)]\(verified)"
    }
}
