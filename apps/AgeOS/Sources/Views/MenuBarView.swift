import SwiftUI
import AppKit
import AgeOSCore

/// The contents of `MenuBarExtra`.
///
/// An important CONSTRAINT: this is a **system menu**, not an ordinary view. macOS
/// accepts only a limited set of controls — `SectionCard`, `StatTile` and `RatioMeter`
/// do NOT render here. So the design-system work for this surface is "say the right
/// thing in menu items", not "apply the components".
struct MenuBarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let managed = model.lock.skills.count
        let summary = model.attentionSummary

        Text("AgeOS — \(managed) skills managed")

        // The same count Overview and Diagnostics read, so the three surfaces cannot
        // report three different numbers.
        if model.hasRunDiagnostics {
            let total = summary.errors + summary.warnings + summary.info
            if total == 0 {
                Text("No problems found")
            } else {
                Text("\(summary.errors) errors · \(summary.warnings) warnings · \(summary.info) info")
            }
        }

        if let sync = model.lastSyncAt {
            Text("Last sync: \(sync.formatted(date: .omitted, time: .shortened))")
        }

        Divider()

        // Closing the main window used to be a dead end — the only way back was to quit.
        //
        // Not `openWindow(id:)`: that needs an id on the WindowGroup, and giving it one
        // was measured to stop the app opening any window at launch. Instead this calls
        // the path macOS itself runs when the user clicks the Dock icon, and SwiftUI
        // rebuilds the WindowGroup's window.
        Button("Open AgeOS") {
            NSApp.activate(ignoringOtherApps: true)
            // Exclude the Settings window: it is also canBecomeMain, so if the user
            // closes the main window and opens Settings, the old path would only bring
            // Settings forward and the main window would never come back.
            if let existing = NSApp.windows.first(where: {
                $0.canBecomeMain && $0.identifier?.rawValue != "com_apple_SwiftUI_Settings_window"
            }) {
                existing.makeKeyAndOrderFront(nil)
            } else {
                _ = NSApp.delegate?.applicationShouldHandleReopen?(NSApp,
                                                                   hasVisibleWindows: false)
            }
        }

        Divider()

        Button("Sync every source") {
            Task { await model.syncAll() }
        }
        Button("Run doctor") {
            Task { await model.runDoctor(fix: false) }
        }

        Divider()

        Button("Quit AgeOS") {
            NSApplication.shared.terminate(nil)
        }
    }
}
