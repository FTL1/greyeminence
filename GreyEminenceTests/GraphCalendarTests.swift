import XCTest
import CryptoKit
@testable import Grey_Eminence

/// Pure, offline tests for the Microsoft Graph calendar mapping and the PKCE
/// transform. No network or credentials involved.
final class GraphCalendarTests: XCTestCase {

    // MARK: - PKCE

    /// RFC 7636 Appendix B test vector: verifier -> S256 code challenge.
    /// Exercises the exact `Data.base64URLEncodedString()` + SHA256 path the
    /// auth service uses to build `code_challenge`.
    func testClientIDFromDefaultsCountsAsConfigured() {
        let key = GraphConfig.clientIDDefaultsKey
        let previous = UserDefaults.standard.string(forKey: key)
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        UserDefaults.standard.set("11111111-2222-3333-4444-555555555555", forKey: key)
        XCTAssertTrue(GraphConfig.isConfigured)
        XCTAssertEqual(GraphConfig.clientID, "11111111-2222-3333-4444-555555555555")
    }

    func testPKCEChallengeMatchesRFCVector() {
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        let expected = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
        XCTAssertEqual(challenge, expected)
    }

    func testBase64URLHasNoPaddingOrUnsafeChars() {
        let encoded = Data([0xFB, 0xFF, 0xFE]).base64URLEncodedString()
        XCTAssertFalse(encoded.contains("="))
        XCTAssertFalse(encoded.contains("+"))
        XCTAssertFalse(encoded.contains("/"))
    }

    // MARK: - Graph JSON -> CalendarEvent

    func testSingleInstanceMapping() throws {
        let json = """
        {"value":[
          {"id":"AAA","subject":"1:1 with Sam","type":"singleInstance",
           "start":{"dateTime":"2026-06-01T15:00:00.0000000","timeZone":"UTC"},
           "end":{"dateTime":"2026-06-01T15:30:00.0000000","timeZone":"UTC"},
           "attendees":[{"emailAddress":{"name":"Sam Lee","address":"sam@org.com"}},
                        {"emailAddress":{"address":"noname@org.com"}}]}
        ]}
        """
        let events = try GraphCalendarProvider.decodeEvents(from: Data(json.utf8))
        XCTAssertEqual(events.count, 1)
        let e = try XCTUnwrap(events.first)
        XCTAssertEqual(e.id, "AAA")
        XCTAssertEqual(e.linkIdentifier, "AAA")        // no series -> id
        XCTAssertFalse(e.isRecurring)
        XCTAssertEqual(e.title, "1:1 with Sam")
        XCTAssertEqual(e.source, .microsoftGraph)
        XCTAssertEqual(e.attendees.map(\.name), ["Sam Lee", "Noname"])  // name, else derived from address
        XCTAssertEqual(e.attendees.map(\.email), ["sam@org.com", "noname@org.com"])
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let expectedStart = cal.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 15, minute: 0, second: 0))!
        XCTAssertEqual(e.startDate, expectedStart)  // parsed as UTC, fractional seconds dropped
    }

    func testResourceAttendeesAreExcluded() throws {
        let json = """
        {"value":[
          {"id":"AAA","subject":"Planning","type":"singleInstance",
           "start":{"dateTime":"2026-06-01T15:00:00.0000000","timeZone":"UTC"},
           "end":{"dateTime":"2026-06-01T15:30:00.0000000","timeZone":"UTC"},
           "attendees":[{"type":"required","emailAddress":{"name":"Sam Lee","address":"sam@org.com"}},
                        {"type":"resource","emailAddress":{"name":"Room 4B","address":"room4b@org.com"}}]}
        ]}
        """
        let e = try XCTUnwrap(try GraphCalendarProvider.decodeEvents(from: Data(json.utf8)).first)
        XCTAssertEqual(e.attendees.map(\.name), ["Sam Lee"])  // room dropped
    }

    func testOrganizerIsIncludedWhenMissingFromAttendees() throws {
        let json = """
        {"value":[
          {"id":"AAA","subject":"Planning","type":"singleInstance",
           "start":{"dateTime":"2026-06-01T15:00:00.0000000","timeZone":"UTC"},
           "end":{"dateTime":"2026-06-01T15:30:00.0000000","timeZone":"UTC"},
           "organizer":{"emailAddress":{"name":"Bob Dipshit","address":"bob@org.com"}},
           "attendees":[{"emailAddress":{"name":"Sam Lee","address":"sam@org.com"}}]}
        ]}
        """
        let e = try XCTUnwrap(try GraphCalendarProvider.decodeEvents(from: Data(json.utf8)).first)
        XCTAssertEqual(e.attendees.map(\.name), ["Bob Dipshit", "Sam Lee"])
    }

    func testRecurringOccurrenceUsesSeriesMasterAsLinkIdentifier() throws {
        let json = """
        {"value":[
          {"id":"OCC-1","subject":"Standup","type":"occurrence","seriesMasterId":"SERIES-9",
           "start":{"dateTime":"2026-06-01T09:00:00.0000000","timeZone":"UTC"},
           "end":{"dateTime":"2026-06-01T09:15:00.0000000","timeZone":"UTC"}},
          {"id":"OCC-2","subject":"Standup","type":"occurrence","seriesMasterId":"SERIES-9",
           "start":{"dateTime":"2026-06-01T10:00:00.0000000","timeZone":"UTC"},
           "end":{"dateTime":"2026-06-01T10:15:00.0000000","timeZone":"UTC"}}
        ]}
        """
        let events = try GraphCalendarProvider.decodeEvents(from: Data(json.utf8))
        XCTAssertEqual(events.count, 2)
        // Per-occurrence ids stay distinct (no ForEach collision)...
        XCTAssertNotEqual(events[0].id, events[1].id)
        // ...but both share the series link identifier we persist.
        XCTAssertTrue(events.allSatisfy { $0.isRecurring && $0.linkIdentifier == "SERIES-9" })
    }

    // MARK: - Calendar selection (opt-out)

    func testCalendarSelectionIsOptOut() {
        let key = "disabledCalendarIDs"
        let original = UserDefaults.standard.stringArray(forKey: key)
        defer { UserDefaults.standard.set(original, forKey: key) }

        UserDefaults.standard.removeObject(forKey: key)
        // Unset preference → everything matches.
        XCTAssertTrue(CalendarSelection.isEnabled("cal-A"))

        CalendarSelection.setEnabled(false, id: "cal-A")
        XCTAssertFalse(CalendarSelection.isEnabled("cal-A"))
        XCTAssertTrue(CalendarSelection.isEnabled("cal-B"))   // others unaffected

        CalendarSelection.setEnabled(true, id: "cal-A")
        XCTAssertTrue(CalendarSelection.isEnabled("cal-A"))   // re-enabling removes from disabled set
        XCTAssertTrue(CalendarSelection.disabledIDs().isEmpty)
    }

    func testRecurringWithoutSeriesMasterIsTreatedAsOneOff() throws {
        // type says occurrence but no seriesMasterId → no stable series key, so
        // treat as a one-off keyed on its own id (don't claim a bogus series).
        let json = """
        {"value":[
          {"id":"OCC-X","subject":"Orphan occurrence","type":"occurrence",
           "start":{"dateTime":"2026-06-01T11:00:00.0000000","timeZone":"UTC"},
           "end":{"dateTime":"2026-06-01T11:30:00.0000000","timeZone":"UTC"}}
        ]}
        """
        let e = try XCTUnwrap(try GraphCalendarProvider.decodeEvents(from: Data(json.utf8)).first)
        XCTAssertFalse(e.isRecurring)
        XCTAssertEqual(e.linkIdentifier, "OCC-X")
        XCTAssertNil(e.recurrenceID)
    }

    func testAllDayEventsAreExcluded() throws {
        let json = """
        {"value":[
          {"id":"AD","subject":"Vacation","type":"singleInstance","isAllDay":true,
           "start":{"dateTime":"2026-06-01T00:00:00.0000000","timeZone":"UTC"},
           "end":{"dateTime":"2026-06-02T00:00:00.0000000","timeZone":"UTC"}},
          {"id":"M","subject":"Standup","type":"singleInstance","isAllDay":false,
           "start":{"dateTime":"2026-06-01T09:00:00.0000000","timeZone":"UTC"},
           "end":{"dateTime":"2026-06-01T09:15:00.0000000","timeZone":"UTC"}}
        ]}
        """
        let events = try GraphCalendarProvider.decodeEvents(from: Data(json.utf8))
        XCTAssertEqual(events.map(\.title), ["Standup"])  // all-day "Vacation" dropped
    }

    func testEventWithUnparseableDateIsSkipped() throws {
        let json = """
        {"value":[
          {"id":"BAD","subject":"No start","type":"singleInstance"}
        ]}
        """
        let events = try GraphCalendarProvider.decodeEvents(from: Data(json.utf8))
        XCTAssertTrue(events.isEmpty)
    }

    func testGraphEventDecodesCancellationFlag() throws {
        let json = """
        {"id":"abc","subject":"Design Session","isCancelled":true}
        """
        let event = try JSONDecoder().decode(GraphEvent.self, from: Data(json.utf8))
        XCTAssertEqual(event.isCancelled, true)
    }

    func testMissingCancellationFlagIsNotCancelled() throws {
        let json = """
        {"id":"abc","subject":"Design Session"}
        """
        let event = try JSONDecoder().decode(GraphEvent.self, from: Data(json.utf8))
        XCTAssertNil(event.isCancelled)
        XCTAssertFalse(event.isCancelled == true)
    }
}
