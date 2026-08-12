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
    static let teams = MeetingAppProfile(
        bundleIDs: ["com.microsoft.teams2", "com.microsoft.teams"],
        displayName: "Microsoft Teams"
    )

    static let zoom = MeetingAppProfile(
        bundleIDs: ["us.zoom.xos"],
        displayName: "Zoom"
    )

    static let profiles: [MeetingAppProfile] = [
        teams,
        zoom,
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
        discord,
    ]

    static let discord = MeetingAppProfile(
        bundleIDs: [
            "com.hnc.Discord",
            "com.hnc.DiscordPTB",
            "com.hnc.DiscordCanary",
            "com.hnc.DiscordDevelopment",
        ],
        displayName: "Discord",
        requiresConfirmation: true,
        startDebounceOverride: 20
    )

    /// `nil` for apps we have no specific policy for — callers treat that as
    /// "the default policy", i.e. exactly how the detector behaved before
    /// profiles existed.
    ///
    /// Matches on a bundle-ID prefix because Electron apps hold audio through
    /// a helper process: Discord's mic holder reports as
    /// `com.hnc.Discord.helper.Renderer`, not `com.hnc.Discord` (observed
    /// 2026-08-03). Exact matches win, so `com.hnc.DiscordPTB` can never be
    /// mistaken for a helper of `com.hnc.Discord`.
    /// Exact IDs and their dotted helper prefixes, built once. The prefix pass
    /// is the common case (the mic holder is usually a helper), so building
    /// `id + "."` per lookup would allocate on every poll.
    private static let exactIndex: [String: MeetingAppProfile] = profiles.reduce(into: [:]) { index, profile in
        for id in profile.bundleIDs { index[id] = profile }
    }
    private static let helperPrefixes: [(prefix: String, profile: MeetingAppProfile)] = profiles.flatMap { profile in
        profile.bundleIDs.map { (prefix: $0 + ".", profile: profile) }
    }

    static func profile(for bundleID: String?) -> MeetingAppProfile? {
        guard let bundleID else { return nil }
        if let exact = exactIndex[bundleID] { return exact }
        return helperPrefixes.first { bundleID.hasPrefix($0.prefix) }?.profile
    }

    /// Friendly name for a bundle ID, falling back to whatever the running
    /// application reported so unknown apps still get a readable label.
    static func displayName(for bundleID: String?, fallback: String? = nil) -> String? {
        profile(for: bundleID)?.displayName ?? fallback
    }
}
