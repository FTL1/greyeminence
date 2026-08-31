import Foundation

/// OpenAI-compatible Chat Completions client for xAI (Grok).
///
/// Anthropic (`ClaudeAPIClient`) and Bedrock (`BedrockAPIClient`) share the
/// Messages API shape. xAI does not — it expects `POST /v1/chat/completions`
/// with Bearer auth and OpenAI-style `messages` / `image_url` content. Do not
/// route through the Anthropic clients or reuse `AIMessageContentBlock`.
struct XAIAPIClient: AIClient, Sendable {
    private let apiKey: String
    private let model: String

    var modelIdentifier: String { "xai:\(model)" }

    init(apiKey: String, model: String = "grok-4.6") {
        self.apiKey = apiKey
        self.model = model
    }

    var supportsImages: Bool { true }

    func sendMessage(
        system: String,
        userContent: String,
        maxTokens: Int = 8192
    ) async throws -> String {
        try await send(
            system: system,
            userContent: .text(userContent),
            maxTokens: maxTokens
        )
    }

    func sendMessage(
        system: String,
        userContent: String,
        images: [AIImageContent],
        maxTokens: Int
    ) async throws -> String {
        // Images first, text last — same order as Anthropic clients / xAI docs.
        var parts: [UserContentPart] = images.map { .image($0) }
        parts.append(.text(userContent))
        return try await send(
            system: system,
            userContent: .parts(parts),
            maxTokens: maxTokens
        )
    }

    // MARK: - Core request

    private func send(
        system: String,
        userContent: UserMessageContent,
        maxTokens: Int
    ) async throws -> String {
        let body = RequestBody(
            model: model,
            max_tokens: maxTokens,
            messages: [
                Message(role: "system", content: .text(system)),
                Message(role: "user", content: userContent),
            ]
        )

        let request = try buildRequest(body: body)
        logRequest(userContent: userContent, body: request.httpBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw XAIAPIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if let apiError = try? JSONDecoder().decode(APIErrorResponse.self, from: data) {
                throw XAIAPIError.apiError(
                    statusCode: httpResponse.statusCode,
                    message: apiError.resolvedMessage
                )
            }
            throw XAIAPIError.httpError(statusCode: httpResponse.statusCode)
        }

        // Log raw response before decoding so shape drift is diagnosable.
        if let prettyString = prettyJSON(data) {
            LogManager.send("xAI response", category: .ai, detail: prettyString)
        }

        let apiResponse = try JSONDecoder().decode(APIResponse.self, from: data)

        guard let choice = apiResponse.choices.first else {
            throw XAIAPIError.noChoices
        }

        let text = choice.message?.resolvedText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else {
            throw XAIAPIError.noTextContent(finishReason: choice.finish_reason)
        }

        if let usage = Self.mapUsage(from: data) {
            UsageRecorder.record(modelIdentifier: modelIdentifier, usage: usage)
            LogManager.send(
                "usage: \(usage.inputTokens.formatted()) in / \(usage.outputTokens.formatted()) out (\(model))",
                category: .ai
            )
        }

        return text
    }

    private func buildRequest(body: RequestBody) throws -> URLRequest {
        guard let url = URL(string: "https://api.x.ai/v1/chat/completions") else {
            throw XAIAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)
        request.timeoutInterval = TimeInterval(AIClientFactory.analysisTimeoutSeconds)
        return request
    }

    private func logRequest(userContent: UserMessageContent, body: Data?) {
        switch userContent {
        case .parts(let parts):
            let imageCount = parts.count(where: {
                if case .image = $0 { true } else { false }
            })
            if imageCount > 0 {
                let bytes = body?.count ?? 0
                let text = parts.compactMap {
                    if case .text(let t) = $0 { t } else { nil }
                }.joined(separator: "\n")
                LogManager.send(
                    "xAI request payload (\(imageCount) images, \(bytes / 1024) KB)",
                    category: .ai,
                    detail: text
                )
                return
            }
        case .text:
            break
        }

        if let prettyString = prettyJSON(body) {
            LogManager.send("xAI request payload", category: .ai, detail: prettyString)
        }
    }

    private func prettyJSON(_ data: Data?) -> String? {
        guard let data,
              let jsonObject = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(
                withJSONObject: jsonObject,
                options: [.prettyPrinted, .sortedKeys]
              ),
              let prettyString = String(data: pretty, encoding: .utf8)
        else {
            return nil
        }
        return prettyString
    }

    // MARK: - Usage mapping (OpenAI field names — not AIUsage.decode)

    /// Maps Chat Completions `usage` into `AIUsage`. Never uses
    /// `AIUsage.decode`, which only understands Anthropic
    /// `input_tokens` / `output_tokens`.
    static func mapUsage(from data: Data) -> AIUsage? {
        struct Envelope: Decodable {
            let usage: UsageBlock?
        }
        struct UsageBlock: Decodable {
            let prompt_tokens: Int?
            let completion_tokens: Int?
            let prompt_tokens_details: PromptTokenDetails?
        }
        struct PromptTokenDetails: Decodable {
            let cached_tokens: Int?
        }

        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              let usage = envelope.usage else {
            return nil
        }

        return AIUsage(
            inputTokens: usage.prompt_tokens ?? 0,
            outputTokens: usage.completion_tokens ?? 0,
            cacheReadTokens: usage.prompt_tokens_details?.cached_tokens ?? 0,
            cacheWriteTokens: 0
        )
    }

    // MARK: - Request types

    private struct RequestBody: Encodable {
        let model: String
        let max_tokens: Int
        let messages: [Message]
    }

    private struct Message: Encodable {
        let role: String
        let content: UserMessageContent
    }

    /// OpenAI-style message content: plain string or multimodal parts.
    private enum UserMessageContent: Encodable {
        case text(String)
        case parts([UserContentPart])

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .text(let string):
                try container.encode(string)
            case .parts(let parts):
                try container.encode(parts)
            }
        }
    }

    private enum UserContentPart: Encodable {
        case text(String)
        case image(AIImageContent)

        private enum CodingKeys: String, CodingKey {
            case type, text, image_url
        }

        private struct ImageURL: Encodable {
            let url: String
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .text(let text):
                try container.encode("text", forKey: .type)
                try container.encode(text, forKey: .text)
            case .image(let image):
                try container.encode("image_url", forKey: .type)
                // data-URL form required for inline base64 (xAI + OpenAI style).
                let dataURL = "data:\(image.mediaType);base64,\(image.base64Data)"
                try container.encode(ImageURL(url: dataURL), forKey: .image_url)
            }
        }
    }

    // MARK: - Response types

    private struct APIResponse: Decodable {
        let choices: [Choice]
    }

    private struct Choice: Decodable {
        let message: ChoiceMessage?
        let finish_reason: String?
    }

    private struct ChoiceMessage: Decodable {
        /// Chat Completions returns a string for text replies.
        let content: String?
        let refusal: String?

        var resolvedText: String? {
            if let content, !content.isEmpty { return content }
            if let refusal, !refusal.isEmpty { return refusal }
            return nil
        }
    }

    private struct APIErrorResponse: Decodable {
        /// OpenAI-style: `{ "error": { "message": "..." } }`
        /// Also tolerate a bare top-level `message`.
        let error: APIErrorDetail?
        let message: String?

        var resolvedMessage: String {
            error?.message ?? message ?? "Unknown xAI error"
        }
    }

    private struct APIErrorDetail: Decodable {
        let message: String?
        let type: String?
        let code: String?
    }
}

enum XAIAPIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int)
    case apiError(statusCode: Int, message: String)
    case noChoices
    case noTextContent(finishReason: String?)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Invalid xAI API URL"
        case .invalidResponse:
            "Invalid response from xAI"
        case .httpError(let statusCode):
            Self.friendlyHTTPMessage(statusCode)
        case .apiError(let statusCode, let message):
            Self.friendlyAPIMessage(statusCode: statusCode, message: message)
        case .noChoices:
            "No choices in xAI response"
        case .noTextContent(let finishReason):
            finishReason == "length"
                ? "The model hit its output limit before answering — try again, or raise max tokens"
                : "No text content in xAI response\(finishReason.map { " (finish reason: \($0))" } ?? "")"
        }
    }

    private static func friendlyHTTPMessage(_ statusCode: Int) -> String {
        switch statusCode {
        case 429: "API rate limit reached — try again shortly"
        case 401: "Invalid API key — check Settings"
        case 403: "API access denied — check your API key permissions"
        default: "HTTP error \(statusCode)"
        }
    }

    private static func friendlyAPIMessage(statusCode: Int, message: String) -> String {
        switch statusCode {
        case 429: "API rate limit reached — try again shortly"
        case 401: "Invalid API key — check Settings"
        case 403: "API access denied — check your API key permissions"
        default: message
        }
    }
}
