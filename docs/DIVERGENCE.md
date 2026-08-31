# What is different from Matt’s Grey Eminence, and why

This is the thorough map. Short version: [ORIGIN.md](ORIGIN.md). Catalog: [FEATURES.md](FEATURES.md).

**Matt** ships **Grey Eminence** from `mpurdon/greyeminence` `main` (latest **v0.30.1**). Sparkle, sandboxed, production library.

**We** ship **Grey Conseil** (formerly older test builds) from `FTL1/grey-conseil` branch `feature/speaker-session-rename` (latest **0.28.4-ftl51**). Unofficial fork. Isolated library. Updates from *this* repo, never from his feed.

Shared ancestor: his **v0.28.4** (13 Aug 2026). Since then he added 5 commits; we added 80+. About **77 files exist only here**, **2 only on his main** (his PDF export sheet), **~92 files both edited**.

We do not merge `main`. We port the pieces we want. We do not push to `mpurdon`.

---

## 1. Packaging — so this is not his product

| | Matt | Grey Conseil | Why |
| --- | --- | --- | --- |
| Dock name | Grey Eminence | **Grey Conseil** | Independent distribution; do not look like production |
| Bundle ID | `com.greyeminence.app` | `com.ftl1.greyeminence` | Separate TCC grants and Sparkle identity |
| Meeting library | Production store | Isolated (`…/com.ftl1.greyeminence`) | Mixing stores loses a week of meetings |
| Auto-update | His Sparkle feed | **This repo’s GitHub Releases** | His feed would install Grey Eminence over us |
| Signing | Developer ID + notarize | Ad-hoc, unsandboxed | Tahoe 26 kills a sandboxed ad-hoc binary |
| Sparkle | On | On, **our** EdDSA key + appcast | Check for Updates installs the next Grey Conseil DMG |
| Ventura | Requested | Not supported | Out of scope |

His `Info.plist` still pointed this fork at **his** `SUFeedURL` / `SUPublicEDKey`. That is now ours. Enabling Sparkle without that change would have overwritten Grey Conseil with production.

---

## 2. Speakers — original reason for the fork (his #3 / #4)

Matt’s app often labels people **Me** / **Speaker**. Grey Conseil treats **you** as the Mac microphone and everyone else as the meeting-app mix.

| Grey Conseil | Why |
| --- | --- |
| People mixer (chips, talk %, lock) | See who is here and who is talking; one strip, not a buried menu |
| Click chip = hide/show (first snippet included) | Mixer, not “click vanished them forever” |
| Guest-1 → Jordan **merges** onto Jordan’s seat | Rename-only left a second hide/show identity |
| Alex you + Alex Morgan = one chip | Calendar name and Me were the same person counted twice |
| Voice prints + re-analyze speakers (unknown-N) | Next meeting can name Pat instead of minting guest-2 |
| Sticky remote ~12s; don’t overwrite a name you chose | Live diarization used to mint guest-2 every sentence |
| This meeting / prior speakers when linking | Not only a generic contact picker |

**Not in this fork on purpose:** live “Pat is talking” from Teams (the system-audio tap is a mix). Voice prints are best-effort.

---

## 3. AI — his #2, plus how we use it

| Grey Conseil | Why |
| --- | --- |
| **xAI (Grok)** as a first-class provider | Console key; same picker for summaries, reanalyze, Tasks, Ask, interviews |
| Analysis timeout Auto / 2–10 min | Long meetings were dying at ~2–4 min |
| Purpose-first reanalyze | First pass summarized the calendar title or a PDF on screen |
| Deep / Deepest per section | Rewrite questions, tasks, summary, or topics alone; Deepest uses measured vocal energy from saved audio (not invented emotion) |
| Bulk reanalyze (selected / all, one at a time) | Don’t click Reanalyze 40 times after switching to Grok |

**Left on his side / not taken:** SuperGrok website login (there is none). His export-PDF checkbox sheet (we already have Intelligence **Export**).

---

## 4. Find, transcript, capture

| Grey Conseil | Why |
| --- | --- |
| **⌘F** this meeting, **⇧⌘F** library Find | Search transcript + Intelligence without Ask |
| Same-speaker auto-merge; play the whole merged line | Streaming ASR crumbs were unreadable |
| Mic convert before AAC (aggregate devices) | `CADefaultDeviceAggregate` made AAC throw −66567; Alex’s file never wrote |
| Capture bar: Watch / Live AI / Stop all | Idle was capturing this Mac; Live AI died at 90 minutes; forgotten windows burned tokens |
| Auto-stop 4 h / 20 min silence | Overnight safety |

---

## 5. Intelligence, reports, Tasks, map

| Grey Conseil | Why |
| --- | --- |
| Sidebar Insights / Questions / Tasks / Summaries / Topic Map | Intelligence was buried in one meeting |
| Click / right-click / drag intelligence items | Edit without regenerating the whole meeting |
| Dossiers + no-hallucination prompt pack | Hand a chatbot *stored facts*, not a prompt that invents diligence |
| Formatted Copy (HTML + plain) | Teams pasted `1.` and `•` as characters (Matt 0.30.0, ported) |
| PDF open-questions callout | Questions looked like one more summary heading (Matt 0.30.1, ported) |
| Tasks filters / export / stalled | Company to-do list, not one meeting at a time |
| Meetings group Date / Series / Related | Exec series was scattered across months |
| Topic map People / Speakers + this-meeting cloud | Map was topics-only |

**Left on his main:** `ReportExportSheet` / `ReportExportOptions` (his “choose PDF sections” UI). We already export sections from Meeting Intelligence.

---

## 6. What we took from him after the fork

| His release | Taken | Left |
| --- | --- | --- |
| 0.29.1 | Core Audio off the main thread; named launch steps | Sparkle “Checking for updates…” copy that named his feed |
| 0.29.2 | Drop `Canceled:` Outlook/Exchange events | — |
| 0.29.3 | Live screenshot strip while recording | PDF export sheet |
| 0.30.0 | Rich clipboard | — |
| 0.30.1 | Open questions lead the report | Dossier/Intelligence Export order unchanged |

His `feature/screen-share` (~296 commits on the 0.21 line) is **not** production. We do not pull it.

---

## 7. Files that exist only in this fork (by area)

**App / packaging:** `AppIdentity.swift`, `GreyConseil.entitlements`, `.github/workflows/grey-conseil-dmg.yml`

**Speakers:** `SpeakerRoster.swift`, `SpeakerRosterBar.swift`, `SpeakerNames.swift`, `SpeakerPalette.swift`, `SpeakerRelabel.swift`, `VoicePrint.swift`, `VoicePrintEnrollment.swift`, `SpeakerReanalyzeSheet.swift`

**AI:** `XAIAPIClient.swift`, `MeetingReanalysis.swift`, `InsightRevision.swift`, `VocalCueAnnotator.swift`

**Find / transcript:** `LibrarySearch.swift`, `LibrarySearchView.swift`, `MeetingFindController.swift`, `TranscriptAutoMerge.swift`, `SegmentAudioPlayer.swift`, `TranscriptExportService.swift`

**Intelligence:** `InsightsHubView.swift`, `AllQuestionsView.swift`, `AllSummariesView.swift`, `InsightItemChrome.swift`, `InsightReanalyzeControl.swift`, `InsightHistorySheet.swift`, `InsightResearchSheet.swift`, dossier set, `IntelligenceExport.swift`, `DOCXWriter.swift`, `ArchiveExtract.swift`, `ArchiveExtractSheet.swift`, `ScreenShareVideoExporter.swift`

**Tasks / map:** `AllTasksView.swift`, `TaskFindControls.swift`, `TaskQueryParser.swift`, `TaskExportService.swift`, `TopicMapRoster.swift`, `TopicDialogMatcher.swift`, `MeetingTopicCloudSheet.swift`

**Capture:** `CaptureKillSwitchBar.swift`, `CaptureSafetyPolicy.swift`, `ScreenCapturePermission.swift`

**Docs:** `FEATURES.md`, `GUIDE.md`, `docs/ORIGIN.md`, this file, `DISCLAIMER.md`

---

## 8. Why we still will not merge `main`

Git’s merge-base is still v0.28.4. A merge re-fights Recording, Calendar, reports, and ContentView and can bring back his Sparkle feed or export sheet. Rebase-onto-0.30.1 is how the isolated store and mixer get lost. Port by theme: [UPSTREAM.md](UPSTREAM.md).
