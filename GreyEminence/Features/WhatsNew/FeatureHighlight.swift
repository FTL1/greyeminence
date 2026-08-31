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
            id: "help-hover-and-feedback",
            version: "0.28.4-ftl51",
            title: "Hover help, and Send feedback",
            summary: "Rest on a control for what / how / why. Help → Controls and options is the full page. Help → Send feedback… files a GitHub issue as text only; screenshot is off unless you opt in.",
            systemImage: "questionmark.circle",
            tint: .cyan,
            destination: nil
        ),
        FeatureHighlight(
            id: "github-repo-grey-conseil",
            version: "0.28.4-ftl50",
            title: "Updates from FTL1/grey-conseil",
            summary: "Check for Updates talks to the Grey Conseil GitHub repo. The Mac identity (bundle ID and library) is unchanged, so your meetings stay put.",
            systemImage: "arrow.down.app",
            tint: .orange,
            destination: .settings
        ),
        FeatureHighlight(
            id: "blank-screenshare-stills",
            version: "0.28.4-ftl42",
            title: "Screen stills that aren't a white box",
            summary: "Teams shares were often captured as a blank white frame and then described as empty. Capture retries a real snapshot and throws the white frames away.",
            systemImage: "rectangle.dashed.badge.record",
            tint: .mint,
            destination: .meetings
        ),
        FeatureHighlight(
            id: "speaker-n-and-self-intro",
            version: "0.28.4-ftl41",
            title: "speaker-1, and I'm Bob",
            summary: "Unnamed voices are speaker-1, speaker-2 — not Guest and Unknown mixed. Calendar invitees (and the organizer) land on the People bar. If someone says “I'm Bob” in the intro, that voice is Bob.",
            systemImage: "person.wave.2",
            tint: .orange,
            destination: .meetings
        ),
        FeatureHighlight(
            id: "archive-full-library-filing",
            version: "0.28.4-ftl40",
            title: "Archive is the whole library",
            summary: "Every meeting is in Archive so you can extract it. File any meeting or selection away from the recent list — you do not wait three months.",
            systemImage: "archivebox",
            tint: .brown,
            destination: .archive
        ),
        FeatureHighlight(
            id: "grok-library-secretary",
            version: "0.28.4-ftl44",
            title: "Grok can read the archive",
            summary: "Grey Conseil writes stored transcripts and intel for the local Secretary plugin. Search the full library; nothing is invented.",
            systemImage: "sparkles",
            tint: .orange,
            destination: .archive
        ),
        FeatureHighlight(
            id: "archive-export-pdf",
            version: "0.28.4-ftl43",
            title: "Export from Archive",
            summary: "Zip is still there. You can also export one PDF (each meeting starts on a new page) or one PDF per meeting. Audio and stills stay in the zip.",
            systemImage: "square.and.arrow.up",
            tint: .brown,
            destination: .archive
        ),
        FeatureHighlight(
            id: "archive-extract-transcripts-intel",
            version: "0.28.4-ftl39",
            title: "Extract from Archive",
            summary: "Pull transcripts and intel for a meeting, a recurring series (Weekly Standup), a speaker, or a bulk selection. Optional audio, screen stills, and a time-lapse of those stills.",
            systemImage: "square.and.arrow.up",
            tint: .brown,
            destination: .archive
        ),
        FeatureHighlight(
            id: "grey-conseil-github-updates",
            version: "0.28.4-ftl38",
            title: "Grey Conseil",
            summary: "Named for éminence grise (Grey Eminence) and Verne’s Conseil — counsel, the servant on the Nautilus. Help → Why Grey Conseil. Not Matt’s product. No warranty; lawful use only.",
            systemImage: "arrow.down.app",
            tint: .orange,
            destination: .settings
        ),
        FeatureHighlight(
            id: "section-reanalyze-deep",
            version: "0.28.4-ftl26",
            title: "Deep reanalyze per section",
            summary: "Summary, questions, tasks, and topics each have Reanalyze. Click Deep, or Deepest to weigh vocal energy from the audio. Revert and View log keep prior results.",
            systemImage: "arrow.clockwise.circle",
            tint: .purple,
            destination: .insights
        ),
        FeatureHighlight(
            id: "meeting-dossier-export",
            version: "0.28.4-ftl25",
            title: "Meeting dossier for a chatbot or a person",
            summary: "Export a zip: report, optional transcript/audio/stills, and a no-hallucination prompt pack. One-pagers per speaker, or a series of related meetings.",
            systemImage: "doc.zipper",
            tint: .purple,
            destination: .insights
        ),
        FeatureHighlight(
            id: "purpose-first-reanalysis",
            version: "0.28.4-ftl24",
            title: "Reanalyze infers what you were trying to do",
            summary: "Reanalyze rewrites summary, questions, and tasks from the full transcript. It follows your purpose (fix documents, align language) instead of the calendar title or a PDF on screen.",
            systemImage: "brain",
            tint: .purple,
            destination: .insights
        ),
        FeatureHighlight(
            id: "merged-line-audio",
            version: "0.28.4-ftl23",
            title: "Play the whole merged line",
            summary: "The triangle on a joined transcript line plays every original audio range for that text, not just the first crumb.",
            systemImage: "play.circle",
            tint: .mint,
            destination: .meetings
        ),
        FeatureHighlight(
            id: "automerge-existing",
            version: "0.28.4-ftl22",
            title: "Same-speaker crumbs merge on old meetings",
            summary: "Opening a finished meeting now joins consecutive lines from the same person. Streaming fragments a few seconds apart count as one turn.",
            systemImage: "arrow.triangle.merge",
            tint: .orange,
            destination: .meetings
        ),
        FeatureHighlight(
            id: "meeting-find-automerge",
            version: "0.28.4-ftl21",
            title: "Find this meeting, merge crumbs",
            summary: "⌘F searches the open meeting. Same-speaker fragments merge automatically (Settings). Rare transcript tools live in ⋯ so the bar no longer clips.",
            systemImage: "magnifyingglass",
            tint: .mint,
            destination: .meetings
        ),
        FeatureHighlight(
            id: "library-find",
            version: "0.28.4-ftl20",
            title: "Find in transcripts and Intelligence",
            summary: "Find in the main pane (⇧⌘F) filters by meeting name, date, speaker, and text — plain or regex — in this meeting, a selection, or the whole library.",
            systemImage: "magnifyingglass",
            tint: .mint,
            destination: .find
        ),
        FeatureHighlight(
            id: "people-chip-mixer",
            version: "0.28.4-ftl19",
            title: "People chips hide, play, and keep colors",
            summary: "Click a name to hide their lines. Same person, same color. Play a line’s audio. Merge selected lines. Apply renames only what you selected.",
            systemImage: "person.crop.circle.badge.checkmark",
            tint: .orange,
            destination: .meetings
        ),
        FeatureHighlight(
            id: "speaker-remap-undo",
            version: "0.28.4-ftl18",
            title: "Speaker assign no longer overwrites you",
            summary: "Hiding or isolating a speaker keeps their lines out of Assign. Undo the last remap, revert original names, or re-analyze remotes from the saved audio.",
            systemImage: "arrow.uturn.backward",
            tint: .blue,
            destination: .meetings
        ),
        FeatureHighlight(
            id: "intelligence-export-menu",
            version: "0.28.4-ftl16",
            title: "Export Meeting Intelligence as you like",
            summary: "The Export menu picks sections, optional raw transcript (de-dupe on by default), and PDF, Word, Excel, CSV, JSON, RTF, or Markdown.",
            systemImage: "square.and.arrow.up",
            tint: .purple,
            destination: .meetings
        ),
        FeatureHighlight(
            id: "export-full-transcript",
            version: "0.28.4-ftl15",
            title: "Export the full transcript",
            summary: "Save every line as text, Markdown, RTF, CSV, Excel, or PDF. Intelligence files use Title_yyyyMMdd-47m-intel.pdf; the full transcript uses …-tr.",
            systemImage: "square.and.arrow.up",
            tint: .orange,
            destination: .meetings
        ),
        FeatureHighlight(
            id: "people-header",
            version: "0.28.4-ftl14",
            title: "People bar: who is here, who is talking",
            summary: "One strip across Record — chips for the room, talk-share for Alex 47% / Pat 22%. Click a chip to hear only them. Pre-tag invitees, assign guest-1, lock IDs.",
            systemImage: "person.3.sequence",
            tint: .green,
            destination: .recording
        ),
        FeatureHighlight(
            id: "voice-print-enroll",
            version: "0.28.4-ftl14",
            title: "Enroll a voice print",
            summary: "Right-click a speaker and enroll them onto a People contact. The next meeting compares new guests against that print and tags a match as Pat instead of guest-2.",
            systemImage: "waveform",
            tint: .teal,
            destination: .people
        ),
        FeatureHighlight(
            id: "speaker-link-list",
            version: "0.28.4-ftl14",
            title: "This meeting and prior speakers",
            summary: "The speaker menu lists people already on this call and people who have spoken before — not just a generic contact picker. A waveform means they already have a print.",
            systemImage: "person.crop.rectangle.stack",
            tint: .mint,
            destination: .recording
        ),
        FeatureHighlight(
            id: "discord-calls",
            version: "0.24.0",
            title: "Record Discord calls",
            summary: "Grey Eminence now recognizes Discord. Because Discord holds the mic the whole time you're in a voice channel, it asks before recording rather than starting on its own — answer from the menu bar without leaving the call. Popped-out or fullscreened streams get captured like any other shared screen.",
            systemImage: "phone.badge.waveform.fill",
            tint: .blue,
            destination: .settings
        ),
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

    /// Cap on how many highlights any one presentation shows — a user who
    /// skipped many releases gets the headline set, not an endless scroll (the
    /// rest stay in the changelog).
    private static let defaultLimit = 4

    /// Highlights newer than `lastSeenVersion`, newest first, capped.
    static func pending(since lastSeenVersion: String, limit: Int = defaultLimit) -> [FeatureHighlight] {
        let newer = all.filter { SemVer.compare($0.version, lastSeenVersion) == .orderedDescending }
        return Array(newer.prefix(limit))
    }

    /// The newest highlights regardless of what the user has already seen — for
    /// Help → What's New, where `pending` would be empty (the post-update sheet
    /// records the current version on dismissal, so nothing is ever pending once
    /// it has been shown). Every shipped highlight postdates "0.0.0", so this is
    /// `pending` with the floor removed — one selection policy, not two.
    static func headline(limit: Int = defaultLimit) -> [FeatureHighlight] {
        pending(since: "0.0.0", limit: limit)
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
