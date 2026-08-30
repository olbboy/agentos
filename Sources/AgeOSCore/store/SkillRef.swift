import Foundation

/// Định danh skill toàn cục: `<namespace>/<name>`.
/// Namespace theo nguồn — GitHub: `owner/repo`, local: `local/<slug>` — nên
/// hai repo khác nhau có skill trùng tên vẫn không đè nhau trong store.
public struct SkillRef: Sendable, Hashable, Codable, CustomStringConvertible {
    public let namespace: String
    public let name: String

    public init(namespace: String, name: String) {
        self.namespace = namespace
        self.name = name
    }

    /// Parse id dạng `a/b/name` (github) hoặc `local/x/name`.
    public init?(id: String) {
        let parts = id.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }
        self.name = parts[parts.count - 1]
        self.namespace = parts.dropLast().joined(separator: "/")
    }

    public var id: String { "\(namespace)/\(name)" }
    public var description: String { id }

    /// Các thành phần path tương đối trong `library/skills/`.
    public var pathComponents: [String] { namespace.split(separator: "/").map(String.init) + [name] }
}
