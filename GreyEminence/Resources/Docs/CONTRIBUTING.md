# Contributing

This is currently a single-developer project, but the workflow is documented
here so the conventions stay consistent if it ever opens up — or if a future
me forgets.

## Project setup

Grey Eminence uses XcodeGen. Don't edit the `.xcodeproj` directly: edit
`project.yml` at the repo root, then run:

```bash
xcodegen generate
```

> **Gotcha:** `xcodegen generate` overwrites
> `GreyEminence/GreyEminence.entitlements` with an empty `<dict/>`. After
> regenerating, restore the entitlements file from git or the working copy
> backup before building, otherwise audio capture / sandbox / Sparkle
> auto-update will all break.

Dependencies are managed via SPM through `project.yml`:

- WhisperKit — on-device transcription
- FluidAudio — on-device diarization (CoreML / ANE)
- KeychainAccess — API key storage
- Sparkle — auto-update

## Coding conventions

- **Swift 6 strict concurrency.** Use `@Observable` for reference-type view
  models; never `Combine`. `@MainActor` for anything UI; `actor` for shared
  mutable services. The `LogManager` singleton is `@MainActor` — actors
  call into it via the static `LogManager.send(...)` form to avoid hopping.
- **SwiftData.** Versioned schemas only — every change adds a new
  `SchemaVNN` enum in `Services/Persistence/SchemaVersions.swift` and a
  lightweight migration stage. Bump the version in `GreyEminenceApp.swift`
  to match. Default-literal initialization on a freshly-added relationship
  has been known to crash migrations on macOS 26; prefer initializing in
  `init` instead.
- **No backwards-compat shims** unless explicitly needed. Delete unused
  code; rely on git history.
- **Comments only when the WHY is non-obvious.** Don't narrate WHAT.
- **One logical change per commit.** Commit messages explain motivation,
  not file lists.

## Testing

Run the unit-test target from Xcode (`GreyEminenceTests`) or:

```bash
xcodebuild test -project GreyEminence.xcodeproj -scheme GreyEminence \
  -destination "platform=macOS,arch=arm64"
```

For UI/feature changes, drive the actual flow in the running app — type
checks don't catch broken layouts.

## Releasing

1. Bump `MARKETING_VERSION` in `project.yml`.
2. Run `xcodegen generate` and restore entitlements.
3. Build and smoke-test the resulting app.
4. Tag the release; CI handles signing and the Sparkle appcast.
5. Watch CI — local builds don't validate notarization or sandbox
   entitlements the same way the release build does.
