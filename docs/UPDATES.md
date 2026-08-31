# Grey Conseil Check for Updates

Sparkle in this fork talks to **github.com/FTL1/grey-conseil/releases**, never to Matt’s feed.

## One-time secret

The private EdDSA seed lives on the build machine as:

`~/.config/grey-conseil-sparkle/eddsa_private_seed.b64`

Public key (already in `Info.plist` as `SUPublicEDKey`):

`YOyoHHGKi4s99Ze1dIcPl1GZKK/bfZtm0QjwATBzI7Q=`

Set the GitHub Actions secret (once):

```bash
gh secret set SPARKLE_PRIVATE_KEY -R FTL1/grey-conseil \
  < ~/.config/grey-conseil-sparkle/eddsa_private_seed.b64
```

Do not commit the private key. If it is lost, generate a new pair, put the new public key in Info.plist, and everyone must reinstall once.

## How a release happens

1. Bump `GC_MARKETING_VERSION` in `.github/workflows/grey-conseil-dmg.yml` (and changelog).
2. Push `feature/speaker-session-rename`.
3. Actions → **Build Grey Conseil DMG** → Run workflow.
4. The job uploads a DMG artifact **and** creates GitHub Release `v0.28.4-ftlN` with the DMG + `appcast.xml`.
5. Installed Grey Conseil: **Check for Updates**. Sparkle reads
   `https://github.com/FTL1/grey-conseil/releases/latest/download/appcast.xml`.

The jump from **older test builds** or **older Notebook builds** to **Grey Conseil.app** is a drag-install (same bundle ID, same library). After that, Check for Updates is enough.

Debug / DerivedData builds never auto-update (they would overwrite your working copy).
