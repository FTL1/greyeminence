# Changelog

All notable changes are listed here, newest first. Recent releases have
full detail; older ones are summarized. The version number tracks
`MARKETING_VERSION` in `project.yml`.

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
