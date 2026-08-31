import Foundation

enum AIProvider: String {
    case anthropic
    case bedrock
    case xai

    var displayName: String {
        switch self {
        case .anthropic: "Anthropic API"
        case .bedrock: "AWS Bedrock"
        case .xai: "xAI (Grok)"
        }
    }

    static func current(defaults: UserDefaults = .standard) -> AIProvider {
        AIProvider(rawValue: defaults.string(forKey: "aiProvider") ?? "anthropic") ?? .anthropic
    }
}

enum AIClientFactory {
    static let defaultClaudeModel = "claude-sonnet-4-20250514"
    static let defaultXAIModel = "grok-4.6"

    static let analysisTimeoutDefaultsKey = "aiAnalysisTimeoutSeconds"
    static let xaiCustomModelDefaultsKey = "xaiCustomModel"

    /// Per-call ceiling for meeting analysis. 0 in UserDefaults means
    /// provider default (240s xAI, 120s Claude/Bedrock). Settings can
    /// override from 30…600.
    static var analysisTimeoutSeconds: Int {
        let stored = UserDefaults.standard.integer(forKey: analysisTimeoutDefaultsKey)
        if stored >= 30 { return min(stored, 600) }
        return current() == .xai ? 240 : 120
    }

    static func current() -> AIProvider { AIProvider.current() }

    static func makeClient() async throws -> (any AIClient)? {
        let provider = AIProvider.current()
        return try await makeClient(provider: provider, model: selectedModel(for: provider))
    }

    /// Provider-specific model UserDefaults. Anthropic / Bedrock share
    /// `claudeModel`; xAI uses `xaiModel` so a leftover Claude ID is never
    /// sent to Grok.
    static func selectedModel(for provider: AIProvider, defaults: UserDefaults = .standard) -> String {
        switch provider {
        case .anthropic, .bedrock:
            return defaults.string(forKey: "claudeModel") ?? defaultClaudeModel
        case .xai:
            let custom = defaults.string(forKey: xaiCustomModelDefaultsKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !custom.isEmpty { return custom }
            let picked = defaults.string(forKey: "xaiModel") ?? defaultXAIModel
            return picked == "custom" ? defaultXAIModel : picked
        }
    }

    /// Client for per-frame vision analysis. Defaults to Haiku — frame
    /// descriptions don't need the main model's depth, and Haiku is ~3×
    /// cheaper per token. Session synthesis and transcript analysis stay
    /// on `makeClient()`.
    static func makeFrameAnalysisClient() async throws -> (any AIClient)? {
        let provider = AIProvider.current()
        let mainModel = selectedModel(for: provider)

        // No trajector settings at all means the main model also runs on
        // foundation IDs, so Haiku's foundation ID is equally reachable.
        let trajector = TrajectorSettings.load()
        let choice = frameAnalysisModel(
            preferred: ScreenShareSettings.frameAnalysisModel,
            mainModel: mainModel,
            provider: provider,
            haikuProfileAvailable: trajector == nil || trajector?.haikuModel != nil
        )
        if choice.fellBackToMainModel {
            let reason = provider == .xai
                ? "Claude frame-analysis model is not valid on xAI"
                : "no Haiku inference profile in trajector settings"
            LogManager.send("Frame analysis using main model \(mainModel): \(reason)", category: .screen)
        }
        return try await makeClient(provider: provider, model: choice.model)
    }

    /// Resolution of which model the frame-analysis client is bound to.
    struct FrameAnalysisModelChoice: Equatable {
        let model: String
        let fellBackToMainModel: Bool
    }

    /// Pure resolver for the frame-analysis model. An empty preference means
    /// "same as main model". Bedrock orgs that route through inference
    /// profiles can't invoke a model without a mapped profile — when Haiku
    /// has no slot, fall back to the main model instead of failing mid-meeting.
    static func frameAnalysisModel(
        preferred: String,
        mainModel: String,
        provider: AIProvider,
        haikuProfileAvailable: Bool
    ) -> FrameAnalysisModelChoice {
        guard !preferred.isEmpty, preferred != mainModel else {
            return FrameAnalysisModelChoice(model: mainModel, fellBackToMainModel: false)
        }
        // xAI cannot invoke Claude IDs. A leftover Haiku default (or any
        // Anthropic family tag) would 400 mid-meeting — fall back to the
        // selected Grok model instead.
        if provider == .xai, isClaudeFamilyModelID(preferred) {
            return FrameAnalysisModelChoice(model: mainModel, fellBackToMainModel: true)
        }
        if provider == .bedrock, preferred.contains("haiku"), !haikuProfileAvailable {
            return FrameAnalysisModelChoice(model: mainModel, fellBackToMainModel: true)
        }
        return FrameAnalysisModelChoice(model: preferred, fellBackToMainModel: false)
    }

    /// True for Anthropic / Claude family IDs that must not be sent to xAI.
    static func isClaudeFamilyModelID(_ model: String) -> Bool {
        let lower = model.lowercased()
        return lower.contains("claude")
            || lower.contains("haiku")
            || lower.contains("sonnet")
            || lower.contains("opus")
    }

    private static func makeClient(provider: AIProvider, model: String) async throws -> (any AIClient)? {
        switch provider {
        case .anthropic:
            guard let apiKey = try KeychainHelper.get(AIPromptTemplates.keychainKey),
                  !apiKey.isEmpty else {
                return nil
            }
            return ClaudeAPIClient(apiKey: apiKey, model: model)

        case .bedrock:
            let profile = UserDefaults.standard.string(forKey: "awsProfile") ?? "default"
            let region = UserDefaults.standard.string(forKey: "awsRegion") ?? "us-east-1"
            AWSCredentialLoader.restoreAccess()
            let credentials = try await AWSCredentialLoader.loadCredentials(profile: profile)
            let bedrockModel = resolveBedrockModel(for: model)
            return BedrockAPIClient(credentials: credentials, region: region, model: bedrockModel)

        case .xai:
            guard let apiKey = try KeychainHelper.get(AIPromptTemplates.xaiKeychainKey),
                  !apiKey.isEmpty else {
                return nil
            }
            return XAIAPIClient(apiKey: apiKey, model: model)
        }
    }

    /// Resolve model: prefer inference profile ARN from trajector settings, fall back to foundation model ID
    static func resolveBedrockModel(for anthropicModel: String) -> String {
        let settings = TrajectorSettings.load()

        // Map the UI model choice to the corresponding inference profile ARN
        switch anthropicModel {
        case "claude-opus-4-20250514":
            if let arn = settings?.opusModel { return arn }
        case "claude-sonnet-4-20250514":
            if let arn = settings?.sonnetModel { return arn }
        case "claude-haiku-4-5-20251001":
            if let arn = settings?.haikuModel { return arn }
        default:
            break
        }

        // Fall back to foundation model ID
        return foundationModelId(for: anthropicModel)
    }

    static func foundationModelId(for anthropicModel: String) -> String {
        switch anthropicModel {
        case "claude-opus-4-20250514":
            "anthropic.claude-opus-4-20250514-v1:0"
        case "claude-sonnet-4-20250514":
            "anthropic.claude-sonnet-4-20250514-v1:0"
        case "claude-haiku-4-5-20251001":
            "anthropic.claude-haiku-4-5-20251001-v1:0"
        default:
            "anthropic.\(anthropicModel)-v1:0"
        }
    }
}
