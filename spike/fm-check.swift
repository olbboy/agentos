// AgeOS spike — kiểm tra khả dụng FoundationModels + NLContextualEmbedding (throwaway).
// Chạy: swift spike/fm-check.swift
import Foundation
import FoundationModels
import NaturalLanguage

// 1) FoundationModels: on-device LLM của Apple Intelligence.
let model = SystemLanguageModel.default
switch model.availability {
case .available:
    print("FM: available")
case .unavailable(let reason):
    print("FM: unavailable — \(reason)")
}

// 2) NLContextualEmbedding: embedding on-device cho near-dupe detection (Phase 5).
if let emb = NLContextualEmbedding(language: .english) {
    print("NLCtx: dim=\(emb.dimension) hasAssets=\(emb.hasAvailableAssets)")
    if !emb.hasAvailableAssets {
        print("NLCtx: assets chưa tải — cần requestAssets (async)")
    } else {
        do {
            try emb.load()
            let r1 = try emb.embeddingResult(for: "Generate marketing images with AI", language: .english)
            let r2 = try emb.embeddingResult(for: "Create promotional pictures using artificial intelligence", language: .english)
            let r3 = try emb.embeddingResult(for: "Configure PostgreSQL database replication", language: .english)
            func meanVec(_ r: NLContextualEmbeddingResult) -> [Double] {
                var acc = [Double](repeating: 0, count: emb.dimension); var n = 0.0
                r.enumerateTokenVectors(in: r.string.startIndex..<r.string.endIndex) { vec, _ in
                    for (i, v) in vec.enumerated() { acc[i] += v }; n += 1; return true
                }
                return n > 0 ? acc.map { $0 / n } : acc
            }
            func cos(_ a: [Double], _ b: [Double]) -> Double {
                let dot = zip(a, b).map(*).reduce(0, +)
                let na = (a.map { $0*$0 }.reduce(0, +)).squareRoot()
                let nb = (b.map { $0*$0 }.reduce(0, +)).squareRoot()
                return dot / (na * nb + 1e-12)
            }
            let (v1, v2, v3) = (meanVec(r1), meanVec(r2), meanVec(r3))
            print(String(format: "NLCtx cosine: similar-pair=%.3f distinct-pair=%.3f", cos(v1, v2), cos(v1, v3)))
        } catch {
            print("NLCtx embed error: \(error)")
        }
    }
} else {
    print("NLCtx: init failed (English unsupported?)")
}
