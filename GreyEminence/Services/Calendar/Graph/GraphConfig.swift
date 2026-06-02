import Foundation

/// Microsoft Graph / Entra ID configuration for the calendar integration.
///
/// SETUP (one-time, ~5 min — see docs/MicrosoftGraphSetup.md):
///   1. Register a multi-tenant public-client app in any Entra tenant (a free
///      personal one works — it does NOT have to be your work tenant).
///   2. Add the redirect URI `msauth.com.greyeminence.app://auth`.
///   3. Add delegated permissions: Calendars.Read, offline_access, User.Read,
///      openid, profile, email.
///   4. Copy the Application (client) ID below.
///
/// The client ID is NOT a secret — public-client OAuth is protected by PKCE,
/// not by a secret, so it's safe to ship embedded.
enum GraphConfig {
    /// Replace the placeholder with the real Application (client) ID.
    static let clientID = "<PASTE_CLIENT_ID>"

    /// Multi-tenant + personal Microsoft accounts.
    static let authority = "https://login.microsoftonline.com/common"

    static var authorizeEndpoint: URL { URL(string: "\(authority)/oauth2/v2.0/authorize")! }
    static var tokenEndpoint: URL { URL(string: "\(authority)/oauth2/v2.0/token")! }

    /// Must match the Azure app registration AND the CFBundleURLTypes entry in Info.plist.
    static let redirectURI = "msauth.com.greyeminence.app://auth"
    static let callbackScheme = "msauth.com.greyeminence.app"

    /// Read-only calendar + the bits needed for refresh tokens and profile.
    static let scopes = "Calendars.Read offline_access User.Read openid profile email"

    static let graphBaseURL = "https://graph.microsoft.com/v1.0"

    /// AppStorage / UserDefaults keys (non-secret display + the enable toggle).
    static let enabledKey = "graphCalendarEnabled"
    static let accountEmailKey = "graphAccountEmail"
    static let accountNameKey = "graphAccountName"

    /// False while the placeholder client ID is in place — the feature stays
    /// dormant (no sign-in attempts) until a real ID is configured.
    static var isConfigured: Bool { !clientID.hasPrefix("<") && !clientID.isEmpty }
}
