import Foundation

/// Lints a description against one criterion: can an agent pick the right skill from it?
/// Long enough to discriminate, carrying a trigger signal ("use when..."), not vague.
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
                                  message: "Description is \(trimmed.count) characters — too short for an agent to tell when to use it (recommend at least 40)"))
        }
        if trimmed.count > 1024 {
            findings.append(.init(rule: .tooLong,
                                  message: "Description is \(trimmed.count) characters, over the 1024 spec limit — some agents truncate it (codex cuts at ~160)"))
        }

        let words = Set(trimmed.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty })
        let meaningful = words.subtracting(vagueWords)
        if !words.isEmpty && meaningful.count < max(3, words.count / 4) {
            findings.append(.init(rule: .vagueOnly,
                                  message: "Description is entirely generic wording (\(words.intersection(vagueWords).sorted().joined(separator: ", "))) — say WHAT the skill does and WHEN to use it"))
        }

        let lowered = trimmed.lowercased()
        // The two Vietnamese phrases are DELIBERATE and are not leftovers from the
        // translation. This array is matched against descriptions written by skill
        // authors, who may write in any language; dropping them would silently stop
        // the linter recognising a trigger signal in a Vietnamese description. They
        // are matching data, not text anyone reads.
        let hasTrigger = ["use when", "use this", "use for", "trigger", "invoke", "khi nào", "dùng khi", "when the user", "when you"]
            .contains { lowered.contains($0) }
        if !hasTrigger && trimmed.count >= 40 {
            findings.append(.init(rule: .noTriggerSignal,
                                  message: "No trigger signal (\"Use when...\") — the agent cannot tell when to activate it"))
        }
        return findings
    }
}
