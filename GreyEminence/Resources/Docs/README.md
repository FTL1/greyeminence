# Grey Eminence

Native macOS meeting recording, transcription, and interview-scoring app.

Grey Eminence captures both the microphone and system audio during a meeting,
transcribes everything on-device with WhisperKit + FluidAudio diarization,
and — for interview workflows — scores the candidate against a rubric using
Claude.

## What it does

- **Mic + system audio capture.** Core Audio Taps on the system side, no
  ScreenCaptureKit fallback. The mic stream is used as a hint to label the
  "Me" speaker in diarization.
- **On-device transcription.** WhisperKit handles speech-to-text; FluidAudio
  handles speaker separation on the Apple Neural Engine. Multi-speaker calls
  (Teams, Zoom, Meet, anything) get distinct "Speaker 1 / 2 / 3..." labels
  with stable colors.
- **AI intelligence.** Claude API only — no local LLM fallback. Used for
  meeting summarization, action-item extraction, and interview scoring
  against rubrics.
- **Interview workflow.** Multi-phase interviews (Intro → System Design →
  Coding → Conclusion, etc.) with per-phase rubrics, AI scoring, and a
  human/AI dual-impression panel. Phase-tagged notes capture context for
  each part of the interview.
- **Vault export.** Optional Obsidian vault export for meetings + interviews.

## Requirements

- macOS 14.4 or later, Apple Silicon only.
- Anthropic API key (Settings → AI) for the intelligence features.
- Optional: an Obsidian vault if you want markdown export.

## Build & run

This project uses XcodeGen. Regenerate the Xcode project after editing
`project.yml`:

```bash
xcodegen generate
xcodebuild -project GreyEminence.xcodeproj -scheme GreyEminence \
  -destination "platform=macOS,arch=arm64" build
```

Open the built app from DerivedData or run from Xcode.

## Where things live

- `GreyEminence/App/` — entry point, lifecycle, root navigation.
- `GreyEminence/Features/` — feature modules (Recording, Interview,
  Insights, Settings, etc.).
- `GreyEminence/Models/` — SwiftData `@Model` classes.
- `GreyEminence/Services/` — audio capture, transcription, AI clients,
  storage, persistence.
- `GreyEminence/Resources/` — assets and bundled docs.

## License

MIT — see [LICENSE](LICENSE) at the repo root, or open
**Help → License** inside the app.
