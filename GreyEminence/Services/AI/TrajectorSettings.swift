import Foundation

struct TrajectorSettings {
    let sonnetModel: String?
    let opusModel: String?
    let haikuModel: String?
    /// Inference-profile ARNs for the embedding models, when the org routes
    /// those through profiles too. Defaulted so adding a slot doesn't ripple
    /// through every construction site.
    var titanEmbedModel: String? = nil
    var cohereEmbedModel: String? = nil
    let awsProfile: String?
    let awsRegion: String?

    private static let bookmarkKey = "claudeConfigBookmark"

    // MARK: - Security-Scoped Bookmark

    static func persistAccess(to fileURL: URL) {
        if let data = try? fileURL.bookmarkData(
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
            return nil
        }

        _ = url.startAccessingSecurityScopedResource()

        if isStale {
            persistAccess(to: url)
        }

        return url
    }

    static var hasBookmark: Bool {
        UserDefaults.standard.data(forKey: bookmarkKey) != nil
    }

    // MARK: - Loading

    static func load() -> TrajectorSettings? {
        guard let url = resolveSettingsFile(),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let env = json["env"] as? [String: String] else {
            return nil
        }

        return TrajectorSettings(
            sonnetModel: env["ANTHROPIC_DEFAULT_SONNET_MODEL"],
            opusModel: env["ANTHROPIC_DEFAULT_OPUS_MODEL"],
            haikuModel: env["ANTHROPIC_DEFAULT_HAIKU_MODEL"],
            titanEmbedModel: env["BEDROCK_TITAN_EMBED_MODEL"],
            cohereEmbedModel: env["BEDROCK_COHERE_EMBED_MODEL"],
            awsProfile: env["AWS_PROFILE"],
            awsRegion: env["AWS_REGION"]
        )
    }

    private static func resolveSettingsFile() -> URL? {
        // Try security-scoped bookmark first
        if let url = restoreAccess(),
           FileManager.default.fileExists(atPath: url.path) {
            return url
        }

        // Fallback: direct path (works outside sandbox)
        let directPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/trajector-settings.json")
        if FileManager.default.fileExists(atPath: directPath.path) {
            return directPath
        }

        return nil
    }
}
