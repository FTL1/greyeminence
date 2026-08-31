# How Grey Conseil relates to Matt’s Grey Eminence

Plain-language map of the two codebases. For how we *port* his releases, see [UPSTREAM.md](UPSTREAM.md). For how we would offer him small PRs, see [MATT-PULL-NOTES.md](MATT-PULL-NOTES.md).

## Two apps, one family

[Matt Purdon’s Grey Eminence](https://github.com/mpurdon/greyeminence) is the **shipping product**. People install it as **Grey Eminence**. It auto-updates from his Sparkle feed. Meetings live in his production library.

**Grey Conseil** (this repo) is a **side-by-side unofficial fork**, hosted at [FTL1/grey-conseil](https://github.com/FTL1/grey-conseil). It is not a replacement. Both can sit in Applications at the same time. Thorough map: [DIVERGENCE.md](DIVERGENCE.md). Legal: [DISCLAIMER.md](DISCLAIMER.md). Why the name: [NAME.md](NAME.md).

Matt’s **Grey Eminence** is *éminence grise* — the unofficial counselor ([word histories](https://wordhistories.net/2019/07/24/eminence-grise/)). **Grey Conseil** keeps that grey and adds Verne’s servant **Conseil** (counsel) from [*Twenty Thousand Leagues Under the Sea*](https://archive.org/details/in.ernet.dli.2015.459144). Homage, plus humor. Not a second Grey Eminence.

| | Matt (`mpurdon/greyeminence`) | Grey Conseil (`FTL1/grey-conseil`) |
| --- | --- | --- |
| What it is | Production Grey Eminence | Unofficial test kitchen |
| GitHub default work | `main`, tagged Sparkle releases | Branch `feature/speaker-session-rename` |
| Latest *his* release (as of this write-up) | **v0.30.1** (20 Aug 2026) | — |
| Latest *our* build | — | **Grey Conseil 0.28.4-ftl51** |
| Dock name | Grey Eminence | **Grey Conseil** |
| Bundle ID | `com.greyeminence.app` | `com.ftl1.greyeminence` |
| Meeting library | Production store | **Isolated** Grey Conseil store |
| Auto-update | Sparkle, **his** feed | Sparkle, **this** repo (`FTL1/grey-conseil` Releases) |
| Tahoe (macOS 26) | Sandboxed production build | **Unsandboxed** ad-hoc DMG so it launches |
| AI | Claude or AWS Bedrock | Those **plus xAI (Grok)** |

We do **not** push to `mpurdon`. The `upstream` remote is fetch-only. We do **not** open a PR against his repo unless we talk to Matt first.

## Shared trunk

Both trees start from Matt’s **v0.28.4** (13 Aug 2026). That is the last release we forked from.

From that point the histories are different products:

- **Matt `main`** added five commits: launch beachball fix, cancelled calendar events, live screenshot strip + his PDF export sheet, formatted copy, open-questions report callout. Those are **0.29.1 through 0.30.1**.
- **This fork** added eighty-plus commits on `feature/speaker-session-rename`: Grok, the People mixer, voice prints, Find, dossiers, capture kill switch, and the rest of the catalog in [FEATURES.md](FEATURES.md).

The Grey Conseil version number stayed **0.28.4-ftlN** on purpose. That suffix is the test series. It does **not** mean we are “stuck on August 13 while he is on 0.30.” It means we froze the *marketing* line at the fork and counted our builds as ftl1, ftl2, … ftl40.

His `feature/screen-share` branch is **not** production. It is old experimental work (hundreds of commits on the 0.21 line). We do not pull it.

`origin/main` on this repo is also **not** Matt’s main. It only holds the Grey Conseil DMG workflow on the fork’s default branch.

## What we took from him (ported)

We do not merge his `main` into Grey Conseil. We **copy the behavior** we want, one theme at a time, onto our branch. Already in this fork:

| His release | In Grey Conseil | Left out |
| --- | --- | --- |
| 0.29.1 | Core Audio poll off the main thread (no launch beachball); named startup steps | Sparkle “Checking for updates…” (Grey Conseil has Sparkle off) |
| 0.29.2 | Drop cancelled Outlook/Exchange meetings (`Canceled: …`) | — |
| 0.29.3 | Live screenshot strip while recording | His Export PDF checkbox sheet  already has Meeting Intelligence **Export** |
| 0.30.0 | Copy puts HTML + plain text on the clipboard (Teams pastes real lists) | — |
| 0.30.1 | PDF/HTML reports lead with open questions as a callout | Intelligence Export / dossier still list questions after the summary |

Marker: Grey Conseil has absorbed **v0.30.1**. The next fetch of `upstream/main` only needs commits **after** that tag.

## What this fork added that he does not ship

These stay in the fork until he asks for small PRs:

- **xAI (Grok)** as a first-class provider
- **People mixer**: chips hide/show, talk-share, lock IDs, one chip per person (Alex you + Alex Morgan collapse), guest-1 tagged as Jordan actually merges
- Voice prints, re-analyze speakers from saved audio, unknown-N leftovers
- Find this meeting (**⌘F**) and library Find (**⇧⌘F**)
- Same-speaker auto-merge, play a merged line’s full audio
- Bulk reanalyze, purpose-first rewrite, Deep / Deepest per section
- Meeting dossiers (no-hallucination prompt pack)
- Tasks rollup filters / export, topic map People / Speakers
- Capture bar: **Watch for meetings**, **Live AI**, **Stop all**; mic capture on aggregate devices
- Isolated store, name **Grey Conseil**, unsandbox, `grey-conseil-dmg.yml`, Help docs, our Sparkle feed (never his)

## Why we do not merge his `main`

A `git merge upstream/main` still thinks the common ancestor is v0.28.4, so Git re-fights files we already ported (Recording, Calendar, reports, ContentView) and can bring back Sparkle UI or his export sheet. Rebase or “reset to 0.30.1 and replay this fork” is how the isolated store and mixer get lost.

Porting is slower per commit and safer per month. Details: [UPSTREAM.md](UPSTREAM.md).

## What testers should remember

- Install **Grey Conseil** from a GitHub Release, or **Check for Updates** in the app (after the first drag-install). Leave Matt’s **Grey Eminence** installed.
- Remove **older test builds** from Applications if it is still there — same library, new name.
- A new Grey Conseil build replaces the **app**, not this library.
- If the window looks empty, you are probably in the wrong app — not a reason to copy production’s database.
- Each ad-hoc Grey Conseil DMG is a new identity to macOS. Re-grant Screen Recording and Microphone to *this* copy.

## Talking to Matt

Offer **small thematic PRs** (Grok first, then speaker UX), never `feature/speaker-session-rename` as-is. Draft: [MATT-PULL-NOTES.md](MATT-PULL-NOTES.md).
