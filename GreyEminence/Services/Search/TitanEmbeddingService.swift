import Foundation

/// Amazon Titan Text Embeddings V2, over Bedrock.
///
/// Chosen over a dedicated embedding vendor because it reuses the AWS
/// credentials the app already holds for Claude — no second API key, and
/// meeting transcripts never leave the AWS account they're already being
/// analyzed in.
///
/// Runs a real vector model instead of Apple's word-averaged `NLEmbedding`,
/// which is what makes paraphrase retrieval work: "couldn't process due to
/// costs" and "there's no way we can turn this on" share no vocabulary, and
/// only a trained sentence encoder puts them near each other.
final class TitanEmbeddingService: EmbeddingService, @unchecked Sendable {
    /// Titan v2 is Matryoshka-trained, so 256 / 512 / 1024 are all valid and
    /// larger is better. 1024 costs 4 KB per record — about 139 MB across a
    /// 34,000-record index, which is acceptable for the quality.
    static let dimensions = 1024

    /// Baked into the identifier because it's part of the vector's meaning:
    /// records embedded at a different width can't be compared, and the
    /// identifier is what gates which records a search will consult. Changing
    /// the model or the width therefore forces a reindex rather than silently
    /// mixing incompatible vectors.
    let modelIdentifier = "bedrock:amazon.titan-embed-text-v2:0:\(TitanEmbeddingService.dimensions)"

    /// Titan v2 accepts 8,192 tokens. Transcript chunks are ~600 characters,
    /// but a meeting summary can run far longer, so clamp well inside the
    /// limit rather than let one oversized record fail the whole meeting.
    private static let maxInputCharacters = 24_000

    /// Upper bound on the fan-out. The limiter below decides how much of it is
    /// actually used, so this is a ceiling rather than a target — work beyond
    /// the current limit is suspended, not running.
    let maxConcurrency = 12

    /// Shared by every worker, so the whole fan-out narrows together when the
    /// account's quota is hit rather than one request at a time.
    private static let limiter = AdaptiveConcurrencyLimiter(start: 6, ceiling: 12)

    /// Attempts per record before giving up. Throttling is transient, and a
    /// dropped record is invisible damage — a meeting stays "indexed" while
    /// part of it is missing from search.
    private static let maxAttempts = 6

    /// Shared across every worker so a throttle response pauses the whole
    /// fan-out, not just the request that hit it. Backing off one worker while
    /// the other three keep hammering is what turns a throttle into a storm.
    private static let throttleGate = ThrottleGate()

    private let region: String
    private let profile: String

    /// Credentials are fetched once and reused. They're SSO session
    /// credentials with an expiry, so a 403 clears this and forces one
    /// refresh rather than failing the rest of a long reindex.
    private let credentialBox = CredentialBox()

    /// Defaults keys for the embedding account. Separate from the analysis
    /// account's `awsProfile` / `awsRegion` because the two need not be the
    /// same: an org can grant a role the Anthropic models and withhold
    /// everything else, leaving Titan reachable only from a different account.
    /// Empty means "use whatever the analysis account uses", so a single-
    /// account setup needs no configuration at all.
    static let profileKey = "embeddingAWSProfile"
    static let regionKey = "embeddingAWSRegion"

    init(region: String? = nil, profile: String? = nil) {
        let defaults = UserDefaults.standard
        self.region = region
            ?? Self.nonEmpty(defaults.string(forKey: Self.regionKey))
            ?? Self.nonEmpty(defaults.string(forKey: "awsRegion"))
            ?? "us-east-1"
        self.profile = profile
            ?? Self.nonEmpty(defaults.string(forKey: Self.profileKey))
            ?? Self.nonEmpty(defaults.string(forKey: "awsProfile"))
            ?? "default"
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return value
    }

    /// Which account and region this instance will actually use — surfaced in
    /// Settings so a failure names the credentials it was tried with rather
    /// than leaving the user to guess which of two accounts was in play.
    var resolvedProfile: String { profile }
    var resolvedRegion: String { region }

    /// Configured, not proven — verifying would mean a network round trip on
    /// a synchronous property. A wrong guess surfaces as a logged failure on
    /// the first embed rather than a silent empty index, because
    /// `EmbeddingIndexer` skips work when this is false.
    ///
    /// Deliberately not tied to the app's AI provider. Embeddings can run on a
    /// different AWS account than the analysis does — which is the whole point
    /// of the separate profile setting — and may even pair a Bedrock index
    /// with analysis on the Anthropic API. All that's required is an AWS
    /// profile to authenticate as.
    var isAvailable: Bool {
        !AWSCredentialLoader.usableProfiles().isEmpty
    }

    func embed(_ text: String) async -> [Float]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let clamped = trimmed.count > Self.maxInputCharacters
            ? String(trimmed.prefix(Self.maxInputCharacters))
            : trimmed

        do {
            return try await withRetries(clamped)
        } catch {
            // Name the credentials, not just the error: with two accounts in
            // play, "not authorized" is meaningless without knowing which one
            // was used.
            LogManager.send(
                "Titan embedding failed (profile \(profile), \(region)): \(error.localizedDescription)",
                category: .ai,
                level: .warning
            )
            return nil
        }
    }

    // MARK: - Retry

    /// Retry throttled requests with exponential backoff and jitter.
    ///
    /// Jitter matters as much as the backoff: without it four workers throttled
    /// at the same moment retry at the same moment, and stay in lockstep.
    private func withRetries(_ text: String) async throws -> [Float]? {
        var lastError: Error = BedrockAPIError.invalidResponse
        for attempt in 0..<Self.maxAttempts {
            try Task.checkCancellation()
            await Self.throttleGate.waitUntilOpen()
            await Self.limiter.acquire()
            do {
                let vector = try await invoke(text, allowingRefresh: attempt == 0)
                await Self.limiter.release(throttled: false)
                return vector
            } catch let error as BedrockAPIError {
                guard case .httpError(let status, _) = error, Self.isTransient(status) else {
                    await Self.limiter.release(throttled: false)
                    throw error
                }
                // Narrow the fan-out AND pause it. Backing off without
                // narrowing just re-runs the same request rate a moment later.
                await Self.limiter.release(throttled: true)
                lastError = error
                guard attempt < Self.maxAttempts - 1 else { break }
                let delay = Self.backoffSeconds(attempt: attempt)
                await Self.throttleGate.close(forSeconds: delay)
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch {
                await Self.limiter.release(throttled: false)
                throw error
            }
        }
        throw lastError
    }

    /// 429 is throttling; 500/503 are Bedrock shedding load. Both are worth
    /// waiting out. Anything else — a bad model id, a denied action — will
    /// fail identically forever, so retrying only delays the report.
    static func isTransient(_ status: Int) -> Bool {
        status == 429 || status == 500 || status == 503
    }

    /// 0.5s, 1s, 2s, 4s, 8s … each ±25%.
    static func backoffSeconds(attempt: Int, jitter: Double = Double.random(in: 0.75...1.25)) -> Double {
        min(30, 0.5 * pow(2, Double(attempt))) * jitter
    }

    /// Holds every worker back until a shared deadline passes.
    private actor ThrottleGate {
        private var openAt = Date.distantPast

        func waitUntilOpen() async {
            while true {
                let remaining = openAt.timeIntervalSinceNow
                guard remaining > 0 else { return }
                try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            }
        }

        /// Never shortens an existing pause — a worker still on its first
        /// retry must not release one that has backed off much further.
        func close(forSeconds seconds: Double) {
            let candidate = Date().addingTimeInterval(seconds)
            if candidate > openAt { openAt = candidate }
        }
    }

    // MARK: - Bedrock

    private func invoke(_ text: String, allowingRefresh: Bool) async throws -> [Float]? {
        let credentials = try await credentialBox.credentials(profile: profile)

        let body = try JSONEncoder().encode(RequestBody(
            inputText: text,
            dimensions: Self.dimensions,
            normalize: true
        ))
        let modelID = "amazon.titan-embed-text-v2:0"
        let path = "/model/\(AWSSigV4Signer.encodeSegment(modelID))/invoke"
        let host = "bedrock-runtime.\(region).amazonaws.com"
        guard let url = URL(string: "https://\(host)\(path)") else {
            throw BedrockAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = 60
        request = AWSSigV4Signer(credentials: credentials, region: region)
            .sign(request: request, body: body, host: host, path: path)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BedrockAPIError.invalidResponse
        }

        // Expired SSO session — refresh once, then give up so a stale
        // credential can't spin the whole reindex.
        if (http.statusCode == 403 || http.statusCode == 401), allowingRefresh {
            await credentialBox.invalidate()
            return try await invoke(text, allowingRefresh: false)
        }
        guard (200...299).contains(http.statusCode) else {
            throw BedrockAPIError.httpError(
                statusCode: http.statusCode,
                body: String(data: data, encoding: .utf8) ?? "Unknown error"
            )
        }

        let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
        guard decoded.embedding.count == Self.dimensions else {
            throw BedrockAPIError.invalidResponse
        }
        if let tokens = decoded.inputTextTokenCount {
            // Embeddings are billed, so they belong in the usage ledger
            // alongside the analysis calls rather than being invisible spend.
            // `AIPricing` has no family for Titan, so the pane shows the token
            // count without a dollar estimate — better than showing a made-up
            // rate, and the ledger stores tokens so a price can be added later.
            await AIUsageContext.attribute(.embedding) {
                UsageRecorder.record(
                    modelIdentifier: modelIdentifier,
                    usage: AIUsage(inputTokens: tokens, outputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0)
                )
            }
        }
        return decoded.embedding
    }

    private struct RequestBody: Encodable {
        let inputText: String
        let dimensions: Int
        let normalize: Bool
    }

    private struct ResponseBody: Decodable {
        let embedding: [Float]
        let inputTextTokenCount: Int?
    }

    /// Serializes credential loading so a fan-out of eight concurrent embeds
    /// triggers one SSO fetch, not eight.
    private actor CredentialBox {
        private var cached: AWSCredentials?
        private var inFlight: Task<AWSCredentials, Error>?

        func credentials(profile: String) async throws -> AWSCredentials {
            if let cached { return cached }
            if let inFlight { return try await inFlight.value }

            let task = Task<AWSCredentials, Error> {
                AWSCredentialLoader.restoreAccess()
                return try await AWSCredentialLoader.loadCredentials(profile: profile)
            }
            inFlight = task
            defer { inFlight = nil }
            let loaded = try await task.value
            cached = loaded
            return loaded
        }

        func invalidate() {
            cached = nil
        }
    }
}

/// Voyage AI embeddings — deliberately not built.
///
/// Voyage benchmarks better and its free tier would have covered this corpus
/// outright, but it means shipping meeting transcripts to a third party. Titan
/// runs inside the AWS account the app already talks to, under whatever
/// agreement already covers it. Revisit only if retrieval quality stalls and
/// the data-handling question has an answer.
final class VoyageEmbeddingService: EmbeddingService, @unchecked Sendable {
    let modelIdentifier = "voyage-4"
    var isAvailable: Bool { false }
    func embed(_ text: String) async -> [Float]? { nil }
}
