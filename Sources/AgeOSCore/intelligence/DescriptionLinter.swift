import Foundation

/// Lint description theo tiêu chí "agent chọn đúng skill nhờ description":
/// đủ dài để phân biệt, có tín hiệu trigger ("use when..."), không mơ hồ.
public enum DescriptionLinter {
    public struct Finding: Sendable, Codable, Equatable {
        public enum Rule: String, Sendable, Codable {
            case tooShort = "too_short"
            case tooLong = "too_long"
            case vagueOnly = "vague_only"
            case noTriggerSignal = "no_trigger_signal"
            case duplicateOf = "duplicate_of"
        }
        public var rule: Rule
        public var message: String
    }

    static let vagueWords: Set<String> = [
        "helper", "utility", "misc", "stuff", "tools", "general", "various", "helpful",
    ]

    public static func lint(name: String, description: String) -> [Finding] {
        var findings: [Finding] = []
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.count < 40 {
            findings.append(.init(rule: .tooShort,
                                  message: "Description \(trimmed.count) ký tự — quá ngắn để agent phân biệt khi nào dùng (khuyến nghị ≥40)"))
        }
        if trimmed.count > 1024 {
            findings.append(.init(rule: .tooLong,
                                  message: "Description \(trimmed.count) ký tự > 1024 (spec) — một số agent sẽ cắt (codex cắt ~160)"))
        }

        let words = Set(trimmed.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty })
        let meaningful = words.subtracting(vagueWords)
        if !words.isEmpty && meaningful.count < max(3, words.count / 4) {
            findings.append(.init(rule: .vagueOnly,
                                  message: "Description toàn từ chung chung (\(words.intersection(vagueWords).sorted().joined(separator: ", "))) — nói rõ skill LÀM GÌ và KHI NÀO dùng"))
        }

        let lowered = trimmed.lowercased()
        let hasTrigger = ["use when", "use this", "use for", "trigger", "invoke", "khi nào", "dùng khi", "when the user", "when you"]
            .contains { lowered.contains($0) }
        if !hasTrigger && trimmed.count >= 40 {
            findings.append(.init(rule: .noTriggerSignal,
                                  message: "Không có tín hiệu trigger (\"Use when...\") — agent khó quyết định lúc nào kích hoạt"))
        }
        return findings
    }
}
