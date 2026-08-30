import Foundation
import FoundationModels

/// Chấm 0-100 heuristic KÈM giải trình từng tiêu chí (không điểm đen hộp).
/// Snapshot tests khóa điểm để chống drift ngẫu nhiên.
public struct QualityScorer: Sendable {
    public init() {}

    public struct Score: Sendable, Codable, Equatable {
        public var total: Int
        public var classification: String
        public var classificationMethod: String
        public var explain: [Criterion]

        public struct Criterion: Sendable, Codable, Equatable {
            public var name: String
            public var points: Int
            public var max: Int
            public var note: String
        }
    }

    public struct Input: Sendable {
        public var parsed: ParsedSkill
        public var sourceStars: Int?
        public var sourcePushedAt: Date?
        public var sourceLicense: String?
        public var installCount: Int?

        public init(parsed: ParsedSkill, sourceStars: Int? = nil, sourcePushedAt: Date? = nil,
                    sourceLicense: String? = nil, installCount: Int? = nil) {
            self.parsed = parsed
            self.sourceStars = sourceStars
            self.sourcePushedAt = sourcePushedAt
            self.sourceLicense = sourceLicense
            self.installCount = installCount
        }
    }

    public func score(_ input: Input, now: Date = Date()) -> Score {
        var criteria: [Score.Criterion] = []
        let m = input.parsed.manifest

        // 1. Metadata đầy đủ (tối đa 20)
        var meta = 0
        var metaNotes: [String] = []
        if !m.name.isEmpty { meta += 5 } else { metaNotes.append("thiếu name") }
        if !m.description.isEmpty { meta += 5 } else { metaNotes.append("thiếu description") }
        if m.license != nil || input.sourceLicense != nil { meta += 5 } else { metaNotes.append("thiếu license") }
        if !m.metadata.isEmpty || !m.extra.isEmpty { meta += 5 } else { metaNotes.append("không có metadata phụ") }
        criteria.append(.init(name: "metadata", points: meta, max: 20,
                              note: metaNotes.isEmpty ? "đầy đủ" : metaNotes.joined(separator: ", ")))

        // 2. Description lint (tối đa 20)
        let lintFindings = DescriptionLinter.lint(name: m.name, description: m.description)
        let lintPoints = max(0, 20 - lintFindings.count * 7)
        criteria.append(.init(name: "description-lint", points: lintPoints, max: 20,
                              note: lintFindings.isEmpty ? "sạch" : lintFindings.map(\.rule.rawValue).joined(separator: ", ")))

        // 3. Cấu trúc tài nguyên (tối đa 15)
        var structure = 0
        var structNotes: [String] = []
        if let dir = Optional(input.parsed.directory) {
            for sub in ["references", "scripts", "assets", "templates"] {
                if FileManager.default.fileExists(atPath: dir.appendingPathComponent(sub).path) {
                    structure += 5
                    structNotes.append("có \(sub)/")
                }
            }
        }
        structure = min(structure, 15)
        criteria.append(.init(name: "resources", points: structure, max: 15,
                              note: structNotes.isEmpty ? "chỉ có SKILL.md" : structNotes.joined(separator: ", ")))

        // 4. Body chất lượng (tối đa 10)
        let bodyLen = input.parsed.body.count
        let bodyPoints = bodyLen >= 2000 ? 10 : (bodyLen >= 500 ? 7 : (bodyLen >= 100 ? 4 : 0))
        criteria.append(.init(name: "body", points: bodyPoints, max: 10, note: "\(bodyLen) ký tự hướng dẫn"))

        // 5. Upstream tín nhiệm (tối đa 25: stars 15 + freshness 10)
        var stars = 0
        if let s = input.sourceStars {
            stars = s >= 1000 ? 15 : (s >= 100 ? 12 : (s >= 10 ? 8 : (s >= 1 ? 4 : 0)))
        }
        criteria.append(.init(name: "stars", points: stars, max: 15,
                              note: input.sourceStars.map { "\($0) sao" } ?? "không rõ nguồn"))
        var fresh = 0
        if let pushed = input.sourcePushedAt {
            let days = now.timeIntervalSince(pushed) / 86_400
            fresh = days <= 30 ? 10 : (days <= 180 ? 7 : (days <= 365 ? 3 : 0))
            criteria.append(.init(name: "freshness", points: fresh, max: 10,
                                  note: "push \(Int(days)) ngày trước"))
        } else {
            criteria.append(.init(name: "freshness", points: 0, max: 10, note: "không rõ"))
        }

        // 6. Cộng đồng skills.sh (tối đa 10)
        var installs = 0
        if let c = input.installCount {
            installs = c >= 1000 ? 10 : (c >= 100 ? 7 : (c >= 10 ? 4 : 1))
        }
        criteria.append(.init(name: "installs", points: installs, max: 10,
                              note: input.installCount.map { "\($0) lượt cài skills.sh" } ?? "không có dữ liệu"))

        let total = min(100, criteria.reduce(0) { $0 + $1.points })
        let (classification, method) = Self.classify(name: m.name, description: m.description)
        return Score(total: total, classification: classification,
                     classificationMethod: method, explain: criteria)
    }

    // MARK: - Classification

    static let taxonomy: [(label: String, keywords: [String])] = [
        ("frontend", ["ui", "css", "react", "frontend", "design", "component", "tailwind", "animation", "svg"]),
        ("backend", ["api", "server", "database", "sql", "backend", "auth", "queue", "graphql"]),
        ("devops", ["deploy", "docker", "kubernetes", "ci", "cd", "infra", "terraform", "cloudflare", "aws"]),
        ("testing", ["test", "coverage", "e2e", "playwright", "vitest", "qa", "regression"]),
        ("security", ["security", "vulnerability", "pentest", "exploit", "audit", "threat", "osint"]),
        ("docs", ["documentation", "docs", "readme", "diagram", "changelog", "wiki"]),
        ("data-ai", ["llm", "embedding", "model", "prompt", "agent", "ml", "dataset", "rag", "mcp"]),
        ("media", ["video", "image", "audio", "ffmpeg", "photo", "render", "3d"]),
        ("productivity", ["workflow", "automation", "schedule", "email", "calendar", "note"]),
    ]

    /// Phân loại sync (dùng trong score snapshot-được): luôn keyword.
    /// Máy bật Apple Intelligence sẽ được refine bằng `classifyWithFoundationModels`
    /// ở tầng CLI/scan (async); máy này (spike 30/8: appleIntelligenceNotEnabled)
    /// chạy "heuristic mode" và UI phải ghi rõ như vậy.
    static func classify(name: String, description: String) -> (String, String) {
        let label = keywordClassify(name: name, description: description)
        if case .available = SystemLanguageModel.default.availability {
            return (label, "keyword (chờ refine FM)")
        }
        return (label, "keyword (heuristic mode)")
    }

    /// Refine phân loại bằng on-device FoundationModels (chỉ khi availability == available).
    /// Prompt cố định, chỉ chấp nhận nhãn trong taxonomy — trả nil khi FM tắt/lỗi/nhãn lạ.
    public static func classifyWithFoundationModels(name: String, description: String) async -> String? {
        guard case .available = SystemLanguageModel.default.availability else { return nil }
        let labels = taxonomy.map(\.label) + ["other"]
        let prompt = """
        Classify this AI agent skill into exactly one category.
        Categories: \(labels.joined(separator: ", ")).
        Skill name: \(name)
        Description: \(description.prefix(500))
        Reply with ONLY the category word, nothing else.
        """
        do {
            let session = LanguageModelSession()
            let response = try await session.respond(to: prompt)
            let answer = response.content.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return labels.contains(answer) ? answer : nil
        } catch {
            return nil
        }
    }

    static func keywordClassify(name: String, description: String) -> String {
        let text = "\(name) \(description)".lowercased()
        var best = ("other", 0)
        for (label, keywords) in taxonomy {
            let hits = keywords.reduce(0) { $0 + (text.contains($1) ? 1 : 0) }
            if hits > best.1 { best = (label, hits) }
        }
        return best.0
    }
}
