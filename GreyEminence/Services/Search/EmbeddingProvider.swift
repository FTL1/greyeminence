import Foundation

enum EmbeddingProvider: String, CaseIterable, Identifiable {
    case nlEmbedding
    case voyage
    case titan
    case cohere

    var id: String { rawValue }

    var label: String {
        switch self {
        case .nlEmbedding: "On-device (Apple NLEmbedding)"
        case .voyage: "Voyage AI — not available"
        case .titan: "AWS Bedrock (Titan Text Embeddings V2)"
        case .cohere: "AWS Bedrock (Cohere Embed English v3) — batched"
        }
    }

    var shortLabel: String {
        switch self {
        case .nlEmbedding: "On-device"
        case .voyage: "Voyage"
        case .titan: "Titan"
        case .cohere: "Cohere"
        }
    }

    var isAvailable: Bool {
        switch self {
        case .nlEmbedding: true
        // Needs an AWS profile to authenticate as — but not the same one the
        // analysis uses. Embeddings can run on a second account, which is
        // often the only way to reach Titan when the primary role is scoped
        // to the Anthropic models.
        case .titan, .cohere: !AWSCredentialLoader.usableProfiles().isEmpty
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
        case .cohere:
            "Also on Bedrock, and the one to pick for a large library. Titan takes one text per request, so indexing this many chunks means tens of thousands of round trips; Cohere takes 96 at a time, roughly two orders of magnitude fewer. Same 1024 dimensions, and it distinguishes stored text from search queries, which helps retrieval."
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
        case .titan, .cohere:
            "No AWS profile this app can authenticate as. It supports SSO and access-key profiles; assume-role and credential_process profiles aren't usable from a sandboxed app."
        case .voyage:
            "Not implemented — Bedrock keeps meeting text inside your own AWS account, which Voyage would not."
        }
    }

    func makeService() -> EmbeddingService {
        switch self {
        case .nlEmbedding: NLEmbeddingService()
        case .voyage: VoyageEmbeddingService()
        case .titan: TitanEmbeddingService()
        case .cohere: CohereEmbeddingService()
        }
    }
}
