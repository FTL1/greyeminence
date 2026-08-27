import Foundation

/// Turns diarization output into named speakers.
///
/// Sits between the clusterer, which knows voices apart but not who they are,
/// and the contact roster, which knows who was invited but not who spoke.
/// Pure — no audio, no store — so the labelling rules are testable.
enum SpeakerIdentification {
    /// A cluster reduced to a signature, ready to be named.
    struct Cluster {
        let clusterID: String
        let label: String
        let signature: VoiceSignature
    }

    /// What a cluster should be called, and why.
    struct Resolution {
        let label: String
        /// Nil when nobody was confident enough — the label stays numbered.
        let match: VoiceProfileStore.Match?
        let applied: Bool

        var displayName: String {
            applied ? (match?.profile.contactName ?? label) : label
        }
    }

    /// Build signatures for each significant cluster from its turns.
    static func clusters(
        from turns: [DiarizedSegment],
        labels: [String: String],
        significant: Set<String>
    ) -> [Cluster] {
        var grouped: [String: [(embedding: [Float], seconds: Double)]] = [:]
        for turn in turns where significant.contains(turn.speakerID) {
            grouped[turn.speakerID, default: []].append(
                (turn.embedding, max(0, turn.endTime - turn.startTime))
            )
        }
        return grouped.compactMap { clusterID, samples in
            guard let label = labels[clusterID],
                  let signature = VoiceSignature.from(turns: samples) else { return nil }
            return Cluster(clusterID: clusterID, label: label, signature: signature)
        }
        .sorted { $0.label < $1.label }
    }

    /// Name the clusters we're sure about, leaving the rest numbered.
    ///
    /// Two people are never given the same name: a meeting has one Erin, and a
    /// second cluster matching her profile means the clusterer split one voice
    /// or two people sound alike. Either way, asserting both are Erin is
    /// wrong, so the weaker claim stays numbered.
    static func resolve(
        clusters: [Cluster],
        attendeeIDs: Set<UUID>,
        profiles: [VoiceProfileStore.Profile]
    ) -> [Resolution] {
        let scored = clusters.map { cluster in
            (cluster, VoiceProfileStore.bestMatch(
                for: cluster.signature,
                among: attendeeIDs.isEmpty ? nil : attendeeIDs,
                profiles: profiles
            ))
        }

        // Strongest claim on each person wins.
        var claimed: [UUID: Float] = [:]
        for (_, match) in scored {
            guard let match, VoiceProfileStore.isConfident(match) else { continue }
            let id = match.profile.contactID
            claimed[id] = max(claimed[id] ?? 0, match.similarity)
        }

        var used = Set<UUID>()
        return scored.map { cluster, match in
            guard let match, VoiceProfileStore.isConfident(match) else {
                return Resolution(label: cluster.label, match: match, applied: false)
            }
            let id = match.profile.contactID
            let isStrongest = claimed[id] == match.similarity && !used.contains(id)
            if isStrongest { used.insert(id) }
            return Resolution(label: cluster.label, match: match, applied: isStrongest)
        }
    }
}
