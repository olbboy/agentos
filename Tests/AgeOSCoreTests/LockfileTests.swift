import Foundation
import Testing
@testable import AgeOSCore

@Suite("Lockfile schema v1")
struct LockfileTests {
    @Test func roundtripIsStable() throws {
        try withTempHomeSync { home in
            var lock = Lockfile()
            lock.skills["owner/repo/demo"] = .init(
                source: "gh/owner/repo", version: "abc123",
                targets: [
                    Lockfile.targetKey(adapter: "claude-code", projectPath: nil):
                        .init(scope: "global", linkMode: .symlink, path: "/tmp/x"),
                    Lockfile.targetKey(adapter: "codex", projectPath: "/proj"):
                        .init(scope: "project", linkMode: .copy, path: "/proj/.agents/skills/demo",
                              manifestSha256: "deadbeef"),
                ])
            try lock.save(to: home.lockfilePath)
            let reloaded = try Lockfile.load(from: home.lockfilePath)
            #expect(reloaded == lock)

            // Writing twice must produce identical bytes (sorted keys) — so git diffs stay clean.
            try reloaded.save(to: home.lockfilePath)
            let a = FileManager.default.contents(atPath: home.lockfilePath.path)
            try lock.save(to: home.lockfilePath)
            let b = FileManager.default.contents(atPath: home.lockfilePath.path)
            #expect(a == b)
        }
    }

    @Test func missingFileGivesEmptyLockfile() throws {
        try withTempHomeSync { home in
            let lock = try Lockfile.load(from: home.lockfilePath)
            #expect(lock.skills.isEmpty)
            #expect(lock.schemaVersion == 1)
        }
    }

    @Test func corruptFileThrowsWithRemedy() throws {
        try withTempHomeSync { home in
            try Data("not json{{{".utf8).write(to: home.lockfilePath)
            #expect(throws: AgeOSError.self) { try Lockfile.load(from: home.lockfilePath) }
        }
    }

    @Test func targetKeyFormat() {
        #expect(Lockfile.targetKey(adapter: "grok", projectPath: nil) == "grok@global")
        #expect(Lockfile.targetKey(adapter: "grok", projectPath: "/a/b") == "grok@/a/b")
    }
}
