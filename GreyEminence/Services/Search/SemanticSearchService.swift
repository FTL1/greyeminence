import Foundation

struct SearchResult: Identifiable {
    let id: String
    let sourceKind: EmbeddingRecord.SourceKind
    let sourceID: UUID
    let meetingID: UUID
    let meetingTitle: String
    let meetingDate: Date
    let text: String
    let score: Float
}

@MainActor
final class SemanticSearchService {
    let store: EmbeddingStore
    let service: EmbeddingService

    /// Weight on the dense (vector) score in the hybrid blend. The lexical
    /// (BM25) score takes (1 - vectorWeight). 0.5 balances exact-keyword
    /// recall (BM25's strength) with paraphrase recall (vector's strength).
    /// On-device NLEmbedding is weak enough that the lexical half does most
    /// of the heavy lifting for keyword-y queries.
    var vectorWeight: Float = 0.5

    init(store: EmbeddingStore, service: EmbeddingService) {
        self.store = store
        self.service = service
    }

    func search(
        _ query: String,
        topK: Int = 25,
        dateRange: ClosedRange<Date>? = nil,
        kinds: Set<EmbeddingRecord.SourceKind>? = nil
    ) async -> [SearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        guard let queryVec = await service.embed(trimmed) else { return [] }

        let records = store.allRecords(for: service.modelIdentifier).filter { rec in
            if let kinds, !kinds.contains(rec.sourceKind) { return false }
            guard let range = dateRange else { return true }
            return range.contains(rec.meetingDate)
        }
        guard !records.isEmpty else { return [] }

        // Dense (vector) pass — cosine over each candidate.
        var vecScores: [Float] = Array(repeating: 0, count: records.count)
        for (i, rec) in records.enumerated() {
            let recVec = rec.vectorArray
            guard recVec.count == queryVec.count else { continue }
            vecScores[i] = Self.cosineSimilarity(recVec, queryVec)
        }

        // Lexical (BM25) pass — query-time tokenization of each candidate's
        // display text plus its meeting title (so title-word matches help).
        let queryTokens = Self.tokenize(trimmed)
        let docTokens: [[String]] = records.map { rec in
            Self.tokenize(rec.text + " " + rec.meetingTitle)
        }
        let lexScores = Self.bm25Scores(queryTokens: queryTokens, docs: docTokens)

        // Min-max normalize each score axis to [0,1] before blending so the
        // raw BM25 scale (unbounded) doesn't dominate cosine (already [-1,1]).
        let normVec = Self.minMaxNormalize(vecScores)
        let normLex = Self.minMaxNormalize(lexScores)
        let alpha = max(0, min(1, vectorWeight))

        let scored: [SearchResult] = records.enumerated().map { (i, rec) in
            let blended = alpha * normVec[i] + (1 - alpha) * normLex[i]
            return SearchResult(
                id: rec.id,
                sourceKind: rec.sourceKind,
                sourceID: rec.sourceID,
                meetingID: rec.meetingID,
                meetingTitle: rec.meetingTitle,
                meetingDate: rec.meetingDate,
                text: rec.text,
                score: blended
            )
        }

        return Array(scored.sorted { $0.score > $1.score }.prefix(topK))
    }

    // MARK: - Cosine

    private static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        var dot: Float = 0
        var aMag: Float = 0
        var bMag: Float = 0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            aMag += a[i] * a[i]
            bMag += b[i] * b[i]
        }
        let denom = sqrt(aMag) * sqrt(bMag)
        guard denom > 0 else { return 0 }
        return dot / denom
    }

    // MARK: - Lexical (BM25)

    private static let stopwords: Set<String> = [
        "a","an","the","and","or","but","if","then","else","of","in","on","at","to",
        "for","with","without","is","are","was","were","be","been","being","am",
        "i","me","my","mine","we","us","our","ours","you","your","yours","he","him",
        "his","she","her","hers","it","its","they","them","their","theirs","this",
        "that","these","those","do","does","did","done","doing","have","has","had",
        "having","will","would","shall","should","can","could","may","might","must",
        "so","than","because","as","about","into","over","under","up","down","out",
        "from","by","not","no","yes","very","just","also","there","here","what",
        "which","who","whom","whose","when","where","why","how","s","t","d","ll",
        "m","ve","re","got","get","go","goes","going","gone","like","really",
        "uh","um","okay","ok","yeah","yep","nope"
    ]

    private static func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        for scalar in text.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                current.unicodeScalars.append(scalar)
            } else if !current.isEmpty {
                if current.count >= 2 && !stopwords.contains(current) {
                    tokens.append(current)
                }
                current = ""
            }
        }
        if !current.isEmpty, current.count >= 2, !stopwords.contains(current) {
            tokens.append(current)
        }
        return tokens
    }

    /// Classic Okapi BM25 over an in-memory corpus. k1=1.5, b=0.75 — standard
    /// defaults that work well without per-corpus tuning at this scale.
    private static func bm25Scores(queryTokens: [String], docs: [[String]]) -> [Float] {
        let n = docs.count
        guard n > 0, !queryTokens.isEmpty else { return Array(repeating: 0, count: n) }

        let k1: Float = 1.5
        let b: Float = 0.75

        let docLengths = docs.map { Float($0.count) }
        let totalLen = docLengths.reduce(0, +)
        let avgdl = totalLen > 0 ? totalLen / Float(n) : 1

        // Document frequency per unique query term.
        let querySet = Set(queryTokens)
        var df: [String: Int] = [:]
        for doc in docs {
            let docSet = Set(doc)
            for t in querySet where docSet.contains(t) {
                df[t, default: 0] += 1
            }
        }

        // BM25+ IDF, floored at 0 so common-everywhere terms don't drag scores negative.
        var idf: [String: Float] = [:]
        for t in querySet {
            let dft = Float(df[t] ?? 0)
            let value = log(((Float(n) - dft + 0.5) / (dft + 0.5)) + 1)
            idf[t] = max(0, value)
        }

        var scores: [Float] = Array(repeating: 0, count: n)
        for (i, doc) in docs.enumerated() {
            guard !doc.isEmpty else { continue }
            var tf: [String: Int] = [:]
            for t in doc where querySet.contains(t) {
                tf[t, default: 0] += 1
            }
            if tf.isEmpty { continue }
            let dl = docLengths[i]
            var s: Float = 0
            for (term, count) in tf {
                let termIdf = idf[term] ?? 0
                let f = Float(count)
                let denom = f + k1 * (1 - b + b * dl / avgdl)
                if denom > 0 {
                    s += termIdf * (f * (k1 + 1)) / denom
                }
            }
            scores[i] = s
        }
        return scores
    }

    private static func minMaxNormalize(_ values: [Float]) -> [Float] {
        guard let mn = values.min(), let mx = values.max(), mx > mn else {
            return Array(repeating: 0, count: values.count)
        }
        let range = mx - mn
        return values.map { ($0 - mn) / range }
    }
}
