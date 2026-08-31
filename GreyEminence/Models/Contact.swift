import Foundation
import SwiftData
import SwiftUI

@Model
final class Contact {
    var id: UUID
    var name: String
    var nickname: String?
    var email: String?
    var isArchived: Bool = false
    var isInterviewer: Bool = false
    var createdAt: Date

    // Future: Microsoft Teams / external sync
    var externalID: String?
    var externalSource: String?

    // Speaker label aliases for auto-linking
    var speakerAliases: [String] = []

    /// WeSpeaker embedding (Float32 little-endian). Lets later meetings
    /// recognize this person instead of minting a new guest-N.
    var voicePrintData: Data?
    var voicePrintUpdatedAt: Date?

    /// Index into `SpeakerPalette.swatches`. Nil until assigned.
    var colorSlot: Int?
    var isColorLocked: Bool = false

    @Relationship(inverse: \Meeting.attendees)
    var meetings: [Meeting] = []

    @Relationship(inverse: \ActionItem.assignedContact)
    var assignedActionItems: [ActionItem] = []

    init(name: String, email: String? = nil) {
        self.id = UUID()
        self.name = name
        self.email = email
        self.createdAt = .now
    }

    var hasVoicePrint: Bool {
        guard let voicePrintData else { return false }
        return voicePrintData.count >= MemoryLayout<Float>.size * 8
    }

    func voicePrintEmbedding() -> [Float]? {
        VoicePrintCodec.decode(voicePrintData)
    }

    func setVoicePrint(_ embedding: [Float]) {
        voicePrintData = VoicePrintCodec.encode(embedding)
        voicePrintUpdatedAt = .now
    }

    /// Average a new sample into the stored print so later enrollments
    /// tighten the match instead of replacing it outright.
    func mergeVoicePrint(_ embedding: [Float]) {
        if let existing = voicePrintEmbedding(), existing.count == embedding.count, !existing.isEmpty {
            setVoicePrint(zip(existing, embedding).map { ($0 + $1) / 2 })
        } else {
            setVoicePrint(embedding)
        }
    }

    func clearVoicePrint() {
        voicePrintData = nil
        voicePrintUpdatedAt = nil
    }

    func asSpeakerLinkPerson() -> SpeakerLinkPerson {
        SpeakerLinkPerson(
            contactID: id,
            name: name,
            hasVoicePrint: hasVoicePrint,
            aliases: speakerAliases,
            meetingCount: meetings.count,
            isThisVoice: false
        )
    }

    func matchesSpeakerName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if self.name.compare(trimmed, options: .caseInsensitive) == .orderedSame { return true }
        return speakerAliases.contains { $0.compare(trimmed, options: .caseInsensitive) == .orderedSame }
    }

    var firstName: String {
        String(name.split(separator: " ").first ?? Substring(name))
    }

    var displayNickname: String {
        if let nickname, !nickname.isEmpty { return nickname }
        return firstName
    }

    var initials: String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    var avatarColor: Color { paletteColor }

    var paletteColor: Color {
        if let colorSlot {
            return SpeakerPalette.color(slot: colorSlot)
        }
        return SpeakerPalette.color(forName: name)
    }
}
