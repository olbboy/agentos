import Foundation
import Testing
@testable import AgeOSCore

@Suite("Store version hóa")
struct StoreTests {
    @Test func installSetCurrentAndSwap() throws {
        try withTempHomeSync { home in
            let store = Store(home: home)
            let ref = SkillRef(namespace: "gh-test/repo", name: "demo")
            let staging = home.cacheDir.appendingPathComponent("stage1")
            try makeSkillDir(in: staging, name: "demo", description: "v1 of demo skill for store tests")

            try store.installVersion(ref, version: "aaa111", from: staging.appendingPathComponent("demo"))
            try store.setCurrent(ref, version: "aaa111")
            #expect(store.currentVersion(ref) == "aaa111")

            // Version mới → swap atomic; current đổi đích, version cũ vẫn còn cho tới khi GC.
            let staging2 = home.cacheDir.appendingPathComponent("stage2")
            try makeSkillDir(in: staging2, name: "demo", description: "v2 updated description")
            try store.installVersion(ref, version: "bbb222", from: staging2.appendingPathComponent("demo"))
            try store.setCurrent(ref, version: "bbb222")
            #expect(store.currentVersion(ref) == "bbb222")
            #expect(store.installedVersions(ref).sorted() == ["aaa111", "bbb222"])

            // Đọc xuyên qua `current` phải ra nội dung v2.
            let parsed = try SkillParser.parse(directory: store.currentLink(ref))
            #expect(parsed.manifest.description.contains("v2"))

            let removed = try store.gcOrphans(ref)
            #expect(removed == ["aaa111"])
            #expect(store.installedVersions(ref) == ["bbb222"])
        }
    }

    @Test func installIsIdempotent() throws {
        try withTempHomeSync { home in
            let store = Store(home: home)
            let ref = SkillRef(namespace: "local/x", name: "idem")
            let staging = home.cacheDir.appendingPathComponent("s")
            let dir = try makeSkillDir(in: staging, name: "idem", description: "idempotent install test")
            let first = try store.installVersion(ref, version: "v1", from: dir)
            let second = try store.installVersion(ref, version: "v1", from: dir)
            #expect(first == second)
        }
    }

    @Test func listInstalledWalksNamespaces() throws {
        try withTempHomeSync { home in
            let store = Store(home: home)
            let staging = home.cacheDir.appendingPathComponent("s")
            for (ns, name) in [("owner/repoa", "one"), ("owner/repob", "two"), ("local/dir", "three")] {
                let ref = SkillRef(namespace: ns, name: name)
                let dir = try makeSkillDir(in: staging.appendingPathComponent(ns), name: name,
                                           description: "skill \(name) for listing test")
                try store.installVersion(ref, version: "v1", from: dir)
                try store.setCurrent(ref, version: "v1")
            }
            let listed = store.listInstalled()
            #expect(listed.count == 3)
            #expect(listed.map(\.ref.id).sorted() == ["local/dir/three", "owner/repoa/one", "owner/repob/two"])
        }
    }

    @Test func nastyVersionStringsAreSanitized() throws {
        try withTempHomeSync { home in
            let store = Store(home: home)
            let ref = SkillRef(namespace: "local/x", name: "nasty")
            let dir = try makeSkillDir(in: home.cacheDir, name: "nasty", description: "sanitize version dir names")
            let installed = try store.installVersion(ref, version: "../../../etc/passwd", from: dir)
            #expect(installed.path.hasPrefix(store.skillDir(ref).path))
            #expect(!installed.path.contains(".."))
        }
    }
}
