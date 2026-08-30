import SwiftUI
import AgeOSCore

@main
struct AgeOSApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .task { await model.start() }
        }

        MenuBarExtra("AgeOS", systemImage: "square.stack.3d.up") {
            MenuBarView()
                .environment(model)
        }

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

struct ContentView: View {
    @Environment(AppModel.self) private var model

    enum Section: String, CaseIterable, Identifiable {
        case library = "Library"
        case matrix = "Target Matrix"
        case budget = "Budget"
        case scan = "Scan"
        case adopt = "Adopt"
        case mcp = "MCP Servers"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .library: "books.vertical"
            case .matrix: "switch.2"
            case .budget: "gauge.with.needle"
            case .scan: "magnifyingglass.circle"
            case .adopt: "square.and.arrow.down.on.square"
            case .mcp: "server.rack"
            }
        }
    }

    @State private var selection: Section = .library

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.icon)
                    .tag(section)
                    .accessibilityLabel(section.rawValue)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            switch selection {
            case .library: LibraryView()
            case .matrix: TargetMatrixView()
            case .budget: BudgetView()
            case .scan: ScanView()
            case .adopt: AdoptView()
            case .mcp: McpView()
            }
        }
        .frame(minWidth: 900, minHeight: 560)
        .overlay(alignment: .bottom) {
            if let error = model.lastError {
                ErrorBanner(message: error)
            }
        }
        .overlay(alignment: .topTrailing) {
            if model.suggestsDoctor {
                DoctorSuggestion()
                    .padding()
            }
        }
    }
}

struct ErrorBanner: View {
    @Environment(AppModel.self) private var model
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(message)
                .lineLimit(3)
                .textSelection(.enabled)
            Spacer()
            Button("Đóng") { model.lastError = nil }
                .accessibilityLabel("Đóng thông báo lỗi")
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .padding()
    }
}

/// FSEvents thấy thay đổi tay trong thư mục agent → gợi ý chạy doctor.
struct DoctorSuggestion: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "stethoscope")
            Text("Thư mục agent vừa thay đổi bên ngoài AgeOS")
            Button("Chạy doctor") {
                Task { await model.runDoctor(fix: false) }
            }
            .accessibilityLabel("Chạy kiểm tra doctor")
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let managed = model.lock.skills.count
        Text("AgeOS — \(managed) skill được quản lý")
        if let sync = model.lastSyncAt {
            Text("Sync gần nhất: \(sync.formatted(date: .omitted, time: .shortened))")
        }
        Divider()
        Button("Sync tất cả nguồn") {
            Task { await model.syncAll() }
        }
        Button("Chạy doctor") {
            Task { await model.runDoctor(fix: false) }
        }
        Divider()
        Button("Thoát AgeOS") {
            NSApplication.shared.terminate(nil)
        }
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            LabeledContent("Library", value: AgeOSHome().root.path)
            LabeledContent("Adapters", value: "\(model.adapters.count) (override: ~/.ageos/adapters/)")
            LabeledContent("Nguồn", value: "\(model.sources.count)")
            Text("Số liệu budget là ước lượng ±20% (hệ số 4 bytes/token, đo từ spike).")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(width: 480)
    }
}
