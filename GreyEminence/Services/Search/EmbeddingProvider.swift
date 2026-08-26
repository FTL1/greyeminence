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
        // Needs an AWS profile to authenticate as — but not the same one the
        // analysis uses. Embeddings can run on a second account, which is
        // often the only way to reach Titan when the primary role is scoped
        // to the Anthropic models.
        case .titan: !AWSCredentialLoader.availableProfiles().isEmpty
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
            "Amazon Titan Text Embeddings V2, over Bedrock. A real sentence encoder, so paraphrased questions match instead of needing the same words. Runs on an AWS account you control — its own profile, so it can differ from the one used for analysis — and meeting text never leaves AWS. Billed per token; a full index of this size is a few cents."
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
            "No AWS profiles found. Point Settings → AI at your ~/.aws directory first."
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
