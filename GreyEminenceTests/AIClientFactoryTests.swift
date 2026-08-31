import XCTest
@testable import Grey_Eminence

/// Pure tests for the frame-analysis model resolver — no UserDefaults,
/// no network.
final class AIClientFactoryTests: XCTestCase {

    private let haiku = "claude-haiku-4-5-20251001"
    private let sonnet = "claude-sonnet-4-20250514"

    func testAnthropicUsesPreferredHaiku() {
        let choice = AIClientFactory.frameAnalysisModel(
            preferred: haiku, mainModel: sonnet,
            provider: .anthropic, haikuProfileAvailable: false
        )
        XCTAssertEqual(choice.model, haiku)
        XCTAssertFalse(choice.fellBackToMainModel)
    }

    func testBedrockWithHaikuProfileUsesHaiku() {
        let choice = AIClientFactory.frameAnalysisModel(
            preferred: haiku, mainModel: sonnet,
            provider: .bedrock, haikuProfileAvailable: true
        )
        XCTAssertEqual(choice.model, haiku)
        XCTAssertFalse(choice.fellBackToMainModel)
    }

    func testBedrockWithoutHaikuProfileFallsBackToMainModel() {
        let choice = AIClientFactory.frameAnalysisModel(
            preferred: haiku, mainModel: sonnet,
            provider: .bedrock, haikuProfileAvailable: false
        )
        XCTAssertEqual(choice.model, sonnet)
        XCTAssertTrue(choice.fellBackToMainModel)
    }

    func testEmptyPreferenceMeansMainModel() {
        for provider in [AIProvider.anthropic, .bedrock] {
            let choice = AIClientFactory.frameAnalysisModel(
                preferred: "", mainModel: sonnet,
                provider: provider, haikuProfileAvailable: true
            )
            XCTAssertEqual(choice.model, sonnet)
            XCTAssertFalse(choice.fellBackToMainModel)
        }
    }

    func testPreferredEqualToMainModelIsNotAFallback() {
        let choice = AIClientFactory.frameAnalysisModel(
            preferred: sonnet, mainModel: sonnet,
            provider: .bedrock, haikuProfileAvailable: false
        )
        XCTAssertEqual(choice.model, sonnet)
        XCTAssertFalse(choice.fellBackToMainModel)
    }

    func testHaikuMainModelStaysOnHaikuWithoutProfile() {
        // Main model IS haiku — nothing to fall back to; the resolver must
        // not loop the choice through the bedrock guard.
        let choice = AIClientFactory.frameAnalysisModel(
            preferred: haiku, mainModel: haiku,
            provider: .bedrock, haikuProfileAvailable: false
        )
        XCTAssertEqual(choice.model, haiku)
        XCTAssertFalse(choice.fellBackToMainModel)
    }

    func testXAIDoesNotKeepClaudeHaikuFrameModel() {
        let choice = AIClientFactory.frameAnalysisModel(
            preferred: haiku, mainModel: "grok-4.6",
            provider: .xai, haikuProfileAvailable: true
        )
        XCTAssertEqual(choice.model, "grok-4.6")
        XCTAssertTrue(choice.fellBackToMainModel)
    }

    func testXAIEmptyPreferenceUsesMainGrokModel() {
        let choice = AIClientFactory.frameAnalysisModel(
            preferred: "", mainModel: "grok-4.6",
            provider: .xai, haikuProfileAvailable: true
        )
        XCTAssertEqual(choice.model, "grok-4.6")
        XCTAssertFalse(choice.fellBackToMainModel)
    }

    func testXAIKeepsExplicitGrokFrameModel() {
        let choice = AIClientFactory.frameAnalysisModel(
            preferred: "grok-4.5", mainModel: "grok-4.6",
            provider: .xai, haikuProfileAvailable: true
        )
        XCTAssertEqual(choice.model, "grok-4.5")
        XCTAssertFalse(choice.fellBackToMainModel)
    }

    func testSelectedModelReadsProviderSpecificDefaults() {
        let defaults = UserDefaults(suiteName: "AIClientFactoryTests.\(UUID().uuidString)")!
        defaults.set("claude-opus-4-20250514", forKey: "claudeModel")
        defaults.set("grok-4.5", forKey: "xaiModel")
        XCTAssertEqual(
            AIClientFactory.selectedModel(for: .anthropic, defaults: defaults),
            "claude-opus-4-20250514"
        )
        XCTAssertEqual(
            AIClientFactory.selectedModel(for: .xai, defaults: defaults),
            "grok-4.5"
        )
        XCTAssertEqual(
            AIClientFactory.selectedModel(for: .xai, defaults: UserDefaults(suiteName: "empty.\(UUID().uuidString)")!),
            "grok-4.6"
        )
    }
}
