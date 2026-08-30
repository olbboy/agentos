import SwiftUI
import AgeOSCore

@main
struct AgeOSApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        // Do NOT give WindowGroup an id. Measured on this very project: with an id the
        // app launches without opening any window (the accessibility tree held only the
        // MenuBar, 0 of 2 runs saw a Window; dropping the id brought it straight back).
        // `defaultLaunchBehavior(.presented)` compiles but does not rescue it.
        // Consequence: the menu bar does not use `openWindow(id:)`; it goes through
        // AppKit's reopen path instead — see MenuBarView.
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

/// One destination in the sidebar. Kept separate from how they are GROUPED: grouping
/// is presentation, a destination is navigation, and Overview deep-links to one
/// without caring which group it lives in.
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

    /// Three groups instead of six flat items: what you have, what distributes it,
    /// and what checks its health.
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
            // An opaque background is REQUIRED, and measured: the default macOS
            // sidebar uses translucent material, and the `.contrast` audit fails on
            // text drawn over it. Removing these two lines brings the failures back.
            //
            // What must NOT be added here is a forced foreground color on the rows.
            // That was tried and made it worse: it fights the system's own
            // selected-row coloring, so the selected item then failed contrast.
            .scrollContentBackground(.hidden)
            .background(Color.ageSurface)
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
            // The identifier is a STABLE address for UI tests. A display label is
            // translatable and changeable, and a sidebar row inside a List does not
            // even expose its label outside the cell, so a test has nothing solid to
            // hold on to.
            .accessibilityIdentifier("sidebar." + destination.rawValue)
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

/// FSEvents saw a hand-made change inside an agent folder → suggest running doctor.
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
