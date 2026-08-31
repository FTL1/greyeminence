# Grey Conseil

Unofficial fork of [Matt Purdon’s Grey Eminence](https://github.com/mpurdon/greyeminence). It records meetings on your Mac, types them out, and asks AI for a summary and a to-do list.

**This is not Grey Eminence.** Matt’s shipping app stays named **Grey Eminence**. Ours is **Grey Conseil** so both can live in Applications. **Leave Matt’s app alone.**

**Why that name:** *Grey Eminence* is English for French *éminence grise* — the counselor who holds influence without the official chair ([the phrase](https://wordhistories.net/2019/07/24/eminence-grise/)). **Grey Conseil** keeps the grey, and borrows **Conseil** from Jules Verne’s *Twenty Thousand Leagues Under the Sea*: Aronnax’s servant, whose name means *counsel*, and who keeps the catalogue while Nemo steers. Homage, plus preferred humor. You have to read the book: [archive.org](https://archive.org/details/in.ernet.dli.2015.459144). Full note: [docs/NAME.md](docs/NAME.md).

**NO WARRANTY. USE AT YOUR OWN RISK. LAWFUL USE ONLY** — you are responsible for consent and recording laws. Full text: [docs/DISCLAIMER.md](docs/DISCLAIMER.md).

**What shipped (catalog):** [docs/FEATURES.md](docs/FEATURES.md)  
**How to use it:** [docs/USER-GUIDE.md](docs/USER-GUIDE.md)  
**How this fork relates to Matt:** [docs/ORIGIN.md](docs/ORIGIN.md)  
**Thorough difference map:** [docs/DIVERGENCE.md](docs/DIVERGENCE.md)  
**Why the name:** [docs/NAME.md](docs/NAME.md)

Inside the app: **Help → What's in Grey Conseil**, **How to use**, **Controls and options**, **Why Grey Conseil**, **How we differ**, **Disclaimer**, **Send feedback…**.

Latest build: **0.28.4-ftl51**. After the first install, **Check for Updates** (Settings → About, or the app menu) fetches [FTL1/grey-conseil releases](https://github.com/FTL1/grey-conseil/releases) — not Grey Eminence’s Sparkle feed. Hover any control for what / how / why; **Help → Controls and options** is the full page.

---

## What this app does (the whole picture)

Grey Eminence is a **native Mac meeting notebook**. In everyday use you:

1. Start a recording when a call begins (or let it notice Zoom / Teams / Meet / Discord).
2. It captures **your microphone** and **what the other people are saying** through the computer.
3. It transcribes on the Mac (no cloud for the raw audio).
4. It labels speakers — you, then guest-1, guest-2, and so on.
5. After the meeting, AI writes a **title**, **summary**, **follow-up questions**, **topics**, and **action items**.
6. You can browse **Meetings**, a rolled-up **Tasks** list, a **Topic Map**, **People**, and a **Dashboard**.

Matt already built all of that. This fork's job was to make speakers usable, add **Grok**, let you **reanalyze many meetings**, roll up **Tasks** in a way a human can filter, and connect **people / speakers / actions** to the topic map — without ever writing over production.

---

## Grey Conseil vs Matt’s app

| | Grey Eminence (Matt) | Grey Conseil (this copy) |
| --- | --- | --- |
| What you see in the Dock | Grey Eminence | **Grey Conseil** |
| What it is for | The real product | A **side-by-side test** build |
| Your meetings | Production library | **A separate library** |
| Auto-update | Sparkle (Matt’s feed) | Sparkle (**this** GitHub) |
| AI you can pick | Claude or AWS Bedrock | Those **plus Grok (xAI)** |
| Speakers | Basic labels, often “Me” / “Speaker” | People mixer: click a chip to hide/show, one chip per person, lock IDs, talk share, voice prints; remotes are guest-1, guest-2… |
| Find | Limited | **⌘F** this meeting, **⇧⌘F** library (transcript + Intelligence) |
| Reanalyze | One meeting at a time | Selected / all; purpose-first; Deep / Deepest per section |
| Tasks | Per meeting + a simple global list | Filters by series / calendar / selection / assignee; copy or export |
| Intelligence | Buried in each meeting | Sidebar **Insights**, **Questions**, **Tasks**, **Summaries**, **Topic Map**; dossiers; formatted Copy |
| Meetings list | By date only | **Date**, **Series**, or **Related** (Exec series in one bucket) |
| Topic map | Topics only | Topics **plus** people, speakers, and action items |
| Latest *his* release | **v0.30.1** on `main` | We **ported** 0.29.1–0.30.1; we did not merge `main` |
| Latest *our* DMG | — | **0.28.4-ftl51** (the `0.28.4` is the fork point, not “behind”) |
| Tahoe (macOS 26) | Sandboxed production build | **Unsandboxed** so it actually launches |
| Ventura | Requested, not done here | **Not supported** |

This is **not** a drop-in replacement. Do not overwrite Matt’s app. Do not copy this library onto his store, or his onto ours.

### How this copy relates to Matt’s code

We forked his **v0.28.4**. His shipping app moved on to **0.30.1**. Grey Conseil kept the marketing line `0.28.4-ftlN` and counted test builds (now **ftl51**).

We **fetch** `mpurdon/greyeminence` (`upstream`, never push). We **port** the bits we want (beachball, cancelled calendar, live screenshots, formatted Copy, open-questions callout). We do **not** `git merge` his `main` — that would fight the People mixer, Grok, and the isolated store.

The long story, including what we took and what we left: [docs/ORIGIN.md](docs/ORIGIN.md). How we port the next release: [docs/UPSTREAM.md](docs/UPSTREAM.md).

---

## Install (Tahoe / Apple Silicon)

You need a Mac with **Apple Silicon** (M1 or later) and **macOS 14.4 or newer**. Ventura will not work.

1. First time: GitHub **Releases** → `GreyConseil-0.28.4-ftl51.dmg`. After that, **Check for Updates** in the app.
2. Open the DMG. Drag **Grey Conseil** into Applications. Remove **older test builds** if it is still there (same library).
3. Leave **Grey Eminence** (Matt’s) installed if you already use it.
4. Open **Grey Conseil**. Accept the legal notice. Grant **microphone**. Grant **contacts** and **calendar** if the Mac asks.
5. When it asks **Who are you?**, type your name (for example Alex) and save. That becomes the default name for *your* voice.
6. Open **Settings → AI**. Pick **xAI (Grok)** or keep Claude / Bedrock. For Grok you need an **xAI Console API key**, not a SuperGrok website login. Details are in the [user guide](docs/USER-GUIDE.md#3-turn-on-grok-xai-for-summaries).

**When a newer Grey Conseil DMG arrives:** replace the **app** only. Do not recopy the meeting library. Grey Conseil will keep using the same meeting library.

**How to tell which app you opened**

- The menu bar says **Grey Conseil**
- **Help** includes **Disclaimer** and **How we differ from Grey Eminence**
- **Settings → AI** includes **xAI (Grok)**
- **Settings → About → Check for Updates** talks to this repo

---

## First ten minutes (a suggested tour)

1. Confirm you are in **Grey Conseil**, not Matt’s app. Accept the legal notice.
2. Finish **Who are you?** if it is still sitting there.
3. **Settings → AI** → **xAI (Grok)** → paste a Console key → **Save to Keychain** → **Validate**.
4. Set **Analysis timeout** to **Auto** (or 6–10 minutes if you have long meetings).
5. Record a short test call, or open a meeting you already have in *this* meeting library.
6. The **People** bar across the top of Record is the room: chips for who is here, talk-share for who is speaking. **Click a chip to hide or show** that person (grey = off). **Show all** turns everyone back on. Click the **lock** on a name to freeze that ID. Right-click a chip or a transcript badge to assign guest-1, enroll a voice print, or pick a prior speaker.
7. Open a finished meeting. **⌘F** finds in this meeting. **Transcript** saves every line. Meeting Intelligence **Export** (and **Create dossier…**) picks sections and/or the raw transcript, then PDF / Word / Excel / CSV / JSON / RTF / Markdown — or a zip for a chatbot. **Archive → Export…** pulls transcripts and intel for a series, a speaker, or a bulk selection as a **zip**, **one PDF** (page break per meeting), or **one PDF per meeting** (optional audio, stills, time-lapse stay in the zip). **Copy** on the summary pastes into Teams as real lists.
8. Open **Tasks**. You should see **your** tasks from **analyzed** meetings. Try the calendar menu and the person menu. Click **Export** and Copy if you want a list in Mail or Notes.
9. Open **Dashboard** and click **Pending Actions** — it should take you to Tasks.
10. Open **Topic Map**. Switch the left control from **Topics** to **People** to **Speakers**. Click a person and watch only their topics light up.
11. If anything fails: **Settings → Developer** → **Dev Mode** → reproduce it → **Export debug log…**

---

## What we added (plain English)

Each item below is a real thing you can click. The [feature catalog](docs/FEATURES.md) is the short list; the [user guide](docs/USER-GUIDE.md) has the exact menus and gotchas.

### 1. Grok / xAI as a first-class AI

Settings → AI → Provider → **xAI (Grok)**.

Paste a key from [console.x.ai](https://console.x.ai). Validate it. Pick **Grok 4.6**, **Grok 4.5**, or a **custom model ID** from the Console.

**SuperGrok Heavy is not a login and not a magic switch.** It is an account tier. If Console lists a Heavy model, paste **that model’s ID** in the custom field.

Changing the Provider picker switches **the whole app** immediately — summaries, reanalyze, Tasks analysis, Ask, interview scoring. A green “validated” on Claude does not keep Claude active if the picker now says Grok.

### 2. More time for long meetings

Same Settings page: **Analysis timeout**. Auto is about 4 minutes for Grok and 2 for Claude. You can pick 2, 4, 6, or 10 minutes.

A timeout is **one** failure, not three retries. Raise it and click Reanalyze once.

### 3. Speakers you can actually work with

This was the original reason for the fork (Matt’s issues #3 and #4).

- **You = the Mac microphone.** Everyone else is the meeting app (Teams, Meet, Slack) on the system-audio tap. Voice prints name remotes; they do not decide who “Me” is.
- **People bar** across Record: who is here, talk-share on the chip. **Click a chip to hide or show** (color = on, grey = off). **Show all** restores. There is no chip chevron — **right-click** the chip or the transcript badge.
- **One person, one chip.** Calendar “Alex Morgan” and Me “Alex you” are the same seat (same color, same %). Jordan and Pat stay separate.
- **Pre-tag** invitees (or pick a calendar event). When `guest-1` talks, right-click → **This is Pat**, then click the **lock**. That **merges** those lines onto Jordan (hide/show and color follow).
- **Right-click** a badge: this meeting / prior speakers, enroll voice print, rename, search, hide, show only, link a contact.
- **Hide includes the first snippet** (Alex at 0:00, first guest-1, first guest-2). **Click to show** on a hide stub reveals that person.
- **Enroll voice print** stores the voice on a People contact so the next meeting can tag a match instead of minting guest-2.
- **Re-analyze speakers** (⋯ menu): tick who was on the call, match voice stamps, leftovers become unknown-1…. You stay you.
- **Transcript** and Meeting Intelligence **Export** use `Title_yyyyMMdd-47m-tr.ext` / `Title_yyyyMMdd-47m-intel.ext`.
- If an old recording lumped everyone together, right-click → **Recover guest-1, guest-2… from audio**.

Rename or lock people **before** you reanalyze if you want those names in the summary and the task list.

### 4. Reanalyze many meetings

After you switch to Grok, fix speakers, or raise the timeout, you should not have to click Reanalyze forty times.

- One meeting: the **Reanalyze** button on that meeting, or right-click → **Reanalyze Meeting**.
- Several: Command-click (or Shift-click) in **Meetings** or **Archive**, then **Meetings → Reanalyze Selected Meetings**, or the bar at the bottom, or **⌥⌘R**.
- Everything eligible: **Meetings → Reanalyze All Meetings…** and confirm.

Jobs run **one at a time**. Interviews, live recordings, and empty transcripts are skipped. **Meetings → Cancel Reanalyze** stops the queue.

### 5. Tasks that roll up the way a human thinks

**Tasks** in the sidebar is the company to-do list from meetings.

Default: **analyzed meetings only**, **your tasks only**.

Then:

- **Meetings menu** (calendar icon) — all analyzed, whatever is selected in the Meetings list, a checkbox picker, a recurring series (Weekly Standup), or a calendar event name.
- **Assigned menu** (person icon) — Me, Me + unassigned, Others, Everyone, or specific people.
- **Search box** — ordinary find in the current list (task text, assignee, meeting title). Not a chatbot.
- **Find** — applies that search. If some meetings have a transcript but **no** AI pass, the app **asks** first.
- **Reset** — back to “analyzed + mine.”
- **Options** — sort by due date, meeting date, created, or A–Z; show Completed / Won’t Do.
- **Stalled** — older than the Settings threshold (default 7 days) sit in an orange group.
- **Export** — on the Tasks bar: Copy, or save **CSV / Excel / RTF / PDF**.
- **Group** — Status, Meeting, Date, or Series / collection. Each row shows the meeting name, date, and due date.
- Click **N failed** on the bottom bar to see which meeting failed and the error.

### 6. Analyze only the meetings you pick

Analysis is slow. Grey Conseil will not quietly queue your entire unanalyzed library.

When Tasks notices transcripts with no AI pass, an orange banner appears: **Analyze…**. The picker starts with **nothing checked**. You choose. Same one-at-a-time queue as Reanalyze.

### 7. Dashboard cards go somewhere

The four big numbers are buttons:

- **This Week** and **Total Meetings** → Meetings
- **Pending Actions** and **Stalled Items** → Tasks

Hover, wait a second, and a tooltip names the destination.

### 8. Meetings list grouping

At the top of Meetings (and Archive) is **Group**:

- **Date** — Today / This Month / July 2026 (the original view)
- **Series** — each recurring series or same-named meeting in its own bucket, newest first
- **Related** — names that share the first two words sit together. Every **Exec series** meeting (Standup + Priorities) becomes one bucket, newest first

### 9. Topic map that includes people

The map is still **topics as dots**. Grey Conseil adds two more ways to browse:

- **People** — contacts, ranked by how many topic-meetings they appear in.
- **Speakers** — names from the transcript, ranked by talk time.

Click a person or speaker and only **their** topics light up. The side panel lists top topics, action items, and meetings. On a topic, you also see who was discussed and who talked.

The purple **Topics** icon on a meeting opens **that meeting’s topic cloud**. Click a topic to see the matching conversation. Check **Include other meetings** to pull in the same topic from elsewhere.

Search matches topic names, people, and speakers.

### 10. Hover help

Rest on an icon-only control for about **one second**. A native Mac tooltip names it. Built so a collapsed sidebar is still learnable.

### 11. Dev Mode

**Settings → Developer → Dev Mode (verbose log)**. Reproduce the bug, then **Export debug log…** (or **View → Export Debug Log…**). Send the JSON with a sentence about what you clicked. Turn it off afterward.

### 12. This written guide, inside the app

- **Help → What's in Grey Conseil** — the [feature catalog](docs/FEATURES.md)
- **Help → How to use Grey Conseil** — the [support how-to](docs/USER-GUIDE.md)
- **Help → What's New** — short trailer after an update
- **Help → Changelog** — every ftlN, including ports from Matt 0.29 / 0.30

### 13. Find this meeting and the library

- **⌘F** — search the **open meeting** (header). Tick **Transcript** to jump lines. **⌘G** / **⇧⌘G** walk hits.
- **⇧⌘F** (sidebar Find, toolbar magnifying glass) — library search in the main pane: meeting name, speaker, dates, plain or regex, Transcript and/or Intelligence.
- **Ask** is still the AI box. Per-speaker find is still on the speaker menu.

### 14. Same-speaker crumbs merge; play the whole line

Opening a finished meeting joins consecutive lines from the same person (Settings → Transcript). The triangle on a merged line plays **every** original audio range, not just the first crumb. **⋯ → Merge consecutive lines** is the one-shot pass. Undo is in **⋯**.

### 15. Dossiers, Deep reanalyze, formatted Copy

- Meeting Intelligence **Export** arrow: **Create dossier…**, **One-pagers for everyone**, **Series dossier…**. A zip of stored facts plus a **no-hallucination** prompt pack for a separate chatbot. Settings prompts still *generate* intelligence; the dossier only packs what is already there.
- **Archive Export…** (also on the recent Meetings list): bulk transcripts and intel for a meeting, a recurring series (Weekly Standup), a speaker, or the current filter. **Zip**, **one PDF** (page break per meeting), or **one PDF per meeting**. Optional audio, screen stills, and a time-lapse stay in the zip. There is no camera movie of the call.
- Each section (Summary, Questions, Tasks, Topics) has **Reanalyze**. Click is **Deep**. Arrow adds **Deepest** (measured vocal energy from saved audio — not invented emotion), Revert, View log. Full Reanalyze is purpose-first: what you were trying to do, not the calendar title.
- Click an intelligence item to select; right-click to modify / research / delete; drag to reorder. Research stays in this meeting’s transcript.
- **Copy** on Summary, Follow-up Questions, and Action Items pastes into Teams / Slack / Outlook as real lists. PDF reports lead with open questions in a callout (Matt 0.30).

### 16. Capture bar, mic, overnight safety

Top of the window: **Watch for meetings**, **Live AI**, **Stop all**. Idle does **not** capture this Mac’s mic. Auto-record stops after 4 hours, or 20 minutes of silence on an auto-started call. Live AI stays on for the whole recording (it used to cut off at 90 minutes).

If the orange encoder banner appears and your lines are missing: install **ftl33+**. The built-in mic behind `CADefaultDeviceAggregate` is converted before AAC so Alex’s audio is kept. Grant Screen Recording and Microphone to *this* copy after each new DMG (**Settings → Developer → Capture permissions**).

---

## What we deliberately did *not* add

- **Ventura support** (Matt’s issue #1) — out of scope.
- **Perfect voice-print matching** — enroll is real; bad call audio can still mint a new guest. Assign that chip.
- **Opening or cloning Matt’s production library** — Grey Conseil starts with this fork's own data. Mixing the two stores is how you lose a week of meetings.
- **Sparkle from Matt’s feed** — Grey Conseil updates from this repo only, so it cannot overwrite Grey Eminence.

---

## Safety: two apps, two libraries

Please treat these as **two different products that happen to look similar**.

- Recordings live under Application Support for `com.ftl1.greyeminence`.
- Production stays in Matt’s container.
- Installing a new Grey Conseil DMG replaces the **program**, not the **library**.
- If Grey Conseil looks empty, you are probably in the wrong app, or this is a brand-new meeting library. That is expected. It is not a reason to copy production’s database.

If someone asks you to “just symlink the store” or “open the production file in place,” say no.

---

## Talking to Matt about pulling features

This repo is updated (**0.28.4-ftl40**). **Do not send him this whole branch.** It includes test-only packaging (name, bundle ID, unsandboxed, no Sparkle) that must stay in the fork.

How the two trees relate: [docs/ORIGIN.md](docs/ORIGIN.md). Ask him if he wants **small, separate PRs** from `FTL1/grey-conseil` into `mpurdon/greyeminence`, one theme at a time. Draft: [docs/MATT-PULL-NOTES.md](docs/MATT-PULL-NOTES.md). How we stay current with *his* releases: [docs/UPSTREAM.md](docs/UPSTREAM.md).

Suggested order, after he agrees:

1. Grok / xAI provider (his issue **#2**)
2. Speaker UX: People bar, hide/show, search, contacts, lock, voice print (issues **#3–#4**)
3. Later: bulk reanalyze, Tasks filters/export, topic-map people, full-transcript export

Do not open those PRs until he says yes.

---

## If something looks wrong

| What you see | What to try |
| --- | --- |
| No meetings | You are in this fork’s separate library, or in the wrong app. Check the menu bar name. |
| No Grok in Settings | Older Grey Conseil build, or Matt’s app. Install the latest `GreyConseil-…dmg`. |
| Reanalyze timed out | Settings → AI → raise **Analysis timeout**, then Reanalyze once. |
| Remotes still say “Speaker” | Right-click → recover guest-1, guest-2 from audio. |
| Pat became guest-2 | Assign the dashed chip → **This is Pat**, click the lock, then **Enroll voice print**. Need ftl16+. |
| Two Alex chips / two colors / 53% twice | Calendar “Alex Morgan” next to Me. Install **ftl34+** and reopen the meeting. |
| Guest-1 tagged as Jordan still hides separately | Install **ftl32+**. Assign now merges onto Jordan’s chip. |
| First Alex / guest line stays when you hide | Install **ftl31+**. Click the grey chip or **Show all**. |
| No Export / no lock on names | Install **Grey Conseil 0.28.4-ftl40**, then Check for Updates. |
| Rename did not stick | Right-click → Rename → **Apply**. **Click the People chip hides** that person (grey = off). |
| Copy into Teams is a wall of `1.` and `•` | Install **ftl35**. Copy on Summary / Questions / Actions now includes HTML. |
| Mic silent / orange encoder banner | Install **ftl33+**. Quit the old copy, grant mic to *this* copy, **Settings → Developer → Capture permissions**. |
| Topic map is a ring of dots | Click a name in the left list, or analyze meetings that have no topics. |
| Tasks Find “does nothing” | Use the Meetings and Assigned menus. Find is search, not a chatbot. |
| Tasks empty | Assigned is **Me** by default. Switch to **Everyone**. Check the orange “needs analysis” banner. |
| App will not launch on Tahoe | Use this Grey Conseil DMG, not a sandboxed production build. |

More detail: [docs/USER-GUIDE.md](docs/USER-GUIDE.md#17-if-something-looks-empty-or-wrong).

---

## For developers (optional)

You can skip this entire section if you only use the DMG.

- Clone: `https://github.com/FTL1/grey-conseil`
- Working branch for fork features: `feature/speaker-session-rename`
- Build a test DMG: GitHub Actions → **Build test DMG** → Run workflow on that branch
- Do **not** regenerate Matt’s `project.yml` over the hand-maintained `GreyEminence.xcodeproj` unless you know you need to — fork files were added to the pbxproj directly
- Upstream (Matt) layout and original README: `GreyEminence/Resources/Docs/README.md`, also **Help → Read Me** in the app

License: MIT, same as upstream. See [LICENSE](LICENSE).
