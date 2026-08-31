# Staying current with Matt without killing fork work

Matt’s repo is `mpurdon/greyeminence`. Ours is `FTL1/grey-conseil`. They will keep diverging. The rule is: **fetch often, merge never, port by theme.**

Plain-language map of the two trees (what we forked, what we ported, why version numbers look “behind”): [ORIGIN.md](ORIGIN.md).

## Remotes (this machine)

```
origin    git@github.com:FTL1/grey-conseil.git     (fetch + push)
upstream  git@github.com:mpurdon/greyeminence.git  (fetch only; push is DISABLE)
```

On a new clone:

```bash
git remote add upstream git@github.com:mpurdon/greyeminence.git
git remote set-url --push upstream DISABLE
git fetch upstream --prune
```

Never `git push upstream`. Never open a PR against `mpurdon` unless we decide after talking to Matt.

## What we already ported

| Matt | What we took | What we left |
| --- | --- | --- |
| 0.29.1 `df8cd22` | Core Audio poll off the main thread; named launch steps | Sparkle “Checking for updates…” (Grey Conseil has Sparkle off) |
| 0.29.2 `b7fea5a` | Drop cancelled Outlook/Exchange events (status + `Canceled:` title) | — |
| 0.29.3 `9884ef5` | Live screenshot strip while recording; drop summary sections **after** figure anchoring | His Export PDF sheet / `ReportExportOptions` — we already have Meeting Intelligence **Export** |
| 0.30.0 `faffbcc` | Rich clipboard on Copy (HTML + plain) so Teams pastes lists | — |
| 0.30.1 `8b9ba97` | Open questions lead the PDF/HTML report as a callout | Intelligence Export / dossier order unchanged |

Marker: we have absorbed **v0.30.1**. Next fetch, only look at commits **after** that tag on `upstream/main`.

## The loop (do this after each of his releases, or weekly)

1. `git fetch upstream`
2. `git log --oneline HEAD..upstream/main` — or since the last port: `git log --oneline v0.30.1..upstream/main`
3. Read the changelog / commit messages. Sort into:
   - **Take** — bugfix or isolated feature we want (beachball, calendar, capture).
   - **Adapt** — same idea, different UI (his export sheet vs our Export menu).
   - **Skip** — Sparkle, his bundle ID, sandbox, Ventura, things we already built.
4. Port **one theme** onto `feature/speaker-session-rename`. Cherry-pick if the file overlap is small; otherwise copy the idea and write it against our files.
5. QA an Grey Conseil DMG. Then fetch again later.

Do **not**:

- `git merge upstream/main`
- Rebase our long branch onto his `main`
- Reset this fork to his tag and “replay” our commits (we would lose isolated store / unsandbox / Grok / speakers in the fight)

Those three all try to make one history. The histories are different products that share a trunk.

## Why merge is the thing that kills our work

His `main` and our branch both edit Recording, Reports, Calendar, and ContentView. A merge resolves that with conflict hunks, not with product judgment. We would spend a day putting Grok, the People bar, and `com.ftl1.greyeminence` back together.

Porting is slower per commit and safer per month.

## When we *do* want a big sync

If he ships something huge (new schema, new capture stack) and we are weeks behind:

1. Branch `sync/upstream-0.XX` from **our** `feature/speaker-session-rename`.
2. Merge `upstream/main` **there**, not on the daily branch.
3. Fix conflicts, run the Grey Conseil DMG, and only then fast-forward the daily branch.

That keeps the broken intermediate off testers.

## What stays fork-only forever

- App name **Grey Conseil**, bundle `com.ftl1.greyeminence`
- Isolated store, unsandboxed Tahoe
- Sparkle feed on **FTL1/grey-conseil** (never Matt’s)
- `.github/workflows/grey-conseil-dmg.yml`
- Help → What's in Grey Conseil / Disclaimer / How we differ
