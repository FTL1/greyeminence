import SwiftUI
import SwiftData

/// Generic list/detail scaffold for "library" tabs (Rubrics, Templates,
/// and any future browsable collection of `@Model` records). Owns the
/// chrome — `NavigationSplitView`, `.searchable`, archive toggle, +Add
/// toolbar item, contextual archive/duplicate/delete, empty states,
/// and the detail-pane placeholder. Callers supply the items, the row
/// view, the editor view, an Add* sheet builder, and per-item verbs.
///
/// Why generic: `RubricListView` and `TemplateLibraryView` had ~90 lines
/// of identical chrome each. Diverging copies bit-rot — adding archived-
/// filter or context-menu items requires touching every page. This
/// scaffold makes adding a new library tab a ~30-line view.
struct LibrarySidebarScaffold<Item, Row, Editor, AddSheet>: View
where Item: Identifiable & Hashable, Row: View, Editor: View, AddSheet: View {
    let title: String
    let items: [Item]
    let searchPlaceholder: String
    let emptyTitle: String
    let emptySystemImage: String
    let emptyDescription: String
    let detailPlaceholderTitle: String
    let detailPlaceholderSystemImage: String
    let detailPlaceholderDescription: String
    let isArchived: (Item) -> Bool
    let toggleArchive: (Item) -> Void
    let duplicate: (Item) -> Void
    let delete: (Item) -> Void
    let matchesSearch: (Item, String) -> Bool

    @ViewBuilder let row: (Item) -> Row
    @ViewBuilder let editor: (Item) -> Editor
    /// Builder for the Add* sheet. The closure passed in selects the
    /// newly-created item in the sidebar.
    @ViewBuilder let addSheet: (@escaping (Item) -> Void) -> AddSheet

    @State private var selected: Item?
    @State private var showAddSheet = false
    @State private var showArchived = false
    @State private var searchText = ""

    private var filteredItems: [Item] {
        let visible = items.filter { showArchived || !isArchived($0) }
        guard !searchText.isEmpty else { return visible }
        return visible.filter { matchesSearch($0, searchText) }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            if let selected {
                editor(selected)
            } else {
                ContentUnavailableView(
                    detailPlaceholderTitle,
                    systemImage: detailPlaceholderSystemImage,
                    description: Text(detailPlaceholderDescription)
                )
            }
        }
    }

    @ViewBuilder
    private var sidebar: some View {
        List(filteredItems, selection: $selected) { item in
            sidebarRow(item)
        }
        .searchable(text: $searchText, placement: .sidebar, prompt: searchPlaceholder)
        .navigationTitle(title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAddSheet = true } label: {
                    Label("Add \(title.dropLast())", systemImage: "plus")
                }
            }
            ToolbarItem {
                Toggle(isOn: $showArchived) {
                    Label("Show Archived", systemImage: "archivebox")
                }
                .help(showArchived ? "Hide archived" : "Show archived")
            }
        }
        .overlay {
            if items.isEmpty {
                ContentUnavailableView(
                    emptyTitle,
                    systemImage: emptySystemImage,
                    description: Text(emptyDescription)
                )
            } else if filteredItems.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
        .sheet(isPresented: $showAddSheet) {
            addSheet { newItem in
                selected = newItem
            }
        }
    }

    private func sidebarRow(_ item: Item) -> some View {
        row(item)
            .tag(item)
            .opacity(isArchived(item) ? 0.5 : 1)
            .contextMenu {
                Button(isArchived(item) ? "Unarchive" : "Archive") {
                    toggleArchive(item)
                }
                Button("Duplicate") {
                    duplicate(item)
                }
                Button("Delete", role: .destructive) {
                    if selected == item { selected = nil }
                    delete(item)
                }
            }
    }
}
