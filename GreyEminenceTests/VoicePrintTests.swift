import SwiftData
import XCTest
@testable import Grey_Eminence

final class VoicePrintTests: XCTestCase {
    func testCodecRoundTrip() {
        let values: [Float] = [0.1, -0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8]
        let data = VoicePrintCodec.encode(values)
        let decoded = VoicePrintCodec.decode(data)
        XCTAssertEqual(decoded, values)
        XCTAssertNil(VoicePrintCodec.decode(nil))
        XCTAssertNil(VoicePrintCodec.decode(Data([0x00])))
    }

    func testCosineDistanceIdenticalIsZero() {
        let vector: [Float] = [1, 0, 0, 0, 0, 0, 0, 0]
        XCTAssertEqual(VoicePrintMatcher.cosineDistance(vector, vector), 0, accuracy: 0.0001)
    }

    func testLooseDistanceDoesNotMatchEnrolledThreshold() {
        let probe: [Float] = [1, 0, 0, 0, 0, 0, 0, 0]
        let kinda: [Float] = [0.6, 0.8, 0, 0, 0, 0, 0, 0]
        let distance = VoicePrintMatcher.cosineDistance(probe, kinda)
        XCTAssertGreaterThan(distance, VoicePrintMatcher.enrolledDistance)
        XCTAssertNil(
            VoicePrintMatcher.bestMatch(
                embedding: probe,
                in: [(item: "jordan", embedding: kinda)],
                threshold: VoicePrintMatcher.enrolledDistance
            )
        )
    }

    func testBestMatchRequiresMarginWhenTwoPeopleAreClose() {
        let probe: [Float] = [1, 0, 0, 0, 0, 0, 0, 0]
        let a: [Float] = [0.99, 0.1, 0, 0, 0, 0, 0, 0]
        let b: [Float] = [0.98, 0.12, 0, 0, 0, 0, 0, 0]
        XCTAssertNil(
            VoicePrintMatcher.bestMatch(
                embedding: probe,
                in: [(item: "jordan", embedding: a), (item: "sam", embedding: b)],
                threshold: 0.5,
                margin: 0.08
            )
        )
    }

    func testBestMatchRespectsThreshold() {
        let probe: [Float] = [1, 0, 0, 0, 0, 0, 0, 0]
        let close: [Float] = [0.95, 0.05, 0, 0, 0, 0, 0, 0]
        let far: [Float] = [0, 1, 0, 0, 0, 0, 0, 0]
        let hit = VoicePrintMatcher.bestMatch(
            embedding: probe,
            in: [(item: "close", embedding: close), (item: "far", embedding: far)],
            threshold: 0.2
        )
        XCTAssertEqual(hit?.item, "close")

        let miss = VoicePrintMatcher.bestMatch(
            embedding: probe,
            in: [(item: "far", embedding: far)],
            threshold: 0.2
        )
        XCTAssertNil(miss)
    }

    func testCatalogSplitsThisMeetingAndPriorSpeakers() {
        let alex = SpeakerLinkPerson(contactID: UUID(), name: "Alex", hasVoicePrint: true, aliases: [], meetingCount: 4, isThisVoice: false)
        let pat = SpeakerLinkPerson(contactID: UUID(), name: "Pat", hasVoicePrint: false, aliases: ["guest-1"], meetingCount: 1, isThisVoice: false)
        let sam = SpeakerLinkPerson(contactID: UUID(), name: "Sam", hasVoicePrint: true, aliases: ["Sam"], meetingCount: 3, isThisVoice: false)
        let unused = SpeakerLinkPerson(contactID: UUID(), name: "Random", hasVoicePrint: false, aliases: [], meetingCount: 0, isThisVoice: false)

        let groups = SpeakerLinkCatalog.groups(
            people: [alex, pat, sam, unused],
            transcriptNames: ["Alex", "Pat", "guest-1"],
            attendeeNames: ["Pat", "Jordan"],
            meName: "Alex",
            currentSpeakerName: "guest-1"
        )

        XCTAssertEqual(groups.thisMeeting.map(\.name), ["Alex", "Pat", "Jordan"])
        XCTAssertTrue(groups.thisMeeting.first { $0.name == "Pat" }?.isThisVoice == true)
        XCTAssertEqual(groups.priorSpeakers.map(\.name), ["Sam"])
        XCTAssertFalse(groups.thisMeeting.contains { $0.name == "Random" })
        XCTAssertFalse(groups.priorSpeakers.contains { $0.name == "Random" })
    }

    @MainActor
    func testSeedingUsesThisMeetingNotTheWholeRolodex() throws {
        let container = try ModelContainer(
            for: Contact.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let me = Contact(name: "Alex")
        let jordan = Contact(name: "Jordan Hale")
        let sam = Contact(name: "Sam")
        me.mergeVoicePrint([Float](repeating: 0.1, count: 8))
        jordan.mergeVoicePrint([Float](repeating: 0.2, count: 8))
        sam.mergeVoicePrint([Float](repeating: 0.3, count: 8))
        container.mainContext.insert(me)
        container.mainContext.insert(jordan)
        container.mainContext.insert(sam)

        let seeded = VoicePrintSeeding.contactsToSeed(
            contacts: [me, jordan, sam],
            meetingAttendeeIDs: [sam.id],
            myContactID: me.id
        )
        XCTAssertEqual(Set(seeded.map(\.name)), Set(["Alex", "Sam"]))
    }

    func testPlaceholderNames() {
        XCTAssertTrue(SpeakerLinkCatalog.isPlaceholder("guest-1"))
        XCTAssertTrue(SpeakerLinkCatalog.isPlaceholder("Me"))
        XCTAssertTrue(SpeakerLinkCatalog.isPlaceholder("Speaker 2"))
        XCTAssertFalse(SpeakerLinkCatalog.isPlaceholder("Pat"))
        XCTAssertTrue(Speaker.other("guest-2").displayNameIsPlaceholder)
        XCTAssertTrue(Speaker.other("unknown-1").displayNameIsPlaceholder)
        XCTAssertFalse(Speaker.other("Pat").displayNameIsPlaceholder)
    }
}
