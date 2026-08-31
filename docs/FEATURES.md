# What’s in Grey Conseil

A plain-language catalog of every extra This fork added on top of Matt Purdon’s Grey Eminence. This is the **what and why**. For click-by-click steps and “it broke,” use [USER-GUIDE.md](USER-GUIDE.md) or **Help → What's in Grey Conseil** in the app.

Latest test build: **0.28.4-ftl51** (`GreyConseil-0.28.4-ftl51.dmg`). After the first install, **Check for Updates**.

Matt’s app stays named **Grey Eminence**. Ours is **Grey Conseil**. They do not share a library. Map: [ORIGIN.md](ORIGIN.md), [DIVERGENCE.md](DIVERGENCE.md). Why the name: [NAME.md](NAME.md). Legal: [DISCLAIMER.md](DISCLAIMER.md).

**Grey Eminence** is *éminence grise* — influence without the official chair ([the phrase](https://wordhistories.net/2019/07/24/eminence-grise/)). **Grey Conseil** keeps the grey and takes **Conseil** (counsel) from Jules Verne’s servant in [*Twenty Thousand Leagues Under the Sea*](https://archive.org/details/in.ernet.dli.2015.459144). Homage, plus preferred humor.

This catalog is current through **ftl51**.

### This build (ftl51)

- Hover any control for a short what / how / why. **Help → Controls and options** is the full page. **Help → Send feedback…** files a GitHub issue as text only; screenshot is off unless you opt in (saved on this Mac, not uploaded).

### This build (ftl50)

- GitHub repo is **FTL1/grey-conseil**. Check for Updates uses that feed. Bundle ID / library / Keychain / Outlook OAuth unchanged. Desktop DMG folder is **GreyConseil**.

### This build (ftl42)

- Screen-share stills: drop the blank white/black captures ScreenCaptureKit sometimes returns for Teams, and retry with a window-server snapshot.

### This build (ftl41)

- Unnamed voices are **speaker-1, speaker-2** (not Guest vs Unknown). Calendar invitees include the organizer. A remote “I'm Bob” in the intro names that voice.

### This build (ftl44)

- **Grok library.** Full archive of stored transcripts and intel for the local Secretary (MCP plugin). Grey Conseil does not organize mail or tasks for Grok; it only exposes what is already stored.

### This build (ftl43)

- **Archive Export.** Zip, one PDF (page break per meeting), or one PDF per meeting. Relabeled from Extract.

### This build (ftl40)

- **Archive is the whole library.** Every meeting is there for export. File any meeting or selection away from the recent Meetings list — you do not wait three months.

### This build (ftl39)

- **Archive Extract:** transcripts and intel for a meeting, a recurring series (Weekly Standup), a speaker, selected meetings, or everything currently listed. Optional audio, screen stills, and a time-lapse video of those stills.

### This build (ftl38)

- **Why Grey Conseil:** *éminence grise* (Matt’s Grey Eminence) plus Verne’s Conseil. Help → Why Grey Conseil. Links in [NAME.md](NAME.md).

### This build (ftl37)

- Product name is **Grey Conseil** — not Grey Eminence. Same library. Remove **older Notebook** from Applications if it is still there.

### This build (ftl35)

- Copy on Summary, Follow-up Questions, and Action Items pastes into Teams / Slack / Outlook as real lists, not `1.` and `•` characters.
- PDF reports put open questions first, in a callout.

### This build (ftl34)

- Calendar “Alex Morgan” and Me “Alex you” are one mixer chip (one color, one talk-share). Jordan and Pat stay separate.

### This build (ftl33)

- Mic capture works when macOS exposes the built-in mic as an aggregate device. AAC no longer rejects that tap format.

### This build (ftl32)

- Tagging guest-1 / guest-2 as Jordan **merges those lines onto Jordan** (one chip, one hide/show). Hide-stub **Click to show** reveals that person.

### This build (ftl31)

- Hiding a speaker removes **their first line too** — Alex at 0:00, the first guest-1, the first guest-2. Deselect/select on a mixer chip now affects that first snippet. (ftl30 still tagged playable rows with a UUID, so SwiftUI kept recycling them.)

### This build (ftl29)

- Live AI stays on for the whole recording. It no longer cuts off at 90 minutes while the meeting is still going.
- Intelligence items (follow-ups, actions, summary, topics): click to select, right-click to modify / research / delete, drag to reorder.
- Hiding you hides the first Alex line at 0:00, not only later Me lines.
- Top bar **Watch for meetings** / **Live AI** / **Stop all**. Idle does not record this Mac. Auto-stop after 4 hours (or 20 minutes of silence on an auto-started call).

---

## Recording and speakers

### Who is Me vs a guest

**You** are whoever is on the **Mac microphone**. Everyone else is the **meeting app** (Teams, Meet, Slack) coming through the system-audio tap.

Voice prints name remotes. They do not decide who “Me” is. Teams does not send live “Pat is talking now” tags on that mixed speaker output. Calendar invitees pre-fill the People bar. After a Teams call, Microsoft can later provide a speaker-labeled VTT (tenant permissions) — that is a second pass, not live ID.

### People bar (the room)

**Where:** across the top of **New Recording**, and above a finished transcript.

One strip instead of a separate attendees row plus a buried talk-time menu.

- **Chips** = who is expected or already named (you, calendar invitees, people you pre-tagged).
- Quiet chip = invited, has not spoken yet.
- Colored chip = this voice has lines in the transcript.
- Dashed **speaker-1** chip = a voice the diarizer heard that you have not assigned.
- **Talk-share bars** on the right (Alex 47%, Pat 22%) = only people who have actually talked.
- **Click** a chip to hide or show that person (every name for them, including the first lines). Color = on, grey = off. **Show all** restores.
- **Right-click** a chip: This is Pat, tag individual lines, enroll a voice print, lock or remove. There is no chip chevron.
- **You** and calendar **Alex Morgan** are one chip. Jordan and Pat stay two.

### Pre-tag and lock IDs

**Where:** People bar, **before** you hit Record, and again once voices appear.

Add Pat, Jordan, or pick a calendar event so invitees are already on the bar. When `guest-1` talks, **right-click** that dashed chip → **This is Pat**. Those lines **move onto Jordan’s seat** (same hide/show, same color). Click the **lock** on Pat’s chip so later sentences stay on them. Click the lock again to unlock. Empty seats (Jordan invited, not yet talking) stay unlocked.

**Tag lines as Pat** is different: it paints **one** mislabeled sentence, not every line that shared the old guest ID.

### Current and prior speakers

**Where:** right-click a speaker badge in the live or finished transcript.

Instead of only “Link Contact…” opening a generic directory:

- **This meeting** — people already on this call.
- **Prior speakers** — people who have a voice print, a speaker alias, or earlier meetings.
- A **waveform** means a voice print is saved.
- A **checkmark** is who this voice is already tagged as.
- **Link other contact…** is the full People / Apple / Outlook list when they are not in those two groups.

### Enroll voice print

**Where:** speaker menu → **Enroll voice print**, or the People chip chevron. Also **People →** that contact’s card.

Saves this voice onto a People contact. The **next** recording loads every enrolled print before guests appear. A new diarizer ID that matches Pat is labeled **Pat**, not `guest-2`.

- You cannot enroll a nameless `guest-N`. Pick the person first.
- Enrolling again averages the new sample into the stored print.
- **People** shows a waveform on anyone who has a print. The contact card can remove it.

This is same-person recognition from audio, not a login and not a guarantee across bad call audio.

### Sticky guests (same person stays the same)

Live transcription used to mint `guest-2` for the next sentence of the same remote voice.

Grey Conseil now keeps the last remote name for about twelve seconds, will not replace a name you chose (Pat) with a fresh guest-N, and matches new diarizer IDs to the session (and enrolled) voice print.

### Hide, isolate, search, rename

**Where:** right-click the speaker badge.

| Action | Meaning |
| --- | --- |
| **Hide** | Click the People chip, or Hide in the speaker menu. Grey chip = off. **Show all** next to the names turns everyone back on. Hidden lines are **not** included in Assign. |
| **Color** | Right-click a name → color dots + **Lock this color**. Alex / Jordan / Sam keep the same color next week. A new rare speaker yields if colors clash. |
| **Search** | Find in *their* lines. The menu stays open. Highlights and 2 of 7 matches. |
| **Rename / Apply** | This meeting. Different remotes stay different people. |
| **Save as default name** | Only you. |
| **Set as Me** | This voice is actually the microphone. |
| **Undo / Revert / Re-analyze speakers** | Undo last remap. Revert original names. Re-analyze: pick who was on the call, match voice stamps, leftovers become unknown-1…. You stay you. |

Rename **before** you reanalyze if you want those names in the summary and the task list.

### Export Full Transcript

**Where:** meeting header, and the transcript toolbar.

Saves every line (speaker + timestamp + text) as Plain Text, Markdown, RTF, CSV, Excel, or PDF. Suggested name: `Meeting Title_yyyyMMdd-47m-tr.txt`. Copy Full Transcript puts the same text on the clipboard. This is not the developer `.getranscript.json` used for rubric tests.

### Find this meeting and the library

**Where:** header **⌘F** (this meeting); sidebar / toolbar **⇧⌘F** (library).

- **⌘F** searches the open meeting. Tick **Transcript** to highlight and jump. **⌘G** / **⇧⌘G** walk hits.
- **⇧⌘F** filters by meeting name, speaker, dates, and text (plain or regex) in Transcript and/or Intelligence. Scope: this meeting, selected meetings, or all meetings.
- **Ask** is the AI question box. Per-speaker find stays on the speaker menu.

### Same-speaker auto-merge and play

**Where:** **Settings → Transcript**; play triangle on a line; **⋯**.

Finished meetings join consecutive lines from the same person. The play button on a merged line plays the whole original audio range. **⋯ → Merge consecutive lines** is a one-shot pass. Undo is in **⋯**. Does not run while recording.

### Export Meeting Intelligence

**Where:** Meeting Intelligence → **Export**.

Open the arrow to tick **All sections** or pick Summary / Action items / Follow-up questions / Topics / Shared screens, and/or **Raw transcript**. **De-dupe transcript** is on by default. Then pick **PDF**, **Word**, **Excel**, **CSV**, **JSON**, **RTF**, or **Markdown**.

Suggested name: `Meeting Title_yyyyMMdd-47m-intel.pdf` (same stem for the other types). The old `Title — 2026-08-18 (RP).pdf` and `…-Meeting-Intelligence_…` patterns are gone.

**Copy** on Summary, Follow-up Questions, and Action Items puts HTML on the clipboard with the plain text, so Teams / Slack / Outlook paste real lists (Matt 0.30.0). PDF / HTML reports lead with open questions as a callout (Matt 0.30.1).

**Export** arrow also: **Create dossier…**, **One-pagers for everyone**, **Series dossier…**. A zip of stored facts plus a no-hallucination prompt pack for a separate chatbot. Settings prompts still generate intelligence; the dossier only packs what is already there.

---

## AI (Grok and analysis)

### xAI (Grok) as a first-class provider

**Where:** **Settings → AI → Provider → xAI (Grok).**

Needs an **xAI Console** API key (`xai-…`), not a SuperGrok website login. SuperGrok Heavy is an **account tier**. If Console lists a Heavy model, paste **that model ID** under **Custom model ID**.

The Provider picker is live for the whole app: summaries, reanalyze, Tasks analysis, Ask, interview scoring.

### Analysis timeout and custom model

**Where:** same Settings page.

**Auto** is about 4 minutes for Grok and 2 for Claude. You can pick 2 / 4 / 6 / 10 minutes. A timeout is **one** failure — raise it and Reanalyze once. The app does not retry three times.

### Reanalyze one, several, or all

**Where:** meeting **Reanalyze** button; right-click a row; **Meetings → Reanalyze Selected / All**; **⌥⌘R**.

Jobs run **one at a time**. Interviews, live recordings, and empty transcripts are skipped. **N failed** on the bottom bar is clickable (error, copy, open, retry). **Meetings → Cancel Reanalyze** stops the queue.

Full Reanalyze is **purpose-first** (what you were trying to do, not the calendar title). Each section has its own **Reanalyze**: click is **Deep**; the arrow adds **Deepest** (measured vocal energy from saved audio — not invented emotion), Revert, View log.

Click an intelligence item to select; right-click to modify / research / delete; drag to reorder. Research uses this meeting’s transcript only.

---

## Meetings, Tasks, Dashboard

### Group the Meetings list

**Where:** **Group** at the top of Meetings and Archive.

- **Date** — Today / This Month / July 2026.
- **Series** — each recurring series or same-named meeting, newest first.
- **Related** — names that share the first two words. Every **Exec series** call (Standup + Priorities) in one bucket.

### Export transcripts and intel

**Where:** Archive (and Meetings) **Export…**, right-click a meeting or a section, selection bar, **Meetings → Export Selected**.

Archive lists **every** meeting. File any meeting away from the recent list (right-click **Archive Meeting**, or **Archive** on the selection bar). **Put Back on Meetings** restores it if it is still in the three-month window.

Copies stored transcripts and intel. Scope: this meeting, a recurring series, the visible group, the selection, or everything currently listed. Optional **per speaker**. Package: **Zip** (markdown plus optional audio, stills, time-lapse), **one PDF** (each meeting starts on a new page), or **one PDF per meeting**. There is no camera movie of the call.

### Tasks rollup

**Where:** sidebar **Tasks**.

Default: **analyzed meetings**, **your** tasks only.

- **Meetings** menu — all analyzed, selected rows, a checkbox picker (select all / none), a series, or a calendar name.
- **Assigned** menu — Me, Me + unassigned, Others, Everyone, specific people.
- **Find** — ordinary search in the current list, not a chatbot. Unanalyzed transcripts are **opt-in**.
- **Group** — Status, Meeting, Date, or Series.
- **Export** — Copy, CSV, Excel, RTF, PDF.
- **Stalled** — older than Settings (default 7 days).

### Analyze only what you pick

When Tasks sees transcripts with no AI pass, an orange **Analyze…** banner opens a picker that starts **unchecked**. Select all / none is on that sheet. Same one-at-a-time queue as Reanalyze.

### Dashboard cards

The four stat cards are buttons: This Week / Total Meetings → Meetings; Pending Actions / Stalled Items → Tasks. Hover about one second for a tooltip.

---

## Intelligence (sidebar homes)

Each Meeting Intelligence icon has a left-rail home:

| In a meeting | Sidebar |
| --- | --- |
| Brain (analysis) | **Insights** |
| Follow-up questions | **Questions** |
| Action items | **Tasks** |
| Summary | **Summaries** |
| Topics | **Topic Map** |

### Topic map plus people

Dots stay **topics**. Left control: **Topics / People / Speakers**. Click a person or speaker and only **their** topics light up. Topic panel lists people discussed, who talked, and action items.

### This meeting’s topic cloud

Purple **Topics** icon on a meeting → cloud for **this** meeting. Click a topic to see matching lines. **Include other meetings** pulls the same topic from elsewhere.

---

## Calendar (Mac and Outlook)

**Where:** **Settings → Calendar**.

- **On this Mac** — EventKit. That includes Outlook/Exchange if the account is synced in System Settings → Internet Accounts with Calendars on.
- **Microsoft 365 / Teams** — direct Outlook calendar over the network. Connect Microsoft 365 when an Entra client ID is configured (`GraphConfig.swift`). Read-only.

---

## Capture bar and microphone

**Where:** top of the main window.

- **Watch for meetings** — notices Zoom / Teams / Meet / Discord without capturing this Mac’s mic while idle. Discord asks first.
- **Live AI** — rolling Grok/Claude notes for the **whole recording**. Uncheck it or hit **Stop all** to cut the API. Transcript still runs locally.
- **Stop all** — ends recording, live AI, and auto-start.
- **Hover help** — what / how / why on a control. Full page: Help → Controls and options.
- **Send feedback…** — GitHub issue, text only by default. Screenshot optional, not uploaded.

Auto-record stops after 4 hours, or after 20 minutes of silence on an auto-started call.

**Microphone.** Grey Conseil converts the built-in mic when macOS exposes it as `CADefaultDeviceAggregate`, so AAC no longer drops Alex’s audio. Each new DMG is a new identity: grant **Microphone** and **Screen Recording** to *this* copy. **Settings → Developer → Capture permissions** tests and logs that.

## App identity and safety

| | Meaning |
| --- | --- |
| Name in the Dock | **Grey Conseil** |
| Bundle | `com.ftl1.greyeminence` |
| Library | Separate from Matt’s. New DMG replaces the **app**, not the meetings. |
| Auto-update | **Check for Updates** → github.com/FTL1/grey-conseil (never Matt’s feed). |
| Tahoe | Unsandboxed so it launches (macOS 26 kills a sandboxed ad-hoc build). |
| Ventura | Not supported. |

Do not symlink, copy, or open-in-place Matt’s store.

---

## Small quality-of-life extras

- **Hover ~1s** on icon-only controls for a native tooltip.
- **Dev Mode** — Settings → Developer → verbose log → **Export debug log…**
- **Help → What's in Grey Conseil** — this catalog.
- **Help → How to use Grey Conseil** — the how-to.
- **Help → Why Grey Conseil** — *éminence grise* + Verne’s Conseil.
- **Help → How we differ from Grey Eminence** — the divergence map.
- **Help → Disclaimer (no warranty)** — lawful use, use at your own risk.
- **Help → What's New** — short trailer after an update.

---

## Not in this fork (on purpose)

- Ventura support (Matt’s issue #1).
- Logging into SuperGrok as if it were an API key.
- Opening or cloning the production library.
- Updating from Grey Eminence’s Sparkle feed (that would overwrite this fork).
- A guarantee that voice-print matching is perfect on bad speakerphone audio.

---

## How this relates to Matt’s codebase

We forked **v0.28.4**. His `main` is now **v0.30.1**. Grey Conseil is `0.28.4-ftl35` because we froze the marketing line at the fork and counted test builds.

We **ported** his 0.29.1–0.30.1 behavior (no beachball, cancelled calendar, live screenshots, formatted Copy, open-questions callout). We did **not** merge `main`. Full map: [ORIGIN.md](ORIGIN.md).

## For Matt (if he asks)

This repo is current (**0.28.4-ftl35**). Ask him if he wants **small PRs**, not `feature/speaker-session-rename` as-is. Draft: [MATT-PULL-NOTES.md](MATT-PULL-NOTES.md).

fork packaging (name, bundle ID, no sandbox, no Sparkle) stays in this fork.
