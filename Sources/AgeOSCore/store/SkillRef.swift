import Foundation

/// A globally unique skill identity: `<namespace>/<name>`.
/// The namespace follows the source — GitHub: `owner/repo`, local: `local/<slug>` — so two
/// different repos holding a same-named skill still cannot overwrite each other in the store.
public struct SkillRef: Sendable, Hashable, Codable, CustomStringConvertible {
    public let namespace: String
    public let name: String

    public init(namespace: String, name: String) {
        self.namespace = namespace
        self.name = name
    }

    /// Parses an id shaped `a/b/name` (github) or `local/x/name`.
    public init?(id: String) {
        let parts = id.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }
        self.name = parts[parts.count - 1]
        self.namespace = parts.dropLast().joined(separator: "/")
    }

    public var id: String { "\(namespace)/\(name)" }
    public var description: String { id }

    /// The relative path components inside `library/skills/`.
    public var pathComponents: [String] { namespace.split(separator: "/").map(String.init) + [name] }
}
