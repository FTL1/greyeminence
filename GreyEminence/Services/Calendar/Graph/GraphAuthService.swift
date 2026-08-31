import AppKit
import AuthenticationServices
import CryptoKit
import Foundation

/// Microsoft Graph OAuth (Authorization Code + PKCE) for the calendar
/// integration. Presents an in-app `ASWebAuthenticationSession` sheet that
/// shares Safari's session (so an already-signed-in user often just consents),
/// stores tokens in the Keychain, and refreshes them transparently.
@MainActor
@Observable
final class GraphAuthService {
    static let shared = GraphAuthService()

    /// Connected account display info (non-secret; mirrored in UserDefaults so the
    /// connected state survives relaunch without touching the Keychain on launch).
    private(set) var connectedEmail: String?
    private(set) var connectedName: String?
    private(set) var isConnecting = false
    /// True when a token refresh failed (revoked/expired) — the UI prompts to reconnect.
    private(set) var needsReconnect = false
    private(set) var lastError: String?

    var isConnected: Bool { connectedEmail != nil }

    private let presentationProvider = AuthPresentationContextProvider()
    private var webAuthSession: ASWebAuthenticationSession?

    private enum Key {
        static let access = "msgraph.accessToken"
        static let refresh = "msgraph.refreshToken"
        static let expiresAt = "msgraph.expiresAt"
    }

    init() {
        connectedEmail = UserDefaults.standard.string(forKey: GraphConfig.accountEmailKey)
        connectedName = UserDefaults.standard.string(forKey: GraphConfig.accountNameKey)
    }

    // MARK: - Connect / disconnect

    func connect() async {
        guard GraphConfig.isConfigured else {
            lastError = "Microsoft 365 isn't set up yet — a client ID still needs to be configured."
            return
        }
        isConnecting = true
        lastError = nil
        defer { isConnecting = false }

        do {
            let verifier = Self.makeCodeVerifier()
            let challenge = Self.codeChallenge(for: verifier)
            let callback = try await presentWebAuth(url: buildAuthorizeURL(challenge: challenge))

            if let error = Self.queryItem("error", from: callback) {
                throw GraphAuthError.server(Self.queryItem("error_description", from: callback) ?? error)
            }
            guard let code = Self.queryItem("code", from: callback) else {
                throw GraphAuthError.noCode
            }

            let tokens = try await exchangeCode(code, verifier: verifier)
            persist(tokens)
            try await fetchAndStoreProfile(accessToken: tokens.accessToken)
            needsReconnect = false
            UserDefaults.standard.set(true, forKey: GraphConfig.enabledKey)
            LogManager.send("Graph: connected as \(connectedEmail ?? "unknown")", category: .general)
        } catch {
            if let asError = error as? ASWebAuthenticationSessionError, asError.code == .canceledLogin {
                // User dismissed the sheet — not an error worth surfacing loudly.
                LogManager.send("Graph: sign-in cancelled by user", category: .general)
                return
            }
            lastError = Self.friendly(error)
            LogManager.send("Graph: connect failed — \(error.localizedDescription)", category: .general, level: .warning)
        }
    }

    /// Hit Graph `/me` with the stored token. Used by Settings → Validate.
    func validate() async {
        guard GraphConfig.isConfigured else {
            lastError = "Paste a Microsoft Application (client) ID in Settings → Calendar first."
            return
        }
        guard let token = await validAccessToken() else {
            lastError = lastError ?? "Not signed in — use Connect Microsoft 365."
            needsReconnect = connectedEmail != nil
            return
        }
        do {
            try await fetchAndStoreProfile(accessToken: token)
            lastError = nil
            needsReconnect = false
            LogManager.send("Graph: validated as \(connectedEmail ?? "unknown")", category: .general)
        } catch {
            lastError = Self.friendly(error)
            needsReconnect = true
        }
    }

    func disconnect() {
        keychainRemove(Key.access)
        keychainRemove(Key.refresh)
        keychainRemove(Key.expiresAt)
        UserDefaults.standard.removeObject(forKey: GraphConfig.accountEmailKey)
        UserDefaults.standard.removeObject(forKey: GraphConfig.accountNameKey)
        UserDefaults.standard.set(false, forKey: GraphConfig.enabledKey)
        connectedEmail = nil
        connectedName = nil
        needsReconnect = false
        lastError = nil
        LogManager.send("Graph: disconnected", category: .general)
    }

    // MARK: - Token access (used by GraphCalendarProvider)

    /// A currently-valid access token, refreshing if expired. nil when not
    /// connected, not configured, or the refresh failed.
    func validAccessToken() async -> String? {
        guard GraphConfig.isConfigured else { return nil }
        if let access = keychainGet(Key.access),
           let expires = keychainGet(Key.expiresAt).flatMap(Double.init),
           Date(timeIntervalSince1970: expires).timeIntervalSinceNow > 60 {
            return access
        }
        guard let refreshToken = keychainGet(Key.refresh) else { return nil }
        do {
            let tokens = try await refresh(using: refreshToken)
            persist(tokens)
            needsReconnect = false
            return tokens.accessToken
        } catch {
            LogManager.send("Graph: token refresh failed — \(error.localizedDescription)", category: .general, level: .warning)
            needsReconnect = true
            // Surface the same actionable message the connect path uses, so the
            // "Reconnect needed" row can explain why (e.g. admin approval).
            lastError = Self.friendly(error)
            return nil
        }
    }

    // MARK: - OAuth network

    private func exchangeCode(_ code: String, verifier: String) async throws -> TokenResponse {
        try await postToken([
            "client_id": GraphConfig.clientID,
            "scope": GraphConfig.scopes,
            "code": code,
            "redirect_uri": GraphConfig.redirectURI,
            "grant_type": "authorization_code",
            "code_verifier": verifier,
        ])
    }

    private func refresh(using refreshToken: String) async throws -> TokenResponse {
        try await postToken([
            "client_id": GraphConfig.clientID,
            "scope": GraphConfig.scopes,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token",
        ])
    }

    private func postToken(_ params: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: GraphConfig.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncode(params).data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            if let err = try? JSONDecoder().decode(TokenError.self, from: data) {
                throw GraphAuthError.server(err.error_description ?? err.error)
            }
            throw GraphAuthError.server("Microsoft token request failed")
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(TokenResponse.self, from: data)
    }

    private func fetchAndStoreProfile(accessToken: String) async throws {
        var request = URLRequest(url: URL(string: "\(GraphConfig.graphBaseURL)/me")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: request)
        let me = try JSONDecoder().decode(GraphMe.self, from: data)
        let email = me.mail ?? me.userPrincipalName
        connectedEmail = email
        connectedName = me.displayName
        if let email { UserDefaults.standard.set(email, forKey: GraphConfig.accountEmailKey) }
        if let name = me.displayName { UserDefaults.standard.set(name, forKey: GraphConfig.accountNameKey) }
    }

    // MARK: - ASWebAuthenticationSession

    private func presentWebAuth(url: URL) async throws -> URL {
        // Release the retained session once we're done, and cancel it if the
        // enclosing Task is cancelled (e.g. the Settings window closes mid-auth)
        // — cancel() triggers the completion handler, so the continuation always
        // resumes instead of stranding "Connecting…" forever.
        defer { webAuthSession = nil }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let session = ASWebAuthenticationSession(
                    url: url,
                    callbackURLScheme: GraphConfig.callbackScheme
                ) { callbackURL, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let callbackURL {
                        continuation.resume(returning: callbackURL)
                    } else {
                        continuation.resume(throwing: GraphAuthError.noCode)
                    }
                }
                session.presentationContextProvider = presentationProvider
                // Share the system browser session so an already-signed-in user
                // doesn't have to retype credentials.
                session.prefersEphemeralWebBrowserSession = false
                webAuthSession = session
                if !session.start() {
                    continuation.resume(throwing: GraphAuthError.cannotStart)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.webAuthSession?.cancel() }
        }
    }

    private func buildAuthorizeURL(challenge: String) -> URL {
        var comps = URLComponents(url: GraphConfig.authorizeEndpoint, resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "client_id", value: GraphConfig.clientID),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: GraphConfig.redirectURI),
            .init(name: "response_mode", value: "query"),
            .init(name: "scope", value: GraphConfig.scopes),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "prompt", value: "select_account"),
        ]
        return comps.url!
    }

    // MARK: - Persistence helpers

    private func persist(_ tokens: TokenResponse) {
        keychainSet(tokens.accessToken, Key.access)
        // Microsoft rotates the refresh token; keep the previous one if a refresh
        // response omits it.
        if let refresh = tokens.refreshToken {
            keychainSet(refresh, Key.refresh)
        }
        let expiresAt = Date().addingTimeInterval(TimeInterval(tokens.expiresIn))
        keychainSet(String(expiresAt.timeIntervalSince1970), Key.expiresAt)
    }

    private func keychainGet(_ key: String) -> String? { (try? KeychainHelper.get(key)) ?? nil }
    private func keychainSet(_ value: String, _ key: String) { try? KeychainHelper.set(value, key: key) }
    private func keychainRemove(_ key: String) { try? KeychainHelper.remove(key) }

    // MARK: - PKCE + helpers

    private static func makeCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    private static func codeChallenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
    }

    private static func queryItem(_ name: String, from url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == name })?.value
    }

    private static let unreserved: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()

    private static func formEncode(_ params: [String: String]) -> String {
        params
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? $0.value)" }
            .joined(separator: "&")
    }

    private static func friendly(_ error: Error) -> String {
        let text = error.localizedDescription
        if text.contains("AADSTS65001") || text.lowercased().contains("consent") || text.lowercased().contains("admin") {
            return "Your organization requires admin approval for this app. Use the “request approval” link on the Microsoft sign-in page, then reconnect."
        }
        if case GraphAuthError.server(let message) = error {
            return message
        }
        return text
    }
}

// MARK: - Supporting types

enum GraphAuthError: LocalizedError {
    case noCode
    case cannotStart
    case server(String)

    var errorDescription: String? {
        switch self {
        case .noCode: "Microsoft sign-in didn't return an authorization code."
        case .cannotStart: "Couldn't open the Microsoft sign-in window."
        case .server(let message): message
        }
    }
}

private struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int
}

private struct TokenError: Decodable {
    let error: String
    let error_description: String?
}

private struct GraphMe: Decodable {
    let displayName: String?
    let mail: String?
    let userPrincipalName: String?
}

/// ASWebAuthenticationSession needs an NSObject anchor provider; kept separate so
/// GraphAuthService can stay a plain @Observable class.
private final class AuthPresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first ?? ASPresentationAnchor()
    }
}

extension Data {
    /// Base64URL without padding (for PKCE).
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
