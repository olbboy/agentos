import Foundation

/// The skills.sh search index (API measured on 2026-08-30:
/// `GET https://skills.sh/api/search?q=<q>` → {skills: [{id, skillId, name, installs, source}]}).
/// An optional source: if the API changes or goes down it degrades silently to empty (with a doctor note) rather than blocking anything.
public struct SkillsShSource: Sendable {
    let http: HTTPClient
    public static let baseURL = "https://skills.sh"

    public init(http: HTTPClient = URLSessionHTTPClient()) {
        self.http = http
    }

    public struct Hit: Sendable, Codable, Equatable {
        /// `owner/repo/skill-name` — the same id format the AgeOS store uses.
        public var id: String
        public var name: String
        public var installs: Int
        /// `owner/repo` — addable directly with `ageos source add`.
        public var source: String
    }

    struct SearchResponse: Decodable {
        var skills: [WireHit]
        struct WireHit: Decodable {
            var id: String?
            var name: String?
            var installs: Int?
            var source: String?
        }
    }

    /// Returns [] when the API errors or changes schema — callers need no try/catch.
    public func search(_ query: String, limit: Int = 20) async -> [Hit] {
        var components = URLComponents(string: "\(Self.baseURL)/api/search")!
        components.queryItems = [.init(name: "q", value: query)]
        guard let url = components.url else { return [] }
        do {
            let (data, response) = try await http.get(url, headers: ["Accept": "application/json"])
            guard response.statusCode == 200 else { return [] }
            let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
            return decoded.skills.prefix(limit).compactMap { hit in
                guard let id = hit.id, let name = hit.name else { return nil }
                return Hit(id: id, name: name, installs: hit.installs ?? 0, source: hit.source ?? "")
            }
        } catch {
            return [] // degrade silently, by design
        }
    }

    /// The install count for one exact skill id (a quality signal) — nil when not found.
    public func installCount(skillId: String) async -> Int? {
        let name = skillId.split(separator: "/").last.map(String.init) ?? skillId
        let hits = await search(name)
        return hits.first { $0.id == skillId }?.installs
            ?? hits.first { $0.name == name }?.installs
    }
}
