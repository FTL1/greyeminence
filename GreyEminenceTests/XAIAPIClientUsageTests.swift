import XCTest
@testable import Grey_Eminence

/// OpenAI-style usage mapping for xAI Chat Completions. Does not hit the network.
final class XAIAPIClientUsageTests: XCTestCase {

    func testMapUsageOpenAIFields() {
        let body = Data("""
        {"choices":[{"message":{"content":"hi"},"finish_reason":"stop"}],
         "usage":{"prompt_tokens":41,"completion_tokens":104,"total_tokens":145,
          "prompt_tokens_details":{"cached_tokens":10}}}
        """.utf8)
        let usage = XAIAPIClient.mapUsage(from: body)
        XCTAssertEqual(usage, AIUsage(inputTokens: 41, outputTokens: 104, cacheReadTokens: 10, cacheWriteTokens: 0))
    }

    func testMapUsageMissingDetails() {
        let body = Data("""
        {"usage":{"prompt_tokens":12,"completion_tokens":3}}
        """.utf8)
        let usage = XAIAPIClient.mapUsage(from: body)
        XCTAssertEqual(usage, AIUsage(inputTokens: 12, outputTokens: 3, cacheReadTokens: 0, cacheWriteTokens: 0))
    }

    func testMapUsageMissingUsageReturnsNil() {
        let body = Data("""
        {"choices":[{"message":{"content":"hi"}}]}
        """.utf8)
        XCTAssertNil(XAIAPIClient.mapUsage(from: body))
    }

    func testMapUsageGarbageReturnsNil() {
        XCTAssertNil(XAIAPIClient.mapUsage(from: Data("not json".utf8)))
    }
}
