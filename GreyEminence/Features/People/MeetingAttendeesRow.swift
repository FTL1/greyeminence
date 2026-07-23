import SwiftUI
import SwiftData

struct ContactChip: View {
    let contact: Contact
    var onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 4) {
            Text(contact.initials)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(contact.avatarColor.gradient, in: Circle())

            Text(contact.displayNickname)
                .font(.caption)
                .lineLimit(1)
        }
        .padding(.leading, 2)
        .padding(.trailing, 8)
        .padding(.vertical, 3)
        .background(.quaternary, in: Capsule())
        .help(contact.attendeeTooltip)
        .contextMenu {
            if let onRemove {
                Button("Remove", role: .destructive) {
                    onRemove()
                }
            }
        }
    }
}

struct CompactContactDot: View {
    let contact: Contact
    var onRemove: (() -> Void)?

    var body: some View {
        Text(contact.initials)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 18, height: 18)
            .background(contact.avatarColor.gradient, in: Circle())
            .help(contact.attendeeTooltip)
            .contextMenu {
                if let onRemove {
                    Button("Remove", role: .destructive) {
                        onRemove()
                    }
                }
            }
    }
}

extension Contact {
    /// Name plus email, unless the "name" *is* the email (calendar invites for
    /// people who aren't in Contacts often come through that way).
    var attendeeTooltip: String {
        if let email, !email.isEmpty, email.lowercased() != name.lowercased() {
            return "\(name) · \(email)"
        }
        return name
    }
}

/// Capsule that stands in for attendees the row had no width to draw — either
/// the tail of a truncated dot run ("+12") or, at the narrowest fallback, the
/// whole roster ("18 people"). Tapping it opens the full list.
private struct AttendeeOverflowPill: View {
    let label: String
    let systemImage: String?
    let contacts: [Contact]
    var onRemove: ((Contact) -> Void)?

    @State private var showList = false

    var body: some View {
        Button {
            showList.toggle()
        } label: {
            HStack(spacing: 3) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 9))
                }
                Text(label)
                    .font(.caption)
                    .lineLimit(1)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.quaternary, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Show all \(contacts.count) attendees")
        .popover(isPresented: $showList, arrowEdge: .bottom) {
            AttendeeListPopover(contacts: contacts, onRemove: onRemove)
        }
    }
}

/// Scrolling roster shown from an overflow pill. Bounded height so a 40-person
/// invite can't grow a popover taller than the screen.
private struct AttendeeListPopover: View {
    let contacts: [Contact]
    var onRemove: ((Contact) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(contacts.count) attendees")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(contacts) { contact in
                        AttendeeListRow(contact: contact, onRemove: onRemove)
                    }
                }
                .padding(6)
            }
            .frame(maxHeight: 320)
        }
        .frame(width: 260)
    }
}

private struct AttendeeListRow: View {
    let contact: Contact
    var onRemove: ((Contact) -> Void)?

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            Text(contact.initials)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(contact.avatarColor.gradient, in: Circle())

            VStack(alignment: .leading, spacing: 0) {
                Text(contact.name)
                    .font(.caption)
                    .lineLimit(1)
                if let email = contact.email,
                   !email.isEmpty,
                   email.lowercased() != contact.name.lowercased() {
                    Text(email)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            if let onRemove, isHovering {
                Button {
                    onRemove(contact)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove \(contact.name)")
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isHovering ? Color.secondary.opacity(0.15) : .clear)
        )
        .onHover { isHovering = $0 }
    }
}

struct MeetingAttendeesRow: View {
    @Bindable var meeting: Meeting
    @State private var showPicker = false

    private var attendees: [Contact] {
        meeting.attendees.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private var excludedIDs: Set<PersistentIdentifier> {
        Set(meeting.attendees.map(\.persistentModelID))
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "person.2")
                .font(.caption)
                .foregroundStyle(.secondary)

            let people = attendees

            if people.isEmpty {
                Text("No attendees")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                // Widest arrangement that fits wins; the trailing summary pill
                // is the always-fits floor, so the row can never push its
                // container wider than the window. Candidates are listed
                // unconditionally — a `nil` branch inside ViewThatFits can be
                // chosen as a zero-size "fitting" candidate and blank the row.
                // Caps above the attendee count just collapse to the same
                // full-run layout, which is harmless.
                ViewThatFits(in: .horizontal) {
                    chipRow(people)
                    dotRow(people, cap: people.count)
                    dotRow(people, cap: 12)
                    dotRow(people, cap: 8)
                    dotRow(people, cap: 5)
                    dotRow(people, cap: 3)
                    summaryPill(people)
                }
            }

            Button {
                showPicker.toggle()
            } label: {
                Image(systemName: "plus.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showPicker) {
                ContactPicker(excludedContacts: excludedIDs) { contact in
                    meeting.attendees.append(contact)
                    // Stay open so the user can add several attendees in one
                    // pass; click outside (or hit Escape) to dismiss.
                }
            }
        }
    }

    private func chipRow(_ people: [Contact]) -> some View {
        HStack(spacing: 6) {
            ForEach(people) { contact in
                ContactChip(contact: contact) { remove(contact) }
            }
        }
    }

    private func dotRow(_ people: [Contact], cap: Int) -> some View {
        let shown = Array(people.prefix(cap))
        let hidden = people.count - shown.count
        return HStack(spacing: 3) {
            ForEach(shown) { contact in
                CompactContactDot(contact: contact) { remove(contact) }
            }
            if hidden > 0 {
                AttendeeOverflowPill(
                    label: "+\(hidden)",
                    systemImage: nil,
                    contacts: people,
                    onRemove: remove
                )
            }
        }
    }

    private func summaryPill(_ people: [Contact]) -> some View {
        AttendeeOverflowPill(
            label: "\(people.count)",
            systemImage: "person.crop.circle",
            contacts: people,
            onRemove: remove
        )
    }

    private func remove(_ contact: Contact) {
        meeting.attendees.removeAll { $0.id == contact.id }
    }
}
