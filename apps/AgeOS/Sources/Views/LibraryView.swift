import SwiftUI
import AgeOSCore

/// Library browser: search + filter, add nguồn, sync.
struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var newSource = ""
    @State private var showDeprecatedOnly = false

    var filtered: [IndexDB.SkillRow] {
        model.skills.filter { skill in
            (!showDeprecatedOnly || skill.deprecated)
                && (query.isEmpty
                    || skill.id.localizedCaseInsensitiveContains(query)
                    || skill.description.localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Thêm nguồn: https://github.com/owner/repo hoặc path local", text: $newSource)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addSource() }
                    .accessibilityLabel("Nhập URL nguồn skill")
                Button("Thêm & Sync") { addSource() }
                    .disabled(newSource.isEmpty || model.busy)
                    .accessibilityLabel("Thêm nguồn và đồng bộ")
                Button {
                    Task { await model.syncAll() }
                } label: {
                    Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(model.busy)
                .accessibilityLabel("Đồng bộ mọi nguồn")
            }
            .padding()

            List(filtered, id: \.id) { skill in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(skill.id).font(.headline)
                        if skill.deprecated {
                            Text("deprecated")
                                .font(.caption2)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(.red.opacity(0.2), in: Capsule())
                        }
                        Spacer()
                        Text(skill.version).font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                    Text(skill.description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .padding(.vertical, 3)
            }
            .searchable(text: $query, placement: .automatic, prompt: "Tìm skill")
            .overlay {
                if model.skills.isEmpty {
                    ContentUnavailableView("Library trống",
                                           systemImage: "books.vertical",
                                           description: Text("Thêm nguồn GitHub hoặc thư mục local để bắt đầu."))
                }
            }
        }
        .navigationTitle("Library (\(filtered.count))")
        .toolbar {
            Toggle("Chỉ deprecated", isOn: $showDeprecatedOnly)
                .accessibilityLabel("Chỉ hiện skill deprecated")
        }
    }

    private func addSource() {
        let value = newSource.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return }
        newSource = ""
        Task { await model.addSource(value) }
    }
}
