import Foundation
import CryptoKit
import NaturalLanguage

/// Finds duplicates: exact (normalized hash) plus near (embedding cosine).
///
/// The lesson from the spike: cosine over raw mean-pooled NLContextualEmbedding CANNOT
/// discriminate — unrelated pairs still score 0.90+ because the vectors are anisotropic.
/// Mean-centering across the corpus before comparing is mandatory; the threshold is calibrated on fixtures.
public struct DedupeEngine: Sendable {
    /// The cosine threshold AFTER mean-centering (calibrated by DedupeTests on real fixtures).
    public var nearThreshold: Double

    public init(nearThreshold: Double = 0.72) {
        self.nearThreshold = nearThreshold
    }

    public struct Item: Sendable {
        public var id: String
        public var name: String
        public var description: String
        public var bodyHead: String
        public var directory: URL?

        public init(id: String, name: String, description: String, bodyHead: String, directory: URL? = nil) {
            self.id = id
            self.name = name
            self.description = description
            self.bodyHead = bodyHead
            self.directory = directory
        }

        public static func from(_ parsed: ParsedSkill, id: String) -> Item {
            let head = parsed.body.split(separator: "\n", omittingEmptySubsequences: false)
                .prefix(200).joined(separator: "\n")
            return Item(id: id, name: parsed.manifest.name,
                        description: parsed.manifest.description,
                        bodyHead: String(head), directory: parsed.directory)
        }
    }

    public struct DupePair: Sendable, Codable, Equatable {
        public enum Kind: String, Sendable, Codable { case exact, near }
        public var kind: Kind
        public var a: String
        public var b: String
        /// exact: 1.0 · near: cosine sau centering.
        public var score: Double
    }

    // MARK: - Exact

    /// A normalized hash: lowercased, whitespace collapsed — reformatting cannot escape exact-duplicate detection.
    public static func normalizedHash(_ item: Item) -> String {
        let normalized = [item.name, item.description, item.bodyHead]
            .joined(separator: "\u{1F}")
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return SHA256.hash(data: Data(normalized.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    public func exactDupes(_ items: [Item]) -> [DupePair] {
        var byHash: [String: [Item]] = [:]
        for item in items {
            byHash[Self.normalizedHash(item), default: []].append(item)
        }
        var pairs: [DupePair] = []
        for group in byHash.values where group.count >= 2 {
            let sorted = group.sorted { $0.id < $1.id }
            for i in 1..<sorted.count {
                pairs.append(DupePair(kind: .exact, a: sorted[0].id, b: sorted[i].id, score: 1.0))
            }
        }
        return pairs.sorted { ($0.a, $0.b) < ($1.a, $1.b) }
    }

    // MARK: - Near (embedding)

    /// The text fed to the embedding: name plus description plus the head of the body (the
    /// input was settled in the plan; the spike confirmed the body head is needed to discriminate).
    static func embeddingText(_ item: Item) -> String {
        "\(item.name). \(item.description)\n\(item.bodyHead.prefix(1000))"
    }

    /// Returns nil when the machine has no embedding assets (CI) — callers degrade to exact-only.
    /// `precomputedVectors` lets the mechanism tests (centering, threshold, pairing) run
    /// deterministically on CI without assets — near-duplicate detection must not be a phantom test.
    public func nearDupes(_ items: [Item], precomputedVectors: [[Double]]? = nil) -> [DupePair]? {
        guard items.count >= 2,
              let vectors = precomputedVectors ?? Self.embedAll(items.map(Self.embeddingText)) else { return nil }

        // Mean-center: subtract the corpus mean vector to break the anisotropy.
        let dim = vectors[0].count
        var mean = [Double](repeating: 0, count: dim)
        for v in vectors {
            for i in 0..<dim { mean[i] += v[i] }
        }
        for i in 0..<dim { mean[i] /= Double(vectors.count) }
        let centered = vectors.map { v in
            (0..<dim).map { v[$0] - mean[$0] }
        }

        var pairs: [DupePair] = []
        for i in 0..<items.count {
            for j in (i + 1)..<items.count {
                let score = Self.cosine(centered[i], centered[j])
                if score >= nearThreshold {
                    pairs.append(DupePair(kind: .near, a: items[i].id, b: items[j].id,
                                          score: (score * 1000).rounded() / 1000))
                }
            }
        }
        return pairs.sorted { $0.score > $1.score }
    }

    /// Embeds sequentially (NLContextualEmbedding is not Sendable — keep it in one scope).
    static func embedAll(_ texts: [String]) -> [[Double]]? {
        guard let embedding = NLContextualEmbedding(language: .english),
              embedding.hasAvailableAssets else { return nil }
        do {
            try embedding.load()
            var result: [[Double]] = []
            for text in texts {
                let r = try embedding.embeddingResult(for: text, language: .english)
                var acc = [Double](repeating: 0, count: embedding.dimension)
                var count = 0.0
                r.enumerateTokenVectors(in: text.startIndex..<text.endIndex) { vector, _ in
                    for (i, v) in vector.enumerated() { acc[i] += v }
                    count += 1
                    return true
                }
                if count > 0 {
                    for i in 0..<acc.count { acc[i] /= count }
                }
                result.append(acc)
            }
            return result
        } catch {
            return nil
        }
    }

    static func cosine(_ a: [Double], _ b: [Double]) -> Double {
        var dot = 0.0, na = 0.0, nb = 0.0
        for i in 0..<min(a.count, b.count) {
            dot += a[i] * b[i]
            na += a[i] * a[i]
            nb += b[i] * b[i]
        }
        return dot / ((na.squareRoot() * nb.squareRoot()) + 1e-12)
    }
}
