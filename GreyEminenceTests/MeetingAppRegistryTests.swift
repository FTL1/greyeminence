import XCTest
@testable import Grey_Eminence

/// Discord holds the microphone for as long as you are connected to a voice
/// channel — idling alone included — so mic-held alone must not start a
/// recording for it. Every other app keeps the pre-existing behaviour.
@MainActor
final class MeetingAppRegistryTests: XCTestCase {

    private func holder(
        _ bundleID: String?,
        outputRunning: Bool = false,
        pid: pid_t = 501
    ) -> MeetingDetectionService.MicHolder {
        MeetingDetectionService.MicHolder(
            pid: pid,
            bundleID: bundleID,
            appName: bundleID.flatMap { MeetingAppRegistry.displayName(for: $0) },
            outputRunning: outputRunning
        )
    }

    // MARK: - Registry

    func testDiscordProfileAsksBeforeRecording() throws {
        let profile = try XCTUnwrap(MeetingAppRegistry.profile(for: "com.hnc.Discord"))
        XCTAssertEqual(profile.displayName, "Discord")
        XCTAssertTrue(profile.requiresConfirmation)
        XCTAssertEqual(profile.startDebounceOverride, 20)
    }

    /// Discord holds the mic through an Electron helper process, so the
    /// bundle ID we see is `com.hnc.Discord.helper.Renderer` (observed
    /// 2026-08-03). Missing this made the profile inert.
    func testDiscordHelperProcessResolvesToDiscord() throws {
        let profile = try XCTUnwrap(
            MeetingAppRegistry.profile(for: "com.hnc.Discord.helper.Renderer")
        )
        XCTAssertEqual(profile.displayName, "Discord")
        XCTAssertTrue(profile.requiresConfirmation)
    }

    func testTeamsHelperProcessResolvesToTeams() throws {
        let profile = try XCTUnwrap(
            MeetingAppRegistry.profile(for: "com.microsoft.teams2.helper")
        )
        XCTAssertEqual(profile.displayName, "Microsoft Teams")
    }

    /// Prefix matching must not blur the Discord channels together, nor
    /// swallow an unrelated app that merely starts with the same characters.
    func testPrefixMatchingRequiresADotBoundary() {
        XCTAssertEqual(
            MeetingAppRegistry.profile(for: "com.hnc.DiscordPTB")?.displayName,
            "Discord"
        )
        XCTAssertNil(MeetingAppRegistry.profile(for: "com.hnc.DiscordLike"))
        XCTAssertNil(MeetingAppRegistry.profile(for: "us.zoom.xoscar"))
    }

    func testDiscordVariantsAllRecognized() {
        for bundleID in [
            "com.hnc.Discord", "com.hnc.DiscordPTB",
            "com.hnc.DiscordCanary", "com.hnc.DiscordDevelopment",
        ] {
            XCTAssertEqual(
                MeetingAppRegistry.profile(for: bundleID)?.displayName,
                "Discord",
                "expected \(bundleID) to resolve to Discord"
            )
        }
    }

    func testConferencingAppsCarryNoExtraGating() throws {
        for bundleID in ["com.microsoft.teams2", "us.zoom.xos", "com.tinyspeck.slackmacgap"] {
            let profile = try XCTUnwrap(MeetingAppRegistry.profile(for: bundleID))
            XCTAssertFalse(profile.requiresConfirmation, "\(bundleID) should not prompt")
            XCTAssertNil(profile.startDebounceOverride, "\(bundleID) should use the default debounce")
        }
    }

    func testUnknownBundleHasNoProfile() {
        XCTAssertNil(MeetingAppRegistry.profile(for: "com.example.unknown"))
        XCTAssertNil(MeetingAppRegistry.profile(for: nil))
    }

    func testDisplayNameFallsBackToReportedName() {
        XCTAssertEqual(
            MeetingAppRegistry.displayName(for: "com.example.unknown", fallback: "Some App"),
            "Some App"
        )
        XCTAssertEqual(MeetingAppRegistry.displayName(for: "us.zoom.xos"), "Zoom")
    }

    // MARK: - Start gate

    /// The whole point: Discord holding the mic must never start a recording
    /// by itself, however the output flag reads — it is true even when you
    /// are sitting in an empty channel.
    func testDiscordAsksRatherThanStarting() {
        for outputRunning in [true, false] {
            let decision = MeetingDetectionService.startDecision(
                for: [holder("com.hnc.Discord.helper.Renderer", outputRunning: outputRunning)]
            )
            guard case .confirm(let holder, let debounce) = decision else {
                return XCTFail("expected .confirm for Discord (outputRunning: \(outputRunning)), got \(decision)")
            }
            XCTAssertEqual(holder.bundleID, "com.hnc.Discord.helper.Renderer")
            XCTAssertEqual(debounce, 20)
        }
    }

    func testTeamsStartsOnMicAloneWithDefaultDebounce() {
        let decision = MeetingDetectionService.startDecision(
            for: [holder("com.microsoft.teams2")]
        )
        guard case .start(let holder, let debounce) = decision else {
            return XCTFail("expected .start for Teams, got \(decision)")
        }
        XCTAssertEqual(holder.bundleID, "com.microsoft.teams2")
        XCTAssertNil(debounce, "nil means the service's default debounce")
    }

    func testUnknownAppStartsOnMicAlone() {
        let decision = MeetingDetectionService.startDecision(
            for: [holder("com.example.somecall")]
        )
        guard case .start(let holder, _) = decision else {
            return XCTFail("expected .start for an unknown app, got \(decision)")
        }
        XCTAssertEqual(holder.bundleID, "com.example.somecall")
    }

    /// Discord parked in a channel must not mask a real Teams call happening
    /// at the same time — that one still auto-records.
    func testAutoStartWinsOverPromptWhenBothPresent() {
        let decision = MeetingDetectionService.startDecision(for: [
            holder("com.hnc.Discord.helper.Renderer", outputRunning: true, pid: 100),
            holder("com.microsoft.teams2", pid: 200),
        ])
        guard case .start(let holder, _) = decision else {
            return XCTFail("expected Teams to win, got \(decision)")
        }
        XCTAssertEqual(holder.bundleID, "com.microsoft.teams2")
    }

    func testNoHoldersMeansNoDecision() {
        XCTAssertEqual(MeetingDetectionService.startDecision(for: []), .none)
    }

    /// A process we can't identify still counts — this is the long-standing
    /// behaviour for HAL-direct clients we can't name.
    func testUnidentifiedProcessStillStarts() {
        let decision = MeetingDetectionService.startDecision(
            for: [holder(nil)]
        )
        guard case .start(let holder, _) = decision else {
            return XCTFail("expected .start for an unidentified process, got \(decision)")
        }
        XCTAssertNil(holder.bundleID)
    }
}
