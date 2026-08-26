import Foundation

enum EmbeddingProvider: String, CaseIterable, Identifiable {
    case nlEmbedding
    case voyage
    case titan

    var id: String { rawValue }

    var label: String {
        switch self {
        case .nlEmbedding: "On-device (Apple NLEmbedding)"
        case .voyage: "Voyage AI — not available"
        case .titan: "AWS Bedrock (Titan Text Embeddings V2)"
        }
    }

    var shortLabel: String {
        switch self {
        case .nlEmbedding: "On-device"
        case .voyage: "Voyage"
        case .titan: "Titan"
        }
    }

    var isAvailable: Bool {
        switch self {
        case .nlEmbedding: true
        // Needs the AWS credentials the Bedrock AI provider already uses;
        // offering it while the app is pointed at the Anthropic API would
        // just fail on the first embed.
        case .titan: UserDefaults.standard.string(forKey: "aiProvider") == "bedrock"
        case .voyage: false
        }
    }

    /// What choosing this method actually means, in the terms that decide it:
    /// where the text goes, and what it costs.
    var explanation: String {
        switch self {
        case .nlEmbedding:
            "Apple's on-device sentence embedding. Nothing leaves the Mac and it's free, but it averages word vectors — it struggles when a question paraphrases what was said rather than reusing its words."
        case .titan:
            "Amazon Titan Text Embeddings V2, over Bedrock on the AWS credentials this app already uses. A real sentence encoder, so paraphrased questions match; transcripts stay inside the same AWS account that already runs the analysis. Billed per token — a full index of this size is a few cents."
        case .voyage:
            "Higher-scoring, but it would send transcripts to a third-party vendor outside your existing AWS agreement. Not enabled."
        }
    }

    /// Why the option can't be picked right now. Only meaningful when
    /// `isAvailable` is false.
    var unavailableReason: String {
        switch self {
        case .nlEmbedding:
            ""
        case .titan:
            "Needs the Bedrock AI provider. Switch AI → Provider to Bedrock first, then come back."
        case .voyage:
            "Not implemented — Bedrock keeps meeting text inside your own AWS account, which Voyage would not."
        }
    }

    func makeService() -> EmbeddingService {
        switch self {
        case .nlEmbedding: NLEmbeddingService()
        case .voyage: VoyageEmbeddingService()
        case .titan: TitanEmbeddingService()
        }
    }
}
