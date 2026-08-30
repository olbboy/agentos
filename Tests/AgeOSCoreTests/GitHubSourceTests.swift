import Foundation
import Testing
@testable import AgeOSCore

@Suite("GitHubSource over a mocked HTTP client")
struct GitHubSourceTests {
    @Test func descriptorParsing() throws {
        for input in ["https://github.com/Owner/Repo", "github.com/owner/repo/", "owner/repo.git", "owner/repo"] {
            let d = try GitHubSource.makeDescriptor(url: input)
            #expect(d.id == "gh/owner/repo")
            #expect(d.namespace == "owner/repo")
        }
        #expect(throws: AgeOSError.self) { _ = try GitHubSource.makeDescriptor(url: "not a url") }
        #expect(throws: AgeOSError.self) { _ = try GitHubSource.makeDescriptor(url: "https://github.com/only-owner") }
    }

    func stubs(sha: String, tarball: Data, archived: Bool = false) -> [String: MockHTTPClient.Stub] {
        let meta = """
        {"default_branch": "main", "archived": \(archived), "stargazers_count": 42,
         "pushed_at": "2026-08-01T00:00:00Z", "license": {"spdx_id": "MIT"}}
        """
        return [
            "https://api.github.com/repos/owner/repo": .init(status: 200, data: Data(meta.utf8),
                                                             headers: ["ETag": "W/\"etag1\""]),
            "https://api.github.com/repos/owner/repo/commits/main": .init(status: 200, data: Data(sha.utf8)),
            "https://api.github.com/repos/owner/repo/tarball/\(sha)": .init(status: 200, data: tarball),
        ]
    }

    @Test func fetchInstallsSkillsFromTarball() async throws {
        try await withTempHome { home in
            // A fake repo: one skill, packed like GitHub does (a top dir named owner-repo-sha).
            let repoDir = home.root.appendingPathComponent("fake-repo")
            try makeSkillDir(in: repoDir, name: "gh-skill", description: "skill delivered via fake github tarball")
            let sha = "abcdef1234567890abcdef1234567890abcdef12"
            let tarball = try Data(contentsOf: makeTarball(of: repoDir, topDirName: "owner-repo-abcdef1"))

            let engine = try SyncEngine(home: home, http: MockHTTPClient(stubs: stubs(sha: sha, tarball: tarball)))
            try engine.registry.add(GitHubSource.makeDescriptor(url: "owner/repo"))
            let reports = try await engine.sync()
            #expect(reports.count == 1)
            #expect(reports[0].changed)
            #expect(reports[0].version == String(sha.prefix(12)))
            #expect(reports[0].installed == ["owner/repo/gh-skill"])

            // A second sync at the same sha → a no-op, with no tarball needed.
            let again = try await engine.sync()
            #expect(again[0].changed == false)
        }
    }

    @Test func archivedRepoFlagsDeprecated() async throws {
        try await withTempHome { home in
            let repoDir = home.root.appendingPathComponent("fake-repo")
            try makeSkillDir(in: repoDir, name: "old-skill", description: "skill from archived repository")
            let sha = "1234567890abcdef1234567890abcdef12345678"
            let tarball = try Data(contentsOf: makeTarball(of: repoDir, topDirName: "owner-repo-1234567"))

            let engine = try SyncEngine(home: home,
                                        http: MockHTTPClient(stubs: stubs(sha: sha, tarball: tarball, archived: true)))
            try engine.registry.add(GitHubSource.makeDescriptor(url: "owner/repo"))
            let reports = try await engine.sync()
            #expect(reports[0].archived)
            let row = try engine.index.findSkill(id: "owner/repo/old-skill")
            #expect(row?.deprecated == true)
        }
    }

    @Test func rateLimitGivesActionableError() async throws {
        try await withTempHome { home in
            let engine = try SyncEngine(home: home, http: MockHTTPClient(stubs: [
                "https://api.github.com/repos/owner/repo": .init(status: 403, data: Data()),
            ]))
            try engine.registry.add(GitHubSource.makeDescriptor(url: "owner/repo"))
            do {
                _ = try await engine.sync()
                Issue.record("It must throw a rate-limit error")
            } catch let error as AgeOSError {
                #expect(error.code == .rateLimited)
                #expect(error.remedy?.contains("GITHUB_TOKEN") == true)
            }
        }
    }
}
