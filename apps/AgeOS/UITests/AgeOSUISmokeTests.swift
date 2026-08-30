import XCTest

/// UI smoke: the app launches, the sidebar is complete, nothing crashes.
///
/// These stay on XCTest rather than swift-testing: `XCUIApplication` and
/// `performAccessibilityAudit` are XCTest APIs and swift-testing has no equivalent.
/// New unit tests go the other way — they use swift-testing.
///
/// Do not let this file grow into a test per screen: UI tests are slow and flaky.
/// The pure logic already has its own tests in `DesignSystemTests` and `DiagnosticSeverityTests`.
final class AgeOSUISmokeTests: XCTestCase {

    /// A temp home per run — the tests never touch the real `~/.ageos`.
    private func makeTempHome() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ageos-ui-smoke-\(UUID().uuidString.prefix(6))").path
    }

    /// `activate()` after `launch()` is REQUIRED, not redundant.
    ///
    /// Measured: with only `launch()`, `app.windows.count == 0` and every assertion
    /// fails as though the app were broken. Adding `activate()` gives one window with
    /// full content. The app itself is fine — opened with `open -n` it always shows its
    /// "Overview" window — the difference is in how XCUITest starts the process.
    private func launch(home: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["AGEOS_HOME"] = home
        app.launch()
        app.activate()
        return app
    }

    /// The sidebar is addressed by identifier rather than by display label: a row inside
    /// a `List` does not expose its label outside the cell, and a label is translatable,
    /// so matching on it means matching on something that will change.
    private func sidebarItem(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        app.descendants(matching: .any)["sidebar.\(name)"]
    }

    private let screens = ["Overview", "Library", "Target Matrix",
                           "MCP Servers", "Context Budget", "Diagnostics"]

    /// Ignore the FRAME elements SwiftUI and AppKit generate; keep everything the app owns.
    ///
    /// Measured: after every contrast failure was fixed, 45 issues remained — 30 `Group`,
    /// 6 `TouchBar`, 2 `Outline` and a few window-chrome `Group`s. NONE carried an
    /// identifier, so none is created by the app. They are the containers SwiftUI builds
    /// implicitly for `NavigationSplitView`, `Section` and `List` — there is no API to
    /// label them, and labelling a layout group would not help VoiceOver anyway.
    ///
    /// The filter is deliberately NARROW: it ignores an element only when it is both a
    /// container type and unidentified. Add an unlabelled Button or a low-contrast
    /// StaticText and this test still goes red — that is what it exists to catch.
    private static func isFrameworkContainer(_ element: XCUIElement?) -> Bool {
        guard let element else { return false }
        guard element.identifier.isEmpty else { return false }
        switch element.elementType {
        case .group, .outline, .touchBar, .table, .scrollView, .splitGroup, .other:
            return true
        default:
            return false
        }
    }

    /// A SwiftUI `Menu` in a toolbar produces an AXMenuButton that exposes no AXPress,
    /// so the `.action` audit always reports it missing. `.accessibilityAddTraits(.isButton)`
    /// was tried and changed nothing; there is no API to add an action to a `Menu`.
    ///
    /// Ignoring it here is a deliberate acceptance, NOT hiding a defect: that the button
    /// actually works is proven by `testFilterMenuOpens`, which clicks it and checks the
    /// items inside. If the control ever breaks, that test goes red.
    private static func isSwiftUIMenuActionGap(_ issue: XCUIAccessibilityAuditIssue) -> Bool {
        issue.auditType == .action && issue.element?.elementType == .menuButton
    }

    func testLaunchShowsSidebar() throws {
        let tmp = makeTempHome()
        let app = launch(home: tmp)
        defer {
            app.terminate()
            try? FileManager.default.removeItem(atPath: tmp)
        }

        XCTAssertTrue(sidebarItem(app, "Overview").waitForExistence(timeout: 15))
        for screen in screens {
            XCTAssertTrue(sidebarItem(app, screen).exists, "Missing sidebar item '\(screen)'")
        }

        // These two dissolved into Overview and Diagnostics — anything left means the
        // old IA was not fully removed.
        XCTAssertFalse(sidebarItem(app, "Adopt").exists)
        XCTAssertFalse(sidebarItem(app, "Scan").exists)

        // The sidebar group headers are still display labels, and that is what a user reads.
        XCTAssertTrue(app.staticTexts["Distribute"].exists)
        XCTAssertTrue(app.staticTexts["Health"].exists)
    }

    /// Acceptance criterion number one for this redesign, so it is locked with a test.
    ///
    /// The bug being fixed: opening the app landed on an EMPTY Library — a blank screen
    /// with nothing to do next. Overview has to show the inventory scanned from the real
    /// machine immediately, even with a completely blank `AGEOS_HOME`, because
    /// `EffectiveLoadScanner` reads the agent folders, not `~/.ageos`.
    func testColdStartLandsOnOverview() throws {
        let tmp = makeTempHome()
        let app = launch(home: tmp)
        defer {
            app.terminate()
            try? FileManager.default.removeItem(atPath: tmp)
        }

        XCTAssertTrue(sidebarItem(app, "Overview").waitForExistence(timeout: 15))

        // The cold-start hero only appears when the library is empty — exactly this case.
        XCTAssertTrue(app.staticTexts["Start here"].waitForExistence(timeout: 15),
                      "An empty library must show the cold-start hero, not a blank screen")

        // Wait for the button to be ENABLED, not merely to exist. A disabled button exists
        // from the first render, before the scan finishes on Task.detached.
        let importButton = app.buttons["Import into library"]
        XCTAssertTrue(importButton.waitForExistence(timeout: 20))
        let enabled = expectation(for: NSPredicate(format: "isEnabled == true"),
                                  evaluatedWith: importButton)
        XCTAssertEqual(XCTWaiter().wait(for: [enabled], timeout: 30), .completed,
                       "The inventory must hold real machine data even with a blank AGEOS_HOME")

        XCTAssertTrue(app.buttons["Add a source"].exists)

        // The four StatTiles are Buttons because each deep-links somewhere — a tile that
        // only shows a number and cannot be clicked was deliberately dropped.
        for tile in ["distinct skills", "agents detected",
                     "managed by AgeOS", "loaded in 2+ agents"] {
            XCTAssertTrue(app.buttons[tile].exists, "Missing StatTile '\(tile)'")
        }
    }

    /// Covers what the `.action` audit cannot: proves the filter Menu actually opens and
    /// has items. This is why ignoring that audit issue is safe.
    func testFilterMenuOpens() throws {
        let tmp = makeTempHome()
        let app = launch(home: tmp)
        defer {
            app.terminate()
            try? FileManager.default.removeItem(atPath: tmp)
        }

        sidebarItem(app, "Library").click()
        let menu = app.descendants(matching: .any)["library.filterMenu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 15))
        XCTAssertTrue(menu.isHittable, "The filter menu must be clickable")
        menu.click()

        XCTAssertTrue(app.menuItems["Deprecated only"].waitForExistence(timeout: 10),
                      "An open menu must contain its filter items")
        XCTAssertTrue(app.menuItems["Enabled somewhere"].exists)
    }

    /// The automatic accessibility audit across all six screens.
    ///
    /// `performAccessibilityAudit()` runs EVERY audit type the platform supports — on
    /// macOS that is `.contrast`, `.sufficientElementDescription`, `.elementDetection`,
    /// `.hitRegion`, `.action` and `.parentChild`. Each problem becomes an `XCTIssue`, so
    /// the test fails on its own without hand-written assertions.
    ///
    /// It does NOT replace a human ear: the audit catches missing labels and insufficient
    /// contrast, but not a label that exists yet says nothing, or an illogical reading order.
    func testAccessibilityAuditAcrossAllScreens() throws {
        let tmp = makeTempHome()
        let app = launch(home: tmp)
        defer {
            app.terminate()
            try? FileManager.default.removeItem(atPath: tmp)
        }

        app.activate()
        XCTAssertTrue(sidebarItem(app, "Overview").waitForExistence(timeout: 15))

        for screen in screens {
            let item = sidebarItem(app, screen)
            XCTAssertTrue(item.waitForExistence(timeout: 10), "Sidebar item '\(screen)' not found")
            item.click()

            // Wait for the detail pane to actually change before auditing. Without
            // this the audit can run against the PREVIOUS screen's tree — and if that
            // one was clean, the test reports a pass for a screen it never examined.
            let title = app.staticTexts[screen]
            _ = title.waitForExistence(timeout: 10)

            XCTContext.runActivity(named: "Accessibility audit: \(screen)") { _ in
                do {
                    try app.performAccessibilityAudit { issue in
                        Self.isFrameworkContainer(issue.element)
                            || Self.isSwiftUIMenuActionGap(issue)
                    }
                } catch {
                    XCTFail("Audit failed on the \(screen) screen: \(error)")
                }
            }
        }
    }
}
