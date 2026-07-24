import SwiftUI

/// One curated, user-facing feature worth surfacing after an update. Drives
/// BOTH the What's New sheet (filtered by `version`) and the in-context "NEW"
/// badge (keyed by `id`). Keep this list SHORT and benefit-oriented — it's the
/// trailer, not the changelog. The exhaustive history lives in ChangelogView.
struct FeatureHighlight: Identifiable, Sendable {
    /// Stable key — also the badge-tracking id. Never reuse or rename once
    /// shipped, or a badge/seen-state will resurface or leak across features.
    let id: String
    /// MARKETING_VERSION this shipped in. The sheet shows highlights newer than
    /// the user's last-seen version.
    let version: String
    let title: String
    let summary: String
    let systemImage: String
    let tint: Color
    /// Where "Try it" takes the user. `nil` hides the button.
    let destination: SidebarDestination?
}

enum FeatureHighlightCatalog {
    /// Newest first. Add an entry when a release ships something worth a nudge;
    /// set its `version` to that release's MARKETING_VERSION.
    static let all: [FeatureHighlight] = [
        FeatureHighlight(
            id: "meeting-prep-panel",
            version: "0.23.13",
            title: "Meeting Prep, beside the transcript",
            summary: "While recording a recurring meeting, flip the side panel to Prep to see carried-over tasks, open questions, and prior topics — your talking points, right where you need them.",
            systemImage: "doc.text.magnifyingglass",
            tint: .indigo,
            destination: .recording
        ),
        FeatureHighlight(
            id: "screen-capture",
            version: "0.23.13",
            title: "Screen-share capture",
            summary: "Grey Eminence now watches for shared screens during a meeting and folds what it sees into the notes and summary — works with Teams, Zoom, Meet, anything.",
            systemImage: "rectangle.inset.filled.and.person.filled",
            tint: .cyan,
            destination: .settings
        ),
    ]

    /// The running app's marketing version (e.g. "0.23.13").
    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    /// Highlights newer than `lastSeenVersion`, newest first, capped so a user
    /// who skipped many releases gets the headline set (the rest stay in the
    /// changelog) rather than an endless scroll.
    static func pending(since lastSeenVersion: String, limit: Int = 4) -> [FeatureHighlight] {
        let newer = all.filter { SemVer.compare($0.version, lastSeenVersion) == .orderedDescending }
        return Array(newer.prefix(limit))
    }
}

/// Numeric, dot-separated version comparison ("0.23.13" vs "0.9.2"). Leading
/// non-digits (a "v" prefix) and trailing build/pre-release tags are ignored;
/// missing components read as 0, so "0.24" == "0.24.0".
enum SemVer {
    static func compare(_ a: String, _ b: String) -> ComparisonResult {
        let ac = parts(a), bc = parts(b)
        for i in 0..<Swift.max(ac.count, bc.count) {
            let x = i < ac.count ? ac[i] : 0
            let y = i < bc.count ? bc[i] : 0
            if x != y { return x < y ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    private static func parts(_ v: String) -> [Int] {
        v.split(whereSeparator: { !$0.isNumber }).map { Int($0) ?? 0 }
    }
}
