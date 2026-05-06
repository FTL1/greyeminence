import SwiftUI

/// Help menu items that open the bundled docs in their own window.
/// Plugged into the App's `.commands` block via
/// `CommandGroup(replacing: .help) { HelpMenuCommands() }`.
struct HelpMenuCommands: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ForEach(HelpDoc.allCases) { doc in
            Button(doc.menuTitle) {
                openWindow(id: "help-doc", value: doc)
            }
        }
    }
}

/// One of the bundled in-app docs surfaced from the Help menu.
enum HelpDoc: String, CaseIterable, Identifiable, Hashable, Codable {
    case readme = "README"
    case contributing = "CONTRIBUTING"
    case changelog = "CHANGELOG"

    var id: String { rawValue }
    var menuTitle: String {
        switch self {
        case .readme: "Read Me"
        case .contributing: "Contributing"
        case .changelog: "Changelog"
        }
    }
    var resourceName: String { rawValue }
    var iconName: String {
        switch self {
        case .readme: "book"
        case .contributing: "hammer"
        case .changelog: "clock.arrow.circlepath"
        }
    }
}

/// Window content for a Help → doc viewer. Loads the named markdown file
/// from the app bundle and renders it with MarkdownView. Read-only —
/// these files are baked into the bundle at build time.
struct HelpDocsView: View {
    let doc: HelpDoc
    @Environment(\.dismiss) private var dismiss

    @State private var markdown: String = ""
    @State private var loadError: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: doc.iconName)
                    .foregroundStyle(.cyan)
                Text(doc.menuTitle)
                    .font(.title3.weight(.semibold))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)

            Divider()

            if let error = loadError {
                ContentUnavailableView(
                    "Couldn't load \(doc.menuTitle)",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    MarkdownView(text: markdown)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                }
            }
        }
        .frame(minWidth: 640, minHeight: 480)
        .onAppear { loadDoc() }
    }

    private func loadDoc() {
        guard let url = Bundle.main.url(
            forResource: doc.resourceName,
            withExtension: "md",
            subdirectory: "Docs"
        ) ?? Bundle.main.url(
            forResource: doc.resourceName,
            withExtension: "md"
        ) else {
            loadError = "Bundled \(doc.resourceName).md not found."
            return
        }
        do {
            markdown = try String(contentsOf: url, encoding: .utf8)
        } catch {
            loadError = error.localizedDescription
        }
    }
}
