import Foundation
import Testing
@testable import AgeOSCore

@Suite("SyncEngine + LocalSource + Index")
struct SyncEngineTests {
    @Test func localSourceEndToEnd() async throws {
        try await withTempHome { home in
            // Nguồn local có 2 skill.
            let src = home.root.appendingPathComponent("my-skills-src")
            try makeSkillDir(in: src, name: "skill-one", description: "first local skill end to end")
            try makeSkillDir(in: src, name: "skill-two", description: "second local skill end to end")

            let engine = try SyncEngine(home: home)
            let (descriptor, report) = try await engine.addSource(src.path)
            #expect(descriptor.id == "local/my-skills-src")
            #expect(report.changed)
            #expect(report.installed.count == 2)

            // Index có đủ 2 skill.
            let listed = try engine.index.listSkills()
            #expect(listed.map(\.name).sorted() == ["skill-one", "skill-two"])

            // Sync lần 2 không đổi → no-op.
            let second = try await engine.sync(sourceId: descriptor.id)
            #expect(second.count == 1)
            #expect(second[0].changed == false)

            // Sửa nội dung → version mới, current swap.
            try "---\nname: skill-one\ndescription: EDITED description now different\n---\nbody"
                .write(to: src.appendingPathComponent("skill-one/SKILL.md"), atomically: true, encoding: .utf8)
            let third = try await engine.sync(sourceId: descriptor.id)
            #expect(third[0].changed == true)
            let ref = SkillRef(namespace: descriptor.namespace, name: "skill-one")
            let parsed = try SkillParser.parse(directory: engine.store.currentLink(ref))
            #expect(parsed.manifest.description.contains("EDITED"))
        }
    }

    @Test func reindexRebuildsAfterIndexLoss() async throws {
        try await withTempHome { home in
            let src = home.root.appendingPathComponent("src")
            try makeSkillDir(in: src, name: "rebuild-me", description: "skill for reindex test")
            var engine = try SyncEngine(home: home)
            _ = try await engine.addSource(src.path)
            #expect(try engine.index.listSkills().count == 1)

            // Mất index.sqlite → reindex khôi phục từ filesystem.
            try FileManager.default.removeItem(at: home.indexPath)
            engine = try SyncEngine(home: home)
            try engine.index.rebuild(home: home, store: engine.store, registry: engine.registry)
            let rows = try engine.index.listSkills()
            #expect(rows.count == 1)
            #expect(rows.first?.name == "rebuild-me")
            #expect(rows.first?.sourceId == "local/src")
        }
    }

    @Test func resolveSkillByShortName() async throws {
        try await withTempHome { home in
            let src = home.root.appendingPathComponent("src")
            try makeSkillDir(in: src, name: "unique-name", description: "resolvable by short name")
            let engine = try SyncEngine(home: home)
            _ = try await engine.addSource(src.path)
            let row = try engine.index.resolveSkill(query: "unique-name")
            #expect(row.id == "local/src/unique-name")
            #expect(throws: AgeOSError.self) { try engine.index.resolveSkill(query: "does-not-exist") }
        }
    }
}
