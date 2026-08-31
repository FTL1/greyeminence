# Asking Matt to pull work

Internal notes. **Do not open PRs against `mpurdon/greyeminence` until Matt says yes.** Keep packaging on this repo.

QA later, then send the note at the bottom.

---

## Why not send the whole branch

`feature/speaker-session-rename` on [FTL1/grey-conseil](https://github.com/FTL1/grey-conseil) is a **test kitchen**, not a clean upstream PR.

It includes things Matt must not ship as Grey Eminence:

| Fork-only | Why it stays here |
| --- | --- |
| App name **Grey Conseil** | So both apps sit in Applications |
| Bundle ID `com.ftl1.greyeminence` | Separate from production |
| Isolated SwiftData store | This fork must not open or overwrite his library |
| Unsandboxed Tahoe entitlements | Workaround so an ad-hoc Grey Conseil DMG launches on macOS 26 |
| Sparkle → this repo | Never his feed — that would install Grey Eminence over us |
| `.github/workflows/grey-conseil-dmg.yml` | disk-image job |
| **Help → What's in Grey Conseil** | Fork documentation |

If he merged that branch as-is, testers could lose a production library or get a second “Grey Eminence” that fights Sparkle.

Offer **small thematic PRs** from this repo into whatever branch he wants (`main`, or a review branch). One theme, reviewable, no fork packaging.

---

## Suggested order (after he agrees)

These map to issues he already has open.

### PR 1 — Grok / xAI (his **#2**)

Smallest, most self-contained.

- Settings → AI → Provider → **xAI (Grok)**
- Console API key (`xai-…`), Keychain, Validate
- Models (Grok 4.6 / 4.5 / custom Console ID)
- Analysis timeout
- Same provider for summaries, reanalyze, Tasks analysis, Ask, interview scoring

Do **not** include: SuperGrok website login (there is none), Settings copy that names the fork.

### PR 2 — Speaker UX (his **#3** and **#4**)

The original reason for the fork. Bigger than PR 1; still one theme.

- People bar: who is here + talk share (not a third attendees row)
- Pre-tag / calendar invitees / **This is Pat** / **Lock IDs** / paint one line
- People chips: hide/show (click-to-hide is a mixer; his app may still want hide on the menu)
- Speaker search that stays open
- **This meeting** and **Prior speakers** when linking (not only a generic directory)
- Enroll voice print on a People contact; seed prints at the next recording
- You = Mac microphone; remotes = meeting-app / system audio
- Sticky remote name (~12s); do not overwrite a name the user chose with `guest-N`

Do **not** include: isolated store, product name, Tahoe unsandbox.

### PR 3+ — only if he wants them

Separate PRs, later:

- Bulk reanalyze (selected / all, sequential queue, skip interview / live / empty)
- Tasks rollup filters, Find, export
- Topic map People / Speakers + this-meeting topic cloud
- Intelligence sidebar homes (Insights, Questions, Tasks, Summaries, Topic Map)
- **Export Full Transcript** (txt / md / rtf / csv / xlsx / pdf)
- Meeting Intelligence filename: `Title_yyyyMMdd-47m-intel.ext`

---

## What “updated GitHub” means today

- Repo: `FTL1/grey-conseil`
- Branch: `feature/speaker-session-rename`
- Latest test DMG: **0.28.4-ftl40** (Grey Conseil)
- Docs: root [README.md](../README.md), [FEATURES.md](FEATURES.md), [USER-GUIDE.md](USER-GUIDE.md), [ORIGIN.md](ORIGIN.md)

He can browse the fork. He should **not** be asked to merge that branch.

---

## How to send PRs (when he says yes)

1. Branch each theme off current `mpurdon/greyeminence` `main` (or the branch he names).
2. Cherry-pick or port **only** that theme. Drop fork packaging, fork Help files, `grey-conseil-dmg.yml`, isolated store, unsandbox, Sparkle-off.
3. Open the PR **from a branch on this repo** (or a personal clone) **into `mpurdon/greyeminence`**.
4. One PR at a time. Wait for review before the next.
5. Do not force-push his branches. Do not touch Sparkle, his bundle ID, or his store.

---

## Paste this to Matt

Hey Matt —

We've been running a side-by-side fork at FTL1/grey-conseil so we could try a few things without touching production. Separate app name, separate library, no auto-update — testers keep Grey Eminence installed as-is.

A few pieces map to issues you already have open, and they're working well enough here that I'd like to offer them as small PRs. I would **not** send the whole fork branch — that branch also has test-only packaging that should stay in the fork.

Would you want any of these, in this order?

1. **Grok / xAI as a first-class AI provider** (your #2) — Settings picker, Console API key, models, used everywhere analysis already goes.

2. **Speaker UX** (your #3 and #4) — a People bar for who is here and who is talking, pre-tag / lock IDs, hide/show you can undo, speaker search that stays open, this-meeting + prior speakers when linking a contact, and enroll a voice print on a People contact.

3. Later, only if useful: bulk reanalyze, Tasks filters/export, topic-map people, Export Full Transcript.

If yes, I'll open PRs one theme at a time from this repo into whatever branch you prefer. Happy to screen-share first if that's easier.

