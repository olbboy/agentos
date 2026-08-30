import SwiftUI
import AgeOSCore

/// MÀN ĐINH: bảng skill × agent, toggle enable/disable global scope.
/// Trạng thái đọc từ lockfile (nguồn chân lý) — FSEvents đổi là bảng tự cập nhật.
///
/// Vấn đề của bản cũ: lưới switch mini không màu, liếc qua không ra agent nào đang
/// bật gì. Bản này thêm tint nền theo trạng thái, và đưa mode + verified từ tooltip
/// lên header cột — "adapter chưa verified" là thứ cần biết TRƯỚC khi bật, không
/// phải sau khi rê chuột.
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
                skillCell(skill)
            }
            .width(min: 260)

            TableColumnForEach(model.matrixAdapters) { adapter in
                TableColumn(columnTitle(adapter)) { (skill: IndexDB.SkillRow) in
                    MatrixToggle(skillId: skill.id, adapter: adapter)
                }
                .width(130)
            }
        }
        .searchable(text: $query, prompt: "Filter skills")
        .navigationTitle("Target Matrix")
        .overlay {
            if model.skills.isEmpty {
                EmptyState(icon: "switch.2",
                           title: "No skills in the library yet",
                           message: "Go to Library to add a source.")
            }
        }
        .toolbar {
            if model.busy { ProgressView().controlSize(.small) }
        }
    }

    /// Header cột mang mode và verified. `Table` chỉ nhận `String` cho tiêu đề cột
    /// nên gộp vào một dòng, chấp nhận thay vì đánh đổi bằng bố cục phức tạp hơn.
    private func columnTitle(_ adapter: AdapterSpec) -> String {
        let mode = adapter.effectiveSkillMode.rawValue
        let verified = (adapter.skills?.verified ?? false) ? "" : " ⚠"
        return "\(adapter.displayName) · \(mode)\(verified)"
    }

    private func skillCell(_ skill: IndexDB.SkillRow) -> some View {
        let count = model.enabledAdapterCount(skillId: skill.id)
        return HStack(spacing: Space.sm) {
            // Chỉ báo KHÔNG phụ thuộc màu, đứng cạnh tint nền: người mù màu và
            // người dùng VoiceOver vẫn phân biệt được dòng đang bật.
            Image(systemName: count > 0 ? "largecircle.fill.circle" : "circle")
                .font(.ageCaption)
                .foregroundStyle(count > 0 ? Color.ageAccentBrand : Color.ageBorderSubtle)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: skill.name)
                    .font(.ageHeadline)
                    .foregroundStyle(Color.ageTextPrimary)
                Text(verbatim: skill.id)
                    .font(.ageCaption)
                    .foregroundStyle(Color.ageTextSecondary)
            }
        }
        .padding(.vertical, Space.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        // AnyShapeStyle vì `.quinary` trả về opaque type, không cùng kiểu với Color
        // nên hai nhánh của `? :` không khớp nếu để trần.
        .background(count > 0 ? AnyShapeStyle(Color.ageAccentBrand.quinary)
                              : AnyShapeStyle(Color.clear))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: skill.name))
        .accessibilityValue(count == 0 ? "not enabled anywhere"
                                       : "enabled in \(count) agents")
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
        .accessibilityLabel("\(skillId) for \(adapter.displayName)")
        .accessibilityValue(enabled ? "on" : "off")
    }

    var helpText: String {
        let mode = adapter.effectiveSkillMode.rawValue
        let verified = (adapter.skills?.verified ?? false)
            ? ""
            : " — adapter not verified on a real machine"
        return "\(adapter.id) [\(mode)]\(verified)"
    }
}
