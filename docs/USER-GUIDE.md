# Grey Conseil — how to use every extra we added

This is the **support guide** for people using the app, not for programmers.

**Grey Conseil** is an unofficial test copy of Matt Purdon’s meeting app. It records meetings on your Mac, types out what was said, and asks AI to write a summary and a to-do list.

Matt’s shipping app is still named **Grey Eminence**. This copy is named **Grey Conseil** so both can sit in Applications at the same time. **Do not replace Matt’s app with this one.**

A one-page list of what shipped: [FEATURES.md](FEATURES.md). Every control: [CONTROL-REFERENCE.md](CONTROL-REFERENCE.md) or **Help → Controls and options**. How this fork relates to Matt’s code: [ORIGIN.md](ORIGIN.md).

Latest test build: **0.28.4-ftl51**.

**New in this build:** Hover any control for what / how / why. Help → Controls and options is the full page. Help → Send feedback… files a GitHub issue as text only (screenshot off by default).

---

## Table of contents

1. [Install the Grey Conseil app next to Matt’s](#1-install-the-grey-conseil-app-next-to-matts)
2. [First launch: tell it who you are](#2-first-launch-tell-it-who-you-are)
3. [Turn on Grok (xAI) for summaries](#3-turn-on-grok-xai-for-summaries)
4. [Give analysis more time, or pick a custom Grok model](#4-give-analysis-more-time-or-pick-a-custom-grok-model)
5. [Speakers: People bar, tagging, voice prints](#5-speakers-people-bar-tagging-voice-prints) (includes [who is Me](#who-is-me-vs-a-guest), [hide / show](#hide--show-a-speaker), [export transcript](#export-the-full-transcript), [Copy into Teams](#copy-a-summary-into-teams))
6. [Meetings list: group by date, series, or related names](#6-meetings-list-group-by-date-series-or-related-names) (includes [extract](#extract-transcripts-and-intel))
7. [Reanalyze one meeting, several, or all of them](#7-reanalyze-one-meeting-several-or-all-of-them)
8. [Intelligence in the left sidebar](#8-intelligence-in-the-left-sidebar)
9. [Tasks: roll up, filter, search, and export](#9-tasks-roll-up-filter-search-and-export)
10. [Analyze meetings that still have no tasks](#10-analyze-meetings-that-still-have-no-tasks)
11. [Dashboard numbers are buttons](#11-dashboard-numbers-are-buttons)
12. [Topic map: topics, people, speakers, and actions](#12-topic-map-topics-people-speakers-and-actions)
13. [Hover on an icon for its name](#13-hover-on-an-icon-for-its-name)
14. [Dev Mode when something breaks](#14-dev-mode-when-something-breaks)
15. [Keyboard shortcuts](#15-keyboard-shortcuts) (includes [Find vs Ask](#find-vs-ask))
16. [What this fork does not do](#16-what-this-fork-does-not-do)
17. [If something looks empty or wrong](#17-if-something-looks-empty-or-wrong)

---

## 1. Install the Grey Conseil app next to Matt’s

**What it is.** A separately named Mac app: **Grey Conseil**. Different name, different identity (`com.ftl1.greyeminence`), its own library of meetings. It can live in Applications next to production.

**Why we built it this way.** So you can try new features without touching Matt’s database, recordings, or auto-update feed. If Grey Conseil misbehaves, production is still there.

**How to install it**

1. First time: GitHub **Releases** → `GreyConseil-0.28.4-ftl51.dmg`. After that, **Check for Updates**.
2. Open the DMG and drag **Grey Conseil** into Applications. Remove **older Notebook** or **older test builds** if those icons are still there (same library).
3. Leave **Grey Eminence** (Matt’s) installed if you already use it.
4. Open **Grey Conseil**. Accept the legal notice. Grant microphone, and contacts / calendar if the Mac asks.

**How to tell which app you are in**

- Menu bar name: **Grey Conseil**
- Help menu: **What's New in Grey Conseil**, **What's in Grey Conseil**, and **Grey Conseil extras**
- Settings → AI includes **xAI (Grok)**
- About / version looks like `0.28.4-ftl51`
- **Check for Updates** is in Settings → About and the app menu

**Important safety rules**

- Do **not** replace Matt’s app with this one.
- Do **not** copy this fork's library on top of production, or the other way around.
- Do **not** symlink the two libraries together.
- When a new Grey Conseil DMG arrives, just replace the **app**. Leave this library where it is. You do not need to recopy meetings each time.

**Outlook / Microsoft 365 calendar.** Settings → Calendar already has two sources: calendars synced to the Mac (including Outlook if that account is in System Settings → Internet Accounts), and **Connect Microsoft 365** for a direct Outlook/Teams feed. That Connect button stays hidden until an Entra app client ID is pasted in `GraphConfig.swift` — same as Matt’s app.

Grey Conseil keeps recordings under Application Support for `com.ftl1.greyeminence`. Production stays in its own container. This build is **not sandboxed** so it will launch on macOS Tahoe. **Check for Updates** uses github.com/FTL1/grey-conseil — never Grey Eminence’s Sparkle feed.

Needs **macOS 14.4+** and an **Apple Silicon** Mac. Ventura is out of scope.

---

## 2. First launch: tell it who you are

**What it is.** A “Who are you?” sheet so the app knows which person in a transcript is you.

**Why.** In Matt’s app the local mic often shows up as a generic **Me**. In Grey Conseil, that speaker should be your real name (for example **Alex**). Tasks that are assigned to you, talk-time, the People bar, and the topic map all work better once the app knows who “me” is.

**How to use it**

1. On first launch, the sheet **Who are you?** appears.
2. Type your name (and email if you want), or pick an existing contact.
3. Click **Save**.
4. If you skipped it, open Settings and complete **My Profile** later.

After that, your lines in a transcript should be labeled with your name, not “Me.” You appear on the People bar as **you**.

You can also right-click a speaker later and choose **Set as Me**, or rename yourself and click **Save as default name**.

---

## 3. Turn on Grok (xAI) for summaries

**What it is.** Meetings can be summarized and turned into action items by **Grok** (xAI), not only Claude or AWS Bedrock.

**Important distinction.** SuperGrok / SuperGrok Heavy is an **account tier** on the xAI website (limits and which models you can buy). The app does **not** log into that. It needs an **xAI Console API key**. Usage is billed per token in the Console.

**How to get a key**

1. Open [https://console.x.ai](https://console.x.ai) in a browser.
2. Create an API key. It usually starts with `xai-`.
3. Keep it somewhere safe. You will paste it once into the app.

**How to turn Grok on**

1. In **Grey Conseil**, open **Settings → AI**.
2. Set **Provider** to **xAI (Grok)**.
3. Read the note under the picker: this switch is live. **Every** AI feature in the app uses the provider you just picked. Validating a key on Claude does not keep Claude active if the picker now says Grok.
4. Paste the key in the **xAI API Key** field.
5. Click **Save to Keychain**.
6. Click **Validate**. You want a success check, not an error.
7. Pick a model:
   - **Grok 4.6 (flagship)** — default
   - **Grok 4.5**
   - **Custom model ID** — paste any ID the Console lists (see the next section)

Then record as usual, or use **Reanalyze** on a meeting you already have.

The Settings page also links to the xAI Console, the API keys page, and the quickstart if you need them later.

---

## 4. Give analysis more time, or pick a custom Grok model

**What it is.** Two extra controls on the same **Settings → AI** page.

### Analysis timeout

Long transcripts can take more than a minute. The old default often failed with a timeout.

**How to use it**

1. Stay on **Settings → AI**.
2. Open **Analysis timeout**.
3. Choose:
   - **Auto** — about **4 minutes** for Grok, **2 minutes** for Claude / Bedrock
   - **2 minutes**, **4 minutes**, **6 minutes**, or **10 minutes**

If a run times out, you get **one** error. The app does **not** retry three times. Raise the timeout and click Reanalyze once.

### Custom Grok model ID

Use this when Console lists a model that is not in the picker (for example a Heavy model ID).

**How to use it**

1. Set **Model** to **Custom model ID**.
2. Paste the exact ID from the Console (the placeholder mentions `grok-4-heavy`).
3. The custom ID is only sent when that field is not empty.

Remember: SuperGrok Heavy is still an account tier. If Console shows you a Heavy model, put **that model’s ID** here. Typing the words “SuperGrok Heavy” will not work.

---

## 5. Speakers: People bar, tagging, voice prints

**What it is.** Each voice in the transcript is a speaker. Grey Conseil treats **people** (who you expect) and **detected voices** (what the diarizer heard) as two different things, then lets you bind them.

### Who is Me vs a guest

- **You** = the **Mac microphone**. Every mic line is Alex (or your profile name). That is a channel rule, not a voice print.
- **Everyone else** = the **meeting app** (Teams is the usual case) coming out of the speakers, captured as system audio. That mix has no live “Pat is talking” tag from Teams.
- **Calendar invitees** land on the People bar before anyone speaks.
- **Voice prints** name remotes after they talk (or on the next meeting). A name you lock or type **wins** over a later guess.
- Teams can later provide a speaker-labeled transcript (Graph VTT) if the tenant allows it. That is an after-the-call check, not live ID on your Mac.

### Default names

- You (the microphone) = your saved profile name, for example **Alex**, not a generic “Me.”
- Other people = **guest-1**, **guest-2**, **guest-3**, … not a pile of identical “Speaker” labels.

If an older recording lumped every remote person into one speaker, right-click that speaker and choose **Recover guest-1, guest-2… from audio**. The app listens to the saved audio and splits them. This can take a while.

### The People bar (the room)

A **People** bar sits across the top of **New Recording** (and above a finished transcript). It is who is here and who is talking.

| What you see | Meaning |
| --- | --- |
| Chip with your name + **you** | The microphone. Already locked. |
| Quiet chip (grey initials) | Expected (calendar or **+**), has not spoken yet. |
| Colored chip | This person has lines in the transcript. |
| Lock | That ID is committed for the rest of this recording. |
| Waveform | A voice print is saved on their People contact. |
| Dashed **guest-1** | Heard, not assigned yet. |
| Talk % on the chip (Alex 47%) | Share of talk time. Only people who have spoken. |

**Click** a chip to **hide or show** that person. Color = their lines are on. Grey = off. **Show all** next to the names turns everyone back on.

**Right-click** a chip (there is no chevron) for assign / tag lines / enroll / lock / remove.

**You** and calendar **Alex Morgan** are the same chip (one color, one %). **Jordan** and **Pat** stay two chips.

There is **no** separate attendees row on the live record screen. That was the same list twice.

At the top of the window: **Watch for meetings**, **Live AI**, **Stop all**. Hover each for a short what / how / why; full text is **Help → Controls and options**.

**Watch for meetings** does **not** record all day. It waits until Zoom, Teams, Meet, Slack, Webex, or FaceTime holds the mic, then starts (~10 seconds). Discord **asks** first, because a voice channel holds the mic even when nobody is talking. Idle captures no microphone and no system audio. Auto-started calls stop when the other app drops the mic (~60s), or after 20 minutes of silence, or 4 hours max.

**Live AI** is rolling Grok/Claude notes while you record (summary, tasks, questions, topics). The transcript still runs on this Mac. Uncheck Live AI to skip API spend until you Reanalyze. It stays on for the whole recording.

**Stop all** ends recording, cancels live AI, and turns off auto-start.

### A typical Exec series call

1. Open **New Recording**. You are already on the bar.
2. Pick the calendar event, or **+** Pat, Jordan, Sam, Riley. Quiet chips appear.
3. Hit Record. First remote line is usually **guest-1**.
4. Right-click the dashed chip → **This is Pat**. Every line of that voice **moves onto Pat’s seat** (same hide/show, same color).
5. Talk-share bars start to fill (Alex 47%, Pat 22%).
6. If one sentence lands on the wrong person: right-click the chip → **Tag lines as Pat**, click that line, **Done tagging**.
7. Click the **lock** on Pat’s name so later lines stay on them. Click again to unlock.
8. Right-click Pat → **Enroll voice print** so next week’s Exec series can tag them automatically.

If you still see **Alex you** and **Alex Morgan** as two chips with the same %, quit, install **ftl34+**, and reopen the meeting.

### Pre-tag and lock

1. **+** a name, **Choose contact…**, or start from a calendar event (invitees land as seats).
2. Recording still starts as guest-1 / guest-2 until you assign them. Pre-tag does **not** guess that the first remote voice is Pat.
3. **This is Pat** = whole voice, **merged onto that seat**. Hide/show and color follow Jordan, not a leftover guest chip.
4. Click the **lock** on a chip to freeze that person. Click again to unlock. Silent invitees stay unlocked.
5. **Tag lines as Pat** = this click only. Use that when two real people got one guest ID, or one sentence is wrong.

### Current and prior speakers (right-click)

Right-click a badge in the live or finished transcript.

- **This meeting** — people already on this call.
- **Prior speakers** — people with a voice print, a speaker alias, or earlier meetings.
- Waveform = print enrolled. Checkmark = this voice is already that person.
- **Link other contact…** — full People / Apple / Outlook directory.
- **Save as new contact** — disabled while the name is still `guest-1` or “Me.”

Click **Pat** in that list to tag this voice as Pat.

### Enroll a voice print

**What it is.** A short audio fingerprint stored on a **People** contact so later meetings can recognize them.

**How**

1. Tag the voice first if it is still `guest-N`.
2. Right-click the badge or the chip → **Enroll voice print**.
3. Wait. Live meetings use the in-memory print if they have spoken enough; otherwise the app listens to the saved recording (needs a few seconds of that person).
4. The contact now has a print. People list shows a waveform. The contact card can **Remove voice print**.

**Next meeting:** Grey Conseil loads enrolled prints when recording starts. A matching guest is labeled with that person’s name instead of a new guest-N.

**Rules**

- Enroll **Alex** from Alex’s menu to save your mic onto your profile.
- You cannot enroll an unnamed guest. Pick someone first.
- Enrolling again averages the new sample in (it gets better, it does not throw the old one away).
- This is **same session + later sessions** for that contact. It is not magic on a terrible speakerphone.

### Hide / show a speaker

**Click the People chip** to hide or show that person. **Color = on. Grey = off.** **Show all** next to the names turns everyone back on.

Right-click the transcript badge → **Hide this speaker** does the same. A dashed row says **Show Pat — N hidden lines**. **Click to show** on that stub **reveals that person** (it does not hide the other copy).

Hiding **Jordan** also hides **Jordan Hale** (and guest lines you assigned to him). Hiding **you** also hides a remote line still labeled with your name. The **first** comments are included — they used to stay visible.

Unassigned leftover voices (unknown-1 / guest-1) stay on so you can identify them. Then assign them: right-click → **This is Jordan**. Those lines join Jordan’s chip.

**Assigning after you hide someone:** only the lines still on screen change. Hidden speakers — including you — stay as they are. Select Visible, then Assign, or Merge.

**Play** on a line plays that line’s saved audio. A merged line plays the whole range of audio for that text, not only the first fragment. **Merge** (Select two or more lines) joins them into one. Finished meetings also **auto-merge** consecutive lines from the same person (Settings → Transcript). Undo that from the transcript **⋯** menu.

**Colors:** right-click a name → pick a swatch → **Lock this color**. Alex, Jordan, and Sam keep those colors in later meetings. If two people would share a color, the more common one keeps it.

If a remap goes wrong: **Undo speaker change** (last remap), **Revert speaker labels** (original names, text edits stay), or **Re-analyze speakers**. Re-analyze opens a sheet: tick who was actually on the call (voice stamps show a waveform). The saved audio is matched against those stamps. Anyone who does not match becomes **unknown-1**, **unknown-2**…. Select one or more unknowns and assign them to a known person, a contact, or a typed name. A voice stamp is saved onto that contact. You stay you. Undo and revert are in **⋯**.

### Right-click a speaker name

Works in the live transcript and in a finished meeting.

| What you see | What it does |
| --- | --- |
| **Talk time** | A percent bar: how much of this meeting they spoke. The People bar also shows the top two or three. |
| **Rename** | Type a name and click **Apply**. It sticks for this meeting. Different remotes stay different people. |
| **Save as default name** | Only on **you**. |
| **Rename inline…** | Edit the name directly on the transcript row. |
| **Search this speaker’s comments** | Type in the box. The menu **stays open**. Matches highlight, you jump to the nearest hit, “2 of 7 matches.” Chevrons walk hits. |
| **Hide this speaker** | Collapse their lines until you Show them. |
| **Show only this speaker** | Isolate: only their lines. Different from **click the chip**, which hides them. |
| **Set as Me** | This voice is you. |
| **This meeting / Prior speakers** | Assign this voice to someone already known. |
| **Link other contact…** | Full directory. |
| **Save as new contact** | Creates a contact from the current display name. |
| **Enroll voice print** | Saves this voice onto that person for later meetings. |
| **Recover guest-1, guest-2… from audio** | Only when the recording lumped every remote together. |

### Keeping the same person as the same guest

The live transcript used to stamp every new remote line as guest-1, then let a 10-second diarization chunk invent guest-2 for the same voice.

Grey Conseil now:

- Keeps the last remote name for about 12 seconds (Pat stays Pat).
- Merges lines only when they are the **same** person.
- Matches new diarization IDs to the session print and to enrolled contact prints.
- Will not replace a name you chose (Pat) with a fresh guest-N.

If an old recording still lumped everyone, use **Recover guest-1, guest-2… from audio** — that pass looks at the whole file at once.

**Tips**

- Rename or lock **before** you reanalyze if you want the new names in the summary and action items.
- Search is ordinary find-in-text, not a chatbot.
- If a locked person comes back as a new `guest-N`, assign that dashed chip to the same seat. Do not paint unless only that one line is wrong.

### Export the full transcript

**Where:** the small **Transcript** button on the finished meeting header, and again on the transcript toolbar.

**How**

1. Open the meeting.
2. Click **Transcript** to save in the last format you used (default is Plain Text).
3. Use the arrow to pick **Plain Text**, **Markdown**, **RTF**, **CSV**, **Excel**, or **PDF**, or **Copy Full Transcript**.

Suggested name: `North Campus Engineering Scope Review_20260818-47m-tr.txt`

Hidden/isolated filters in the window do **not** change the file.

### Export Meeting Intelligence

On the Meeting Intelligence pane, **Export** (click uses the last file type; arrow opens the menu).

**Dossier (new).** This is not the Settings prompt that *generates* Meeting Intelligence. It is a package of what is already stored.

1. **Create dossier…** — pick audience (Me, my boss / everyone, or one speaker), depth (Brief / Summary / Detailed), and what to include: written report (md, txt, pdf, docx, rtf, json), transcript, audio (.m4a), screen stills, and a **chatbot prompt pack**.
2. **One-pagers for everyone** — one zip: `_general.md` plus a short page per speaker, plus the prompt pack.
3. **Series dossier…** — same composer, with every meeting in the calendar series (or the same first-two-words family).

The zip looks like `…-dossier-boss.zip` or `…-onepagers.zip`. Upload `prompt/PROMPT.md` and `prompt/meeting.json` to a separate Grok. The prompt says **do not invent** — no extra diligence questions, no numbers that are not in the file.

Audio for one speaker concatenates that person’s time ranges. Other voices can still be heard when they overlapped. There is no movie of the call.

The Settings **Edit AI Prompts** screen is still how intelligence is *generated*. Reanalyze first if the on-screen summary is wrong; then export a dossier.

### Copy a summary into Teams

On **Summary**, **Follow-up Questions**, and **Action Items**, **Copy** puts HTML on the clipboard next to the plain text. Paste into Teams, Slack, Outlook, or Notes and you get real headings and lists instead of `1.` and `•`. Anything that only accepts plain text still gets the readable text.

PDF / HTML reports (Meeting Intelligence Export → PDF) lead with **open questions** in a callout, not buried under the summary.

Below the dossier items, the older single-file dump is unchanged:

1. Tick **All sections**, or pick Summary / Action items / Follow-up questions / Topics / Shared screens.
2. Optionally tick **Raw transcript**. **De-dupe transcript** stays on unless you turn it off.
3. Pick **PDF**, **Word (.docx)**, **Excel**, **CSV**, **JSON**, **RTF**, or **Markdown**.

Suggested name: `North Campus Engineering Scope Review_20260818-47m-intel.pdf` (same stem for the other types).

---

## 6. Meetings list: group by date, series, or related names

**What it is.** The left Meetings list used to only pile meetings under **This Month**, **July 2026**, and so on. Weekly Standup and every Exec series Priorities call were scattered across months.

**How to use it.** At the top of the Meetings list (and Archive), open **Group**:

| Choice | What you get |
| --- | --- |
| **Date** | The original view: Today, This Week, This Month, then calendar months. |
| **Series** | Each recurring series or same-named meeting is its own bucket. Newest meeting on top. |
| **Related** | Names that share the first two words sit together. All **Exec series** meetings (Standup + Priorities) become one bucket, newest first. |

The section title shows a count, for example **Exec series (5)**. Archive uses the same Group menu (Date there still means quarters).

**Archive is the whole library**, not only meetings older than three months. The recent **Meetings** list stays the last three months so it stays scannable.

**File a meeting away.** Right-click → **Archive Meeting**, or select several and **Archive** on the bar. It leaves the recent list immediately and stays in Archive for export. **Put Back on Meetings** restores it if it is still in the three-month window. The **Filed away** chip in Archive shows only those.

### Export transcripts and intel

**Where:** Archive (and the recent Meetings list). **Export…** in the list header, on a right-click, on the selection bar, or **Meetings → Export Selected**.

This is a bulk copy of what is already stored. It is not the per-meeting dossier zip on Meeting Intelligence, and it does not call AI.

**How**

1. Open **Archive** (or **Meetings**). Group by **Series** or **Related** if you want a recurring bucket such as **Weekly Standup**.
2. Click **Export…**, or right-click a meeting / a section title.
3. Pick the scope:
   - **This meeting**
   - **This series** — every occurrence, including meetings still on the recent list
   - **This group** — the quarter or named bucket you right-clicked
   - **Selected**
   - **All visible** (current search and filters)
4. Pick **Everyone** or one **speaker**. Optional: **One folder per speaker**.
5. Pick **Zip**, **One PDF** (page break per meeting), or **One PDF per meeting**.
6. Tick what to include. Transcript and intel are on. Zip can also include **Audio file**, **Screen captures**, and **Video (screen-share time-lapse)**.
7. Save. Finder highlights the file or folder.

Zip has `index.md`, combined `transcript.md` / `intel.md` when there is more than one meeting, and a folder per meeting. A speaker filter keeps only that person’s lines and their action items. One PDF concatenates the set. One PDF per meeting writes a file per meeting into a folder.

**Video** is a slideshow of captured screen-share stills. There is no camera movie of the call. If a meeting has no stills, that file is skipped.

---

## 7. Reanalyze one meeting, several, or all of them

**What it is.** AI analysis writes the suggested title, summary, follow-up questions, topics, and action items. You can run it again after you rename speakers, switch to Grok, raise the timeout, or when a pass failed — including when the first write-up summarized the **subject** (a PDF, a calendar name) instead of **what you were trying to get done**.

Reanalyze uses whatever provider is selected in **Settings → AI** right now. It throws away the previous summary, questions, and topics and writes them again from the full transcript. It infers your purpose first: fixing documents you send to prospects so they match what someone actually said is the meeting, not a generic engineering review. Calendar-linked names in the list stay as the event; the intelligence pane shows the AI purpose title when it differs. Tasks you already completed, dated, or assigned are kept; untouched suggested tasks are replaced.

If you customized prompts under **Settings → Developer → Edit AI Prompts**, use **Restore All Defaults** so these purpose-first rules apply.

### One meeting

1. Open the meeting.
2. Click **Reanalyze** at the top of Meeting Intelligence for a full rewrite (purpose-first).

The arrow on that button: **Deep**, **Deepest** (weighs louder/quieter lines measured from the saved audio — it does not invent “frustration”), **Revert to prior**, **View log**. **Re-transcribe with large-v3** is at the bottom.

Each section (Follow-up Questions, Action Items, Summary, Topics) has its own **Reanalyze**. Click runs **Deep** for that section only.

The **Export** arrow is a different job (dossier zip). Do not mix them up.

You can also right-click a meeting in the list and choose **Reanalyze Meeting**.

### Several meetings

1. Go to **Meetings** or **Archive**.
2. **Command-click** extra rows, or **Shift-click** a range.
3. Then do any of these:
   - Menu **Meetings → Reanalyze Selected Meetings (N)**
   - Right-click → **Reanalyze Selected (N)**
   - The bar at the bottom of the list → **Reanalyze**
   - Keyboard: **Option-Command-R** (⌥⌘R)

The menu says “Reanalyze Selected Meeting” when only one row is selected.

### The whole library

1. **Meetings → Reanalyze All Meetings…**
2. Confirm **Reanalyze All**.

The confirm sheet tells you the jobs run **one at a time** with your configured AI provider.

**What gets skipped**

- Interviews
- Recordings still in progress or paused
- Meetings with no transcript yet

**While it runs**

- A status bar at the bottom shows which meeting is in progress (3 of 40, and so on).
- If any fail, **N failed** is clickable. It lists each meeting, the error, **Copy error**, **Open meeting**, and **Retry failed**.
- **Meetings → Cancel Reanalyze** stops the rest of the queue.
- First-pass analysis on a meeting you just recorded can still be cancelled from the inspector. Bulk reanalyze does not steal that cancel button.

Do not start “Reanalyze All” and walk away expecting it to finish in a minute. Each meeting can take several minutes, especially on Grok with a long timeout.

---

## 8. Intelligence in the left sidebar

Each Meeting Intelligence icon now has a home in the **Intelligence** group on the left:

| Icon in a meeting | Sidebar | What you can do there |
| --- | --- | --- |
| **Meeting Intelligence** (brain) | **Insights** | See what is analyzed, what still needs a pass, jump to a meeting, open the other workspaces |
| **Follow-up Questions** | **Questions** | Search every follow-up, add your own, copy, delete, open the meeting |
| **Action Items** | **Tasks** | The existing task rollup (filters, export, group) |
| **Summary** | **Summaries** | Browse write-ups, search, group by series, copy |
| **Topics** | **Topic Map** | Library topic cloud (and this meeting’s cloud from the Topics icon) |

Click the colored icon on a meeting to jump to that workspace. The title next to it still expands or collapses the section.

**On the items themselves:** click to select, **right-click** to modify / research / delete, **drag** to reorder. Research uses this meeting’s transcript only (no invented facts).

---

## 9. Tasks: roll up, filter, search, and export

**What it is.** **Tasks** in the sidebar is the rolled-up to-do list from meetings — not one meeting at a time.

**Default view.** Every **analyzed** meeting, **your** tasks only (“Me”).

### Meetings menu (calendar icon)

Pick **where** tasks come from:

| Choice | Meaning |
| --- | --- |
| **All analyzed meetings** | Default. Meetings that already have an AI pass. |
| **Selected in Meetings list** | Whatever you Command-clicked in Meetings or Archive. If nothing is selected, this list is empty on purpose. |
| **Choose meetings…** | A checkbox sheet. Use **Select all** at the top of the list (or **Select shown** / **Clear** at the bottom). Search by title, series, or calendar event. Then **Use selected**. |
| A **recurring series** | For example every Weekly Standup. Appears only if meetings have a series. |
| A **calendar event** | Meetings linked to that calendar name. |

### Assigned menu (person icon)

Pick **whose** tasks you see:

- **Me** — default. Your name, “me,” “myself,” or your profile contact.
- **Me + unassigned**
- **Others**
- **Everyone**
- **Specific people** — check contacts from your People list.

### Search box

Type words from the task, the assignee, or the meeting title. This filters the **list you already have**. It is ordinary search, not a chatbot.

Press Return or click **Find**.

**Reset** appears when you have changed anything. It puts you back to “all analyzed meetings” and “my tasks.”

### Group and save (same bar)

- **Group:** Status (Pending / Stalled / Completed), **Meeting**, **Date**, or **Series / collection** (recurring meetings together; one-offs in their own pile).
- Each task row shows **who**, the **meeting name**, the **meeting date**, and a **due date** if one is set. Click the meeting name to open it.
- **Export** sits on this bar (and still in the toolbar): **Copy**, **CSV**, **Excel**, **RTF**, **PDF**.

The info button on a row opens full task tools: due date, mark complete / won’t do, conversation context, open meeting.

### Sort and what is shown

Toolbar **Options**:

- Sort by **Due Date** (default), **Meeting Date**, **Date Created**, or **Alphabetical**
- Direction: ascending or descending
- **Show Completed**
- **Show Won't Do**
- If anything is stalled: **Mark Stalled as Won't Do**

### Stalled

Tasks older than the Settings threshold (default **7 days**) sit in an orange **Stalled** section at the top, with a day count. After 14 days the badge turns red.

### Export

Toolbar **Export** (works on the **visible** list — whatever your filters currently show):

- **Copy** — plain text onto the clipboard
- **Export CSV…**
- **Export Excel…**
- **Export RTF…**
- **Export PDF…**

Columns: status, action, assignee, due date, meeting, meeting date.

### Open a task

Click a row to open details, edit the text, change the assignee, set a due date, or mark it done / won’t do.

---

## 10. Analyze meetings that still have no tasks

**What it is.** A meeting only grows tasks after AI analysis. If you have transcripts that were never analyzed, Tasks will **ask** before spending minutes (or hours) on them.

**How you will notice**

- An orange banner: “N meetings have a transcript but no analysis, so they have no tasks yet.”
- Buttons: **Analyze…** and **Dismiss**.
- Clicking **Find** when unanalyzed meetings exist also asks first.

**How to use the picker**

1. Click **Analyze…** (or confirm when Find asks).
2. A sheet lists those meetings. Each row shows the date, duration, **analyzed** / **not analyzed**, and calendar name if any.
3. **Nothing is checked.** Analysis is slow, so you must pick.
4. Check the ones you care about. The **Select all** checkbox at the top of the list toggles every meeting currently shown (search filter included). **Select shown** / **Clear** at the bottom do the same.
5. Click **Analyze selected**.

Jobs run **one at a time**, same queue as Reanalyze. Watch the status bar. Cancel from **Meetings → Cancel Reanalyze**.

Dismissing the banner only hides it for this visit. It does not analyze anything.

---

## 11. Dashboard numbers are buttons

**What it is.** The four big numbers at the top of **Dashboard** are clickable.

| Card | Where it takes you |
| --- | --- |
| **This Week** | Meetings (this week’s recordings) |
| **Total Meetings** | Meetings (full library) |
| **Pending Actions** | Tasks |
| **Stalled Items** | Tasks |

Hover highlights the card. After about a second, a tooltip names the destination.

Recent meeting rows still open that meeting. The short pending-action list under the cards is a preview, not the full Tasks page.

---

## 12. Topic map: topics, people, speakers, and actions

**What it is.** **Topic Map** is still a map of **themes** from analyzed meetings (North Campus, Site B, hiring, and so on). Grey Conseil adds **who was there**, **who talked**, and **what was assigned**.

The dots stay topics. People and speakers are a way to **light up** the topics they belong to.

### Topics tab

1. Open **Topic Map**.
2. Leave the segmented control on **Topics**.
3. Sort **Mentions** (most meetings) or **Recent**.
4. Click a topic in the left list or on the map.

The right panel shows:

- **People discussed** — contacts on those meetings. Click one to jump to that person.
- **Who talked** — Alex, Jordan, guest-1, … with talk-time %. Click one to jump to that speaker.
- **Action items** — click one to open the meeting.
- The meetings themselves.
- Connected topics.

### People tab

Contacts ranked by how many topic-meetings they appear in.

Click a person: the graph **lights only the topics they discussed**. The panel shows what they talked about most, their actions, and those meetings.

### Speakers tab

Same idea from the **transcript** (Alex, Jordan, guest-1), ranked by how much they spoke, not by the People list.

### This meeting’s topic cloud

On a finished meeting, the purple **Topics** icon (the link badge next to the word Topics) opens a **topic cloud for that meeting only**.

1. Click the icon, or click a topic chip.
2. The cloud lists this meeting’s topics. Click one.
3. Matching transcript lines appear underneath (speaker, timestamp, what they said).
4. Check **Include other meetings** to also see lines from other analyzed meetings tagged with the same topic.
5. Click a line to jump to that moment in the transcript. **Open in Topic Map** still takes you to the library-wide map.

If a topic was tagged from the whole discussion but no line uses those words, the cloud says so.

### Search

The search field at the top matches **topic names, people, and speakers**.

### If the map is empty

Those meetings have not been analyzed yet. Use:

- The **Analyze N Meetings** button on the empty Topic Map, or
- **Meetings → Reanalyze All…**, or
- The Tasks **Analyze…** picker

---

## 13. Hover on an icon for its name

**What it is.** Icon-only controls (collapsed sidebar, dashboard cards, many toolbar icons) show a native macOS tooltip after about **one second**.

**How to use it.** Rest the pointer on the icon. You do not need to click. If nothing appears, wait a full second — it is slower than a typical Mac tooltip on purpose, so the labels do not flash while you move around.

---

## 14. Dev Mode when something breaks

**What it is.** Extra diagnostics for testing: speaker clicks, renames, AI failures, queue events.

**How to turn it on**

1. **Settings → Developer**
2. Turn on **Dev Mode (verbose log)**
3. Optionally turn on **Enable developer tools** — that adds **Activity Log** in the sidebar and extra transcript debug tools

**How to send a log**

- On that same Settings page: **Export debug log…**
- Or **View → Export Debug Log…**

Save the JSON and send it with a description of what you clicked. Turn Dev Mode **off** when you are done — the file can get large.

Developer tools also show where the meeting library and recordings live, and let you edit AI prompts. Leave prompt editing alone unless you are deliberately testing wording.

---

## 15. Keyboard shortcuts

| Shortcut | What it does |
| --- | --- |
| **⌥⌘R** (Option-Command-R) | Reanalyze the meetings selected in Meetings or Archive |
| **Meetings → Export Selected…** | Zip or PDF transcripts and intel for the selected meetings |
| **⌘S** | Collapse / expand the sidebar (already in Matt’s app) |
| **⇧⌘I** | Toggle the insights / transcript pane (already in Matt’s app) |
| **⌘F** | Search the **open meeting** (header field) |
| **⌘G** / **⇧⌘G** | Next / previous transcript match in this meeting |
| **⇧⌘F** | Open **Find** — search transcripts and Meeting Intelligence |

There is no extra shortcut for Tasks Find or Topic Map. Use the sidebar.

### Find vs Ask

- **⌘F** searches the **open meeting** from the header field. Tick **Transcript** to highlight and jump lines in the inspector. **⌘G** / **⇧⌘G** walk transcript hits.
- **Find** (sidebar, toolbar magnifying glass, **⇧⌘F**) is library search in the **main pane**. Type text (optional **Regex**). Filter by **meeting name**, **speaker** (Me, Jordan, …), and **from / to date**. Tick **Transcript** and/or **Intelligence**. Pick **This meeting**, **Selected meetings**, or **All meetings**. Click a result to open that meeting; transcript hits jump to the line.
- **Ask** is the AI question box (“What did we say about cabinets?”). It needs indexed meetings.
- Right-click a speaker → **Find in their lines** still searches only that person in the current transcript.

---

## 16. What this fork does not do

- **Ventura** — not supported (Matt’s issue #1). macOS 14.4+ / Apple Silicon only.
- **Logging into SuperGrok** — website login is not an API key. Use the Console.
- **Opening Matt’s production library** — Grey Conseil starts empty (or with whatever *this* meeting library already has). That is by design.
- **Updating from Grey Eminence’s Sparkle feed** — that would overwrite this fork. Our Check for Updates is this repo only.
- **Perfect voice-print matching** — enroll helps the next meeting; bad call audio can still mint a new guest. Assign that chip; do not assume it will never miss.
- **Landing in Matt’s production app automatically** — only if he reviews a **small, clean pull request**. This branch also has fork packaging (name, bundle ID, no sandbox, no Sparkle) that should stay out of his release.

---

## 17. If something looks empty or wrong

**I have no meetings in this fork.**  
Grey Conseil does not open production’s library. Record new meetings here, or keep using Matt’s app for the old ones. Do not copy the production store into Grey Conseil.

**I installed a new Grey Conseil DMG and my Grey Conseil meetings vanished.**  
You may have launched Matt’s app, or a different copy of Grey Conseil. Check the menu bar name. Replacing the app should **not** wipe this library. Do not recopy anything unless someone on the Grey Conseil side asked you to.

**There is no Grok in Settings.**  
You are in Matt’s app, or an older Grey Conseil build. Use **Grey Conseil** from the latest `GreyConseil-…dmg`.

**Reanalyze timed out / “analysis failed.”**  
Settings → AI → raise **Analysis timeout**, confirm **Provider** is the one you meant, then Reanalyze **once**.

**Every remote is still named “Speaker.”**  
Right-click → **Recover guest-1, guest-2… from audio**. New recordings should already come in as guest-1, guest-2.

**I remapped guest-1 and it also renamed Me.**  
That was a bug in ftl17: **Select All** included hidden lines. In ftl18 it selects **only visible** lines, and remapping a guest never overwrites **you**. Use **Undo speaker change** right away, **Revert speaker labels** to put original names back, or **Re-analyze speakers** to rebuild remote labels from the saved audio.

**Pat’s next sentence became guest-2.**  
On current Grey Conseil, assign the dashed **guest-2** chip → **This is Pat** and **Enroll voice print**. If this still happens every sentence, you are on an older DMG than ftl15.

**A rename did not stick.**  
Use **Apply** in the right-click menu (or **Save as default name** if it is you). A single click on the badge does **not** hide or rename.

**I clicked a People chip and they vanished.**  
That is hide (ftl19+). Grey chip = off. Click it again, or **Show all**, or **Click to show** on the dashed stub.

**I have Alex you and Alex Morgan as two chips with the same %.**  
They are the same person. Install **ftl34+** and reopen the meeting. Jordan vs Pat stay separate.

**Copy into Teams is a wall of `1.` and `•`.**  
Install **ftl35**. Copy on Summary / Questions / Actions includes HTML.

**My microphone is silent / orange encoder banner, but permissions look ON.**  
Install **ftl33+**. Quit the old copy. Grant Microphone and Screen Recording to *this* copy. **Settings → Developer → Capture permissions**. The built-in mic behind an aggregate device is converted before AAC.

**Search popped closed while I typed.**  
That was an older bug. In current Grey Conseil the speaker search box stays open. Get the latest DMG if it still closes.

**Enroll voice print is disabled / says pick someone.**  
The voice is still `guest-N`. Choose them under **This meeting** or **Prior speakers**, then enroll.

**Enroll failed (“not enough audio”).**  
Let them talk a few more seconds and try again. On a finished meeting the system (or mic, for you) recording must still be on disk.

**Topic map is a ring of unlabeled dots.**  
Click a topic in the **left list**, or switch to **People** / **Speakers**. Analyze meetings that have no topics yet.

**Tasks Find “does nothing.”**  
Use the **Meetings** and **Assigned** menus first. Type in the search box to filter the list you already have. Find is not a chatbot. If you wanted unanalyzed meetings included, answer the analyze prompt and pick them.

**Tasks is empty but I know there were action items.**  
Check **Assigned** — default is **Me** only. Switch to **Everyone**. Also check that those meetings are **analyzed** (orange banner).

**I selected meetings for Tasks and see nothing.**  
Go back to Meetings, Command-click the rows, then in Tasks choose **Selected in Meetings list**. Or use **Choose meetings…** instead.

**Dashboard cards do not click.**  
You are on an older Grey Conseil build. Install the latest DMG.

**The People bar is missing / I still see a separate attendees row under REC.**  
Install **0.28.4-ftl35**. Quit the old copy completely before opening the new one.

**There is no Export / the Transcript button is huge / Lock IDs is still a separate button.**  
Install **0.28.4-ftl35**. Quit the old copy completely before opening the new one.

**Export PDF still suggests `Title — date (RP).pdf`.**  
That name changed in ftl15. Re-export after installing.

**The app will not launch on Tahoe.**  
Use the Grey Conseil DMG (unsandboxed), not Matt’s sandboxed production build, and not an old ad-hoc sandbox copy.

**Screen Recording is ON in System Settings but the app still says it is off.**  
Each new Grey Conseil DMG is ad-hoc signed, so macOS treats it as a **new app**. Grant **Screen & System Audio Recording** *and* **System Audio Recording Only** to the copy you just installed (check the path), then **quit and reopen**. Open **Settings → Developer → Capture permissions** → **Test capture permissions**. If CGPreflight is denied while Settings shows ON, you granted a different binary. Copy the log if you need to send it.

**Hiding me and Jordan still shows the first Alex / Jordan lines.**  
Install **ftl31** or newer. Hide you / guest-1 / guest-2 now removes their **first** line as well. ftl29/ftl30 still left that first playable snippet because SwiftUI recycled mixed UUID/String row identities.

**I tagged guest-1 as Jordan but hide/show still treats them as someone else.**  
Install **ftl32**. Assigning a leftover guest to Jordan now puts those lines on Jordan’s chip. **Click to show** on the dashed bar reveals that person.

**The app ran overnight and used a pile of API tokens.**  
Use **Stop all** at the top of the window. That ends recording, cancels live AI, and turns off auto-start. Idle then waits — it does not capture this Mac’s mic. Auto-started calls also stop after 4 hours, or 20 minutes of silence. Live AI stays on for as long as the recording is going; uncheck **Live AI** or hit **Stop all** to cut the API.

**I want Matt to have these features.**  
This repo is updated (**0.28.4-ftl35**). How the two trees relate: [ORIGIN.md](ORIGIN.md). Ask him if he wants **small PRs** (Grok, then speakers). Do not send `feature/speaker-session-rename` as one merge. See [MATT-PULL-NOTES.md](MATT-PULL-NOTES.md).
