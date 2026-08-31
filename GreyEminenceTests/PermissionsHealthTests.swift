import AVFoundation
import Contacts
import EventKit
import XCTest
@testable import Grey_Eminence

final class PermissionsHealthTests: XCTestCase {
    func testMicrophoneVerdicts() {
        XCTAssertEqual(PermissionsHealth.verdict(fromMicrophone: .authorized), .ok)
        XCTAssertEqual(PermissionsHealth.verdict(fromMicrophone: .denied), .denied)
        XCTAssertEqual(PermissionsHealth.verdict(fromMicrophone: .notDetermined), .notDetermined)
    }

    func testCalendarWriteOnlyIsDenied() {
        XCTAssertEqual(PermissionsHealth.verdict(fromCalendar: .writeOnly), .denied)
        XCTAssertEqual(PermissionsHealth.verdict(fromCalendar: .fullAccess), .ok)
        XCTAssertEqual(PermissionsHealth.verdict(fromCalendar: .notDetermined), .notDetermined)
    }

    func testContactsVerdicts() {
        XCTAssertEqual(PermissionsHealth.verdict(fromContacts: .authorized), .ok)
        XCTAssertEqual(PermissionsHealth.verdict(fromContacts: .denied), .denied)
        XCTAssertEqual(PermissionsHealth.verdict(fromContacts: .notDetermined), .notDetermined)
    }

    func testKeyItemRedactsSecret() {
        let secret = "xai-super-secret-key"
        let item = PermissionsHealth.keyItem(id: "xai", title: "xAI (Grok)", key: secret)
        XCTAssertEqual(item.verdict, .ok)
        XCTAssertTrue(item.canValidate)
        XCTAssertTrue(item.detail.hasSuffix("key)"))
        XCTAssertFalse(item.detail.contains(secret))
        XCTAssertFalse(item.detail.contains("super-secret"))
    }

    func testMissingKey() {
        let item = PermissionsHealth.keyItem(id: "anthropic", title: "Anthropic API", key: "  ")
        XCTAssertEqual(item.verdict, .missing)
        XCTAssertFalse(item.canValidate)
    }

    func testActiveAIItemsOnlyListsTheSelectedProvider() {
        let items = PermissionsHealth.activeAIItems(
            current: .xai,
            anthropicKey: nil,
            xaiKey: "xai-test-key"
        )
        XCTAssertEqual(items.map(\.id), ["xai"])
        XCTAssertEqual(items.first?.verdict, .ok)
        XCTAssertFalse(items.contains { $0.id == "anthropic" && $0.verdict.isProblem })
    }

    func testPrivacyURLsNeverUseBrokenSystemsettingsScheme() {
        for pane in ["Privacy_Microphone", "Privacy_ScreenCapture", "Privacy_AudioCapture", "Privacy_Calendars", "Privacy_Notifications"] {
            let urls = AudioSessionManager.privacyURLCandidates(for: pane)
            XCTAssertFalse(urls.isEmpty, pane)
            XCTAssertTrue(urls.allSatisfy { $0.hasPrefix("x-apple.systempreferences:") }, pane)
            XCTAssertFalse(urls.contains { $0.contains("x-apple.systemsettings:") }, pane)
        }
        let audio = AudioSessionManager.privacyURLCandidates(for: "Privacy_AudioCapture")
        XCTAssertTrue(audio.contains { $0.contains("Privacy_ScreenCapture") })
        XCTAssertFalse(audio.contains { $0.contains("Privacy_AudioCapture") })
    }
}
