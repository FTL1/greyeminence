import XCTest
@testable import Grey_Eminence

/// A person named in a question must become a filter, not a search term.
/// These tests pin both halves of that: the name resolves and is removed, and
/// — just as important — an ordinary sentence that happens to contain a word
/// which is also somebody's name does NOT silently narrow the search.
final class AskPersonFilterTests: XCTestCase {

    private let roster: [AskPersonFilter.Candidate] = [
        .init(canonicalName: "Stephen Smith"),
        .init(canonicalName: "Leah Stephens"),
        .init(canonicalName: "Erin O'Brien", aliases: ["Erin"]),
        .init(canonicalName: "Mark Chen"),
        .init(canonicalName: "Teancum Besendorfer", aliases: ["Teejay"]),
    ]

    // MARK: - The case that prompted this

    func testFullNameResolvesAndLeavesTheQuery() throws {
        let detection = try XCTUnwrap(
            AskPersonFilter.detect(in: "what did stephen smith say about the ingestion pipeline", roster: roster)
        )
        XCTAssertEqual(detection.names, ["Stephen Smith"])
        XCTAssertFalse(detection.strippedQuery.lowercased().contains("stephen"))
        XCTAssertTrue(detection.strippedQuery.contains("ingestion pipeline"))
    }

    func testFullNameMatchWinsOverASharedFirstName() throws {
        // "Stephen" alone also prefixes "Stephen Smith"; the two-token match
        // has to win or the wrong person's meetings get searched.
        let detection = try XCTUnwrap(
            AskPersonFilter.detect(in: "Stephen Smith's take on the rollout", roster: roster)
        )
        XCTAssertEqual(detection.names, ["Stephen Smith"])
    }

    func testSurnameIsNotMatchedByAShorterName() {
        // "Stephens" must not resolve to "Stephen Smith".
        let detection = AskPersonFilter.detect(in: "what did leah stephens say about hiring", roster: roster)
        XCTAssertEqual(detection?.names, ["Leah Stephens"])
    }

    // MARK: - Single names

    func testFirstNameResolvesWithAnAttributionCue() throws {
        let detection = try XCTUnwrap(
            AskPersonFilter.detect(in: "what did erin say about the migration", roster: roster)
        )
        XCTAssertEqual(detection.names, ["Erin O'Brien"])
        XCTAssertFalse(detection.strippedQuery.lowercased().contains("erin"))
        XCTAssertTrue(detection.strippedQuery.contains("migration"))
    }

    func testFirstNameWithNoAttributionCueIsNotAPersonReference() {
        // No cue: this is a topic search that happens to contain a name.
        XCTAssertNil(AskPersonFilter.detect(in: "erin migration rollout timeline", roster: roster))
    }

    func testNicknameResolvesToTheCanonicalName() throws {
        let detection = try XCTUnwrap(
            AskPersonFilter.detect(in: "what did teejay say about the runway", roster: roster)
        )
        XCTAssertEqual(detection.names, ["Teancum Besendorfer"])
    }

    func testPossessiveResolvesAndIsStripped() throws {
        let detection = try XCTUnwrap(
            AskPersonFilter.detect(in: "erin's concerns about latency", roster: roster)
        )
        XCTAssertEqual(detection.names, ["Erin O'Brien"])
        XCTAssertFalse(detection.strippedQuery.lowercased().contains("erin"))
        XCTAssertTrue(detection.strippedQuery.contains("latency"))
    }

    func testApostropheInsideASurnameSurvives() throws {
        let detection = try XCTUnwrap(
            AskPersonFilter.detect(in: "what did Erin O'Brien say about latency", roster: roster)
        )
        XCTAssertEqual(detection.names, ["Erin O'Brien"])
    }

    // MARK: - Words that are also names

    func testOrdinaryWordThatIsAlsoANameDoesNotFilterWhenLowercase() {
        // The whole point of the guard: this is a request, not a question
        // about Mark Chen, and filtering to his meetings would wreck it.
        XCTAssertNil(AskPersonFilter.detect(in: "can you mark the schema work as done", roster: roster))
    }

    func testOrdinaryWordThatIsAlsoANameFiltersWhenCapitalized() throws {
        let detection = try XCTUnwrap(
            AskPersonFilter.detect(in: "what did Mark say about the schema", roster: roster)
        )
        XCTAssertEqual(detection.names, ["Mark Chen"])
    }

    func testFullNameStillResolvesEvenWhenLowercaseAndAmbiguous() throws {
        // Two tokens are unambiguous regardless of capitalization.
        let detection = try XCTUnwrap(
            AskPersonFilter.detect(in: "mark chen on the schema", roster: roster)
        )
        XCTAssertEqual(detection.names, ["Mark Chen"])
    }

    // MARK: - Multiple people

    func testTwoPeopleResolveInQueryOrder() throws {
        let detection = try XCTUnwrap(
            AskPersonFilter.detect(in: "what did leah stephens and stephen smith say about staffing", roster: roster)
        )
        XCTAssertEqual(detection.names, ["Leah Stephens", "Stephen Smith"])
        XCTAssertTrue(detection.strippedQuery.contains("staffing"))
        XCTAssertFalse(detection.strippedQuery.lowercased().contains("leah"))
        XCTAssertFalse(detection.strippedQuery.lowercased().contains("smith"))
    }

    // MARK: - Nothing to match

    func testNoNameMeansNoDetection() {
        XCTAssertNil(AskPersonFilter.detect(in: "what did we decide about the ingestion pipeline", roster: roster))
    }

    func testEmptyRosterMeansNoDetection() {
        XCTAssertNil(AskPersonFilter.detect(in: "what did stephen smith say", roster: []))
    }

    func testEmptyQueryMeansNoDetection() {
        XCTAssertNil(AskPersonFilter.detect(in: "   ", roster: roster))
    }

    func testAllNameQueryStripsToNothing() throws {
        // The caller has to notice this and keep the original wording — assert
        // the detector reports it honestly rather than inventing content.
        let detection = try XCTUnwrap(
            AskPersonFilter.detect(in: "Stephen Smith", roster: roster)
        )
        XCTAssertEqual(detection.names, ["Stephen Smith"])
        XCTAssertTrue(detection.strippedQuery.isEmpty)
    }

    func testCueWordThatIsAlsoANameDoesNotVouchForItself() {
        // A contact literally named "Will" can't be resolved by the presence
        // of the word "will" — that would be circular.
        let willRoster = [AskPersonFilter.Candidate(canonicalName: "Will")]
        XCTAssertNil(AskPersonFilter.detect(in: "what will the schema look like", roster: willRoster))
    }
}

extension AskPersonFilterTests {
    /// First and last names resolve on their own — that is how questions get
    /// asked — but only ever with an attribution cue behind them.
    func testBareFirstNameOfAMultiWordContactResolves() throws {
        let detection = try XCTUnwrap(
            AskPersonFilter.detect(in: "what did stephen say about the pipeline", roster: roster)
        )
        XCTAssertEqual(detection.names, ["Stephen Smith"])
    }

    func testBareSurnameResolves() throws {
        let detection = try XCTUnwrap(
            AskPersonFilter.detect(in: "what did besendorfer say about the runway", roster: roster)
        )
        XCTAssertEqual(detection.names, ["Teancum Besendorfer"])
    }

    func testBareFirstNameStillNeedsACue() {
        XCTAssertNil(AskPersonFilter.detect(in: "stephen pipeline throughput", roster: roster))
    }

    func testSharedFirstNameResolvesToEveryoneWhoHasIt() throws {
        // Two Stephens and no way to tell them apart: search both, and let the
        // UI name both, rather than silently picking one.
        let twoStephens: [AskPersonFilter.Candidate] = [
            .init(canonicalName: "Stephen Smith"),
            .init(canonicalName: "Stephen Okafor"),
        ]
        let detection = try XCTUnwrap(
            AskPersonFilter.detect(in: "what did stephen say about hiring", roster: twoStephens)
        )
        XCTAssertEqual(Set(detection.names), ["Stephen Smith", "Stephen Okafor"])
    }

    /// Regression guard on the stoplist: names of people you actually meet
    /// with must resolve from a lowercase question. "Gene" was on the list
    /// and collided with the fourth-most-frequent attendee in a real roster.
    func testPlausibleNameWordsAreNotSuppressed() throws {
        let names = ["Gene Huh", "Ray Alvarez", "Max Fischer", "Frank Oyelaran", "Penny Zhao"]
        for name in names {
            let first = name.split(separator: " ")[0].lowercased()
            let detection = AskPersonFilter.detect(
                in: "what did \(first) say about the intake process",
                roster: names.map { .init(canonicalName: $0) }
            )
            XCTAssertEqual(detection?.names, [name], "\(first) should resolve without capitalization")
        }
    }
}
