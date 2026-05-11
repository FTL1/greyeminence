import SwiftUI

// MARK: - Model

struct ChangelogRelease: Identifiable {
    /// Version string, used as the stable identity and the read-tracking key.
    let id: String
    let version: String
    let date: Date?
    let body: String
}

// MARK: - Parser

enum ChangelogParser {
    /// Split a CHANGELOG markdown file into `## <heading>` sections. Text
    /// before the first `##` (the file's intro) is dropped. Each heading is
    /// parsed for a version token and an optional `— YYYY-MM-DD` date.
    static func parse(_ markdown: String) -> [ChangelogRelease] {
        var releases: [ChangelogRelease] = []
        var heading: String?
        var body: [String] = []

        func flush() {
            guard let h = heading else { body = []; return }
            let (version, date) = parseHeading(h)
            releases.append(
                ChangelogRelease(
                    id: version,
                    version: version,
                    date: date,
                    body: body.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                )
            )
            body = []
        }

        for line in markdown.components(separatedBy: "\n") {
            if line.hasPrefix("## ") {
                flush()
                heading = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            } else if heading != nil {
                body.append(line)
            }
        }
        flush()
        return releases
    }

    private static func parseHeading(_ heading: String) -> (version: String, date: Date?) {
        // Accepted forms:
        //   "0.11.0 — 2026-05-08"        → ("0.11.0", date)
        //   "0.10.0 — 2026-05-07 (notes)" → ("0.10.0", date)
        //   "0.9.x"                       → ("0.9.x", nil)
        //   "Earlier"                     → ("Earlier", nil)
        //   "0.12.0-dev (in progress)"    → ("0.12.0-dev", nil)
        for sep in [" — ", " – ", " - "] {
            guard let range = heading.range(of: sep) else { continue }
            let version = String(heading[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            let rest = String(heading[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            return (version.isEmpty ? heading : version, parseDate(rest))
        }
        let version = heading
            .replacingOccurrences(of: #"\s*\(.*\)\s*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return (version.isEmpty ? heading : version, nil)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static func parseDate(_ s: String) -> Date? {
        guard s.count >= 10 else { return nil }
        return dateFormatter.date(from: String(s.prefix(10)))
    }
}

// MARK: - Read-state store

enum ChangelogReadStore {
    private static let key = "changelogReadVersions"

    static func readVersions() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }

    static func markRead(_ version: String) {
        var current = readVersions()
        guard current.insert(version).inserted else { return }
        UserDefaults.standard.set(Array(current), forKey: key)
    }

    static func markAllRead(_ versions: [String]) {
        let union = readVersions().union(versions)
        UserDefaults.standard.set(Array(union), forKey: key)
    }
}

// MARK: - Scroll-to-bottom detection

/// True once the bottom sentinel of the release content has scrolled into
/// (or started inside) the viewport. Drives mark-as-read.
private struct BottomReachedKey: PreferenceKey {
    static let defaultValue: Bool = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

// MARK: - View

/// Two-pane changelog browser: release list on the left (newest first, with
/// an unread dot per version), the selected release's notes on the right.
/// Scrolling to the end of a release's notes marks it read; the only thing
/// the user has to do is reach the bottom.
struct ChangelogView: View {
    @State private var releases: [ChangelogRelease] = []
    @State private var selectedVersion: String?
    @State private var readVersions: Set<String> = []
    @State private var loadError: String?

    private var unreadCount: Int {
        releases.filter { !readVersions.contains($0.version) }.count
    }

    var body: some View {
        Group {
            if let error = loadError {
                ContentUnavailableView(
                    "Couldn't load the changelog",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else {
                HStack(spacing: 0) {
                    sidebar.frame(width: 200)
                    Divider()
                    detail
                }
            }
        }
        .onAppear(perform: load)
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("Releases")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                if unreadCount > 0 {
                    Text("\(unreadCount) new")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.tint, in: Capsule())
                }
                Spacer()
                if unreadCount > 0 {
                    Button("Mark all read") {
                        ChangelogReadStore.markAllRead(releases.map(\.version))
                        readVersions = ChangelogReadStore.readVersions()
                    }
                    .font(.caption2)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)

            Divider()

            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(releases) { release in
                        sidebarRow(release)
                    }
                }
                .padding(6)
            }
        }
    }

    private func sidebarRow(_ release: ChangelogRelease) -> some View {
        let isSelected = selectedVersion == release.version
        let isUnread = !readVersions.contains(release.version)
        return Button {
            selectedVersion = release.version
        } label: {
            HStack(spacing: 7) {
                Circle()
                    .fill(isUnread ? Color.accentColor : Color.clear)
                    .frame(width: 6, height: 6)
                VStack(alignment: .leading, spacing: 1) {
                    Text(release.version)
                        .font(.callout.weight(isUnread ? .semibold : .regular))
                        .foregroundStyle(.primary)
                    if let date = release.date {
                        Text(date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(
                isSelected ? Color.accentColor.opacity(0.15) : Color.clear,
                in: RoundedRectangle(cornerRadius: 4)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        if let version = selectedVersion,
           let release = releases.first(where: { $0.version == version }) {
            GeometryReader { viewport in
                let viewportBottom = viewport.frame(in: .global).maxY
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(release.version)
                                .font(.largeTitle.weight(.bold))
                            if let date = release.date {
                                Text(date.formatted(date: .long, time: .omitted))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }

                        MarkdownView(text: release.body)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        // Bottom sentinel — reports whether its bottom edge has
                        // reached the viewport's bottom, i.e. the user scrolled
                        // through the whole release. A short release whose notes
                        // fit without scrolling reports `true` immediately, which
                        // is correct ("you've seen all of it").
                        Color.clear
                            .frame(height: 1)
                            .background(
                                GeometryReader { sentinel in
                                    Color.clear.preference(
                                        key: BottomReachedKey.self,
                                        value: viewportBottom > 0
                                            && sentinel.frame(in: .global).maxY <= viewportBottom + 2
                                    )
                                }
                            )
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .id(version)  // resets scroll position + sentinel preference per release
                .onPreferenceChange(BottomReachedKey.self) { reached in
                    if reached { markRead(version) }
                }
            }
        } else {
            ContentUnavailableView(
                "Select a release",
                systemImage: "list.bullet.rectangle.portrait",
                description: Text("Pick a version on the left to see what changed.")
            )
        }
    }

    // MARK: Actions

    private func markRead(_ version: String) {
        guard !readVersions.contains(version) else { return }
        ChangelogReadStore.markRead(version)
        readVersions.insert(version)
    }

    private func load() {
        readVersions = ChangelogReadStore.readVersions()
        guard let url = Bundle.main.url(
            forResource: "CHANGELOG",
            withExtension: "md",
            subdirectory: "Docs"
        ) ?? Bundle.main.url(forResource: "CHANGELOG", withExtension: "md") else {
            loadError = "Bundled CHANGELOG.md not found."
            return
        }
        do {
            releases = ChangelogParser.parse(try String(contentsOf: url, encoding: .utf8))
        } catch {
            loadError = error.localizedDescription
            return
        }
        // Open on the newest release the user hasn't read yet; if everything's
        // read, open the latest one.
        selectedVersion = releases.first(where: { !readVersions.contains($0.version) })?.version
            ?? releases.first?.version
    }
}
