import Foundation
import SwiftData

/// Float32 little-endian packing for a speaker embedding stored on a Contact.
enum VoicePrintCodec {
    static func encode(_ values: [Float]) -> Data {
        var copy = values
        return copy.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    static func decode(_ data: Data?) -> [Float]? {
        guard let data, data.count >= MemoryLayout<Float>.size * 8 else { return nil }
        guard data.count.isMultiple(of: MemoryLayout<Float>.size) else { return nil }
        return data.withUnsafeBytes { raw in
            Array(raw.bindMemory(to: Float.self))
        }
    }
}

/// Cosine-distance matching for live and enrolled speaker embeddings.
enum VoicePrintMatcher {
    /// New FluidAudio IDs in the same meeting (cosine distance).
    static let sessionDistance: Float = 0.38
    /// Cross-meeting enrolled prints. 0.52 was so loose that the only
    /// enrolled person (often Jordan) won every remote cluster.
    static let enrolledDistance: Float = 0.30
    /// Best match must beat the runner-up by this much, else leave unlabeled.
    static let matchMargin: Float = 0.08

    static func cosineDistance(_ a: [Float], _ b: [Float]) -> Float {
        let n = min(a.count, b.count)
        guard n > 0 else { return 1 }
        var dot: Float = 0
        var na: Float = 0
        var nb: Float = 0
        for i in 0..<n {
            dot += a[i] * b[i]
            na += a[i] * a[i]
            nb += b[i] * b[i]
        }
        let denom = na.squareRoot() * nb.squareRoot()
        guard denom > 0 else { return 1 }
        return max(0, 1 - dot / denom)
    }

    static func bestMatch<T>(
        embedding: [Float],
        in candidates: [(item: T, embedding: [Float])],
        threshold: Float,
        margin: Float = 0
    ) -> (item: T, distance: Float)? {
        guard embedding.count >= 8, !candidates.isEmpty else { return nil }
        var ranked: [(item: T, distance: Float)] = []
        for candidate in candidates {
            guard candidate.embedding.count >= 8 else { continue }
            ranked.append((candidate.item, cosineDistance(embedding, candidate.embedding)))
        }
        ranked.sort { $0.distance < $1.distance }
        guard let best = ranked.first, best.distance <= threshold else { return nil }
        if margin > 0, ranked.count >= 2 {
            let second = ranked[1].distance
            if second - best.distance < margin { return nil }
        }
        return best
    }
}

/// Which stored voice stamps to load at record-start. Never the whole
/// People list — that made Jordan the default remote on every call.
enum VoicePrintSeeding {
    static func contactsToSeed(
        contacts: [Contact],
        meetingAttendeeIDs: Set<UUID>,
        myContactID: UUID?
    ) -> [Contact] {
        contacts.filter { contact in
            guard !contact.isArchived, contact.hasVoicePrint else { return false }
            if let myContactID, contact.id == myContactID { return true }
            return meetingAttendeeIDs.contains(contact.id)
        }
    }
}

/// A person the speaker menu can assign this voice to.
struct SpeakerLinkPerson: Identifiable, Hashable {
    var contactID: UUID?
    var name: String
    var hasVoicePrint: Bool
    var aliases: [String]
    var meetingCount: Int
    var isThisVoice: Bool

    var id: String {
        if let contactID { return contactID.uuidString }
        return "name:\(name.lowercased())"
    }
}

struct SpeakerLinkGroups: Equatable {
    var thisMeeting: [SpeakerLinkPerson]
    var priorSpeakers: [SpeakerLinkPerson]

    static let empty = SpeakerLinkGroups(thisMeeting: [], priorSpeakers: [])

    var isEmpty: Bool { thisMeeting.isEmpty && priorSpeakers.isEmpty }
}

/// Split People contacts + transcript names into "this meeting" vs people
/// who have spoken (or been tagged) before.
enum SpeakerLinkCatalog {
    static func groups(
        people: [SpeakerLinkPerson],
        transcriptNames: [String],
        attendeeNames: [String],
        meName: String?,
        currentSpeakerName: String
    ) -> SpeakerLinkGroups {
        var meetingNames: [String] = []
        func consider(_ raw: String) {
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !isPlaceholder(name) else { return }
            if meetingNames.contains(where: { $0.compare(name, options: .caseInsensitive) == .orderedSame }) {
                return
            }
            meetingNames.append(name)
        }
        if let meName { consider(meName) }
        for name in attendeeNames { consider(name) }
        for name in transcriptNames { consider(name) }

        let thisMeeting = meetingNames.map { name in
            resolvedPerson(named: name, in: people, currentSpeakerName: currentSpeakerName)
        }

        let meetingKeys = Set(thisMeeting.map { $0.id })
        var prior: [SpeakerLinkPerson] = []
        for person in people {
            guard person.hasVoicePrint || !person.aliases.isEmpty || person.meetingCount > 0 else { continue }
            if meetingKeys.contains(person.id) { continue }
            if thisMeeting.contains(where: { $0.name.compare(person.name, options: .caseInsensitive) == .orderedSame }) {
                continue
            }
            var copy = person
            copy.isThisVoice = matches(person, name: currentSpeakerName)
            prior.append(copy)
        }
        prior.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        return SpeakerLinkGroups(thisMeeting: thisMeeting, priorSpeakers: prior)
    }

    static func isPlaceholder(_ name: String) -> Bool {
        let lower = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lower.isEmpty { return true }
        if lower == "me" || lower == "other" || lower == "speaker" || lower == "unknown" {
            return true
        }
        if lower.hasPrefix("speaker ") { return true }
        if lower.hasPrefix("guest-") { return true }
        if lower.hasPrefix("unknown-") { return true }
        if lower.hasPrefix("speaker-") { return true }
        return Speaker.remoteIndex(fromLegacyName: name) != nil
    }

    private static func resolvedPerson(
        named name: String,
        in people: [SpeakerLinkPerson],
        currentSpeakerName: String
    ) -> SpeakerLinkPerson {
        if let existing = people.first(where: { matches($0, name: name) }) {
            var copy = existing
            copy.isThisVoice = matches(existing, name: currentSpeakerName)
            return copy
        }
        return SpeakerLinkPerson(
            contactID: nil,
            name: name,
            hasVoicePrint: false,
            aliases: [],
            meetingCount: 0,
            isThisVoice: name.compare(currentSpeakerName, options: .caseInsensitive) == .orderedSame
        )
    }

    private static func matches(_ person: SpeakerLinkPerson, name: String) -> Bool {
        if person.name.compare(name, options: .caseInsensitive) == .orderedSame { return true }
        return person.aliases.contains { $0.compare(name, options: .caseInsensitive) == .orderedSame }
    }
}

enum VoicePrintUIState: Equatable {
    case ready(onto: String?)
    case enrolled(onto: String, at: Date?)
    case working
    case failed(String)
    case needsPerson
}

enum VoicePrintEnrollmentProgress: Equatable {
    case idle
    case working(Speaker.IdentityKey)
    case failed(Speaker.IdentityKey, String)
}
