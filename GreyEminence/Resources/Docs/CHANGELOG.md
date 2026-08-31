# Changelog

All notable changes are listed here, newest first. Recent releases have
full detail; older ones are summarized. The version number tracks
`MARKETING_VERSION` in `project.yml`.

Grey Conseil test builds below are **this fork only**. They are not Matt’s shipping
Grey Eminence releases.

## 0.28.4-ftl51 — 2026-08-28

**Help on every control; Send feedback.** Hover a control for a short what / how / why. **Help → Controls and options** is the full page (also `docs/CONTROL-REFERENCE.md`). **Help → Send feedback…** opens a GitHub issue as text only (pane + what you want). Screenshot is off unless you check it; the picture stays on this Mac until you attach it. Emails and phone numbers in the text are scrubbed. No transcript is attached.

## 0.28.4-ftl50 — 2026-08-28

**GitHub is FTL1/grey-conseil.** Check for Updates uses that repo (old `FTL1/greyeminence` URLs redirect). Docs, Settings About/export copy, Grok plugin comments, and the Desktop DMG folder say Grey Conseil. Bundle ID, SwiftData store, Keychain, and Outlook OAuth stay `com.ftl1.greyeminence` / `com.greyeminence.app` so the library and grants stay. About copyright still names Matthew Purdon; Help still has **How we differ from Grey Eminence**.

## 0.28.4-ftl49 — 2026-08-28

**Outlook connect, voice IDs, Grok library.** Settings → Calendar always shows Connect / Validate and a field for the Microsoft client ID (it was hidden while the ID was a placeholder). Voice prints load only for **you and this meeting’s invitees**, not everyone in People — that is why Jordan kept getting the other seat. Enrolled match is tighter. Open Grey Conseil once so it writes the Grok library; the local `grey-conseil` plugin is already in Grok config.

## 0.28.4-ftl48 — 2026-08-27

**Permissions pane.** Open System Settings no longer uses `x-apple.systemsettings:…Privacy_AudioCapture` (Tahoe has no handler — Search App Store dialog). System Audio opens Screen & System Audio Recording. Developer → Permissions only checks the **active** AI provider, so a missing Anthropic key is not an error when Grok is selected.

## 0.28.4-ftl47 — 2026-08-27

**Rename a session.** Click the meeting name in the header (or on Record), or double-click it in Meetings / Archive. Return saves, Escape cancels. Reanalyze keeps a name you typed.

## 0.28.4-ftl46 — 2026-08-27

**Mic meter and full permissions.** Settings → Audio level LEDs used a linear 0…1 scale, so speech only lit the first bar while the number still moved. The bar is dBFS now (−50…−8). Developer → Permissions lists microphone, screen, system audio (Test tap), calendar, contacts, notifications, Microsoft 365, Anthropic/xAI keys (Validate), Bedrock, recordings folder, and the Sparkle feed.

## 0.28.4-ftl45 — 2026-08-27

**Check for Updates and mic grant.** Sparkle was fetching `github.com/FTL1/grey-conseil` (that repo does not exist), so the in-app updater 404ed. Feed is `FTL1/greyeminence` again. Opening Record, or first capture after a new DMG, prompts for Microphone; a denial opens System Settings. Screen Recording / System Audio is requested on record start (ad-hoc DMGs orphan TCC).

## 0.28.4-ftl44 — 2026-08-27

**Secretary access.** Grey Conseil writes a Grok library (full archive: transcript + intel + actions) on launch, after a recording, and after reanalyze. Local Grok plugin `grey-conseil` searches it. No new organizer in the app.

## 0.28.4-ftl43 — 2026-08-26

**Grey Conseil. Archive Export (zip or PDF).**

- Archive (and Meetings) **Export…** — it was labeled Extract; it is an export.
- **Zip** still packs markdown plus optional audio, stills, and a screen-share time-lapse.
- **One PDF** concatenates the set; each meeting starts on a new page.
- **One PDF per meeting** writes a file per meeting into a folder you choose.
- GitHub repo is **FTL1/grey-conseil**. Bundle ID is still `com.ftl1.greyeminence`. Check for Updates uses that repo. Copyright names Matthew Purdon; Unofficial Grey Conseil portions under the same license.

## 0.28.4-ftl42 — 2026-08-26

**this fork only. Blank screen-share stills.**

- ScreenCaptureKit sometimes returns a white rectangle for Teams/Electron
  windows. Capture now sizes from the filter's content rect, falls back to
  a window-server snapshot, and **drops** uniform white/black frames so
  they are not kept or sent to vision.

## 0.28.4-ftl41 — 2026-08-26

**this fork only. speaker-1 and calendar self-intro.**

- Unnamed remotes are **speaker-1, speaker-2** — not Guest vs Unknown.
- Calendar invitees include the **organizer**. Linking an event still
  puts those names on the People bar.
- If a remote voice says **I'm Bob** (or my name is) in the first eight
  minutes, that voice is Bob. If Bob is on the invite, the full invite
  name is used. Me saying “this is Bob” does not count.

## 0.28.4-ftl40 — 2026-08-25

**this fork only. Archive is the whole library.**

- Archive lists **every** meeting (not only older than three months) so
  extract can hit Weekly Standup from last week.
- Right-click or the selection bar: **Archive Meeting** / **Archive
  Selected** files them away from the recent Meetings list. **Put Back
  on Meetings** restores a filed meeting that is still in the three-month
  window.

## 0.28.4-ftl39 — 2026-08-25

**this fork only. Extract transcripts and intel from Archive.**

- Archive (and the recent Meetings list): **Extract…** for the current
  meeting, a recurring series (Weekly Standup), selected meetings, or
  everything currently listed. Optional **per speaker**.
- Checkboxes: transcript, intel, audio, screen captures, and a **video**
  time-lapse of those stills. There is no camera movie of the call.

## 0.28.4-ftl38 — 2026-08-25

**this fork only. Why the name is Grey Conseil.**

- **Grey Eminence** is *éminence grise* — unofficial counselor
  (https://wordhistories.net/2019/07/24/eminence-grise/). **Grey Conseil**
  keeps the grey and adds Verne’s servant Conseil (counsel) from *Twenty
  Thousand Leagues Under the Sea*
  (https://archive.org/details/in.ernet.dli.2015.459144). Homage, plus
  humor. Help → **Why Grey Conseil**.

## 0.28.4-ftl37 — 2026-08-25

**this fork only. Product name is Grey Conseil.**

- Dock name is **Grey Conseil** — not Grey Eminence. Bundle ID is unchanged
  (`com.ftl1.greyeminence`), so the existing library stays. Drag this app in
  and remove **older Notebook** / older test builds if those icons are still
  in Applications.

## 0.28.4-ftl36 — 2026-08-25

**this fork only. Renamed older Notebook; updates from this repo; legal notice.**

- Dock name became **older Notebook** (later **Grey Conseil** in ftl37).
  Bundle ID unchanged. Unofficial fork, not Grey Eminence.
- **Check for Updates** uses github.com/FTL1/greyeminence Releases, not
  Matt’s Sparkle feed. First launch asks you to acknowledge: no warranty,
  use at your own risk, lawful use only (you are responsible).
- Help: **Disclaimer** and **How we differ from Grey Eminence**.

## 0.28.4-ftl35 — 2026-08-24

**this fork only. Port of Matt 0.30 copy-with-format and open-questions callout.**

- Copy on a summary (and on follow-up questions / action items) now also
  puts HTML on the clipboard, so Teams, Slack, Outlook, and Notes paste
  real headings and lists. Plain text is still there for everything else.
- PDF / HTML reports lead with open questions in a callout, not buried
  under the summary looking like one more section.

## 0.28.4-ftl34 — 2026-08-24

**this fork only. One mixer chip for you.**

- Calendar “Alex Morgan” and Me “Alex you” were two chips on the same
  lines (two colors, the same 53% twice). The roster now treats those as
  one person: one name, one color, one talk-share. Jordan and Pat stay
  separate.

## 0.28.4-ftl33 — 2026-08-24

**this fork only. Mic capture on aggregate devices.**

- Built-in mic behind `CADefaultDeviceAggregate` was delivering a format
  AAC refused (`avfaudio -66567`), so Alex’s audio was dropped and the
  encoder banner appeared. Mic buffers are now converted to a standard
  float32 layout before encoding. Transcription keeps running even if a
  file cannot be written.

## 0.28.4-ftl32 — 2026-08-24

**this fork only. Tagging guest-1 as Jordan actually merges them.**

- Selecting guest-1 / guest-2 and setting them to Jordan now puts those lines
  on Jordan’s seat (same chip, same hide/show, same color). It was only
  renaming the badge. **Click to show** on a hide stub reveals that
  person instead of rolling up the other copy.

## 0.28.4-ftl31 — 2026-08-24

**this fork only. First snippet of every speaker actually hides.**

- Mixer hide was still leaving the first Alex / guest-1 / guest-2 line
  playable. Playable rows were tagged with a UUID while hide stubs used
  a String, so SwiftUI recycled index 0 as the original snippet and
  deselect/select did nothing to it. Every transcript row now uses the
  same String identity, and hide rebuilds the list. Click a grey chip
  or **Show all** — the first comment goes with the rest.

## 0.28.4-ftl30 — 2026-08-24

**this fork only. First hidden line actually hides.**

- Mixer hide stubs no longer reuse the first line’s UUID. SwiftUI was
  keeping that original playable row, so Alex at 0:00 and the first
  guest-1 / guest-2 snippets stayed on screen. Hide now shows a “Show
  …” stub instead of the first comment.

## 0.28.4-ftl29 — 2026-08-24

**this fork only. Live AI lasts the whole meeting.**

- Live AI no longer stops at 90 minutes while you are still recording.
  It follows the meeting: on until you turn **Live AI** off, hit **Stop
  all**, or the recording itself ends (including the 4-hour / idle-speech
  auto-stops).

## 0.28.4-ftl28 — 2026-08-24

**this fork only. Intelligence item editing, Alex hide leak, capture kill switch.**

- Follow-up questions, action items, summary sections, and topics: **click**
  to select, **right-click** to modify / research / delete, **drag** to
  reorder. Research uses this meeting’s transcript only (no invented facts).
- Hiding **you** now hides the first Alex line at 0:00 as well (Alex as a
  remote label vs Me).
- Top bar: **Watch for meetings**, **Live AI**, **Stop all**. Idle does not
  capture this Mac’s mic. Auto-record stops after 4 hours, or after 20
  minutes of silence on an auto-started call. Live AI originally stopped
  after 90 minutes even if you kept recording (changed in ftl29).

## 0.28.4-ftl27 — 2026-08-21

**this fork only. Speaker re-analyze with voice stamps, hide-filter leak, capture-permission probe.**

- **Re-analyze speakers** now opens a sheet: pre-select who was actually on
  the call. Saved voice stamps for those people are used first. Leftover
  clusters are **unknown-1, unknown-2…** (not extra guest names). Select
  one or more unknowns and assign them to a known person, a contact, or a
  typed name. A voice stamp is saved and tied to that contact.
- Hiding **Me** and **Jordan** now hides every identity for those people,
  including the first transcript lines (Alex labeled as a remote, Jordan
  Hale vs Jordan). Unassigned leftover guests stay visible.
- Screen-share no longer treats every ScreenCaptureKit error as “permission
  off.” If macOS already granted this binary, a transient list-windows
  failure does not latch the red banner.
- **Settings → Developer → Capture permissions**: test/validate/log
  CGPreflight, ScreenCaptureKit, mic, bundle path, and signing. Copy the
  log. Each ad-hoc Grey Conseil DMG is a new identity — System Settings can show ON
  for an older copy.

## 0.28.4-ftl26 — 2026-08-20

**this fork only. Deep / Deepest reanalyze on every intelligence section.**

- Follow-up Questions, Action Items, Summary, and Topics each have a
  **Reanalyze** control. Click runs **Deep** (a more thorough prompt for
  that section only). Arrow: Deep, **Deepest** (adds measured vocal
  energy from the saved audio — not invented emotions), **Revert**,
  **View log**.
- The top Reanalyze button keeps a normal full rewrite on click.
  Its arrow adds Deep, Deepest, Revert, View log; re-transcribe with
  large-v3 is at the bottom.
- Prior insights are kept so revert and the log work.

## 0.28.4-ftl25 — 2026-08-20

**this fork only. Meeting dossier export (chatbot pack, series, one-pagers).**

- Meeting Intelligence **Export** arrow: **Create dossier…**, **One-pagers
  for everyone**, **Series dossier…** when related meetings exist. Still
  dumps a single file the old way below those items.
- A dossier is a zip: README, written report (md/txt/pdf/docx/rtf/json),
  optional transcript, optional AAC audio, optional screen stills, and a
  **prompt pack** (`PROMPT.md` + `meeting.json`) you upload to a separate
  Grok. The prompt forbids inventing facts.
- One-pagers: `_general.md` plus one short page per speaker.
- Series: calendar series if linked, otherwise meetings that share the
  first two name words.
- Analysis now **stores everyone’s action items**. The on-screen list is
  still yours (plus unowned, plus the other person in a 1:1). Reanalyze
  to fill other people’s tasks on older meetings.

## 0.28.4-ftl24 — 2026-08-20

**this fork only. Reanalyze infers purpose, not calendar subject.**

- **Reanalyze** now runs a fresh purpose-first prompt instead of replaying
  the live first-pass. It infers what you (Me) were trying to get done —
  fix outbound documents, align language with what someone actually said —
  rather than summarizing the calendar title or a PDF on screen.
- Follow-up questions are unanswered in-room questions and outstanding
  work, not a generic due-diligence questionnaire.
- Previous summary / questions / topics are replaced. Untouched suggested
  tasks are replaced; completed, dated, or assigned tasks stay.
- Calendar-linked meeting names stay as the event. The intelligence pane
  shows the AI purpose title when it differs.
- Whisper re-transcribe, split, and topic-map analysis use the same
  rewrite (one pass, not first-pass then polish).

## 0.28.4-ftl23 — 2026-08-20

**this fork only. Play a merged line’s full audio.**

- The play button on a joined transcript line now plays from that line’s
  start through the next line, covering every original crumb — including
  across split audio files. No HLS rewrite; it just walks the matching
  time ranges.

## 0.28.4-ftl22 — 2026-08-20

**this fork only. Auto-merge actually runs on existing transcripts.**

- Opening a finished meeting now merges same-speaker crumbs after the
  lines are loaded (ftl21 ran too early against an empty list, then
  never retried).
- Pause default is 4s, window 15s, so streaming fragments 3–5s apart
  join. Existing 2s/10s settings are bumped once.
- **⋯ → Merge consecutive lines** still does a one-shot pass.
- Developer → Edit AI Prompts no longer says the prompts are “sent to Claude.” They go to whichever provider is selected (Grok for Grey Conseil).

## 0.28.4-ftl21 — 2026-08-19

**this fork only. In-meeting Find, auto-merge, transcript ⋯ menu.**

- **⌘F** searches the open meeting (header field). Tick **Transcript** to
  highlight and jump lines in the inspector. **⇧⌘F** is still library Find.
- **Settings → Transcript**: auto-merge same-speaker fragments (10–30s
  window or a long pause, whichever comes first). Dedupes ASR crumbs.
  Undo is in the transcript **⋯** menu. Does not run while recording.
- Transcript toolbar: Select / export / re-analyze stay visible. Undo,
  revert, merge-now, and DEV tools move into **⋯** so a narrow pane no
  longer clips labels.

## 0.28.4-ftl20 — 2026-08-19

**this fork only. Find in transcripts and Meeting Intelligence.**

- Sidebar **Find** is a main-pane search (toolbar magnifying glass, **⇧⌘F**).
  Scope: this meeting, selected meetings, or the whole library.
- Filters: meeting name, speaker (Me, Jordan, …), from/to date, and text
  (plain or **Regex**). Tick **Transcript**, **Intelligence**, or both.
- Click a hit to open that meeting. Transcript hits jump to the line.
- **Ask** is still the AI question box. Per-speaker **Find in their lines**
  is still on the speaker menu.

## 0.28.4-ftl19 — 2026-08-18

**this fork only. People chips, colors, line playback, merge.**

- Click a People chip to hide or show that speaker. Color = on, grey = off.
  Talk % sits on the chip. The extra talk-share row and chip chevrons are gone.
- Show all sits next to the names. Empty leftover guests drop off the bar.
- Same person, same color in the meeting header and the transcript. Pick and
  lock a color in the speaker menu. A clash keeps the more common speaker.
- Apply renames only the selected line(s). Rename inline is gone. Prior
  speakers are a dropdown. Hide is one toggle. Set as Me is under Rename.
- Play on each line plays that line’s saved audio.
- Select two or more lines and **Merge**.

## 0.28.4-ftl18 — 2026-08-18

**this fork only. Speaker remap no longer eats hidden Me lines.**

- Isolate Guest-1, then assign: only those visible lines change. Hidden
  speakers (including you) stay put. **Select Visible** replaced Select All.
- The isolate banner says how many lines will change and has **Assign these N**.
- Remapping a guest never overwrites Me.
- **Undo speaker change** puts the last remap back. **Revert speaker labels**
  restores the original names. **Re-analyze speakers** listens to the saved
  audio again and relabels remotes as guest-1, guest-2…. You stay you.

## 0.28.4-ftl17 — 2026-08-18

**this fork only. Shorter export names, and three ports from Matt 0.29.**

- Export files are now `Title_yyyyMMdd-47m-intel.pdf` and
  `Title_yyyyMMdd-47m-tr.txt`.
- Launch no longer beachballs while Core Audio enumerates devices.
  Startup names the interrupted-recording, interview, and screen-frame
  checks in the footer.
- Cancelled Outlook/Exchange meetings (`Canceled: …`) no longer appear
  in the calendar picker.
- While recording, shared-screen thumbnails show as soon as frames
  exist (text list only until the first frame lands).
- Intelligence Export drops summary sections *after* screenshot
  anchoring, so the PDF cannot grow a dead figure link.

## 0.28.4-ftl16 — 2026-08-18

**this fork only. Smaller transcript button, per-name locks, richer Intelligence Export.**

- **Transcript** in the meeting header and transcript bar is a small
  control. Same formats as before.
- Speaker names wrap in the People bar so they all stay visible. Each
  name has a lock icon you click to lock or unlock that ID. The old
  **Lock IDs** button is gone.
- Meeting Intelligence **Export** (was Export PDF) lets you tick
  sections, add the raw transcript with **De-dupe** on by default, and
  save as PDF, Word, Excel, CSV, JSON, RTF, or Markdown.

## 0.28.4-ftl15 — 2026-08-18

**this fork only. Export the full transcript, and name Intelligence files clearly.**

- **Export Full Transcript** on the meeting header and the transcript toolbar.
  Saves every line (speaker, timestamp, text) as Plain Text, Markdown, RTF,
  CSV, Excel, or PDF. Suggested name:
  `Title-Full-Transcript_yyyyMMdd-<minutes>.txt`. Copy Full Transcript puts
  the same text on the clipboard. This is not the developer
  `.getranscript.json` used for rubric tests.
- Meeting Intelligence **Export PDF** (and csv / rtf / xlsx) now suggests
  `Title-Meeting-Intelligence_yyyyMMdd-<minutes>.pdf`. The old
  `Title — 2026-08-18 (RP).pdf` pattern is gone.
- **You** are whoever is on the Mac microphone. Everyone else is the
  meeting app (Teams, Meet, Slack) on the system-audio tap. Voice prints
  name remotes; they do not decide who Me is.

## 0.28.4-ftl14 — 2026-08-18

**this fork only. People bar, voice prints, this-meeting / prior speakers.**

- One **People** strip across Record: chips for who is here, talk-share for
  who is speaking. Click a chip to isolate them.
- Pre-tag invitees, assign `guest-1` → **This is Pat**, **Lock IDs**.
- Right-click a badge: **This meeting** and **Prior speakers**, enroll a
  voice print onto a People contact, hide (and **Show Pat**), search that
  stays open. A click on the name does not hide them.
- Enrolled prints load at the next recording so a match is labeled Pat
  instead of a new guest-N.

## 0.28.4 — 2026-08-13

**Fixed: the release build failed to compile**
- A test set up its scratch directory in `setUpWithError`, which is a
  nonisolated override and so cannot touch a property of a main-actor
  test case. The local toolchain allowed it; the one CI builds with did
  not, so 0.28.3 never produced a release.

## 0.28.3 — 2026-08-12

**The masthead now reaches the top of the page**
- Trajector and Matthew Purdon reports opened with a white strip above the
  coloured header band. The band now starts at the paper's edge. Pages
  after the first keep their margins, and the templates whose header is
  plain text are unaffected.

## 0.28.2 — 2026-08-12

**Fixed: the header sat in the middle of the page instead of spanning it**
- Every template's masthead was inset by exactly one page margin, so it read
  as a floating rectangle rather than a band across the top. A negative
  margin cannot escape the page's own margin — the renderer clips it — so
  the side margins now come from the page body, which leaves the masthead
  room to reach both edges. Continuation pages keep their margins.

## 0.28.1 — 2026-08-12

**Fixed: contents entries were numbered twice, and brand colours vanished**
- The contents list showed "1. 1. AI-first workflow" — an ordered list
  drawing both its own number and the styled one.
- Every background colour was being dropped on export, because printing
  omits them by default. The Trajector report was printing white text on
  white paper where its navy header should be, and every tinted panel was
  invisible.
- The Matthew Purdon template now leads with a full-bleed cream masthead
  rather than trying to tint the whole sheet, which is not something the
  PDF renderer can do.

## 0.28.0 — 2026-08-12

**The report is a summary again, and screenshots carry the story**
- Only the few screenshots that make a point in the summary are printed,
  and they sit beside the point they make. The rest are not printed at all
  — they made the report long without making it clearer, and everything
  captured is still in the app.
- Captions now say what the screenshot shows *and* what it establishes for
  that part of the summary, so a picture explains why it is on the page
  rather than restating what you can see.
- Screenshots are set inline with the summary by default. Collecting them
  at the end, cross-linked, is still available in the Export PDF menu for
  when the prose should read uninterrupted.
- Without AI configured nothing can be tied to a section, so a report keeps
  at most three screenshots spread across the meeting rather than all of
  them.

## 0.27.2 — 2026-08-12

**Fixed: captions described the meeting instead of the screenshot**
- A screenshot of a document being reviewed was captioned "Zoom call in
  progress during early discussion of the design workflow" — text taken
  from the key moment, which describes what was happening in the meeting,
  not what is in the picture. Captions now come from the screenshot's own
  description, so they name the tool, the screen and the values on it.
- The AI captioner was also only seeing the first 300 characters of each
  screenshot's description. The specifics are spread through the whole
  paragraph, so it was left describing the application window rather than
  the contents. It now sees enough to be specific, and is told outright
  that the call, the video tiles and the toolbar are chrome — caption what
  is inside them.

## 0.27.1 — 2026-08-12

**Fixed: exports were named after the AI's title, not the meeting's**
- The report title and filename used the AI-generated title in preference to
  the meeting's actual name. For a meeting linked to a calendar event that
  meant exporting under a name the app never shows, and if you had renamed a
  meeting yourself it ignored the rename entirely. Exports are now titled
  whatever the meeting is called at the moment you export it.

## 0.27.0 — 2026-08-12

**Every screenshot now says what it is and why it's there**
- Each figure gets a short caption naming what you're looking at and, where
  it relates to something the summary discusses, naming that too. Previously
  only the handful of screenshots tied to a summary section got a written
  caption; the rest carried either a bare timestamp label or the entire
  100–250 word description the vision pass had written, printed raw under
  the picture.
- The same pass that decides which screenshots belong beside which section
  now captions all of them, so this costs nothing extra.
- Without AI configured, captions fall back to the first sentence of the
  description, clipped at a word boundary, rather than the whole paragraph.

## 0.26.2 — 2026-08-12

**Fixed: improved screenshot picking didn't reach meetings you'd already exported**
- The figure-anchoring result is cached per meeting, and the only thing that
  expired it was re-running the analysis. So a meeting exported before
  today's improvements would have kept its old choices forever. Worse, the
  cached anchors named screenshots the new selection no longer picks, which
  would have quietly produced a report with no links at all.
- The cache now expires when the anchoring logic itself changes, so
  improvements land on the next export with nothing to re-run.

## 0.26.1 — 2026-08-12

**Better screenshots, and you choose where they go**
- Screenshot selection now favours actual content over the video call. It
  weighs what the frame was identified as — a slide, document, diagram,
  code, dashboard — and how much text is on it, so a gallery of faces
  loses to a slide. The AI is told the same thing explicitly: never anchor
  a frame showing only participant tiles or a speaker's camera.
- Key moments now pick the best frame *near* the moment rather than the
  nearest one, since the closest frame in time is often a cut to whoever
  was speaking.
- The Export PDF menu now lets you choose between screenshots collected at
  the end (cross-linked to the summary) and set inline with the summary.
- Sections no longer start on their own page — on real reports it left
  pages of white space and a lot of scrolling. The contents list stays.

## 0.26.0 — 2026-08-12

**Contents page, and a page per section**
- Reports now open with a linked table of contents, and each section of the
  summary starts on its own page. Contents entries are clickable in the
  exported PDF. Plain stays plain — it has neither.

**Fixed: the screenshot cross-links never appeared**
- The links between a screenshot and the part of the summary it supports
  only worked when screenshots were collected at the end, which only the
  Report template did. Every template now collects them at the end, which
  is what makes the links exist: a screenshot set inside its own section
  has nothing to link to, and the leftovers at the back had nothing to
  link back to.

## 0.25.3 — 2026-08-12

**Exports no longer overwrite each other**
- The suggested filename now carries a two-letter tag for the template it
  was made with — "Braintrust — 2026-08-12 (TJ).pdf" — so you can export
  one meeting under every theme into the same folder and compare them,
  instead of each export replacing the last. The tag is shown beside each
  template in the picker.

## 0.25.2 — 2026-08-12

**Jump between a screenshot and the part of the summary it belongs to**
- Screenshots printed in the appendix now carry a link back to the section
  they evidence, and that section links forward to them. Both work as real
  clickable links in the exported PDF, so you can read a point, jump to the
  picture, and come straight back.
- The Report template now collects every screenshot at the end and refers
  to them from the text, the way a formal report does. The other templates
  keep setting them beside the prose.

**Easier-to-read bullets**
- Summary points used an em dash as their marker, which was hard to pick
  out at a glance. Each template now uses a mark you can actually see.

## 0.25.1 — 2026-08-12

**Five report templates, and a picker**
- Export PDF is now a split button: click exports with your last-used
  template, the arrow picks a different one. Plain, Report (formal and
  numbered), Trajector, Matthew Purdon, and PurdonMoi.

**Fixed: reports exported with no screenshots at all**
- A shared screen only made it into a report if its AI session recap had
  also been generated. If that pass never ran, every screenshot from that
  share was silently dropped. Screenshots now stand on their own, and a
  share with no recap contributes a spread across its length instead.
- If a report still comes out with no figures, the activity log now says
  which reason it was.

## 0.25.0 — 2026-08-12

**Screenshots land beside the part of the summary they prove**
- Exporting a report now works out which captured screenshots are direct
  evidence for which section of the summary, and prints them there rather
  than in a lump at the end. A screenshot from roughly the same moment
  doesn't qualify — it has to actually show the thing being discussed.
- Most screenshots don't earn a place, and that's the intended outcome.
  Whatever no section claims still appears in the "Shared screens"
  appendix, so nothing you captured is thrown away.
- It costs one small text-only AI call per meeting — no images are
  uploaded, since the screenshots were already described during the
  recording. The result is cached, so switching templates or exporting
  the same meeting again is free. Re-running the analysis recomputes it.
- Shows up in AI Usage under a new "Reports" group.
- If AI isn't configured, or the call fails, the report still exports with
  its figures in the appendix.

## 0.24.3 — 2026-08-12

**Export a meeting as a PDF report**
- Meeting Intelligence has an "Export PDF" button. It turns the summary,
  action items, open questions and shared screens into a proper paginated
  document you can send to someone who doesn't run Grey Eminence — real
  pages, selectable text, and screenshots embedded in the file rather than
  linked to it.
- Screenshots are chosen rather than dumped: each share session contributes
  the frames tied to the key moments the analysis already identified, and a
  figure never gets separated from its caption across a page break.
- One "Plain" template for now. Branded templates, a template picker, and
  chatting at a template to restyle it are next.

## 0.24.1 — 2026-08-12

**Fixed: Zoom's popped-out screen share was missing from the window picker**
- Zoom pins its meeting windows above the normal window level, and the
  window list quietly skipped anything up there. The main Zoom window
  showed up, the popped-out shared content never did — the one window
  you actually wanted to capture. Elevated windows are now listed.
- Zoom also had no auto-detection rules at all, so its windows were only
  ever manually selectable. A popped-out or fullscreened share is now
  detected automatically, while the meeting window itself stays
  picker-only: when nobody is sharing it is a wall of faces, and
  screenshotting that would spend your frame budget on video thumbnails.
- Every window considered for capture is now logged with its window level
  in the activity log, so a share that goes undetected can be told apart
  from one that was never offered.

## 0.24.0 — 2026-08-07

**Discord calls**
- Grey Eminence now recognizes Discord alongside Teams, Zoom, and the rest.
  Discord is different: it holds your microphone for as long as you're
  connected to a voice channel, including sitting in one alone, so
  auto-recording it would capture a lot of nothing. It asks instead —
  once per call, from the menu bar or a bar at the bottom of the window,
  so you can answer without leaving the call.
- Streams get captured like any other shared screen, as long as they're
  popped out or fullscreened. The main Discord window stays available in
  the window picker but is never captured automatically, since it would
  frame the channel list and chat rather than the stream.
- Meetings now record which app they came from, shown on the meeting row.

**Fixed: recordings that captured everyone except you**
- When another app claimed the microphone a moment after recording
  started — which is exactly what happens on an auto-started call — the
  microphone could stop feeding the recording silently. The transcript
  came back with the far end only. Capture now notices and restarts
  itself, and tells you if it can't.

**A tidier transcript toolbar**
- The controls above a transcript were crowded into one row that
  compressed everything at once in a narrow panel. Selection actions now
  take over the bar only while you're selecting, and the developer tools
  have their own strip.

## 0.23.16 — 2026-08-03

**Fixed: a month of meetings appearing to be missing**
- The Meetings list sorted its month headings alphabetically instead of by
  date, so July sat below June and looked like it had vanished. Nothing was
  ever lost — the meetings were there the whole time, just filed under the
  wrong heading order. The same slip affected January and February, and any
  other pair of months whose names sort differently than the calendar does.
- Month sections now follow the calendar, newest first.

## 0.23.15 — 2026-07-30

**Fixed: meeting analysis producing no insights**
- 0.23.14 fixed the "data couldn't be read" error and revealed the next
  one: on long meetings the model was spending its entire output budget
  reasoning and never getting to the answer, so analysis failed with "No
  text content". That reasoning step is now switched off — it was doing
  nothing for these prompts, which ask for a fixed set of fields.
- When a response does come back empty, the error now says the model hit
  its output limit rather than just reporting nothing.

**Fixed: screen shares shown under the wrong meeting**
- Selecting a different meeting could leave the previous meeting's screen
  share on screen — its images, descriptions and frame count — whenever the
  two meetings happened to have the same number of frames. Nothing was
  mis-filed: the recordings were always stored against the right meeting,
  only the panel was slow to catch up. It now follows the selection.

**Re-open What's New whenever you like**
- Help → What's New in Grey Eminence brings the update highlights back
  after you've dismissed them.

## 0.23.14 — 2026-07-29

**Fixed: meeting analysis failing with "The data couldn't be read"**
- AI analysis stopped producing insights entirely, showing only the error
  "The data couldn't be read because it is missing." The Bedrock model
  behind the Sonnet profile now returns a reasoning block ahead of its
  answer, and the app rejected the whole response rather than reading past
  it. Analysis works again; screen-share frame analysis was unaffected.
- The raw AI response is now written to the activity log before it's
  parsed, so a future change in response shape leaves something to
  diagnose from instead of a bare error.

## 0.23.13 — 2026-07-24

**What's New after updates**
- A curated "What's New" sheet now appears once after the app updates to a
  version you haven't seen, highlighting the headline features with a "Try
  it" link straight into each one. Skipped several versions? You get the
  union of what you missed, capped to the headline set — the full history
  stays in this changelog. New installs are suppressed (you're onboarding,
  not catching up), and the sheet sequences behind first-run setup so the
  two never stack.
- Tasteful "NEW" badges mark new affordances in context (the recording
  side-panel's Prep tab, the screen-share capture chip) and clear the first
  time you use them — catching anything you dismissed on the sheet.

**Meeting Prep beside the transcript**
- While recording, the side panel now has a Transcript / Prep toggle. Flip
  to Prep to keep carried-over unresolved tasks, open questions, and prior
  topics in view during the meeting. The toggle only appears for recurring
  meetings that have prep to show; one-off meetings keep the plain
  transcript.

**Fixes & cleanup**
- Fixed a 100% CPU / beachball regression where the attendees row's
  `ViewThatFits` rebuilt every candidate's view tree on every layout pass.
  The roster arrangement is now chosen by headcount, not measurement.
- Deleting a meeting whose audio is shared with a split sibling no longer
  leaves that meeting's screen-frame JPEGs orphaned on disk.
- Removed two per-redraw costs read from view bodies (the dashboard's
  stalled-item count and the header's edited-segment count).

## 0.17.4 — 2026-05-26

**Re-processing robustness**
- AI response parsing now salvages prose-wrapped JSON by clipping to the
  outermost `{…}` pair before decoding, instead of failing with
  Foundation's opaque "data couldn't be read because it is in the wrong
  format". Granular reasons (empty response / top-level not an object /
  underlying decode error) now flow into the meeting's re-processing
  error.
- Failed re-processing pills now show an info icon with the underlying
  error message as a tooltip, so you can see why a job failed without
  digging through the activity log.

**Follow-up questions: blockers, not paraphrases**
- The analysis prompt now requires follow-ups to be questions about
  blockers, missing information, or dependencies for the listed action
  items — or genuine gaps the meeting didn't resolve. Restating an
  action item as a question (e.g. action: "Investigate X" + follow-up:
  "Why does X happen?") is explicitly forbidden. Empty array if there
  are no real blockers.

## 0.17.3 — 2026-05-21

**Add attendees while recording**
- The recording view now has an attendee strip below the toolbar showing
  the current meeting's attendees with a + button to add more via the
  same contact picker used elsewhere. Attendees can be added or removed
  mid-recording.
- Newly added attendees are pushed into the speaker-contact mapper
  immediately so their aliases participate in auto-matching diarized
  speakers for the rest of the session.

## 0.17.2 — 2026-05-20

**Transcript section tagging**
- Tagging a phase on a transcript segment now extends to the end of the
  transcript instead of stopping at the next existing boundary. Walking
  the transcript top-to-bottom and tagging at each phase transition just
  works — later tags overwrite earlier ones in their range, so stale
  boundaries can't strand themselves mid-transcript.
- "Clear Tag From Here Onward" → "Clear All Tags From Here Onward" and
  actually clears every following segment, not just the first run.

## 0.17.1 — 2026-05-20

**Tasks: Won't Do status**
- Tasks now have a "Won't Do" state separate from "Completed". Right-click
  any task → Mark as Won't Do. Strikes the row through (like completed
  but in secondary tone) and drops it out of Pending + Stalled. Restore
  from the Won't Do section's context menu.
- New bulk action in the Tasks options menu: "Mark Stalled as Won't Do
  (N)" with confirmation. Affects whichever tasks are currently visible
  under the Mine + Unassigned / All filter, so the scope matches what
  you see on screen.
- New "Show Won't Do" toggle in the same options menu, off by default
  so the dismissed pile doesn't clutter the list.
- SchemaV16 adds `ActionItem.dismissedAt`. Lightweight migration; existing
  items keep `nil` and stay Pending.

## 0.17.0 — 2026-05-19

**Recovery & safety**
- Re-processing jobs interrupted by a crash or restart are no longer
  auto-resumed on next launch — they're marked failed with an
  "interrupted — click Retry to resume" reason. Auto-resume of a
  misbehaving job had been creating crash loops.
- Interviews left stuck in `.recording` and recovered to `.scheduled`
  on launch now carry an `interruptedAt` timestamp (SchemaV15) and
  show an orange "Interrupted" badge on the list, so a recovered
  session is visually distinct from a never-started one.
- End Interview now asks for confirmation before flipping status to
  complete. The previous one-click destructive action had no undo.

**Score All Sections gating**
- Hidden when there's no transcript (status `.scheduled` or zero
  segments). Click used to error.

**Phase timer**
- Per-phase mute button next to the timer pill on the live phase
  header. The pill stays visible; the banner + sound are silenced
  for the current phase only. Resets on the next phase.
- Phase timer pill also surfaces inline on the active row in the
  Interviews list — glance at the list to see if the current phase
  is running long without opening the live view.

**Tagging the transcript**
- Tag Phase context menu now offers "Clear Tag From Here Onward"
  alongside the single-segment clear, so the cascading-clear is
  symmetric with the cascading-tag.
- ⌘1 / ⌘2 / ⌘3 … shortcuts inside the open menu select the matching
  phase. Faster than aiming with the mouse over a long phase list.

**Activity Log**
- Search field added; filters by message and detail-payload text in
  addition to the existing category + level pickers.

**Transient activity surface**
- Two new launch-time flashes: "N re-processing job(s) interrupted —
  open meeting to retry" and "Restored N interrupted interview(s) —
  click Start to resume" so silent recovery isn't silent anymore.

## 0.16.4 — 2026-05-19

**Crash fix (the actual one — sorry)**
- v0.16.1's resumable re-processing introduced a Swift exclusivity
  violation in `HighQualityTranscriber.transcribe(...)`. The
  checkpoint-emit closure captured local vars (`completedMic`,
  `accumulatedMic`, `segments`, ...) by reference, and those same vars
  were then passed `inout` to `runChunks`. When `runChunks` invoked
  the closure mid-loop, Swift's law of exclusivity tripped — two
  active accesses to the same storage — and aborted the process.
- Refactored to bundle all mutable progress into a single
  `TranscriptionProgress` struct passed once as `inout`. The
  checkpoint emission reads from the inout binding directly, no
  outer capture, no overlapping access.
- Any user with a Meeting stuck in `reProcessingState` from a prior
  session hit this on every launch, 4-9 seconds in, with no UI feedback
  — the queue auto-resumes orphaned jobs at startup, fires the
  buggy code path, dies before painting a window. v0.16.2's
  NLEmbedding lock and v0.16.3's eager Sparkle check were both
  misdiagnoses on my part; the actual race was never NLEmbedding.

## 0.16.3 — 2026-05-19

**Update reliability**
- Force a Sparkle background appcast fetch on every launch. The default
  schedule defers the first check by a few minutes and then waits 24 h
  between checks — long enough that a user who relaunches a buggy build
  several times in a row might never see the update prompt. Now the
  prompt fires the moment a fix is available, even if the previous
  check was minutes ago. Silent when there's nothing to install.

## 0.16.2 — 2026-05-19

**Crash fix**
- App could abort mid-flight when two embedding consumers ran at the
  same time — typically the post-recording indexer and the
  re-processing re-index, or Ask + re-index. Apple's
  `NLEmbedding.vector(for:)` shares a cached singleton internally and
  isn't thread-safe; concurrent calls trip Swift's exclusive-access
  check inside CoreNLP / BNNS and `abort()` the process. Serialized at
  the framework boundary with a process-wide lock.

## 0.16.1 — 2026-05-18

**Re-processing resumes after interruption**
- The high-accuracy re-transcription pass now checkpoints after every
  chunk. If a job is interrupted — a new recording starts (yield), the
  app is restarted, or the user cancels and re-enqueues — it picks up
  from the next un-done chunk instead of restarting from zero. Progress
  is persisted to a sidecar `reprocess-checkpoint.json` in the meeting's
  recording directory; gets cleaned up automatically on success, user
  cancel, or meeting deletion.

**Interview lifecycle / recovery**
- **End Interview** button on the scorecard toolbar. Previously the only
  End control lived in the live header — unreachable when status was
  stuck at `.recording` with no live recording. Routes through a new
  `markInterviewComplete(_:)` that handles both the live path and the
  zombie-row path.
- **Resume Interview** button replaces the misleading "In Progress"
  badge when status is `.recording` but the audio engine is idle (post
  app-restart or crash). Without it the live phase board was
  unreachable and there was no path forward.
- App-launch orphan cleanup reverts any Interview row stuck in
  `.recording` back to `.scheduled`, so the regular Start button comes
  back naturally.
- Resume reuses `interview.meeting` instead of creating a fresh one —
  prevents the original audio + segments from being orphaned and stops
  foreign transcripts from landing on the interview's now-empty meeting.

**Multi-phase rescore**
- "Score All Sections" now actually scores all phases. The old path
  hard-gated on `interview.rubric` (the legacy single-rubric field,
  typically nil for multi-phase interviews) and would only ever score
  one phase. Rewritten to iterate `interview.orderedPhases` and score
  each phase's sections against the segments tagged with that phase.

**UI regressions fixed**
- Rubrics / Templates / Candidates / Test tabs stay reachable during a
  live interview. The full tab picker was previously hidden the moment
  recording started, with the Interviews tab being the only one that
  swaps to the live layout.
- Settings sidebar (General, Audio, AI, Ask, Vocabulary, Organization,
  Interview, Obsidian, Developer) is now always visible. The nested
  NavigationSplitView was collapsing its inner sidebar in some layouts,
  hiding Developer behind a chevron toggle most users wouldn't think
  to click.

**Phase-alert sounds**
- Per-threshold sound pickers (First warning / Second warning /
  Overtime) in the Interview settings tab, with a preview button for
  each. Choose from the 14 macOS system sounds. Defaults unchanged
  (Tink / Hero / Funk).

## 0.16.0 — 2026-05-15

**Phase time-box alerts**
- Per-phase countdown pill in the live interview view — shows
  `MM:SS left` at the top of the active phase, tinted green → orange →
  red as you burn through the budget. Once the clock runs out, the pill
  flips to `+MM:SS over` and flashes red so it can't be missed while
  you're focused on the candidate.
- Threshold alerts fire at 5 min remaining, 1 min remaining, and at
  overtime. Each one shows an in-app banner at the top of the live view,
  plays a system sound (`Tink` / `Hero` / `Funk`), and writes an entry
  to the Activity Log. Phases without a `targetMinutes` budget (intro,
  ad-hoc discussion) stay silent — no pill, no alerts.
- New **Interview** tab in Settings: toggle each alert independently,
  customize the lead-time minutes (1–30 for the first warning, 1–10 for
  the second), and silence the sound entirely.

**Interview scheduling**
- The interview-creation modal now has a "Scheduled for" date+time picker
  in the footer next to the Schedule button — defaults to the top of the
  next hour. Backed by a new `Interview.scheduledAt` field (SchemaV14,
  lightweight additive migration).
- The Interview list now shows the planned slot (with a 📅 glyph) when
  one was picked; older / ad-hoc interviews keep showing their creation
  timestamp.

**Candidate brief**
- The brief panel is now collapsed by default everywhere it appears
  (live phase board, scorecard phase plan). The header still shows
  Copy and Export-PDF buttons even when collapsed — so you can hand the
  prompt to the candidate mid-interview without having to expand and
  scroll past it first.

**Roles UI wording**
- Department / Team pickers say "All" / "All Teams" instead of "None" for
  the nil option — matches what the value actually means (the role isn't
  scoped to a specific department / team). The Roles browser's group
  headers follow suit: "All Departments" / "All Teams".

## 0.15.1 — 2026-05-13

**Rubric editor**
- Section-weight dividers are draggable again. The handles were rendered
  with `.position`, which silently makes a view claim its parent's full
  size — every handle was secretly sized to the whole bar, fighting for
  hit-tests, and the Form's ScrollView was eating the first drag event
  anyway. Switched to `.offset`, gave the hit area a non-transparent
  fill (clear views aren't reliably hit-testable on macOS), and bumped
  to `.highPriorityGesture` so the Form can't intercept.

## 0.15.0 — 2026-05-12

**Organization settings — Roles**
- The Roles list is now a browsable hierarchy instead of a flat list:
  roles group under their Department, and within a department under their
  Team (with a "— no team —" group, and a "No department" group for
  unassigned roles). Each department is a collapsible section with a
  role-count badge.
- A filter field at the top searches role titles, levels, teams, and
  departments — matching groups auto-expand. "Expand all" / "Collapse
  all" for bulk control.
- Click a role to expand an inline detail card: change its
  department / team / level / custom title in place, and see which
  rubrics (with their strictness) and templates are linked to it. Delete
  is in there too. Newly-added roles auto-expand and select so you land
  right on them.

## 0.14.0 — 2026-05-11

**Interview scorecard**
- Overall assessment now sits at the top of the scorecard — it's the
  headline, so it leads.
- Copy buttons on the assessment, strengths, weaknesses, and red-flags
  sections (and the text is selectable). One click to drop the AI's
  write-up into your notes / ATS / email.
- "Scored …" indicator in the scorecard header shows when the AI last
  ran (relative, with the exact timestamp on hover).
- Impressions are editable from the scorecard — tap a dot on the "You"
  row to set a trait you forgot to rate during the interview.

**Interview scoring**
- AI section scoring at interview end actually produces grades now. The
  end-of-interview pass was falling through to the live analyzer's
  intro/conclusion branch, which returns an empty score set — so a short
  interview (or one where the live loop never got a turn) finished with
  every AI grade blank. The final pass now scores every section directly
  from the transcript regardless of what the live loop accumulated.
- Sections that weren't covered are graded **F**, not left blank. A phase
  that was skipped or never reached, or a section the transcript never
  touched, now shows an F with a rationale ("This phase was not conducted
  …" / "Not discussed …") instead of an empty "—". An interviewer grade
  always wins; this only fills in genuinely ungraded sections.
- "Score All Sections" is more robust to the model echoing back a wrong
  `section_id` — the single-section pass now attributes the result to the
  section it asked about instead of dropping it on the floor.
- Phases that were planned but never started no longer get scored against
  the whole transcript — they're marked incomplete instead.

## 0.12.0 — 2026-05-11

**Recording**
- Mic-silence auto-pause no longer fires while you're just listening to a
  meeting. It used to watch only the microphone, so a quiet stretch where
  the meeting audio was playing but you weren't talking would pause *both*
  streams and lose the meeting capture. It now also requires the system
  audio to have been silent — a real device fault (mic permission revoked,
  hardware mute, input volume at zero, another app holding the mic) still
  pauses and notifies; "you're listening" does not.

**Changelog viewer**
- Rebuilt as a two-pane browser. The left rail lists every release, newest
  first, with an unread dot on versions you haven't read yet and an "N new"
  badge in the header. The right pane shows the selected release's notes on
  their own — no more scrolling through one giant blob to find what changed.
- Read tracking: scroll to the bottom of a release's notes and it's marked
  read. Short releases that fit without scrolling mark themselves read.
  There's a "Mark all read" shortcut in the rail header if you want it.

## 0.11.0 — 2026-05-08

**Interview — live phase board**
- The live phase view now shows *every* rubric section of the active phase
  at once, as compact cards (it used to surface one section at a time). The
  candidate brief sits once at the top and collapses; AI-vs-interviewer
  grade disagreement is flagged; each criterion expands inline to show its
  evidence quotes, and tapping a quote jumps the transcript.

**Interview — notes panel**
- Rebuilt around the active phase. A phase banner sits up top; the composer
  is a multi-line field, auto-focused when you switch to the Notes tab.
  Keyboard-first sentiment: `↩` neutral, `⌘↩` "wow", `⇧↩` red-flag, `⇥`
  toggles "next note is a sub-note". Past phases collapse below a divider;
  the Notes tab badge counts notes for the active phase.

**Recording**
- Vocabulary booster actually works now. The per-term boost slider was
  stored but never read by the rescorer; it's now used as the term's
  context-biasing weight, and the string-similarity floor relaxes for
  high-boost terms so near-homophones (e.g. "Erin" ↔ "Aaron") can win.
- The elapsed-time timer runs in `.common` run-loop mode so it keeps
  ticking while a SwiftUI menu is open — opening a phase-icon dropdown
  used to freeze the timer and look like a recording pause.

**Internal**
- Shared `CriterionStatus` icon/colour styling; rubric-section and
  criterion-evaluation lookups moved onto the view model.

## 0.10.0 — 2026-05-07

**Interview templates (V9)**
- New `InterviewTemplate` concept: a reusable, named, role-scoped plan
  that composes rubrics into the loop you actually run. Distinct from
  rubrics (which define *what* to evaluate). Templates live under a new
  Templates hub tab.
- New interview creation modal launched from the Interviews tab (+
  button or ⌘N). Two-pane layout: template rail on the left (Recent /
  Templates / Role-linked rubrics palette), editable phase pane on the
  right. Drag a rubric from the rail onto the phases; click a template
  to adopt its phases as the spine, then add/remove/reorder freely.
- "New Interview" tab removed — creation lives in the modal.
- Default templates seeded on first run: Standard Interview, Backend
  Loop, Frontend Loop. Rubric refs resolve via fuzzy name match against
  the user's existing rubrics.
- Scorecard header shows "scheduled from template X" when applicable.
- Per-phase target minutes (soft time-box) are part of the template and
  carry through into scheduled phases.

**Interview workflow**
- Per-phase scorecard. Each phase (Intro / System Design / etc.) gets its
  own card with a composite grade and its rubric sections nested inside.
- Dual AI + human impressions. `InterviewImpression.aiValue` is a separate
  field; the AI no longer clobbers the interviewer's manual rating. The
  live strip and scorecard render solid dots for "You" and hollow for "AI".
- Phase-tagged notes. Each note inherits the active phase; the live notes
  panel groups by phase header.
- Per-phase icon picker (`InterviewPhase.iconName`, curated catalog) so
  System Design / Coding / Take-home are glance-distinguishable.
- Two-stage interview start: "Ready to interview" schedules without
  recording; "Start Interview" on the scorecard begins capture.
- Candidate brief at the rubric (phase) level, with a markdown editor
  (formatting controls + live preview), plus Copy and PDF export.
- Resume summarization + DnD-style character sheet driven by AI;
  resume↔interview contradictions surface as red flags during scoring.
- Many-to-many Rubric ↔ Role with per-link strictness metadata.
- Test tab rescores past interviews against any rubric (was meeting-based).

**Recording**
- Mic-silence auto-pause no longer trips spuriously across 30s windows —
  the check uses the just-computed window average and requires at least
  one buffer. (Further hardened in 0.12.0.)
- Configurable audio retention: auto-deletes audio files for completed
  meetings older than the configured threshold; transcripts always stay.

**Settings / misc**
- Developer Settings: database size reads the actual ModelContainer config
  URL instead of guessing; schema version is read live.
- Help menu surfaces README, CONTRIBUTING, CHANGELOG, and the MIT LICENSE
  inside the app.
- Schema migrations through V8: rubric brief moved from section to rubric;
  AI impression value; per-note phase; per-phase icon. All lightweight.

## 0.9.x

- Stable mic + system audio capture and on-device transcription.
- Activity Log surfaced in the sidebar; idempotent seeders.
- Sparkle auto-update wired with sandbox-friendly entitlements.
- Obsidian vault export.
- Initial interview / rubric / candidate flow.

## Earlier

Pre-0.9 work covered the core foundations: SwiftData store + versioned
schemas, FluidAudio diarization, WhisperKit transcription, Claude API
client and prompt scaffolding, NavigationSplitView shell with inspector
panel.
