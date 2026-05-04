import SwiftUI
import SwiftData

struct ContactPicker: View {
    @Query(sort: \Contact.name) private var allContacts: [Contact]
    @State private var searchText = ""
    @State private var hoveredID: PersistentIdentifier?
    @FocusState private var searchFocused: Bool
    var excludedContacts: Set<PersistentIdentifier>
    /// Contacts to surface above the divider — typically the attendees of the
    /// meeting this picker is being shown from. The same contact never appears
    /// in both groups; if a contact is in `prioritizedContacts`, it's omitted
    /// from the "other" list below the divider.
    var prioritizedContacts: [Contact] = []
    /// Header shown above the prioritized group. Only rendered when there's
    /// at least one prioritized contact and the user hasn't typed a search.
    var prioritizedHeader: String = "Meeting attendees"
    var onSelect: (Contact) -> Void

    private var availableContacts: [Contact] {
        allContacts.filter { !$0.isArchived && !excludedContacts.contains($0.persistentModelID) }
    }

    private var prioritizedIDs: Set<PersistentIdentifier> {
        Set(prioritizedContacts.map(\.persistentModelID))
    }

    private var prioritizedAvailable: [Contact] {
        let available = availableContacts
        return prioritizedContacts
            .filter { contact in available.contains(where: { $0.persistentModelID == contact.persistentModelID }) }
    }

    private var otherAvailable: [Contact] {
        let priorIDs = prioritizedIDs
        return availableContacts.filter { !priorIDs.contains($0.persistentModelID) }
    }

    private func match(_ contact: Contact, query: String) -> Bool {
        contact.name.lowercased().contains(query) ||
        (contact.nickname?.lowercased().contains(query) ?? false) ||
        (contact.email?.lowercased().contains(query) ?? false)
    }

    /// Flat list used when the user is searching — grouping headers go away
    /// so a query like "sa" shows every match without forcing the user to
    /// scan two sections. Prioritized contacts still appear first within the
    /// flat list since their relevance hasn't changed.
    private var flatSearchResults: [Contact] {
        let query = searchText.lowercased()
        return (prioritizedAvailable + otherAvailable).filter { match($0, query: query) }
    }

    private var allFilteredCount: Int {
        searchText.isEmpty
            ? prioritizedAvailable.count + otherAvailable.count
            : flatSearchResults.count
    }

    private var firstSelectable: Contact? {
        if !searchText.isEmpty { return flatSearchResults.first }
        return prioritizedAvailable.first ?? otherAvailable.first
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                TextField("Search name or email", text: $searchText)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .onSubmit {
                        if let first = firstSelectable {
                            onSelect(first)
                            searchText = ""
                        }
                    }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.background.secondary)

            Divider()

            if allFilteredCount == 0 {
                VStack(spacing: 4) {
                    Image(systemName: "person.slash")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    Text(allContacts.isEmpty ? "No contacts yet" : "No matches")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        if searchText.isEmpty {
                            groupedRows
                        } else {
                            ForEach(flatSearchResults) { contact in
                                row(for: contact)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 320)
            }
        }
        .frame(width: 320)
        .onAppear { searchFocused = true }
    }

    @ViewBuilder
    private var groupedRows: some View {
        if !prioritizedAvailable.isEmpty {
            sectionHeader(prioritizedHeader)
            ForEach(prioritizedAvailable) { contact in
                row(for: contact)
            }
            if !otherAvailable.isEmpty {
                Divider()
                    .padding(.vertical, 4)
                sectionHeader("Other contacts")
            }
        }
        ForEach(otherAvailable) { contact in
            row(for: contact)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 2)
    }

    @ViewBuilder
    private func row(for contact: Contact) -> some View {
        let isHovered = hoveredID == contact.persistentModelID
        Button {
            onSelect(contact)
            searchText = ""
        } label: {
            HStack(spacing: 10) {
                Text(contact.initials)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(contact.avatarColor.gradient, in: Circle())

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(contact.name)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if let nickname = contact.nickname, !nickname.isEmpty {
                            Text("(\(nickname))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    if let email = contact.email, !email.isEmpty {
                        Text(email)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .background(
                isHovered ? Color.accentColor.opacity(0.15) : Color.clear,
                in: RoundedRectangle(cornerRadius: 4)
            )
        }
        .buttonStyle(.plain)
        .help(contact.email.flatMap { $0.isEmpty ? nil : "\(contact.name) · \($0)" } ?? contact.name)
        .onHover { hovering in
            hoveredID = hovering ? contact.persistentModelID : nil
        }
    }
}
