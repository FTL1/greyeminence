import SwiftUI
import SwiftData
import Contacts

struct ContactPicker: View {
    @Query(sort: \Contact.name) private var allContacts: [Contact]
    @Environment(\.modelContext) private var modelContext
    @State private var searchText = ""
    @State private var hoveredID: PersistentIdentifier?
    @State private var appleHits: [AppleDirectoryHit] = []
    @State private var appleStatus: String?
    @FocusState private var searchFocused: Bool
    var excludedContacts: Set<PersistentIdentifier>
    /// Contacts to surface above the divider — typically the attendees of the
    /// meeting this picker is being shown from.
    var prioritizedContacts: [Contact] = []
    var includeAppleDirectory: Bool = false
    var onSelect: (Contact) -> Void

    private struct Partition {
        let prioritized: [Contact]
        let other: [Contact]
        var isEmpty: Bool { prioritized.isEmpty && other.isEmpty }
    }

    private var partition: Partition {
        let availableIDs = Set(
            allContacts
                .filter { !$0.isArchived && !excludedContacts.contains($0.persistentModelID) }
                .map(\.persistentModelID)
        )
        let prioritizedIDs = Set(prioritizedContacts.map(\.persistentModelID))
        let prior = prioritizedContacts.filter { availableIDs.contains($0.persistentModelID) }
        let other = allContacts.filter {
            availableIDs.contains($0.persistentModelID) && !prioritizedIDs.contains($0.persistentModelID)
        }
        return Partition(prioritized: prior, other: other)
    }

    private func match(_ contact: Contact, query: String) -> Bool {
        contact.name.lowercased().contains(query) ||
        (contact.nickname?.lowercased().contains(query) ?? false) ||
        (contact.email?.lowercased().contains(query) ?? false)
    }

    private var flatSearchResults: [Contact] {
        let query = searchText.lowercased()
        let p = partition
        return (p.prioritized + p.other).filter { match($0, query: query) }
    }

    private var firstSelectable: Contact? {
        if !searchText.isEmpty { return flatSearchResults.first }
        let p = partition
        return p.prioritized.first ?? p.other.first
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

            let isEmpty = (searchText.isEmpty ? partition.isEmpty : flatSearchResults.isEmpty)
                && visibleAppleHits.isEmpty && appleStatus == nil
            if isEmpty {
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
                            groupedRows(partition)
                            appleDirectorySection
                        } else {
                            ForEach(flatSearchResults) { contact in
                                row(for: contact)
                            }
                            appleDirectorySection
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 320)
            }
        }
        .frame(width: 320)
        .onAppear {
            searchFocused = true
            if includeAppleDirectory {
                Task { await loadAppleDirectory() }
            }
        }
    }

    private var visibleAppleHits: [AppleDirectoryHit] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let existingEmails = Set(allContacts.compactMap { $0.email?.lowercased() })
        return appleHits.filter { hit in
            if let email = hit.email, existingEmails.contains(email.lowercased()) { return false }
            if query.isEmpty { return true }
            return hit.name.lowercased().contains(query)
                || (hit.email?.lowercased().contains(query) ?? false)
        }
    }

    @MainActor
    private func loadAppleDirectory() async {
        let store = CNContactStore()
        do {
            let granted = try await store.requestAccess(for: .contacts)
            guard granted else {
                appleStatus = "Apple Contacts access denied"
                return
            }
            let keys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactNicknameKey, CNContactEmailAddressesKey] as [CNKeyDescriptor]
            let request = CNContactFetchRequest(keysToFetch: keys)
            var hits: [AppleDirectoryHit] = []
            try store.enumerateContacts(with: request) { contact, _ in
                let name = [contact.givenName, contact.familyName]
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                let nickname = contact.nickname.trimmingCharacters(in: .whitespaces)
                let display = name.isEmpty ? nickname : name
                guard !display.isEmpty else { return }
                let email = contact.emailAddresses.first.map { String($0.value) }
                hits.append(AppleDirectoryHit(id: contact.identifier, name: display, email: email))
            }
            appleHits = hits.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            appleStatus = appleHits.isEmpty ? "No Apple Contacts found" : nil
        } catch {
            appleStatus = error.localizedDescription
        }
    }

    private func selectApple(_ hit: AppleDirectoryHit) {
        if let email = hit.email,
           let existing = allContacts.first(where: { $0.email?.lowercased() == email.lowercased() }) {
            onSelect(existing)
            return
        }
        if let existing = allContacts.first(where: { $0.name.caseInsensitiveCompare(hit.name) == .orderedSame }) {
            onSelect(existing)
            return
        }
        let contact = Contact(name: hit.name, email: hit.email)
        contact.externalSource = "apple"
        contact.externalID = hit.id
        modelContext.insert(contact)
        onSelect(contact)
    }

    @ViewBuilder
    private func groupedRows(_ partition: Partition) -> some View {
        if !partition.prioritized.isEmpty {
            sectionHeader("Meeting attendees")
            ForEach(partition.prioritized) { contact in
                row(for: contact)
            }
            if !partition.other.isEmpty {
                Divider()
                    .padding(.vertical, 4)
                sectionHeader("Other contacts")
            }
        }
        ForEach(partition.other) { contact in
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
    private var appleDirectorySection: some View {
        if includeAppleDirectory {
        let hits = visibleAppleHits
        if !hits.isEmpty {
            Divider().padding(.vertical, 4)
            sectionHeader("Apple / Outlook Contacts")
            ForEach(hits.prefix(40)) { hit in
                Button {
                    selectApple(hit)
                    searchText = ""
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "person.crop.circle")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .frame(width: 26, height: 26)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(hit.name)
                                .font(.body)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            if let email = hit.email {
                                Text(email)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        } else if let appleStatus {
            Divider().padding(.vertical, 4)
            Text(appleStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
        }
        }
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

private struct AppleDirectoryHit: Identifiable {
    let id: String
    let name: String
    let email: String?
}
