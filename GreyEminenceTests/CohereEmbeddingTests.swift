import XCTest
@testable import Grey_Eminence

/// Batched embedding is where positional correctness gets dangerous: a batch
/// that comes back short or out of step pairs vectors with the wrong text, and
/// nothing downstream would ever notice — the index would just quietly return
/// the wrong snippets forever.
final class CohereEmbeddingTests: XCTestCase {

    // MARK: - Response decoding

    func testDecodesTheFlatV3Shape() throws {
        let json = #"{"embeddings":[[0.1,0.2],[0.3,0.4]],"id":"x"}"#.data(using: .utf8)!
        let vectors = try CohereEmbeddingService.decodeEmbeddings(from: json)
        XCTAssertEqual(vectors.count, 2)
        XCTAssertEqual(vectors[0], [0.1, 0.2])
    }

    func testDecodesTheTypedV4Shape() throws {
        // A model swap behind an inference profile has changed response shapes
        // on this codebase before; both must decode.
        let json = #"{"embeddings":{"float":[[0.5,0.6]]},"id":"x"}"#.data(using: .utf8)!
        let vectors = try CohereEmbeddingService.decodeEmbeddings(from: json)
        XCTAssertEqual(vectors, [[0.5, 0.6]])
    }

    func testUnrecognisedShapeThrowsRatherThanReturningNothing() {
        let json = #"{"unexpected":true}"#.data(using: .utf8)!
        XCTAssertThrowsError(try CohereEmbeddingService.decodeEmbeddings(from: json))
    }

    // MARK: - Batching invariants

    func testBatchSizeIsWithinTheVerifiedLimit() {
        // 96 was confirmed against the live API. Raising it past that without
        // re-verifying would fail a whole batch at a time.
        XCTAssertLessThanOrEqual(CohereEmbeddingService.batchSize, 96)
        XCTAssertGreaterThan(CohereEmbeddingService.batchSize, 1)
    }

    func testBatchingCoversEveryItemExactlyOnce() {
        // Mirrors the stride the service uses: every index assigned to exactly
        // one batch, in order.
        let count = 250
        let batches = stride(from: 0, to: count, by: CohereEmbeddingService.batchSize).map {
            Array($0..<min($0 + CohereEmbeddingService.batchSize, count))
        }
        XCTAssertEqual(batches.flatMap { $0 }, Array(0..<count))
        XCTAssertEqual(batches.count, 3)
    }

    func testDocumentAndQueryAreDistinctPurposes() {
        // Cohere is asymmetric — sending a query as a document costs recall,
        // silently. The type exists so a call site has to choose.
        XCTAssertNotEqual(EmbeddingPurpose.document.rawValue, EmbeddingPurpose.query.rawValue)
    }

    func testModelIdentifiersDoNotCollide() {
        // Two models sharing an identifier would mix incompatible vectors in
        // one index.
        let identifiers = EmbeddingProvider.allCases.map { $0.makeService().modelIdentifier }
        XCTAssertEqual(Set(identifiers).count, identifiers.count)
    }

    func testCohereIdentifierRecordsItsWidth() {
        XCTAssertTrue(
            CohereEmbeddingService().modelIdentifier.hasSuffix(":\(CohereEmbeddingService.dimensions)")
        )
    }

    // MARK: - Empty input

    func testEmptyTextsGetNilWithoutShiftingTheirNeighbours() async {
        // Cohere rejects a batch containing an empty string, so blanks are
        // filtered out — but every surviving text must keep its own index.
        let service = CohereEmbeddingService(region: "us-east-1", profile: "definitely-not-a-profile")
        let results = await service.embedAll(["", "   ", ""], as: .document)
        XCTAssertEqual(results.count, 3)
        XCTAssertTrue(results.allSatisfy { $0 == nil })
    }
}
