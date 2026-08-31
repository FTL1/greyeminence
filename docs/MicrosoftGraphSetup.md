# Microsoft 365 (Graph) calendar — one-time setup

The Graph calendar integration is fully built but dormant until a real Entra
(Azure AD) **Application (client) ID** is dropped into
`GreyEminence/Services/Calendar/Graph/GraphConfig.swift`.

The client ID is **not a secret** — public-client OAuth is protected by PKCE, so
it's safe to commit/ship embedded.

## 1. Register the app (~5 min)

You can register in **any** Entra tenant — it does **not** have to be your work
tenant. If your work tenant blocks app registration, create a free personal one
(sign in to <https://entra.microsoft.com> with a personal Microsoft account, or
use the Microsoft 365 Developer Program).

1. <https://entra.microsoft.com> → **App registrations** → **New registration**.
2. **Name:** `Grey Eminence`.
3. **Supported account types:** *Accounts in any organizational directory and
   personal Microsoft accounts* (multi-tenant + consumers).
4. **Redirect URI:** platform **Mobile and desktop applications** →
   `msauth.com.greyeminence.app://auth`.
5. **Register.**

## 2. Make it a public client

- **Authentication** → **Advanced settings** → **Allow public client flows** → **Yes**.
- Confirm the redirect URI from step 1 is listed under *Mobile and desktop applications*.

## 3. Add delegated permissions

**API permissions** → **Add a permission** → **Microsoft Graph** → **Delegated**:

- `Calendars.Read`
- `offline_access`
- `User.Read`
- `openid`, `profile`, `email`

These are user-consentable in most tenants (read-only, acting as the signed-in
user). Some locked-down orgs require a **one-time admin consent** — the Microsoft
sign-in page shows a "request approval" link if so.

## 4. Wire it in

- **Overview** → copy the **Application (client) ID**.
- In Grey Conseil: **Settings → Calendar** → paste the ID → **Connect Microsoft 365**.
  (You can still compile it into `GraphConfig.compiledClientID` if you want it baked in.)

That's it. The in-app sheet shares your Safari session, so an already-signed-in account is often a single consent tap. Use **Validate connection** to confirm. Connected state, an include-toggle, and Disconnect live in the same pane. Tokens are stored in the Keychain and refreshed automatically.

## Notes

- The redirect scheme is also registered in `Info.plist`
  (`CFBundleURLTypes` → `msauth.com.greyeminence.app`) and matches the bundle id
  `com.greyeminence.app`. If the bundle id changes, update all three.
- This is read-only and single-account by design. Writing events, multiple
  accounts, and push sync are out of scope for the first cut.
