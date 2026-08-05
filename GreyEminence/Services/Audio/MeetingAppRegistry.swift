import Foundation

/// What we know about an app that holds the microphone, and how much
/// corroboration we want before treating that as "a meeting started".
///
/// Most conferencing apps take the mic only for the duration of a call, so
/// holding the input device is signal enough. Discord is the exception: it
/// holds the mic the entire time you are connected to a voice channel,
/// including sitting in one alone, so mic-held alone would auto-start a
/// recording of nothing.
struct MeetingAppProfile: Sendable, Equatable {
    let bundleIDs: Set<String>
    let displayName: String

    /// Ask before recording rather than starting on our own.
    ///
    /// For apps that hold the mic outside of an actual call, holding the
    /// input device says nothing about whether a conversation is happening,
    /// and there is no cheap signal that does — so the user is asked once per
    /// hold instead of being guessed at.
    var requiresConfirmation: Bool = false

    /// Overrides `MeetingDetectionService.startDebounce` for this app.
    var startDebounceOverride: TimeInterval? = nil
}

/// Per-app meeting-detection policy. Pure data — no I/O, no state.
enum MeetingAppRegistry {

    /// Apps that behave the way the detector has always assumed: they grab
    /// the mic when a call starts and release it when the call ends. These
    /// entries exist so the meeting can be *labelled*; they intentionally
    /// carry no extra gating, so detection behaviour is unchanged for them.
    static let profiles: [MeetingAppProfile] = [
        MeetingAppProfile(
            bundleIDs: ["com.microsoft.teams2", "com.microsoft.teams"],
            displayName: "Microsoft Teams"
        ),
        MeetingAppProfile(
            bundleIDs: ["us.zoom.xos"],
            displayName: "Zoom"
        ),
        MeetingAppProfile(
            bundleIDs: ["com.tinyspeck.slackmacgap"],
            displayName: "Slack"
        ),
        MeetingAppProfile(
            bundleIDs: ["com.cisco.webexmeetingsapp", "com.webex.meetingmanager"],
            displayName: "Webex"
        ),
        MeetingAppProfile(
            bundleIDs: ["com.apple.FaceTime"],
            displayName: "FaceTime"
        ),
        // Discord keeps the input device for as long as you are connected to
        // a voice channel — idling alone, push-to-talk armed, or actually in
        // a conversation all look identical at the HAL. Measured 2026-08-03:
        // `kAudioProcessPropertyIsRunningOutput` is *also* continuously true
        // while sitting alone in an empty channel, so "is anyone talking"
        // cannot be inferred from the process flags at all. We ask instead.
        MeetingAppProfile(
            bundleIDs: [
                "com.hnc.Discord",
                "com.hnc.DiscordPTB",
                "com.hnc.DiscordCanary",
                "com.hnc.DiscordDevelopment",
            ],
            displayName: "Discord",
            requiresConfirmation: true,
            startDebounceOverride: 20
        ),
    ]

    /// `nil` for apps we have no specific policy for — callers treat that as
    /// "the default policy", i.e. exactly how the detector behaved before
    /// profiles existed.
    ///
    /// Matches on a bundle-ID prefix because Electron apps hold audio through
    /// a helper process: Discord's mic holder reports as
    /// `com.hnc.Discord.helper.Renderer`, not `com.hnc.Discord` (observed
    /// 2026-08-03). Exact matches win, so `com.hnc.DiscordPTB` can never be
    /// mistaken for a helper of `com.hnc.Discord`.
    static func profile(for bundleID: String?) -> MeetingAppProfile? {
        guard let bundleID else { return nil }
        if let exact = profiles.first(where: { $0.bundleIDs.contains(bundleID) }) {
            return exact
        }
        return profiles.first { profile in
            profile.bundleIDs.contains { bundleID.hasPrefix($0 + ".") }
        }
    }

    /// Friendly name for a bundle ID, falling back to whatever the running
    /// application reported so unknown apps still get a readable label.
    static func displayName(for bundleID: String?, fallback: String? = nil) -> String? {
        profile(for: bundleID)?.displayName ?? fallback
    }
}
