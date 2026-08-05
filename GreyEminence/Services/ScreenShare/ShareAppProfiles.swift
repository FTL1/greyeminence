import CoreGraphics
import Foundation

/// How to recognize the "shared content" window for one conferencing app.
///
/// Each app signals a share differently: Teams pops the content into a window
/// whose title names the presenter, while Discord renders a stream inside the
/// main window until you pop it out or fullscreen it. Keeping the signals as
/// data means adapting to a UI change is an edit here, not a rewrite of the
/// scorer.
struct ShareAppProfile: Sendable, Equatable {
    let id: String
    let bundleIDs: Set<String>
    let displayName: String

    /// Lowercased substrings that mark a window as the shared content itself.
    let shareTitlePatterns: [String]

    /// Lowercased substrings that mark the app's own chrome — the chat/home
    /// window we must never auto-capture.
    let mainWindowPatterns: [String]

    /// Lowercased phrases on the placeholder screen left behind when the
    /// presenter stops sharing.
    let shareEndedPhrases: [String]

    /// This app puts shared content in a *second* window, so a second window
    /// that isn't the main one is very likely the share.
    var secondaryWindowIsShare: Bool = false

    /// This app is commonly fullscreened to view a share, so a window filling
    /// a whole display is likely the share.
    var fullscreenIsShare: Bool = false

    /// Shown in the picker and settings to explain how to get a clean capture.
    let popOutHint: String
}

/// Registry of per-app screen-share recognition profiles.
enum ShareAppProfiles {

    /// Teams — unchanged from the original Teams-only implementation. The
    /// pop-out content window carries the presenter's name ("Alice is
    /// presenting"), and the main window is branded "| Microsoft Teams".
    static let teams = ShareAppProfile(
        id: "teams",
        bundleIDs: [
            "com.microsoft.teams2",   // "new" Teams
            "com.microsoft.teams",    // classic
        ],
        displayName: "Microsoft Teams",
        shareTitlePatterns: [
            "is presenting",
            "is sharing",
            "screen shar",       // "screen share" / "screen sharing"
            "shared content",
            "content shared",
        ],
        mainWindowPatterns: [
            "| microsoft teams",
            "microsoft teams",
        ],
        shareEndedPhrases: [
            "content sharing has ended",
            "sharing is paused",
        ],
        popOutHint: "Pop out the shared content in Teams for the cleanest capture.",
    )

    /// Discord — a Go Live stream renders *inside* the main window alongside
    /// the channel sidebar, member list, and chat, all of which churn
    /// constantly and would dominate change detection. So we only auto-capture
    /// the popped-out or fullscreened stream, which is chrome-free.
    ///
    /// The title patterns are a starting guess: Discord's pop-out title is
    /// not documented and varies by what is being streamed. Every candidate's
    /// title is logged under the `screen` category, so the first real stream
    /// tells us what to put here. Until then the secondary-window and
    /// fullscreen rules carry the auto-detection.
    static let discord = ShareAppProfile(
        id: "discord",
        bundleIDs: [
            "com.hnc.Discord",
            "com.hnc.DiscordPTB",
            "com.hnc.DiscordCanary",
            "com.hnc.DiscordDevelopment",
        ],
        displayName: "Discord",
        shareTitlePatterns: [
            "stream",
            "screen share",
            "screenshare",
            "is live",
            "go live",
        ],
        mainWindowPatterns: [
            "discord",
        ],
        shareEndedPhrases: [
            "the stream has ended",
            "stream ended",
            "no one is streaming",
            "screen share ended",
            "nobody is streaming",
        ],
        secondaryWindowIsShare: true,
        fullscreenIsShare: true,
        popOutHint: "Pop out the stream in Discord, or fullscreen it, for the cleanest capture.",
    )

    static let all: [ShareAppProfile] = [teams, discord]

    static func profile(for bundleID: String) -> ShareAppProfile? {
        all.first { $0.bundleIDs.contains(bundleID) }
    }

    /// Generic guidance for the settings pane, which is app-agnostic because
    /// it is read before any call is in progress.
    static var genericPopOutHint: String {
        "Pop out the shared content (Teams) or the stream (Discord) for the cleanest capture."
    }
}
