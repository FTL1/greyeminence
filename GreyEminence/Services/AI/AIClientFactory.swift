import Foundation

enum AIProvider: String {
    case anthropic
    case bedrock
}

enum AIClientFactory {
    static func makeClient() async throws -> (any AIClient)? {
        let providerRaw = UserDefaults.standard.string(forKey: "aiProvider") ?? "anthropic"
        let provider = AIProvider(rawValue: providerRaw) ?? .anthropic
        let model = UserDefaults.standard.string(forKey: "claudeModel") ?? "claude-sonnet-4-20250514"
        return try await makeClient(provider: provider, model: model)
    }

    /// Client for per-frame vision analysis. Defaults to Haiku — frame
    /// descriptions don't need the main model's depth, and Haiku is ~3×
    /// cheaper per token. Session synthesis and transcript analysis stay
    /// on `makeClient()`.
    static func makeFrameAnalysisClient() async throws -> (any AIClient)? {
        let providerRaw = UserDefaults.standard.string(forKey: "aiProvider") ?? "anthropic"
        let provider = AIProvider(rawValue: providerRaw) ?? .anthropic
        let mainModel = UserDefaults.standard.string(forKey: "claudeModel") ?? "claude-sonnet-4-20250514"

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
            LogManager.send("Frame analysis using main model \(mainModel): no Haiku inference profile in trajector settings", category: .screen)
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
        if provider == .bedrock, preferred.contains("haiku"), !haikuProfileAvailable {
            return FrameAnalysisModelChoice(model: mainModel, fellBackToMainModel: true)
        }
        return FrameAnalysisModelChoice(model: preferred, fellBackToMainModel: false)
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
