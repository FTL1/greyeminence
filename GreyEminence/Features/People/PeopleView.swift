import SwiftUI
import SwiftData

struct PeopleView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Contact.name) private var contacts: [Contact]
    @State private var selectedContact: Contact?
    @State private var showAddSheet = false
    @State private var showArchived = false
    @State private var searchText = ""

    private var filteredContacts: [Contact] {
        let visible = contacts.filter { showArchived || !$0.isArchived }
        if searchText.isEmpty { return visible }
        let query = searchText.lowercased()
        return visible.filter {
            $0.name.lowercased().contains(query) ||
            ($0.nickname?.lowercased().contains(query) ?? false) ||
            ($0.email?.lowercased().contains(query) ?? false)
        }
    }

    var body: some View {
        NavigationSplitView {
            // The search bar sits OUTSIDE the List in the VStack — always
            // visible regardless of scroll position. (.searchable(.sidebar)
            // lost its material in this nested split view, and a
            // safeAreaInset bar on a macOS List can end up inside the
            // scroll region.)
            VStack(spacing: 0) {
                searchBar
                Divider()
                List(filteredContacts, selection: $selectedContact) { contact in
                    ContactRowView(contact: contact)
                        .tag(contact)
                        .opacity(contact.isArchived ? 0.5 : 1)
                        .contextMenu {
                            Button(contact.isArchived ? "Unarchive" : "Archive") {
                                contact.isArchived.toggle()
                            }
                            Button("Delete", role: .destructive) {
                                if selectedContact == contact {
                                    selectedContact = nil
                                }
                                modelContext.delete(contact)
                            }
                        }
                }
            }
            .navigationTitle("People")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAddSheet = true
                    } label: {
                        Label("Add Contact", systemImage: "plus")
                    }
                }
                ToolbarItem {
                    Toggle(isOn: $showArchived) {
                        Label("Show Archived", systemImage: "archivebox")
                    }
                    .help(showArchived ? "Hide archived contacts" : "Show archived contacts")
                }
            }
            .overlay {
                if contacts.isEmpty {
                    ContentUnavailableView(
                        "No Contacts",
                        systemImage: "person.2",
                        description: Text("Add contacts to assign them to meetings and action items")
                    )
                } else if filteredContacts.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddContactSheet()
            }
        } detail: {
            if let contact = selectedContact {
                ContactDetailView(contact: contact)
            } else {
                ContentUnavailableView(
                    "No Contact Selected",
                    systemImage: "person",
                    description: Text("Select a contact to view details")
                )
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search contacts", text: $searchText)
                .textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.bar)
    }
}
