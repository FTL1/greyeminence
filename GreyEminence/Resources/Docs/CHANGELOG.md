# Changelog

All notable changes are listed here. Earlier entries are summarized; recent
work has more detail. The version number reflects the `MARKETING_VERSION`
in `project.yml`.

## 0.10.0-dev (in progress)

**Interview workflow**
- Per-phase scorecard. Each phase (Intro / System Design / etc.) gets its
  own card with a composite grade and its rubric sections nested inside.
- Dual AI + human impressions. `InterviewImpression.aiValue` is a separate
  field; the AI no longer clobbers the interviewer's manual rating. The
  live strip and scorecard render solid dots for "You" and hollow dots
  for "AI".
- Phase-tagged notes. Each note inherits the active phase; the live notes
  panel groups by phase header and pulses the active one.
- Per-phase icon picker. `InterviewPhase.iconName` (with a curated
  catalog) so System Design, Coding, Take-home, etc. are
  glance-distinguishable in the live phase strip and setup view.
- Two-stage interview start: "Ready to interview" schedules without
  recording; "Start Interview" on the scorecard begins capture.
- Candidate brief at the rubric (phase) level, with a markdown editor
  that has formatting controls and a live preview pane, plus Copy and
  PDF export.
- Resume summarization + DnD-style character sheet driven by AI.
  Contradictions between resume and interview are flagged in red flags
  during scoring.
- Many-to-many Rubric ↔ Role with per-link strictness metadata.
- Test tab rescores past interviews against any rubric (was meeting-based).

**Recording**
- Mic silence auto-pause no longer trips spuriously across 30s windows.
  The check now uses the just-computed window average and requires at
  least one buffer.
- Configurable audio retention. Auto-deletes audio files for completed
  meetings older than the configured threshold; transcripts always stay.

**Settings**
- Interview hub tab order: Candidates · New Interview · Interviews ·
  Rubrics · Test.
- Developer Settings: database size now reads the actual ModelContainer
  config URL instead of guessing a path; schema version is read live.
- Help menu surfaces README, CONTRIBUTING, CHANGELOG, and the MIT
  LICENSE inside the app.

**Schema**
- Migrations through V8: rubric brief moved from section to rubric;
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
