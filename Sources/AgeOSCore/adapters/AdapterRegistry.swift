import Foundation

/// Nạp adapter: bundled (đóng gói theo app) → override bởi `~/.ageos/adapters/*.json`
/// (trùng id thì user thắng). User vá path một agent mà không đợi release.
public struct AdapterRegistry: Sendable {
    public let adapters: [AdapterSpec]

    /// `includeBundled: false` → chỉ nạp adapter từ `~/.ageos/adapters/` — dùng cho test
    /// để mọi path đều nằm trong fake home, không bao giờ chạm thư mục agent thật.
    public init(home: AgeOSHome, includeBundled: Bool = true) throws {
        var byId: [String: AdapterSpec] = [:]
        let decoder = JSONDecoder()

        for url in includeBundled ? Self.bundledSpecURLs() : [] {
            do {
                let spec = try decoder.decode(AdapterSpec.self, from: Data(contentsOf: url))
                byId[spec.id] = spec
            } catch {
                // Spec bundled hỏng là lỗi build của chính AgeOS — ném để CI bắt.
                throw AgeOSError(.configUnreadable, "Bundled adapter is malformed \(url.lastPathComponent): \(error)")
            }
        }

        let userDir = home.adaptersDir
        if let entries = try? FileManager.default.contentsOfDirectory(at: userDir, includingPropertiesForKeys: nil) {
            for url in entries where url.pathExtension == "json" {
                do {
                    let spec = try decoder.decode(AdapterSpec.self, from: Data(contentsOf: url))
                    guard spec.schemaVersion == 1 else {
                        throw AgeOSError(.unsupported, "Adapter \(url.lastPathComponent) declares schemaVersion \(spec.schemaVersion), which is not supported",
                                         remedy: "This AgeOS understands schemaVersion 1 — update AgeOS, or fix the file")
                    }
                    byId[spec.id] = spec // user override thắng
                } catch let e as AgeOSError {
                    throw e
                } catch {
                    throw AgeOSError(.configUnreadable, "User adapter is malformed \(url.path): \(error)",
                                     remedy: "Fix the JSON, or delete the file to fall back to the bundled spec")
                }
            }
        }

        self.adapters = byId.values.sorted { $0.id < $1.id }
    }

    static func bundledSpecURLs() -> [URL] {
        guard let specsDir = Bundle.module.resourceURL?.appendingPathComponent("specs", isDirectory: true),
              let entries = try? FileManager.default.contentsOfDirectory(at: specsDir, includingPropertiesForKeys: nil)
        else { return [] }
        return entries.filter { $0.pathExtension == "json" }.sorted { $0.path < $1.path }
    }

    public func adapter(id: String) throws -> AdapterSpec {
        guard let found = adapters.first(where: { $0.id == id }) else {
            let known = adapters.map(\.id).joined(separator: ", ")
            throw AgeOSError(.notFound, "No adapter named '\(id)'",
                             remedy: "Available adapters: \(known). Add a new one with a JSON file in ~/.ageos/adapters/")
        }
        return found
    }

    /// Adapter phát hiện được trên máy (để `targets list` và adopt scan).
    public func detected() -> [AdapterSpec] {
        adapters.filter { $0.isDetected() }
    }
}
