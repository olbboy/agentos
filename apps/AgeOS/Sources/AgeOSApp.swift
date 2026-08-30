import SwiftUI
import AgeOSCore

@main
struct AgeOSApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        // KHÔNG đặt id cho WindowGroup. Đo được trên chính project này: đặt id thì
        // app khởi động mà không mở cửa sổ nào (cây accessibility chỉ có MenuBar,
        // 0/2 lần chạy thấy Window; bỏ id ra thì thấy ngay). `defaultLaunchBehavior
        // (.presented)` biên dịch được nhưng không cứu được.
        // Hệ quả: menu bar không dùng `openWindow(id:)` mà đi đường reopen của
        // AppKit — xem MenuBarView.
        WindowGroup {
            ContentView()
                .environment(model)
                .task { await model.start() }
        }
        // Đo được: WindowGroup CÓ id thì app khởi động KHÔNG mở cửa sổ nào.
        // defaultLaunchBehavior(.presented) ép nó mở, để vẫn giữ được id cho
        // openWindow(id:) của menu bar.

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

/// Một đích trong sidebar. Tách khỏi việc NHÓM chúng lại: nhóm là chuyện trình bày,
/// đích là chuyện điều hướng, và Overview cần deep-link tới đích mà không quan tâm
/// nó nằm nhóm nào.
enum Destination: String, CaseIterable, Identifiable, Hashable {
    case overview = "Overview"
    case library = "Library"
    case matrix = "Target Matrix"
    case mcp = "MCP Servers"
    case budget = "Context Budget"
    case diagnostics = "Diagnostics"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .overview:    "square.grid.2x2"
        case .library:     "books.vertical"
        case .matrix:      "switch.2"
        case .mcp:         "server.rack"
        case .budget:      "gauge.with.needle"
        case .diagnostics: "stethoscope"
        }
    }

    /// Ba nhóm thay cho 6 mục phẳng: cái đang có tổng quan, cái để phân phối,
    /// cái để kiểm tra sức khoẻ.
    enum Group: String, CaseIterable, Identifiable {
        case none = ""
        case distribute = "Distribute"
        case health = "Health"

        var id: String { rawValue }

        var destinations: [Destination] {
            switch self {
            case .none:       [.overview]
            case .distribute: [.library, .matrix, .mcp]
            case .health:     [.budget, .diagnostics]
            }
        }
    }
}

struct ContentView: View {
    @Environment(AppModel.self) private var model

    @State private var selection: Destination = .overview

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(Destination.Group.allCases) { group in
                    if group == .none {
                        ForEach(group.destinations) { row($0) }
                    } else {
                        Section(group.rawValue) {
                            ForEach(group.destinations) { row($0) }
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
        } detail: {
            switch selection {
            case .overview:    OverviewView(selection: $selection)
            case .library:     LibraryView()
            case .matrix:      TargetMatrixView()
            case .mcp:         McpView()
            case .budget:      BudgetView()
            case .diagnostics: DiagnosticsView()
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

    private func row(_ destination: Destination) -> some View {
        Label(destination.rawValue, systemImage: destination.icon)
            .tag(destination)
            .accessibilityLabel(destination.rawValue)
    }
}

struct ErrorBanner: View {
    @Environment(AppModel.self) private var model
    let message: String

    var body: some View {
        HStack(spacing: Space.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.ageStatusDanger)
            Text(verbatim: message)
                .font(.ageBody)
                .foregroundStyle(Color.ageTextPrimary)
                .lineLimit(3)
                .textSelection(.enabled)
            Spacer()
            Button("Dismiss") { model.lastError = nil }
                .accessibilityLabel("Dismiss the error message")
        }
        .padding(Space.md)
        .background(Color.ageSurfaceRaised, in: RoundedRectangle(cornerRadius: Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .strokeBorder(Color.ageStatusDanger, lineWidth: Stroke.hairline)
        )
        .padding(Space.lg)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error")
        .accessibilityValue(Text(verbatim: message))
    }
}

/// FSEvents thấy thay đổi tay trong thư mục agent → gợi ý chạy doctor.
struct DoctorSuggestion: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: Space.sm) {
            Image(systemName: "stethoscope")
                .foregroundStyle(Color.ageStatusInfo)
            Text("An agent folder changed outside AgeOS")
                .font(.ageBody)
                .foregroundStyle(Color.ageTextPrimary)
            Button("Run doctor") {
                Task { await model.runDoctor(fix: false) }
            }
            .accessibilityLabel("Run a doctor check")
        }
        .padding(Space.md)
        .background(Color.ageSurfaceRaised, in: RoundedRectangle(cornerRadius: Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .strokeBorder(Color.ageBorderSubtle, lineWidth: Stroke.hairline)
        )
    }
}
