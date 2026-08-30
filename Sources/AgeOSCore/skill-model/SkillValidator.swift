import Foundation

/// Validate cấu trúc theo spec agentskills.io. Chỉ bắt lỗi CHẶN (structural);
/// style/chất lượng description thuộc DescriptionLinter (Phase 5).
public enum SkillValidator {
    public struct Issue: Sendable, Equatable, CustomStringConvertible {
        public enum Severity: String, Sendable { case error, warning }
        public let severity: Severity
        public let message: String
        public var description: String { "[\(severity.rawValue)] \(message)" }
    }

    public static let namePattern = "^[a-z0-9]+(-[a-z0-9]+)*$"

    public static func validate(_ skill: ParsedSkill) -> [Issue] {
        var issues: [Issue] = []
        let m = skill.manifest

        if m.name.isEmpty {
            issues.append(.init(severity: .error, message: "Missing required field `name` in the frontmatter"))
        } else {
            if m.name.range(of: namePattern, options: .regularExpression) == nil {
                issues.append(.init(severity: .error, message: "`name` must be ASCII hyphen-case (a-z, 0-9, -): '\(m.name)'"))
            }
            if m.name.count > 64 {
                issues.append(.init(severity: .error, message: "`name` is \(m.name.count) characters, over the 64 limit"))
            }
            let dirName = skill.directory.lastPathComponent
            if !dirName.isEmpty, dirName != m.name {
                issues.append(.init(severity: .warning, message: "Directory name '\(dirName)' differs from `name` '\(m.name)' — some agents discover skills by directory name"))
            }
        }

        if m.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.init(severity: .error, message: "Missing required field `description` in the frontmatter"))
        } else if m.description.count > 1024 {
            // Warning chứ không error: agent thật (Claude Code) vẫn load skill vượt 1024
            // (vd anthropics/skills/claude-api = 1068 chars) — manager không được nghiêm hơn agent.
            issues.append(.init(severity: .warning, message: "`description` is \(m.description.count) characters, over the 1024 limit (agentskills.io spec) — consider shortening"))
        }

        if skill.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.init(severity: .warning, message: "SKILL.md body is empty — the skill gives the agent no instructions"))
        }

        return issues
    }

    /// Ném lỗi nếu có issue mức error.
    public static func requireValid(_ skill: ParsedSkill) throws {
        let errors = validate(skill).filter { $0.severity == .error }
        guard errors.isEmpty else {
            throw AgeOSError(.invalidSkill,
                             "Invalid SKILL.md (\(skill.directory.path)): " + errors.map(\.message).joined(separator: "; "),
                             remedy: "Fix the frontmatter to match the agentskills.io spec, then sync again")
        }
    }
}
