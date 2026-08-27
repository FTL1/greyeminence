import Foundation

/// Enrolled voices, keyed by contact.
///
/// A JSON file rather than a field on `Contact`: signatures are derived data
/// that can always be rebuilt by re-tagging, and giving them a `@Model` would
/// mean a schema migration every time the signature format changes — which it
/// will, because the right vector width and weighting are things you learn by
/// running it.
enum VoiceProfileStore {
    struct Profile: Codable, Equatable, Sendable {
        let contactID: UUID
        /// Kept for display and logs; the contact is the source of truth.
        var contactName: String
        var signature: VoiceSignature
        /// How many separate meetings have contributed. A voice confirmed in
        /// six meetings is a much stronger claim than one tagged once, and the
        /// UI says so rather than presenting both as equally certain.
        var meetingCount: Int
        var updatedAt: Date
    }

    struct Match: Equatable {
        let profile: Profile
        let similarity: Float
        /// Similarity to the next-best profile. A voice that scores 0.71
        /// against one person and 0.70 against another is not a match, however
        /// high the top score — this is what catches two people who genuinely
        /// sound alike.
        let runnerUpSimilarity: Float

        var margin: Float { similarity - runnerUpSimilarity }
    }

    /// Below this, no match is offered at all.
    ///
    /// Deliberately cautious to begin with. A wrong name stated confidently is
    /// worse than "Speaker 2" — the reader has no way to know it's wrong,
    /// whereas a number is honestly uninformative.
    static let suggestThreshold: Float = 0.55
    /// At or above this, and clear of the runner-up, the name is applied
    /// without asking.
    static let autoApplyThreshold: Float = 0.70
    /// How far ahead of the next-best candidate a match must be.
    static let requiredMargin: Float = 0.06

    private static var fileURL: URL {
        StorageManager.shared.appSupportURL.appendingPathComponent("VoiceProfiles.json")
    }

    static func load() -> [Profile] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        do {
            return try JSONDecoder().decode([Profile].self, from: data)
        } catch {
            LogManager.send(
                "Voice profiles couldn't be read — starting empty: \(error.localizedDescription)",
                category: .transcription,
                level: .warning
            )
            return []
        }
    }

    static func save(_ profiles: [Profile]) {
        do {
            try JSONEncoder().encode(profiles).write(to: fileURL, options: .atomic)
        } catch {
            LogManager.send(
                "Couldn't save voice profiles: \(error.localizedDescription)",
                category: .transcription,
                level: .warning
            )
        }
    }

    /// Record that `signature` belongs to a contact, folding it into any
    /// profile already held for them.
    @discardableResult
    static func enroll(_ signature: VoiceSignature, contactID: UUID, contactName: String) -> Profile {
        var profiles = load()
        let updated: Profile
        if let index = profiles.firstIndex(where: { $0.contactID == contactID }) {
            updated = Profile(
                contactID: contactID,
                contactName: contactName,
                signature: profiles[index].signature.merged(with: signature),
                meetingCount: profiles[index].meetingCount + 1,
                updatedAt: .now
            )
            profiles[index] = updated
        } else {
            updated = Profile(
                contactID: contactID,
                contactName: contactName,
                signature: signature,
                meetingCount: 1,
                updatedAt: .now
            )
            profiles.append(updated)
        }
        save(profiles)
        LogManager.send(
            "Voice profile for \(contactName): \(updated.meetingCount) meeting(s), \(Int(updated.signature.seconds))s of speech",
            category: .transcription
        )
        return updated
    }

    static func forget(contactID: UUID) {
        save(load().filter { $0.contactID != contactID })
    }

    /// Best candidate for a signature, or nil when nothing is close enough.
    ///
    /// `among` restricts to the people who could plausibly be speaking —
    /// normally a meeting's attendees. Comparing against everyone ever
    /// enrolled invites a confident match on someone who wasn't in the room.
    static func bestMatch(
        for signature: VoiceSignature,
        among contactIDs: Set<UUID>? = nil,
        profiles: [Profile]? = nil
    ) -> Match? {
        let pool = (profiles ?? load()).filter { profile in
            guard let contactIDs else { return true }
            return contactIDs.contains(profile.contactID)
        }
        guard !pool.isEmpty, !signature.isEmpty else { return nil }

        let ranked = pool
            .map { (profile: $0, similarity: signature.similarity(to: $0.signature)) }
            .sorted { $0.similarity > $1.similarity }
        guard let top = ranked.first, top.similarity >= suggestThreshold else { return nil }

        return Match(
            profile: top.profile,
            similarity: top.similarity,
            runnerUpSimilarity: ranked.count > 1 ? ranked[1].similarity : 0
        )
    }

    /// Whether a match is strong enough to apply without asking.
    static func isConfident(_ match: Match) -> Bool {
        match.similarity >= autoApplyThreshold && match.margin >= requiredMargin
    }
}
