import XCTest
@testable import Grey_Eminence

/// Reducing a diarized cluster to one comparable vector, and folding
/// sightings together as someone is recognised again. Getting the weighting
/// wrong doesn't crash anything — it quietly mislabels people, which is worse
/// than leaving them numbered.
final class VoiceSignatureTests: XCTestCase {

    private func sig(_ v: [Float], seconds: Double = 60) -> VoiceSignature {
        VoiceSignature.from(turns: [(v, seconds)])!
    }

    // MARK: - Building

    func testSignatureIsUnitLength() throws {
        let s = try XCTUnwrap(VoiceSignature.from(turns: [([3, 4], 10)]))
        XCTAssertEqual(s.vector[0], 0.6, accuracy: 0.0001)
        XCTAssertEqual(s.vector[1], 0.8, accuracy: 0.0001)
        XCTAssertEqual(s.seconds, 10, accuracy: 0.0001)
    }

    func testLongTurnsOutweighShortOnes() throws {
        // A half-second "mm-hm" carries almost no vocal information and must
        // not count as much as a minute of speech.
        let s = try XCTUnwrap(VoiceSignature.from(turns: [([1, 0], 120), ([0, 1], 0.5)]))
        XCTAssertGreaterThan(s.vector[0], 0.99)
        XCTAssertLessThan(s.vector[1], 0.1)
    }

    func testSecondsAccumulateAcrossTurns() throws {
        let s = try XCTUnwrap(VoiceSignature.from(turns: [([1, 0], 30), ([1, 0], 45)]))
        XCTAssertEqual(s.seconds, 75, accuracy: 0.0001)
    }

    func testZeroLengthTurnsAreIgnored() throws {
        let s = try XCTUnwrap(VoiceSignature.from(turns: [([1, 0], 10), ([0, 1], 0)]))
        XCTAssertGreaterThan(s.vector[0], 0.99)
    }

    func testMismatchedWidthsAreSkippedRatherThanCorrupting() throws {
        // A short vector would otherwise be summed into the wrong dimensions.
        let s = try XCTUnwrap(VoiceSignature.from(turns: [([1, 0, 0], 10), ([9, 9], 10)]))
        XCTAssertEqual(s.vector.count, 3)
        XCTAssertGreaterThan(s.vector[0], 0.99)
    }

    func testNoUsableTurnsProducesNothing() {
        XCTAssertNil(VoiceSignature.from(turns: []))
        XCTAssertNil(VoiceSignature.from(turns: [([], 10)]))
        XCTAssertNil(VoiceSignature.from(turns: [([0, 0], 10)]), "a zero vector has no direction")
    }

    // MARK: - Comparing

    func testIdenticalVoicesScoreOne() {
        XCTAssertEqual(sig([1, 2, 3]).similarity(to: sig([1, 2, 3])), 1, accuracy: 0.0001)
    }

    func testUnrelatedVoicesScoreZero() {
        XCTAssertEqual(sig([1, 0]).similarity(to: sig([0, 1])), 0, accuracy: 0.0001)
    }

    func testScaleDoesNotAffectSimilarity() {
        // Only direction carries identity; loudness must not.
        XCTAssertEqual(sig([1, 2, 3]).similarity(to: sig([10, 20, 30])), 1, accuracy: 0.0001)
    }

    func testDifferentWidthsCannotBeCompared() {
        XCTAssertEqual(sig([1, 0]).similarity(to: sig([1, 0, 0])), 0)
    }

    // MARK: - Enrolling

    func testMergeMovesTowardsTheNewSighting() {
        let merged = sig([1, 0], seconds: 60).merged(with: sig([0, 1], seconds: 60))
        XCTAssertEqual(merged.vector[0], merged.vector[1], accuracy: 0.0001)
    }

    func testWellEstablishedProfileResistsAShortSample() {
        // Ten minutes of Erin shouldn't be dragged off course by four seconds
        // of someone who happened to sound similar.
        let established = sig([1, 0], seconds: 600)
        let brief = sig([0, 1], seconds: 4)
        let merged = established.merged(with: brief)
        XCTAssertGreaterThan(merged.similarity(to: established), 0.99)
    }

    func testEvidenceIsCappedSoAProfileStaysCorrectable() {
        var s = sig([1, 0], seconds: 600)
        for _ in 0..<20 { s = s.merged(with: sig([1, 0], seconds: 600)) }
        XCTAssertEqual(s.seconds, VoiceSignature.maxEnrolledSeconds, accuracy: 0.0001)
    }

    func testMergeStaysUnitLength() {
        let merged = sig([1, 0], seconds: 30).merged(with: sig([0, 1], seconds: 90))
        let magnitude = merged.vector.reduce(0) { $0 + $1 * $1 }.squareRoot()
        XCTAssertEqual(magnitude, 1, accuracy: 0.0001)
    }

    func testMergingIncompatibleWidthsKeepsTheOriginal() {
        let original = sig([1, 0])
        XCTAssertEqual(original.merged(with: sig([1, 0, 0])), original)
    }

    // MARK: - Stored clusters

    func testStaleClusterFilesAreRejected() {
        // Signatures built by an older format can't be compared against
        // current ones; the version guard is what stops that being silent.
        var stored = MeetingVoiceClusters(clusters: [])
        XCTAssertTrue(stored.isCurrent)
        stored.version = MeetingVoiceClusters.currentVersion - 1
        XCTAssertFalse(stored.isCurrent)
    }

    func testClusterLookupIsByTranscriptLabel() {
        let stored = MeetingVoiceClusters(clusters: [
            .init(label: "Speaker 1", signature: sig([1, 0])),
            .init(label: "Speaker 2", signature: sig([0, 1])),
        ])
        XCTAssertEqual(stored.cluster(labelled: "Speaker 2")?.signature, sig([0, 1]))
        XCTAssertNil(stored.cluster(labelled: "Speaker 9"))
    }

    func testSignatureSurvivesARoundTrip() throws {
        let original = MeetingVoiceClusters(clusters: [.init(label: "Speaker 1", signature: sig([0.3, 0.9]))])
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(MeetingVoiceClusters.self, from: data), original)
    }
}
