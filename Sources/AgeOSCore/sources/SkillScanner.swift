import Foundation

/// Dò mọi `**/SKILL.md` (độ sâu ≤ maxDepth) trong một cây thư mục.
/// Repo ngoài hoang dã có đủ kiểu layout (skill ở root, nested `skills/`, multi-skill
/// kiểu anthropics/skills) — dò theo file marker thay vì đoán cấu trúc.
public enum SkillScanner {
    public struct ScanOutput: Sendable {
        public var skills: [ParsedSkill]
        public var skipped: [(path: String, reason: String)]
    }

    static let ignoredDirs: Set<String> = ["node_modules", ".git", ".venv", "__pycache__", ".build"]

    public static func scan(root: URL, maxDepth: Int = 4) -> ScanOutput {
        var skills: [ParsedSkill] = []
        var skipped: [(String, String)] = []
        let fm = FileManager.default

        func walk(_ dir: URL, depth: Int) {
            guard depth <= maxDepth,
                  let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey],
                                                            options: [.skipsHiddenFiles]) else { return }
            let hasSkillFile = entries.contains { $0.lastPathComponent == "SKILL.md" }
            if hasSkillFile {
                do {
                    let parsed = try SkillParser.parse(directory: dir)
                    let errors = SkillValidator.validate(parsed).filter { $0.severity == .error }
                    if errors.isEmpty {
                        skills.append(parsed)
                    } else {
                        skipped.append((dir.path, errors.map(\.message).joined(separator: "; ")))
                    }
                } catch {
                    skipped.append((dir.path, "\(error)"))
                }
                return // skill dir không lồng skill dir khác
            }
            for entry in entries {
                let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                if isDir, !ignoredDirs.contains(entry.lastPathComponent) {
                    walk(entry, depth: depth + 1)
                }
            }
        }

        walk(root, depth: 0)
        skills.sort { $0.manifest.name < $1.manifest.name }
        return ScanOutput(skills: skills, skipped: skipped)
    }
}
