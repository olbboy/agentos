import XCTest
import AgeOSCore
@testable import AgeOS

/// ViewModel tests — chạy trên AGEOS_HOME tạm (setenv trước khi model chạm core).
@MainActor
final class AppModelTests: XCTestCase {
    var homeRoot: URL!

    override func setUp() async throws {
        homeRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ageos-app-test-\(UUID().uuidString.prefix(8))", isDirectory: true)
        setenv("AGEOS_HOME", homeRoot.path, 1)
        let home = AgeOSHome()
        try home.ensureLayout()

        // Fake adapter trong home tạm — model không đụng máy thật.
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
        // Nguồn local 1 skill.
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

        // Matrix adapter chỉ chứa fake-agent (bundled adapter trỏ máy thật vẫn detected
        // nhưng toggle test chỉ đụng fake-agent).
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
