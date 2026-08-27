import XCTest
@testable import Grey_Eminence

/// An org that routes Bedrock through application inference profiles cannot
/// invoke a foundation model directly — the role is scoped to the ARNs, and
/// the bare id 403s naming a model the user never chose. These pin the
/// resolution order and, more importantly, that one model's ARN can never be
/// handed to another.
final class BedrockModelResolutionTests: XCTestCase {
    private var saved: [String: Any?] = [:]

    private var keys: [String] {
        EmbeddingProvider.allCases.map { BedrockEmbeddingAccount.arnKey(for: $0) }
    }

    override func setUp() {
        super.setUp()
        for key in keys {
            saved[key] = UserDefaults.standard.object(forKey: key)
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    override func tearDown() {
        for (key, value) in saved {
            if let value { UserDefaults.standard.set(value, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        saved = [:]
        super.tearDown()
    }

    func testFoundationIDIsUsedWhenNoProfileIsConfigured() {
        XCTAssertEqual(
            BedrockEmbeddingAccount.modelID(for: .cohere, foundation: "cohere.embed-english-v3"),
            "cohere.embed-english-v3"
        )
    }

    func testConfiguredARNWins() {
        let arn = "arn:aws:bedrock:us-east-2:1234:application-inference-profile/abc"
        UserDefaults.standard.set(arn, forKey: BedrockEmbeddingAccount.arnKey(for: .cohere))
        XCTAssertEqual(
            BedrockEmbeddingAccount.modelID(for: .cohere, foundation: "cohere.embed-english-v3"),
            arn
        )
    }

    func testARNsAreKeyedPerModel() {
        // Handing Cohere's profile to Titan would fail as a confusing
        // validation error rather than an obvious misconfiguration.
        let cohereARN = "arn:aws:bedrock:us-east-2:1234:application-inference-profile/cohere"
        UserDefaults.standard.set(cohereARN, forKey: BedrockEmbeddingAccount.arnKey(for: .cohere))
        XCTAssertEqual(
            BedrockEmbeddingAccount.modelID(for: .titan, foundation: "amazon.titan-embed-text-v2:0"),
            "amazon.titan-embed-text-v2:0"
        )
        XCTAssertNotEqual(
            BedrockEmbeddingAccount.arnKey(for: .titan),
            BedrockEmbeddingAccount.arnKey(for: .cohere)
        )
    }

    func testBlankARNFallsBackRatherThanInvokingAnEmptyModelID() {
        UserDefaults.standard.set("   ", forKey: BedrockEmbeddingAccount.arnKey(for: .cohere))
        XCTAssertEqual(
            BedrockEmbeddingAccount.modelID(for: .cohere, foundation: "cohere.embed-english-v3"),
            "cohere.embed-english-v3"
        )
    }

    func testOnDeviceProvidersNeverResolveToAnARN() {
        UserDefaults.standard.set("arn:aws:bedrock:x", forKey: BedrockEmbeddingAccount.arnKey(for: .cohere))
        XCTAssertEqual(
            BedrockEmbeddingAccount.modelID(for: .nlEmbedding, foundation: "apple"),
            "apple"
        )
    }
}
