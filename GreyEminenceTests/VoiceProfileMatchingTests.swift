import XCTest
@testable import Grey_Eminence

/// Deciding whose voice a cluster is. The asymmetry here is deliberate: a
/// wrong name stated confidently is worse than "Speaker 2", because the reader
/// has no way to tell it's wrong, whereas a number is honestly uninformative.
final class VoiceProfileMatchingTests: XCTestCase {

    private func sig(_ v: [Float], seconds: Double = 120) -> VoiceSignature {
        VoiceSignature.from(turns: [(v, seconds)])!
    }

    private func profile(_ name: String, _ v: [Float], meetings: Int = 1) -> VoiceProfileStore.Profile {
        .init(contactID: UUID(), contactName: name, signature: sig(v), meetingCount: meetings, updatedAt: .now)
    }

    func testClearMatchIsFound() throws {
        let erin = profile("Erin", [1, 0, 0])
        let match = try XCTUnwrap(
            VoiceProfileStore.bestMatch(for: sig([0.98, 0.2, 0]), profiles: [erin, profile("Walter", [0, 1, 0])])
        )
        XCTAssertEqual(match.profile.contactName, "Erin")
        XCTAssertTrue(VoiceProfileStore.isConfident(match))
    }

    func testUnknownVoiceMatchesNobody() {
        XCTAssertNil(
            VoiceProfileStore.bestMatch(for: sig([0, 0, 1]), profiles: [profile("Erin", [1, 0, 0])])
        )
    }

    func testTwoSimilarVoicesAreNotConfidentlyToldapart() throws {
        // The failure this guards: two people who genuinely sound alike, where
        // the top score is high but the runner-up is right behind it. Naming
        // one of them would be a coin flip presented as fact.
        let match = try XCTUnwrap(VoiceProfileStore.bestMatch(
            for: sig([1, 1, 0]),
            profiles: [profile("Amit", [1, 0.98, 0]), profile("Abhishek", [0.98, 1, 0])]
        ))
        XCTAssertGreaterThan(match.similarity, VoiceProfileStore.autoApplyThreshold)
        XCTAssertFalse(
            VoiceProfileStore.isConfident(match),
            "a near-tie must be offered as a suggestion, never applied"
        )
    }

    func testMatchingIsRestrictedToPeopleWhoCouldBeInTheRoom() {
        // Comparing against everyone ever enrolled invites a confident match
        // on somebody who wasn't in the meeting.
        let erin = profile("Erin", [1, 0, 0])
        let walter = profile("Walter", [0, 1, 0])
        XCTAssertNil(
            VoiceProfileStore.bestMatch(
                for: sig([1, 0, 0]),
                among: [walter.contactID],
                profiles: [erin, walter]
            ),
            "Erin isn't an attendee, so her voice must not be offered"
        )
    }

    func testWeakSimilarityIsNotEvenSuggested() {
        // cos ≈ 0.45 — below the suggestion floor.
        XCTAssertNil(
            VoiceProfileStore.bestMatch(for: sig([1, 2, 0]), profiles: [profile("Erin", [1, 0, 0])])
        )
    }

    func testBorderlineMatchIsSuggestedButNotApplied() throws {
        // Between the two thresholds: worth showing, not worth asserting.
        // cos ≈ 0.61 — between the two thresholds.
        let match = try XCTUnwrap(
            VoiceProfileStore.bestMatch(for: sig([1, 1.3, 0]), profiles: [profile("Erin", [1, 0, 0])])
        )
        XCTAssertGreaterThanOrEqual(match.similarity, VoiceProfileStore.suggestThreshold)
        XCTAssertFalse(VoiceProfileStore.isConfident(match))
    }

    func testEmptyPoolMatchesNothing() {
        XCTAssertNil(VoiceProfileStore.bestMatch(for: sig([1, 0, 0]), profiles: []))
    }

    func testEmptySignatureMatchesNothing() {
        let empty = VoiceSignature(vector: [], seconds: 0)
        XCTAssertNil(VoiceProfileStore.bestMatch(for: empty, profiles: [profile("Erin", [1, 0, 0])]))
    }

    func testThresholdsAreOrderedSoSuggestionIsTheWiderNet() {
        XCTAssertLessThan(VoiceProfileStore.suggestThreshold, VoiceProfileStore.autoApplyThreshold)
        XCTAssertGreaterThan(VoiceProfileStore.requiredMargin, 0)
    }
}
