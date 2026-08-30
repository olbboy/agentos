import XCTest
import AgeOSCore
@testable import AgeOS

/// View-model tests — run against a temporary AGEOS_HOME (setenv before the model
/// touches core).
@MainActor
final class AppModelTests: XCTestCase {
    var homeRoot: URL!

    override func setUp() async throws {
        homeRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ageos-app-test-\(UUID().uuidString.prefix(8))", isDirectory: true)
        setenv("AGEOS_HOME", homeRoot.path, 1)
        let home = AgeOSHome()
        try home.ensureLayout()

        // A fake adapter inside the temp home — the model never touches the real machine.
        let agentDir = homeRoot.appendingPathComponent("fake-agent/skills", isDirectory: true)
        try FileManager.default.createDirectory(at: agentDir, withIntermediateDirectories: true)
        try """
        {"schemaVersion": 1, "id": "fake-agent", "displayName": "Fake",
         "detect": ["\(homeRoot.path)/fake-agent"],
         "skills": {"globalPath": "\(agentDir.path)", "projectPath": null,
                    "folderSymlink": true, "fileSymlink": false,
                    "preferredMode": "symlink", "verified": true},
         "mcp": null, "budget": null, "notes": null}
        """.write(to: home.adaptersDir.appendingPathComponent("fake-agent.json"),
                  atomically: true, encoding: .utf8)
    }

    override func tearDown() async throws {
        unsetenv("AGEOS_HOME")
        try? FileManager.default.removeItem(at: homeRoot)
    }

    func testRefreshOnEmptyHomeDoesNotCrash() async throws {
        let model = AppModel()
        await model.refreshAll()
        XCTAssertNil(model.lastError)
        XCTAssertTrue(model.skills.isEmpty)
        XCTAssertFalse(model.adapters.isEmpty) // bundled + fake
    }

    func testAddSourceToggleFlow() async throws {
        // A local source with one skill.
        let src = homeRoot.appendingPathComponent("src/toggle-me", isDirectory: true)
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        try """
        ---
        name: toggle-me
        description: Skill for AppModel toggle flow test with enough description length.
        ---
        # Toggle
        """.write(to: src.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let model = AppModel()
        await model.addSource(src.deletingLastPathComponent().path)
        XCTAssertNil(model.lastError)
        XCTAssertEqual(model.skills.count, 1)
        let skillId = model.skills[0].id

        // The matrix adapters hold only the fake agent (bundled adapters pointing at the
        // real machine are still detected, but the toggle test only touches the fake one).
        XCTAssertFalse(model.isEnabled(skillId: skillId, adapterId: "fake-agent"))
        await model.toggle(skillId: skillId, adapterId: "fake-agent", enabled: true)
        XCTAssertNil(model.lastError)
        XCTAssertTrue(model.isEnabled(skillId: skillId, adapterId: "fake-agent"))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: homeRoot.appendingPathComponent("fake-agent/skills/toggle-me/SKILL.md").path))

        await model.toggle(skillId: skillId, adapterId: "fake-agent", enabled: false)
        XCTAssertFalse(model.isEnabled(skillId: skillId, adapterId: "fake-agent"))
    }

    func testErrorSurfacesToBanner() async throws {
        let model = AppModel()
        await model.addSource("https://definitely-not-github/invalid")
        XCTAssertNotNil(model.lastError)
    }
}
