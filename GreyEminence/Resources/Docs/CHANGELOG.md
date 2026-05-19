# Changelog

All notable changes are listed here, newest first. Recent releases have
full detail; older ones are summarized. The version number tracks
`MARKETING_VERSION` in `project.yml`.

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
