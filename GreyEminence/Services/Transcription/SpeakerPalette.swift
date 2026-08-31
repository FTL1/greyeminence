import Foundation
import SwiftUI

/// Shared person colors for header attendees, People chips, talk %, and
/// transcript badges. A contact can lock a slot; clashes give the color to
/// the more common speaker in the library.
enum SpeakerPalette {
    struct Swatch: Identifiable, Hashable {
        let slot: Int
        let name: String
        let color: Color
        var id: Int { slot }
    }

    static let swatches: [Swatch] = [
        Swatch(slot: 0, name: "Blue", color: .blue),
        Swatch(slot: 1, name: "Green", color: .green),
        Swatch(slot: 2, name: "Orange", color: .orange),
        Swatch(slot: 3, name: "Purple", color: .purple),
        Swatch(slot: 4, name: "Pink", color: .pink),
        Swatch(slot: 5, name: "Teal", color: .teal),
        Swatch(slot: 6, name: "Indigo", color: .indigo),
        Swatch(slot: 7, name: "Mint", color: .mint),
        Swatch(slot: 8, name: "Cyan", color: .cyan),
        Swatch(slot: 9, name: "Red", color: .red)
    ]

    static func color(slot: Int?) -> Color {
        guard let slot, let swatch = swatches.first(where: { $0.slot == slot }) else {
            return .secondary
        }
        return swatch.color
    }

    static func hashSlot(for name: String) -> Int {
        var hasher = Hasher()
        hasher.combine(name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        return abs(hasher.finalize()) % swatches.count
    }

    static func color(forName name: String) -> Color {
        color(slot: hashSlot(for: name))
    }

    static func color(for speaker: Speaker, contacts: [Contact]) -> Color {
        if let contact = contact(for: speaker, in: contacts) {
            return contact.paletteColor
        }
        return color(forName: speaker.displayName)
    }

    static func contact(for speaker: Speaker, in contacts: [Contact]) -> Contact? {
        let name = speaker.displayName
        if speaker.isMe {
            if let id = Meeting.storedMyContactID,
               let mine = contacts.first(where: { $0.id == id }) {
                return mine
            }
            return contacts.first { $0.matchesSpeakerName(name) }
                ?? contacts.first { $0.matchesSpeakerName(SpeakerNames.effectiveMeName ?? "Me") }
        }
        return contacts.first { $0.matchesSpeakerName(name) }
    }

    struct Claim: Equatable {
        var id: UUID
        var name: String
        var meetingCount: Int
        var createdAt: Date
        var slot: Int?
        var locked: Bool
    }

    /// Higher-priority people keep a color; newer / less common people move.
    static func resolve(_ claims: inout [Claim]) {
        claims.sort { a, b in
            if a.locked != b.locked { return a.locked && !b.locked }
            if a.meetingCount != b.meetingCount { return a.meetingCount > b.meetingCount }
            if a.createdAt != b.createdAt { return a.createdAt < b.createdAt }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
        var used = Set<Int>()
        for index in claims.indices {
            if claims[index].locked, let slot = claims[index].slot {
                used.insert(slot)
                continue
            }
            let preferred = claims[index].slot ?? hashSlot(for: claims[index].name)
            if !used.contains(preferred) {
                claims[index].slot = preferred
                used.insert(preferred)
                continue
            }
            let next = (0..<swatches.count).first { !used.contains($0) } ?? preferred
            claims[index].slot = next
            used.insert(next)
        }
    }

    static func assign(contacts: [Contact]) {
        var claims = contacts.map {
            Claim(
                id: $0.id,
                name: $0.name,
                meetingCount: $0.meetings.count,
                createdAt: $0.createdAt,
                slot: $0.colorSlot,
                locked: $0.isColorLocked
            )
        }
        resolve(&claims)
        let byID = Dictionary(uniqueKeysWithValues: claims.compactMap { claim -> (UUID, Int)? in
            guard let slot = claim.slot else { return nil }
            return (claim.id, slot)
        })
        for contact in contacts {
            if let slot = byID[contact.id] {
                if contact.colorSlot != slot, !contact.isColorLocked {
                    contact.colorSlot = slot
                } else if contact.colorSlot == nil {
                    contact.colorSlot = slot
                }
            }
        }
    }
}
