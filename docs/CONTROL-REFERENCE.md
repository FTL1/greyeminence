# Controls and options

Hover any control for a short **what / how / why**. This page is the full version. Same text: GitHub `docs/CONTROL-REFERENCE.md`.

**Help → Send feedback…** files a GitHub issue as **text only** by default (pane + what you want). Screenshots and meeting content stay off unless you opt in. The app never uploads a picture.

---

## Capture bar (top of the main window)

| Control | What | How | Why |
| --- | --- | --- | --- |
| **Watch for meetings** | Wait for a real call, then record it. | Polls whether Zoom, Teams, Meet, Slack, Webex, or FaceTime is holding the mic. After ~10s it starts. Discord **asks** first (notification) because a voice channel holds the mic even when nobody is talking. | So you do not capture this Mac all day. Idle captures **no** microphone and **no** system audio. |
| **Live AI** | Rolling analysis while you record. | ~30s after start, then about every 45s, the current transcript (and screen-share notes) go to the provider in **Settings → AI**. Updates summary, actions, questions, topics. | Live notes during the call. **Not** the transcript — that always runs on this Mac. Uncheck to skip API spend; use **Reanalyze** later. Stays on for the whole recording (it used to die at 90 minutes). |
| **Stop all** | Hard stop. | Ends recording, cancels Live AI, turns Watch off. | Forgotten windows will not keep capturing or burning tokens. |
| Idle label **Waiting for a call** / **Not watching** | Status of Watch. | No audio until a meeting starts or you hit Record. | Confirms you are not recording silence. |

**Auto-stop.** Any recording stops after **4 hours**. An **auto-started** recording also stops after **20 minutes of silence**, or ~**60 seconds** after the other app releases the mic. If you **manually stop** mid-call, Watch will not restart on that same call.

Same Watch switch: **Settings → General**.

---

## New Recording

| Control | What | How | Why |
| --- | --- | --- | --- |
| Calendar chip | Which event this recording is. | Pick a nearby event, or **Not a calendar meeting**. Drives title, invitees, People bar. | So we do not guess silently. |
| Prep card | Notes before you record. | Shows when there is a linked event with useful context. | Reminds you what the meeting is for. |
| **Start Recording** | Manual start. | Red button or **⌘R**. Independent of Watch. | You start when you mean to. Lawful use only. |

---

## Recording toolbar (while capturing)

| Control | What | How | Why |
| --- | --- | --- | --- |
| **Record** | Start. | Same as Start Recording. | One click from the toolbar. |
| **Pause** / **Resume** | Hold the meeting open without capturing. | Pause stops audio; Resume continues the same file. | Bathroom / sidebar without splitting the meeting. |
| **Stop** | End and save. | Writes the meeting into this library. | Normal end of a call you started yourself. |
| Timer | Elapsed time. | Wall clock for this recording. | See the 4-hour cap coming. |
| Mic meter | Your voice. | Level of the microphone seat (Me). | If this is dead, grant Microphone to *this* copy. |
| Speaker meter | Everyone else. | System audio (Teams/Zoom through the speakers). | If this is dead, grant Screen & System Audio Recording. |
| Line count | Transcript lines so far. | Local ASR, not Live AI. | Confirms capture is producing text. |
| **Link event** | Calendar attach mid-call. | Nearby events ±1 hour. Change or unlink. | Late join / wrong auto-match. |
| Screen-share indicator | Shared-window stills. | Settings → Screen Share must be on. | Vision notes for slides, not a movie of the call. |
| AI activity | Live AI state. | Waiting / analyzing / idle. | See whether the API is running. |

---

## People bar (the room)

| Control | What | How | Why |
| --- | --- | --- | --- |
| Colored chip | A person who has spoken. | **Click** hide/show (grey = off). **Right-click** assign, tag lines, enroll voice print, lock, remove. | Mixer for who is in the transcript. |
| **you** | The Mac microphone. | Locked. Voice prints do not decide Me. | You stay you. |
| Talk % | Share of talk time. | Only people who have spoken. | Who is dominating. |
| Lock | Freeze that ID. | Click the lock. Unlock to retag. | Stops speaker-2 from stealing Pat. |
| Dashed **speaker-1** | Heard, not named. | Right-click → **This is Pat** merges the whole voice onto that seat. | First remote line before you tag them. |
| **+** | Pre-add a person. | Type a name or pick a contact. | Invitees you expect. Still starts as speaker-1 until you assign. |
| **Show all** | Unhide everyone. | One click. | After you hid people to read one voice. |

Calendar **Alex Morgan** and Me **Alex you** are the same chip.

---

## Sidebar

**⌘S** collapses it. Hover an icon for its name.

| Item | What | How | Why |
| --- | --- | --- | --- |
| **Dashboard** | Counts. | Cards are buttons to Meetings or Tasks. | Glance, then jump. |
| **Ask** | AI search. | Needs indexed transcripts and an API key. | Questions in prose. Not Find. |
| **Find** | Library search (⇧⌘F). | Name, speaker, dates, transcript and/or intel. Regex optional. | Ordinary find. ⌘F is this meeting only. |
| **New Recording** | Capture. | Watch, Live AI, Record. | Where a call starts. |
| **Meetings** | Recent list (~3 months), minus filed items. | Group by date, series, or related. | Day-to-day library. |
| **Archive** | Whole library. | Export zip / one PDF / one PDF per meeting. File away / put back. | Last week’s Exec series is here. |
| **Interviews** | Candidates and rubrics. | Separate from ordinary meetings. | Hiring scorecards. |
| **People** | Contacts and voice prints. | Enroll from a chip; archive inactive. | Who is who next week. |
| **Insights** | Intelligence across meetings. | Open a meeting’s intel from here. | Not buried in one recording. |
| **Questions** | Follow-ups rolled up. | Create, copy, organize. | What is still open. |
| **Tasks** | Action items. | Default: analyzed meetings, **your** tasks. | Company to-do from calls. |
| **Summaries** | Write-ups. | Browse and copy. | Formatted paste into Teams. |
| **Topic Map** | Topics as dots. | List: Topics / People / Speakers. Click a person to light their topics. | Themes, not a calendar. |
| **Activity Log** | Developer diagnostics. | Settings → Developer tools. | When something breaks. |
| **Settings** | Keys, audio, calendar, profile. | Also Grey Conseil → Settings. | One place for identity and APIs. |
| Toolbar **Find** | Library Find. | ⇧⌘F. | Same as sidebar Find. |
| Toolbar **Insights** | Inspector. | Show/hide beside a meeting. | Transcript + intel side by side. |

---

## Meeting header

| Control | What | How | Why |
| --- | --- | --- | --- |
| Title | Session name. | Click (or double-click in the list) to rename. Return saves, Escape cancels. | So “Exec series” is the name you want. |
| **⌘F** | Find in this meeting. | Tick **Transcript** to jump lines. ⌘G / ⇧⌘G. | This meeting only. |
| **Upgrade to large-v3** | Better transcript. | WhisperKit large-v3 in the background. First run ~1.5 GB download. | Live capture uses a fast model. |
| **Index for search** | Ask index. | If Ask cannot see this meeting. | Recovery when the post-record index failed. |
| Export / dossier | Stored intel out. | Click last format; arrow for dossier / series / one-pagers. | Chatbot pack of **stored** facts — no hallucination. |
| Attendees row | Invitees. | From the linked calendar event. | People bar seats. |

---

## Meetings and Archive

| Control | What | How | Why |
| --- | --- | --- | --- |
| **Group** | How the list piles. | Date, Series, or Related (shared first two words). | Exec series in one bucket. |
| **Export…** | Bulk transcripts/intel. | Zip, one PDF (page break per meeting), or one PDF per meeting. Optional audio/stills/time-lapse stay in the zip. | It was labeled Extract; it is an export. |
| **Archive Meeting** | File away from recent. | Right-click or selection bar. | Keep Meetings short. |
| **Put Back on Meetings** | Restore to recent. | If it is still in the three-month window. | Undo filing. |
| **Reanalyze** | Run AI again. | One, selected (⌥⌘R), or all. One at a time. | After you fix speakers or switch to Grok. |

---

## Tasks, Questions, Summaries, Topic Map, Ask, Find

| Control | What | How | Why |
| --- | --- | --- | --- |
| Tasks **Meetings** menu | Which meetings. | All analyzed, selection, series, calendar name. | Filter like a human. |
| Tasks **Assigned** menu | Whose tasks. | Me (default), Me + unassigned, Others, Everyone. | Your list first. |
| Tasks search / **Find** | Text find. | Not a chatbot. May ask to analyze first. | Ordinary search. |
| **Reset** | Default filters. | Analyzed + mine. | Back to start. |
| **Export** | Copy or file. | CSV / Excel / RTF / PDF. | Paste into Mail or Notes. |
| **Group** | Pile tasks. | Status, meeting, date, series. | Scan stalled vs new. |
| Questions **Copy** | Clipboard. | Visible questions. | Share the open list. |
| Topic Map list | Browse mode. | Topics, People, Speakers. | Same map, different door. |
| Topic Map refresh / reset | Rebuild or reset view. | Refresh from meetings; reset zoom. | After new analysis. |
| Ask | AI Q&A. | Needs index + API key. History in the pane. | Prose questions. |
| Find regex | Pattern match. | Example: `cabinet.?count`. | Power search. |
| Find speaker menu | Limit to a voice. | Speakers heard in scope. | “What did Jordan say.” |

---

## Settings → General

| Control | What | How | Why |
| --- | --- | --- | --- |
| **My Profile** | Who you are. | People contact that is you. | Tasks “Assigned to Me”, talk-share. |
| **My display name** | Default mic label. | Instead of “Me”. Per-meeting rename can override. | Alex, not Me. |
| **Launch at login** | Open the app. | Does not start recording. | Ready without a click. |
| **Show menu bar icon** | Extra in the menu bar. | Record/Stop from there. | When the window is buried. |
| **Text size** | UI scale. | Extra small → extra large. | Readability. |
| **Auto-merge same-speaker fragments** | Join crumbs. | After the meeting, not live. Window and pause pickers. Undo in transcript ⋯. | Fewer one-word lines. |
| **Watch for meetings** | Same as the capture bar. | See above. | One switch, two places. |
| **Auto-delete audio** | Retention. | Audio files only; transcripts stay. Sweep at launch. | Disk. |
| **Stalled threshold** | Task age flag. | Default 7 days. | Orange group in Tasks. |
| **Check for Updates** | Sparkle. | **FTL1/grey-conseil** only. Never Grey Eminence’s feed. | This fork’s DMGs. |

---

## Settings → Audio

| Control | What | How | Why |
| --- | --- | --- | --- |
| **Input device** | Which mic is you. | Built-in or headset. | The Me seat. |
| **Input gain** | Boost. | 0.25×–4×. Turn down if you clip. | Quiet rooms vs headsets. |
| Level LEDs | Mic loudness. | dBFS, not a linear 0–1 bar. | Speech should light more than one LED. |
| **Capture system audio** | Other people. | Needs Screen & System Audio Recording (Tahoe combined pane). | Remotes are not on your mic. |
| **Re-transcribe after recording** | large-v3 pass. | Background; pauses while you record again. First run ~1.5 GB. | Live ASR is fast; this is accurate. |
| Storage path | Where files live. | `~/Library/Application Support/com.ftl1.greyeminence/Recordings` | Bundle ID on purpose — do not rename it. |

---

## Settings → Calendar

| Control | What | How | Why |
| --- | --- | --- | --- |
| **Auto-detect calendar events** | Mac calendars. | EventKit / Internet Accounts. Local. | Name the recording, fill invitees. |
| Per-calendar toggles | Which calendars match. | Uncheck noise calendars. | Avoid birthday spam. |
| Microsoft client ID | Entra app. | Paste, then **Connect** / **Validate**. | Outlook/Teams when not synced to the Mac. |
| **Connect** / **Disconnect** | Graph login. | PKCE in-app. Read-only calendar. | Direct Outlook feed. |

---

## Settings → AI

| Control | What | How | Why |
| --- | --- | --- | --- |
| **Provider** | Who answers. | Anthropic, Bedrock, or **xAI (Grok)**. This picker is live for the **whole app**. | One brain at a time. |
| API key | Secret. | Save to Keychain; **Validate** tests that provider only. | Keys never go to Matt or this repo. |
| Model / timeout | Which model and how long. | Auto ~4 min Grok / ~2 min Claude. Raise it and Reanalyze **once**. | Long Exec series calls. |

---

## Settings → Screen Share

| Control | What | How | Why |
| --- | --- | --- | --- |
| **Capture shared screens** | Stills of a share. | Teams popped-out share, Discord popped-out/fullscreen. | Slides in the notes. Not a camera movie. |
| **Auto-detect share windows** | Find the window. | Off: **Choose Window** on Record. | Electron/Teams sometimes needs a manual pick. |
| Interval | How often. | Unchanged frames are dropped. | Disk and API cost. |
| Analyze frames | Vision on stills. | Uses the active AI provider. | Describe what was on screen. |

---

## Settings → Developer

| Control | What | How | Why |
| --- | --- | --- | --- |
| **Enable developer tools** | Extra UI. | Activity Log, transcript debug. | Ordinary use can leave this off. |
| **Dev Mode (verbose log)** | Diagnostics. | Clicks, AI errors, capture. **Export debug log…** | Send JSON with a sentence about what you clicked. |
| **Permissions** | Health of grants. | Mic, screen, system audio, calendar, contacts, keys, Sparkle feed. Only the **active** AI provider is required. | After a new ad-hoc DMG. |
| **Edit AI Prompts** | Override templates. | Next AI call. Clear to restore defaults. | Experiments. |

---

## Help menu

| Item | What |
| --- | --- |
| **What's New** | Short trailer after an update. |
| **How to use Grey Conseil** | Step-by-step support guide. |
| **Controls and options** | This page. |
| **What's in Grey Conseil** | Catalog of Grey Conseil extras. |
| **Why Grey Conseil** | Name: *éminence grise* + Verne’s Conseil. |
| **How we differ from Grey Eminence** | Divergence map. Not a second Grey Eminence. |
| **Disclaimer** | No warranty; lawful use only. |
| **Send feedback…** | GitHub issue, **text only by default**. Optional screenshot is saved on this Mac; the app does not upload it. Emails/phones in the text are scrubbed. |

---

## Keyboard

| Key | What |
| --- | --- |
| **⌘R** | Start Recording. |
| **⌘F** | Find in this meeting. |
| **⌘G** / **⇧⌘G** | Next / previous find hit. |
| **⇧⌘F** | Library Find. |
| **⌘S** | Collapse/expand sidebar. |
| **⌘E** | Obsidian export (if a vault is set). |
| **⌥⌘R** | Reanalyze selected meetings. |

---

## What this app will not do

- Capture the mic while Watch is waiting and no call is in progress.
- Send recordings to grok.com or X. The Grok **library** is on this Mac for Grok TUI.
- Update from Matt’s Sparkle feed.
- Open or mix Matt’s Grey Eminence library.
- Auto-upload screenshots or transcripts when you send feedback.
