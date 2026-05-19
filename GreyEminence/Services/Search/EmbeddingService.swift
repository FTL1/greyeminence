import Foundation
@preconcurrency import NaturalLanguage

protocol EmbeddingService: Sendable {
    var modelIdentifier: String { get }
    var isAvailable: Bool { get }
    func embed(_ text: String) async -> [Float]?
}

/// Apple's built-in sentence embedding. Offline, free, ~300-dim vectors.
/// Quality is adequate for personal meeting search but lags behind current
/// API-based models (Voyage v3, Titan v2). Good default.
final class NLEmbeddingService: EmbeddingService, @unchecked Sendable {
    let modelIdentifier = "apple-nlembedding-sentence-en-chunked-v1"

    private let embedding: NLEmbedding?

    /// Process-wide serialization for `NLEmbedding.vector(for:)`.
    /// `NLEmbedding.sentenceEmbedding(for:)` returns a cached singleton
    /// shared across every `NLEmbeddingService` instance, and the
    /// framework's `vector(for:)` internally fans out via `libBNNS`'s
    /// `dispatch_apply`. Two concurrent Tasks calling it simultaneously
    /// trip Swift's exclusive-access check inside CoreNLP and abort the
    /// process. Holding this lock across each call serializes at the
    /// framework boundary; the work is CPU-bound and short.
    private static let embeddingLock = NSLock()

    init() {
        self.embedding = NLEmbedding.sentenceEmbedding(for: .english)
    }

    var isAvailable: Bool { embedding != nil }

    func embed(_ text: String) async -> [Float]? {
        guard let embedding else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let vec = Self.synchronizedVector(embedding: embedding, text: trimmed) else { return nil }
        return vec.map { Float($0) }
    }

    /// Sync wrapper — `NSLock.lock()` isn't callable from an async frame
    /// under Swift 6, but the body is short and CPU-bound so a static
    /// helper is the simpler fix than refactoring to actor isolation.
    private static func synchronizedVector(embedding: NLEmbedding, text: String) -> [Double]? {
        embeddingLock.lock()
        defer { embeddingLock.unlock() }
        return embedding.vector(for: text)
    }
}

/// TODO: Voyage AI embeddings.
/// - Endpoint: https://api.voyageai.com/v1/embeddings
/// - Recommended model: voyage-3 (1024 dims)
/// - API key in Keychain under "voyageAPIKey"
/// - Anthropic recommends Voyage for RAG with Claude.
final class VoyageEmbeddingService: EmbeddingService, @unchecked Sendable {
    let modelIdentifier = "voyage-3"
    var isAvailable: Bool { false }
    func embed(_ text: String) async -> [Float]? { nil }
}

/// TODO: AWS Bedrock Titan Text Embeddings V2.
/// - Model id: amazon.titan-embed-text-v2:0 (configurable 256/512/1024 dims)
/// - Reuses existing AWS SSO credentials from `AWSCredentialLoader`.
final class TitanEmbeddingService: EmbeddingService, @unchecked Sendable {
    let modelIdentifier = "amazon.titan-embed-text-v2:0"
    var isAvailable: Bool { false }
    func embed(_ text: String) async -> [Float]? { nil }
}
