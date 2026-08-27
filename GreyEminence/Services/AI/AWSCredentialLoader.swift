import CryptoKit
import Foundation

struct AWSCredentials: Sendable {
    let accessKeyId: String
    let secretAccessKey: String
    let sessionToken: String?
}

struct SSOProfileConfig {
    let startUrl: String
    let ssoRegion: String
    let accountId: String
    let roleName: String
    let sessionName: String?
}

enum AWSCredentialLoader {
    private static let bookmarkKey = "awsDirectoryBookmark"

    // MARK: - Security-Scoped Bookmark

    static func persistAccess(to directoryURL: URL) {
        if let data = try? directoryURL.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            UserDefaults.standard.set(data, forKey: bookmarkKey)
        }
    }

    @discardableResult
    static func restoreAccess() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else {
            return nil
        }

        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            // Bookmark can't be resolved — clear it so UI shows "Locate" prompt
            clearBookmark()
            return nil
        }

        let didAccess = url.startAccessingSecurityScopedResource()

        if isStale || !didAccess {
            // Try to re-create the bookmark from the resolved URL
            persistAccess(to: url)
        }

        return didAccess ? url : nil
    }

    static var hasBookmark: Bool {
        UserDefaults.standard.data(forKey: bookmarkKey) != nil
    }

    static func clearBookmark() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
    }

    // MARK: - Credential Loading

    static func loadCredentials(profile: String) async throws -> AWSCredentials {
        // Check if this is an SSO profile first
        if let ssoConfig = parseSSOConfig(profile: profile) {
            return try await loadSSOCredentials(config: ssoConfig)
        }

        // credential_process: an external helper prints credentials as JSON.
        // Whether a sandboxed app may spawn one is decided by the sandbox at
        // run time, so this attempts it and reports what actually happened
        // rather than refusing on principle.
        if let command = credentialProcessCommand(profile: profile) {
            return try await loadProcessCredentials(command: command, profile: profile)
        }

        // Fall back to static credentials from ~/.aws/credentials
        return try loadStaticCredentials(profile: profile)
    }

    // MARK: - credential_process

    static func credentialProcessCommand(profile: String) -> String? {
        guard let configURL = try? resolveConfigFile(),
              let content = try? String(contentsOf: configURL, encoding: .utf8) else { return nil }
        let sectionName = profile == "default" ? "default" : "profile \(profile)"
        let value = parseINI(content)[sectionName]?["credential_process"]
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    /// Split a credential_process command the way a shell would, so a quoted
    /// path containing spaces stays one argument.
    static func tokenizeCommand(_ command: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var quote: Character?

        for character in command {
            if let active = quote {
                if character == active { quote = nil } else { current.append(character) }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character.isWhitespace {
                if !current.isEmpty { tokens.append(current); current = "" }
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    /// Response shape defined by the credential_process contract.
    private struct ProcessCredentials: Decodable {
        let Version: Int?
        let AccessKeyId: String
        let SecretAccessKey: String
        let SessionToken: String?
    }

    private static func loadProcessCredentials(command: String, profile: String) async throws -> AWSCredentials {
        let tokens = tokenizeCommand(command)
        guard let executable = tokens.first else {
            throw AWSCredentialError.credentialProcessFailed(profile, "empty credential_process command")
        }
        // No reachability pre-check. Inside the sandbox a helper that exists
        // and is executable still reports as neither, because the stat itself
        // is denied — so the check produced "not found" for a file that is
        // plainly there, sending the user to fix a path that was correct.
        // Let the launch itself decide, and report the real errno.

        let output: Data
        do {
            output = try await runProcess(executable: executable, arguments: Array(tokens.dropFirst()))
        } catch let error as AWSCredentialError {
            throw error
        } catch {
            let nsError = error as NSError
            // The sandbox denies exec with EPERM. Say that plainly — it is a
            // property of the app, not of the user's AWS setup, and no amount
            // of reconfiguring the profile will change it.
            // The sandbox surfaces as either a denied exec (EPERM) or a file
            // it won't admit exists (ENOENT / NSFileNoSuchFile) — both mean
            // "this app may not launch that", not "your config is wrong".
            let blocked = (nsError.domain == NSPOSIXErrorDomain && (nsError.code == Int(EPERM) || nsError.code == Int(ENOENT)))
                || (nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileNoSuchFileError)
            if blocked {
                throw AWSCredentialError.credentialProcessBlocked(profile)
            }
            throw AWSCredentialError.credentialProcessFailed(profile, error.localizedDescription)
        }

        guard let decoded = try? JSONDecoder().decode(ProcessCredentials.self, from: output) else {
            let text = String(data: output, encoding: .utf8) ?? ""
            throw AWSCredentialError.credentialProcessFailed(
                profile,
                text.isEmpty ? "helper produced no output" : "unexpected output: \(text.prefix(200))"
            )
        }
        return AWSCredentials(
            accessKeyId: decoded.AccessKeyId,
            secretAccessKey: decoded.SecretAccessKey,
            sessionToken: decoded.SessionToken
        )
    }

    /// A helper may need to refresh an SSO session, so allow it real time —
    /// but never hang the caller forever.
    private static let credentialProcessTimeout: TimeInterval = 60

    private static func runProcess(executable: String, arguments: [String]) async throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()

        let deadline = Date().addingTimeInterval(credentialProcessTimeout)
        while process.isRunning && Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        if process.isRunning {
            process.terminate()
            throw AWSCredentialError.credentialProcessFailed(
                executable,
                "timed out after \(Int(credentialProcessTimeout))s"
            )
        }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let message = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw AWSCredentialError.credentialProcessFailed(
                executable,
                message.isEmpty ? "exited with status \(process.terminationStatus)" : String(message.prefix(200))
            )
        }
        return data
    }

    static func loadRegion(profile: String) -> String? {
        guard let configURL = try? resolveConfigFile(),
              let content = try? String(contentsOf: configURL, encoding: .utf8) else {
            return nil
        }

        let parsed = parseINI(content)
        let sectionName = profile == "default" ? "default" : "profile \(profile)"
        return parsed[sectionName]?["region"]
    }

    static func availableProfiles() -> [String] {
        guard let configURL = try? resolveConfigFile(),
              let content = try? String(contentsOf: configURL, encoding: .utf8) else {
            return []
        }

        return parseINI(content).keys.compactMap { key in
            if key == "default" { return key }
            if key.hasPrefix("profile ") { return String(key.dropFirst(8)) }
            return nil
        }.sorted()
    }

    /// How a profile obtains credentials, and whether this app can follow it.
    ///
    /// `availableProfiles()` lists everything in the config file, including
    /// profiles that can never authenticate here — offering one of those in a
    /// picker produces a baffling "profile not found" at the first request,
    /// which is exactly what happened. Classify instead, so the UI can offer
    /// only what works and say why the rest don't.
    enum ProfileKind: Equatable {
        case sso
        case staticCredentials
        /// `role_arn` + `source_profile`: needs an STS AssumeRole call that
        /// isn't implemented yet.
        case assumeRole(source: String?)
        /// `credential_process`: shells out to an external helper. The app is
        /// sandboxed, so it cannot spawn one — this is a permanent no, not a
        /// missing feature.
        case credentialProcess
        case noCredentials

        var isSupported: Bool {
            switch self {
            // credential_process is attempted rather than assumed: whether the
            // sandbox permits launching the helper is decided at run time, and
            // the Test connection button reports what actually happened.
            case .sso, .staticCredentials, .credentialProcess: true
            case .assumeRole, .noCredentials: false
            }
        }

        var reason: String {
            switch self {
            case .sso: "AWS SSO"
            case .staticCredentials: "access key"
            case .assumeRole(let source):
                "assumes a role via \(source ?? "another profile") — not supported yet"
            case .credentialProcess:
                "external credential helper"
            case .noCredentials:
                "no credentials configured"
            }
        }
    }

    struct ProfileInfo: Equatable, Identifiable {
        let name: String
        let kind: ProfileKind
        let region: String?

        var id: String { name }
        var isSupported: Bool { kind.isSupported }
    }

    /// Every profile from both `~/.aws/config` and `~/.aws/credentials`,
    /// classified. Credentials-file-only profiles are included: they
    /// authenticate perfectly well and were invisible before, because the
    /// listing only ever read the config file.
    static func describedProfiles() -> [ProfileInfo] {
        var config: [String: [String: String]] = [:]
        if let url = try? resolveConfigFile(), let content = try? String(contentsOf: url, encoding: .utf8) {
            config = parseINI(content)
        }
        var credentials: [String: [String: String]] = [:]
        if let url = try? resolveCredentialsFile(), let content = try? String(contentsOf: url, encoding: .utf8) {
            credentials = parseINI(content)
        }

        var infos: [String: ProfileInfo] = [:]
        for (section, values) in config {
            // sso-session blocks are shared configuration, not profiles.
            guard !section.hasPrefix("sso-session") else { continue }
            let name = section == "default" ? "default" : (section.hasPrefix("profile ") ? String(section.dropFirst(8)) : section)
            let kind: ProfileKind
            if values["sso_start_url"] != nil || values["sso_session"] != nil {
                kind = .sso
            } else if values["role_arn"] != nil {
                kind = .assumeRole(source: values["source_profile"])
            } else if values["credential_process"] != nil {
                kind = .credentialProcess
            } else if credentials[name]?["aws_access_key_id"] != nil {
                kind = .staticCredentials
            } else {
                kind = .noCredentials
            }
            infos[name] = ProfileInfo(name: name, kind: kind, region: values["region"])
        }

        for (name, values) in credentials where infos[name] == nil {
            guard values["aws_access_key_id"] != nil else { continue }
            infos[name] = ProfileInfo(name: name, kind: .staticCredentials, region: nil)
        }

        return infos.values.sorted { $0.name < $1.name }
    }

    /// Profiles this app can actually authenticate as.
    static func usableProfiles() -> [ProfileInfo] {
        describedProfiles().filter(\.isSupported)
    }

    // MARK: - Static Credentials

    private static func loadStaticCredentials(profile: String) throws -> AWSCredentials {
        let credentialsURL = try resolveCredentialsFile()
        let content = try String(contentsOf: credentialsURL, encoding: .utf8)
        let parsed = parseINI(content)

        guard let section = parsed[profile] else {
            throw AWSCredentialError.profileNotFound(profile)
        }

        guard let accessKey = section["aws_access_key_id"],
              let secretKey = section["aws_secret_access_key"] else {
            throw AWSCredentialError.missingCredentials(profile)
        }

        return AWSCredentials(
            accessKeyId: accessKey,
            secretAccessKey: secretKey,
            sessionToken: section["aws_session_token"]
        )
    }

    // MARK: - SSO

    static func parseSSOConfig(profile: String) -> SSOProfileConfig? {
        guard let configURL = try? resolveConfigFile(),
              let content = try? String(contentsOf: configURL, encoding: .utf8) else {
            return nil
        }

        let parsed = parseINI(content)
        let sectionName = profile == "default" ? "default" : "profile \(profile)"

        guard let section = parsed[sectionName] else { return nil }

        // New format: sso_session reference
        if let sessionName = section["sso_session"],
           let ssoSession = parsed["sso-session \(sessionName)"],
           let startUrl = ssoSession["sso_start_url"],
           let ssoRegion = ssoSession["sso_region"],
           let accountId = section["sso_account_id"],
           let roleName = section["sso_role_name"] {
            return SSOProfileConfig(
                startUrl: startUrl,
                ssoRegion: ssoRegion,
                accountId: accountId,
                roleName: roleName,
                sessionName: sessionName
            )
        }

        // Legacy format: SSO fields directly in profile
        if let startUrl = section["sso_start_url"],
           let ssoRegion = section["sso_region"],
           let accountId = section["sso_account_id"],
           let roleName = section["sso_role_name"] {
            return SSOProfileConfig(
                startUrl: startUrl,
                ssoRegion: ssoRegion,
                accountId: accountId,
                roleName: roleName,
                sessionName: nil
            )
        }

        return nil
    }

    private static func loadSSOCredentials(config: SSOProfileConfig) async throws -> AWSCredentials {
        let token = try loadCachedSSOToken(config: config)
        return try await fetchRoleCredentials(config: config, accessToken: token)
    }

    private static func loadCachedSSOToken(config: SSOProfileConfig) throws -> String {
        // Cache key: SHA1 of session name (new format) or start URL (legacy)
        let cacheKeySource = config.sessionName ?? config.startUrl
        let hash = Insecure.SHA1.hash(data: Data(cacheKeySource.utf8))
        let cacheFileName = hash.map { String(format: "%02x", $0) }.joined() + ".json"

        let cacheFile: URL
        if let dirURL = restoreAccess() {
            cacheFile = dirURL.appendingPathComponent("sso/cache/\(cacheFileName)")
        } else {
            cacheFile = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".aws/sso/cache/\(cacheFileName)")
        }

        guard let data = try? Data(contentsOf: cacheFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["accessToken"] as? String else {
            throw AWSCredentialError.ssoTokenNotFound
        }

        // Check expiration
        if let expiresAt = json["expiresAt"] as? String {
            let formats = [
                "yyyy-MM-dd'T'HH:mm:ss'Z'",
                "yyyy-MM-dd'T'HH:mm:ss'UTC'",
                "yyyy-MM-dd'T'HH:mm:ssZ",
                "yyyy-MM-dd'T'HH:mm:ssXXXXX",
            ]
            for format in formats {
                let df = DateFormatter()
                df.locale = Locale(identifier: "en_US_POSIX")
                df.timeZone = TimeZone(identifier: "UTC")
                df.dateFormat = format
                if let expiry = df.date(from: expiresAt), expiry < Date() {
                    throw AWSCredentialError.ssoTokenExpired
                }
            }
        }

        return accessToken
    }

    private static func fetchRoleCredentials(
        config: SSOProfileConfig,
        accessToken: String
    ) async throws -> AWSCredentials {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "portal.sso.\(config.ssoRegion).amazonaws.com"
        components.path = "/federation/credentials"
        components.queryItems = [
            URLQueryItem(name: "role_name", value: config.roleName),
            URLQueryItem(name: "account_id", value: config.accountId),
        ]

        guard let url = components.url else {
            throw AWSCredentialError.ssoFetchFailed("Invalid SSO URL")
        }

        var request = URLRequest(url: url)
        request.setValue(accessToken, forHTTPHeaderField: "x-amz-sso_bearer_token")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AWSCredentialError.ssoFetchFailed("HTTP \(statusCode): \(body)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let roleCreds = json["roleCredentials"] as? [String: Any],
              let accessKeyId = roleCreds["accessKeyId"] as? String,
              let secretAccessKey = roleCreds["secretAccessKey"] as? String,
              let sessionToken = roleCreds["sessionToken"] as? String else {
            throw AWSCredentialError.ssoFetchFailed("Invalid response format")
        }

        return AWSCredentials(
            accessKeyId: accessKeyId,
            secretAccessKey: secretAccessKey,
            sessionToken: sessionToken
        )
    }

    // MARK: - File Resolution

    private static func resolveConfigFile() throws -> URL {
        if let dirURL = restoreAccess() {
            let configURL = dirURL.appendingPathComponent("config")
            if FileManager.default.fileExists(atPath: configURL.path) {
                return configURL
            }
        }

        let directPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".aws/config")
        if FileManager.default.fileExists(atPath: directPath.path) {
            return directPath
        }

        throw AWSCredentialError.configFileNotFound
    }

    private static func resolveCredentialsFile() throws -> URL {
        if let dirURL = restoreAccess() {
            let credURL = dirURL.appendingPathComponent("credentials")
            if FileManager.default.fileExists(atPath: credURL.path) {
                return credURL
            }
        }

        let directPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".aws/credentials")
        if FileManager.default.fileExists(atPath: directPath.path) {
            return directPath
        }

        throw AWSCredentialError.credentialsFileNotFound
    }

    // MARK: - INI Parser

    private static func parseINI(_ content: String) -> [String: [String: String]] {
        var result: [String: [String: String]] = [:]
        var currentSection: String?

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix(";") {
                continue
            }

            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                currentSection = String(trimmed.dropFirst().dropLast())
                    .trimmingCharacters(in: .whitespaces)
                if result[currentSection!] == nil {
                    result[currentSection!] = [:]
                }
                continue
            }

            if let section = currentSection,
               let eqIndex = trimmed.firstIndex(of: "=") {
                let key = trimmed[trimmed.startIndex..<eqIndex]
                    .trimmingCharacters(in: .whitespaces)
                let value = trimmed[trimmed.index(after: eqIndex)...]
                    .trimmingCharacters(in: .whitespaces)
                result[section, default: [:]][key] = value
            }
        }

        return result
    }
}

enum AWSCredentialError: LocalizedError {
    case profileNotFound(String)
    case missingCredentials(String)
    case credentialsFileNotFound
    case configFileNotFound
    case ssoTokenNotFound
    case ssoTokenExpired
    case ssoFetchFailed(String)
    case credentialProcessFailed(String, String)
    /// The sandbox refused to launch the helper. A property of this app, not
    /// of the user's AWS configuration.
    case credentialProcessBlocked(String)

    var errorDescription: String? {
        switch self {
        case .credentialProcessFailed(let profile, let detail):
            "Profile '\(profile)' credential helper failed: \(detail)"
        case .credentialProcessBlocked(let profile):
            "Profile '\(profile)' gets its credentials from an external helper, and macOS won't let this app launch it — the app is sandboxed, so programs outside it are off-limits regardless of whether the path is correct. Use an SSO or access-key profile instead."
        case .profileNotFound(let profile):
            "AWS profile '\(profile)' not found"
        case .missingCredentials(let profile):
            "Missing access key or secret key in profile '\(profile)'"
        case .credentialsFileNotFound:
            "~/.aws/credentials not found — use 'Locate' to grant access"
        case .configFileNotFound:
            "~/.aws/config not found — use 'Locate' to grant access"
        case .ssoTokenNotFound:
            "SSO token not found — run 'aws sso login' first"
        case .ssoTokenExpired:
            "SSO token expired — run 'aws sso login' to refresh"
        case .ssoFetchFailed(let detail):
            "SSO credential fetch failed: \(detail)"
        }
    }
}
