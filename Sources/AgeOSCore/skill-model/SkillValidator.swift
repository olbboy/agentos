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
            issues.append(.init(severity: .error, message: "Thiếu field bắt buộc `name` trong frontmatter"))
        } else {
            if m.name.range(of: namePattern, options: .regularExpression) == nil {
                issues.append(.init(severity: .error, message: "`name` phải là hyphen-case ASCII (a-z, 0-9, -): '\(m.name)'"))
            }
            if m.name.count > 64 {
                issues.append(.init(severity: .error, message: "`name` dài \(m.name.count) > 64 ký tự"))
            }
            let dirName = skill.directory.lastPathComponent
            if !dirName.isEmpty, dirName != m.name {
                issues.append(.init(severity: .warning, message: "Tên thư mục '\(dirName)' khác `name` '\(m.name)' — một số agent discovery theo tên thư mục"))
            }
        }

        if m.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.init(severity: .error, message: "Thiếu field bắt buộc `description` trong frontmatter"))
        } else if m.description.count > 1024 {
            // Warning chứ không error: agent thật (Claude Code) vẫn load skill vượt 1024
            // (vd anthropics/skills/claude-api = 1068 chars) — manager không được nghiêm hơn agent.
            issues.append(.init(severity: .warning, message: "`description` dài \(m.description.count) > 1024 ký tự (spec agentskills.io) — cân nhắc rút gọn"))
        }

        if skill.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.init(severity: .warning, message: "Body SKILL.md rỗng — skill không có hướng dẫn gì cho agent"))
        }

        return issues
    }

    /// Ném lỗi nếu có issue mức error.
    public static func requireValid(_ skill: ParsedSkill) throws {
        let errors = validate(skill).filter { $0.severity == .error }
        guard errors.isEmpty else {
            throw AgeOSError(.invalidSkill,
                             "SKILL.md không hợp lệ (\(skill.directory.path)): " + errors.map(\.message).joined(separator: "; "),
                             remedy: "Sửa frontmatter theo spec agentskills.io rồi sync lại")
        }
    }
}
