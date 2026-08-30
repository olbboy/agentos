import Foundation
import Testing
@testable import AgeOSCore

@Suite("SkillParser golden tests")
struct SkillParserTests {
    @Test func parsesValidSkill() throws {
        let parsed = try SkillParser.parse(directory: fixturesDir().appendingPathComponent("valid-skill"))
        #expect(parsed.manifest.name == "valid-skill")
        #expect(parsed.manifest.description.contains("well-formed"))
        #expect(parsed.manifest.license == "MIT")
        #expect(parsed.manifest.allowedTools == ["Bash", "Read"])
        #expect(parsed.manifest.metadata["category"] == "testing")
        #expect(parsed.manifest.extra["author"] == "ageos-tests")
        #expect(parsed.title == "Valid Skill")
        #expect(SkillValidator.validate(parsed).filter { $0.severity == .error }.isEmpty)
    }

    @Test func missingNameIsError() throws {
        let parsed = try SkillParser.parse(directory: fixturesDir().appendingPathComponent("missing-name"))
        let errors = SkillValidator.validate(parsed).filter { $0.severity == .error }
        #expect(!errors.isEmpty)
        #expect(throws: AgeOSError.self) { try SkillValidator.requireValid(parsed) }
    }

    @Test func brokenYamlThrows() {
        #expect(throws: AgeOSError.self) {
            try SkillParser.parse(directory: fixturesDir().appendingPathComponent("broken-yaml"))
        }
    }

    @Test func noFrontmatterThrows() {
        #expect(throws: AgeOSError.self) {
            try SkillParser.parse(directory: fixturesDir().appendingPathComponent("no-frontmatter"))
        }
    }

    /// The Vietnamese text and the emoji below are FIXTURE DATA, not leftovers from the
    /// translation. This test exists to prove non-ASCII content survives a parse round trip,
    /// so replacing them with English would delete the only thing it checks.
    @Test func unicodeSurvivesRoundtrip() throws {
        let parsed = try SkillParser.parse(directory: fixturesDir().appendingPathComponent("unicode-skill"))
        #expect(parsed.manifest.description.contains("tiếng Việt"))
        #expect(parsed.manifest.description.contains("🚀"))
        #expect(parsed.title == "Kỹ năng Unicode")
    }

    @Test func validatorRejectsBadNames() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Bad_Name-\(UUID().uuidString.prefix(6))")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "---\nname: Bad_Name\ndescription: x\n---\nbody".write(
            to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        let parsed = try SkillParser.parse(directory: dir)
        let errors = SkillValidator.validate(parsed).filter { $0.severity == .error }
        #expect(errors.contains { $0.message.contains("hyphen-case") })
    }

    @Test func scannerFindsNestedSkillsAndSkipsInvalid() {
        let output = SkillScanner.scan(root: fixturesDir())
        let names = output.skills.map(\.manifest.name)
        #expect(names.contains("alpha"))
        #expect(names.contains("beta"))
        #expect(names.contains("valid-skill"))
        // broken-yaml, missing-name and no-frontmatter must all appear in skipped, never swallowed.
        #expect(output.skipped.count >= 3)
    }
}
