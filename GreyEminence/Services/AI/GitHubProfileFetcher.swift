import Foundation

/// Fetches a public GitHub user profile + their pinned/popular repos and
/// returns a short prose summary suitable for the AI candidate-context
/// pre-amble. Unauthenticated — uses GitHub's public REST endpoints.
/// Public profiles only; private repos / orgs / employer flags require
/// auth and are out of scope for this pass.
///
/// Failure modes are logged and surfaced as nil — the candidate detail
/// view falls back to "no summary yet" with the link still clickable.
enum GitHubProfileFetcher {
    struct UserPayload: Decodable {
        let login: String
        let name: String?
        let bio: String?
        let blog: String?
        let location: String?
        let publicRepos: Int
        let followers: Int

        enum CodingKeys: String, CodingKey {
            case login
            case name
            case bio
            case blog
            case location
            case publicRepos = "public_repos"
            case followers
        }
    }

    struct RepoPayload: Decodable {
        let name: String
        let description: String?
        let language: String?
        let stargazersCount: Int
        let fork: Bool
        let archived: Bool
        let updatedAt: Date

        enum CodingKeys: String, CodingKey {
            case name
            case description
            case language
            case stargazersCount = "stargazers_count"
            case fork
            case archived
            case updatedAt = "updated_at"
        }
    }

    enum FetchError: LocalizedError {
        case invalidUsername
        case notFound
        case rateLimited
        case network(String)

        var errorDescription: String? {
            switch self {
            case .invalidUsername: "Invalid GitHub username."
            case .notFound: "GitHub user not found."
            case .rateLimited: "GitHub API rate-limited. Try again later."
            case .network(let m): "Network error: \(m)"
            }
        }
    }

    /// Pull the user + their top public, non-fork, non-archived repos by
    /// stars, and render a Markdown summary. Caller persists into
    /// `Candidate.githubSummary`.
    static func fetchSummary(for rawUsername: String) async throws -> String {
        let username = rawUsername
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "@", with: "")
        guard !username.isEmpty,
              username.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else {
            throw FetchError.invalidUsername
        }

        let user = try await fetchUser(username)
        let repos = try await fetchRepos(username)
        return renderSummary(user: user, repos: repos)
    }

    private static func fetchUser(_ username: String) async throws -> UserPayload {
        guard let url = URL(string: "https://api.github.com/users/\(username)") else {
            throw FetchError.invalidUsername
        }
        let (data, response) = try await session.data(for: requestForJSON(url))
        try validate(response: response)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(UserPayload.self, from: data)
    }

    private static func fetchRepos(_ username: String) async throws -> [RepoPayload] {
        guard let url = URL(string: "https://api.github.com/users/\(username)/repos?per_page=100&sort=updated") else {
            throw FetchError.invalidUsername
        }
        let (data, response) = try await session.data(for: requestForJSON(url))
        try validate(response: response)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([RepoPayload].self, from: data)
    }

    private static func requestForJSON(_ url: URL) -> URLRequest {
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("GreyEminence-macOS", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 15
        return req
    }

    private static func validate(response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw FetchError.network("non-HTTP response")
        }
        switch http.statusCode {
        case 200...299: return
        case 404: throw FetchError.notFound
        case 403, 429: throw FetchError.rateLimited
        default: throw FetchError.network("HTTP \(http.statusCode)")
        }
    }

    private static var session: URLSession { .shared }

    private static func renderSummary(user: UserPayload, repos: [RepoPayload]) -> String {
        var lines: [String] = []
        let displayName = user.name ?? user.login
        lines.append("**\(displayName)** (@\(user.login))")
        if let bio = user.bio, !bio.isEmpty {
            lines.append(bio)
        }

        var meta: [String] = []
        if let location = user.location, !location.isEmpty {
            meta.append("📍 \(location)")
        }
        meta.append("\(user.publicRepos) public repos")
        meta.append("\(user.followers) followers")
        if let blog = user.blog, !blog.isEmpty {
            meta.append(blog)
        }
        lines.append(meta.joined(separator: " · "))

        let interesting = repos
            .filter { !$0.fork && !$0.archived }
            .sorted { $0.stargazersCount > $1.stargazersCount }
            .prefix(5)

        if !interesting.isEmpty {
            lines.append("")
            lines.append("**Top repositories**")
            for repo in interesting {
                var bullet = "- **\(repo.name)**"
                if let lang = repo.language { bullet += " · \(lang)" }
                if repo.stargazersCount > 0 { bullet += " · ★\(repo.stargazersCount)" }
                if let desc = repo.description, !desc.isEmpty {
                    bullet += " — \(desc)"
                }
                lines.append(bullet)
            }
        }

        let recentPushes = repos
            .filter { !$0.fork && !$0.archived }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(3)
            .map(\.name)
        if !recentPushes.isEmpty {
            lines.append("")
            lines.append("Recently active: \(recentPushes.joined(separator: ", "))")
        }

        return lines.joined(separator: "\n")
    }
}
