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
    /// Compiled fallback. Prefer Settings → Calendar (UserDefaults).
    static let compiledClientID = "<PASTE_CLIENT_ID>"
    static let clientIDDefaultsKey = "graphClientID"

    /// Application (client) ID. Settings can paste one without a rebuild.
    static var clientID: String {
        let stored = UserDefaults.standard.string(forKey: clientIDDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !stored.isEmpty { return stored }
        return compiledClientID
    }

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

    /// False until a real Entra Application (client) ID is pasted in Settings
    /// or compiled into `compiledClientID`.
    static var isConfigured: Bool {
        let id = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        return !id.isEmpty && !id.hasPrefix("<")
    }
}
