import Foundation

/// Search index skills.sh (API đo thực tế 30/8/2026:
/// `GET https://skills.sh/api/search?q=<q>` → {skills: [{id, skillId, name, installs, source}]}).
/// Nguồn optional: API đổi/sập → degrade im lặng trả rỗng (doctor note), không chặn flow.
public struct SkillsShSource: Sendable {
    let http: HTTPClient
    public static let baseURL = "https://skills.sh"

    public init(http: HTTPClient = URLSessionHTTPClient()) {
        self.http = http
    }

    public struct Hit: Sendable, Codable, Equatable {
        /// `owner/repo/skill-name` — trùng format id của AgeOS store.
        public var id: String
        public var name: String
        public var installs: Int
        /// `owner/repo` — add được ngay bằng `ageos source add`.
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

    /// Trả [] khi API lỗi/đổi schema — caller không cần try/catch.
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
            return [] // degrade im lặng theo thiết kế
        }
    }

    /// Install-count cho 1 skill id chính xác (quality signal) — nil nếu không tìm thấy.
    public func installCount(skillId: String) async -> Int? {
        let name = skillId.split(separator: "/").last.map(String.init) ?? skillId
        let hits = await search(name)
        return hits.first { $0.id == skillId }?.installs
            ?? hits.first { $0.name == name }?.installs
    }
}
