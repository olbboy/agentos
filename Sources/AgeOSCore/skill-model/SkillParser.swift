import Foundation
import Markdown
import Yams

/// Parse SKILL.md: tách YAML frontmatter (Yams) + body Markdown (swift-markdown).
public enum SkillParser {
    /// Parse từ thư mục skill (phải chứa SKILL.md).
    public static func parse(directory: URL) throws -> ParsedSkill {
        let file = directory.appendingPathComponent("SKILL.md")
        guard let data = FileManager.default.contents(atPath: file.path) else {
            throw AgeOSError(.invalidSkill, "No SKILL.md found in \(directory.path)",
                             remedy: "A valid skill has a SKILL.md at the root of its directory (agentskills.io spec)")
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw AgeOSError(.invalidSkill, "SKILL.md is not UTF-8: \(file.path)")
        }
        return try parse(markdown: text, directory: directory)
    }

    public static func parse(markdown text: String, directory: URL) throws -> ParsedSkill {
        let (frontmatter, body) = try splitFrontmatter(text, file: directory.appendingPathComponent("SKILL.md"))
        let manifest = try decodeManifest(frontmatter, file: directory.appendingPathComponent("SKILL.md"))
        let title = firstHeading(in: body)
        return ParsedSkill(manifest: manifest, body: body, directory: directory, title: title)
    }

    // MARK: - Frontmatter

    /// Frontmatter = khối giữa `---` dòng đầu tiên và `---` kế tiếp.
    static func splitFrontmatter(_ text: String, file: URL) throws -> (yaml: String, body: String) {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        guard normalized.hasPrefix("---\n") || normalized == "---" else {
            throw AgeOSError(.invalidSkill, "SKILL.md has no YAML frontmatter: \(file.path)",
                             remedy: "Open the file with a `---` block containing `name` and `description`")
        }
        let afterOpen = normalized.dropFirst(4)
        guard let closeRange = afterOpen.range(of: "\n---") else {
            throw AgeOSError(.invalidSkill, "Frontmatter is not closed by `---`: \(file.path)",
                             remedy: "Add a `---` line to end the frontmatter block")
        }
        let yaml = String(afterOpen[..<closeRange.lowerBound])
        var body = String(afterOpen[closeRange.upperBound...])
        if let newline = body.firstIndex(of: "\n") {
            body = String(body[body.index(after: newline)...])
        } else {
            body = ""
        }
        return (yaml, body)
    }

    static func decodeManifest(_ yaml: String, file: URL) throws -> SkillManifest {
        let loaded: Any?
        do {
            loaded = try Yams.load(yaml: yaml)
        } catch {
            throw AgeOSError(.invalidSkill, "Frontmatter YAML is malformed in \(file.path): \(error)",
                             remedy: "Fix the YAML syntax (check indentation, colons, and quotes)")
        }
        guard let dict = loaded as? [String: Any] else {
            throw AgeOSError(.invalidSkill, "Frontmatter must be a YAML mapping (key: value): \(file.path)")
        }

        func str(_ key: String) -> String? {
            if let s = dict[key] as? String { return s }
            if let v = dict[key], !(v is NSNull) { return String(describing: v) }
            return nil
        }

        var extra: [String: String] = [:]
        var metadata: [String: String] = [:]
        var allowedTools: [String]?
        let knownKeys: Set<String> = ["name", "description", "license", "allowed-tools", "metadata", "deprecated"]

        if let tools = dict["allowed-tools"] as? [Any] {
            allowedTools = tools.map { String(describing: $0) }
        } else if let tools = dict["allowed-tools"] as? String {
            allowedTools = tools.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        }
        if let meta = dict["metadata"] as? [String: Any] {
            for (k, v) in meta { metadata[k] = String(describing: v) }
        }
        for (k, v) in dict where !knownKeys.contains(k) {
            extra[k] = (v as? String) ?? String(describing: v)
        }

        let deprecated: Bool
        switch dict["deprecated"] {
        case let b as Bool: deprecated = b
        case let s as String: deprecated = ["true", "yes", "1"].contains(s.lowercased())
        default: deprecated = false
        }

        return SkillManifest(
            name: str("name") ?? "",
            description: str("description") ?? "",
            license: str("license"),
            allowedTools: allowedTools,
            metadata: metadata,
            deprecated: deprecated,
            extra: extra
        )
    }

    // MARK: - Body

    static func firstHeading(in body: String) -> String? {
        let doc = Document(parsing: body)
        for child in doc.children {
            if let heading = child as? Heading {
                return heading.plainText
            }
        }
        return nil
    }
}
