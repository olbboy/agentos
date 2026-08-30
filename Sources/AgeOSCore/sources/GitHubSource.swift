import Foundation

/// Nguồn GitHub qua REST API — tarball, KHÔNG cần git:
/// 1. `GET /repos/{o}/{r}` (ETag) → default_branch, archived, stars, license
/// 2. `GET /repos/{o}/{r}/commits/{branch}` (Accept: sha) → commit sha = version
/// 3. sha đổi → tải tarball `/repos/{o}/{r}/tarball/{sha}` và quét SKILL.md
public struct GitHubSource: SourceProvider {
    public let descriptor: SourceDescriptor
    let http: HTTPClient
    let token: String?

    public init(descriptor: SourceDescriptor, http: HTTPClient = URLSessionHTTPClient(),
                environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.descriptor = descriptor
        self.http = http
        self.token = environment["GITHUB_TOKEN"] ?? environment["GH_TOKEN"]
    }

    /// Parse `https://github.com/owner/repo[.git]` | `owner/repo` → descriptor.
    public static func makeDescriptor(url input: String) throws -> SourceDescriptor {
        var trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["https://github.com/", "http://github.com/", "git@github.com:", "github.com/"] {
            if trimmed.lowercased().hasPrefix(prefix) { trimmed = String(trimmed.dropFirst(prefix.count)); break }
        }
        if trimmed.hasSuffix(".git") { trimmed = String(trimmed.dropLast(4)) }
        trimmed = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let parts = trimmed.split(separator: "/").map(String.init)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else {
            throw AgeOSError(.invalidSource, "Not a valid GitHub URL: '\(input)'",
                             remedy: "Accepted forms: https://github.com/owner/repo or owner/repo")
        }
        let (owner, repo) = (parts[0].lowercased(), parts[1].lowercased())
        return SourceDescriptor(id: "gh/\(owner)/\(repo)", kind: .github,
                                location: "https://github.com/\(owner)/\(repo)")
    }

    var ownerRepo: String { descriptor.namespace }

    func headers(etag: String? = nil) -> [String: String] {
        var h = [
            "Accept": "application/vnd.github+json",
            "User-Agent": "ageos",
            "X-GitHub-Api-Version": "2022-11-28",
        ]
        if let token { h["Authorization"] = "Bearer \(token)" }
        if let etag { h["If-None-Match"] = etag }
        return h
    }

    struct RepoMeta: Decodable {
        var default_branch: String
        var archived: Bool
        var stargazers_count: Int?
        var pushed_at: Date?
        var license: License?
        struct License: Decodable { var spdx_id: String? }
    }

    public func fetch(staging: URL) async throws -> SourceFetchResult {
        var updated = descriptor
        let api = URL(string: "https://api.github.com/repos/\(ownerRepo)")!

        let (metaData, metaResp) = try await http.get(api, headers: headers(etag: descriptor.etag))
        var meta: RepoMeta?
        switch metaResp.statusCode {
        case 304:
            break // không đổi — vẫn check sha vì ETag chỉ cover metadata
        case 200:
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            meta = try decoder.decode(RepoMeta.self, from: metaData)
            updated.etag = metaResp.value(forHTTPHeaderField: "ETag")
            updated.archived = meta!.archived
            updated.stars = meta!.stargazers_count
            updated.license = meta!.license?.spdx_id
            updated.pushedAt = meta!.pushed_at
        case 403, 429:
            throw AgeOSError(.rateLimited, "GitHub rate-limited the call to \(api.absoluteString)",
                             remedy: "Set GITHUB_TOKEN to raise the limit (5000 req/h), or try again later")
        case 404:
            throw AgeOSError(.notFound, "Repo does not exist, or is private: \(ownerRepo)",
                             remedy: "Check the URL; a private repo needs a GITHUB_TOKEN with read access")
        default:
            throw AgeOSError(.network, "GitHub API returned \(metaResp.statusCode) for \(api.absoluteString)")
        }

        let branch = meta?.default_branch ?? "HEAD"
        let shaURL = URL(string: "https://api.github.com/repos/\(ownerRepo)/commits/\(branch)")!
        var shaHeaders = headers()
        shaHeaders["Accept"] = "application/vnd.github.sha"
        let (shaData, shaResp) = try await http.get(shaURL, headers: shaHeaders)
        guard shaResp.statusCode == 200, let sha = String(data: shaData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !sha.isEmpty else {
            throw AgeOSError(.network, "Cannot resolve the commit sha for \(ownerRepo)@\(branch) (HTTP \(shaResp.statusCode))")
        }
        let version = String(sha.prefix(12))

        if version == descriptor.lastVersion {
            updated.lastSync = Date()
            return SourceFetchResult(version: version, changed: false, skills: [], skipped: [], descriptor: updated)
        }

        let tarURL = URL(string: "https://api.github.com/repos/\(ownerRepo)/tarball/\(sha)")!
        let (tarData, tarResp) = try await http.get(tarURL, headers: headers())
        guard tarResp.statusCode == 200 else {
            throw AgeOSError(.network, "Tarball download failed (HTTP \(tarResp.statusCode)) for \(ownerRepo)@\(version)")
        }
        let tarFile = staging.appendingPathComponent("src.tar.gz")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        try tarData.write(to: tarFile)
        let extracted = try TarballExtractor.extract(tarFile, into: staging.appendingPathComponent("extracted"))

        let scan = SkillScanner.scan(root: extracted)
        updated.lastVersion = version
        updated.lastSync = Date()
        return SourceFetchResult(version: version, changed: true, skills: scan.skills.map(FetchedSkill.init),
                                 skipped: scan.skipped, descriptor: updated)
    }
}
