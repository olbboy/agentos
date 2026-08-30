import Foundation

/// Ranh giới network duy nhất của core — protocol để test mock được toàn bộ
/// GitHubSource mà không chạm mạng thật.
public protocol HTTPClient: Sendable {
    func get(_ url: URL, headers: [String: String]) async throws -> (data: Data, response: HTTPURLResponse)
}

public struct URLSessionHTTPClient: HTTPClient {
    public init() {}

    public func get(_ url: URL, headers: [String: String]) async throws -> (data: Data, response: HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AgeOSError(.network, "Non-HTTP response from \(url.host ?? "?")")
        }
        return (data, http)
    }
}
