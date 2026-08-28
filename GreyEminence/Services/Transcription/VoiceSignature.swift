import Foundation

/// A voice, reduced to one vector.
///
/// Diarization gives every turn an embedding and a cluster id, but the cluster
/// id means nothing outside its own meeting — the same person is "Speaker 2"
/// today and "Speaker 1" tomorrow. The embedding is the part that travels, so
/// a cluster is collapsed to a single signature that can be compared against
/// people we already know.
struct VoiceSignature: Codable, Equatable, Sendable {
    /// Unit-length, so comparison is a dot product.
    let vector: [Float]
    /// Seconds of speech behind it. A signature built from four seconds is a
    /// far weaker claim than one built from four minutes, and enrolment
    /// weights by this rather than treating every sample as equal.
    let seconds: Double

    var isEmpty: Bool { vector.isEmpty }

    /// Build from a cluster's turns, weighting each by how long it lasted.
    ///
    /// Weighting matters: a diarized cluster is mostly short turns with a few
    /// long ones, and an unweighted mean lets a half-second "mm-hm" — which
    /// carries almost no vocal information — count as much as a minute of
    /// speech.
    static func from(turns: [(embedding: [Float], seconds: Double)]) -> VoiceSignature? {
        let usable = turns.filter { !$0.embedding.isEmpty && $0.seconds > 0 }
        guard let width = usable.first?.embedding.count, width > 0 else { return nil }

        var sum = [Float](repeating: 0, count: width)
        var total: Double = 0
        for turn in usable where turn.embedding.count == width {
            let weight = Float(turn.seconds)
            for i in 0..<width { sum[i] += turn.embedding[i] * weight }
            total += turn.seconds
        }
        guard total > 0, let normalized = normalize(sum) else { return nil }
        return VoiceSignature(vector: normalized, seconds: total)
    }

    /// Cosine similarity in −1…1. Both vectors are unit length, so this is
    /// their dot product.
    func similarity(to other: VoiceSignature) -> Float {
        guard vector.count == other.vector.count, !vector.isEmpty else { return 0 }
        var dot: Float = 0
        for i in 0..<vector.count { dot += vector[i] * other.vector[i] }
        return max(-1, min(1, dot))
    }

    /// Fold another sighting into this one, weighted by evidence.
    ///
    /// A profile confirmed across ten meetings shouldn't be dragged around by
    /// an eleventh, and a long sample shouldn't be outvoted by a short one —
    /// so both sides are weighted by their seconds of speech.
    func merged(with other: VoiceSignature) -> VoiceSignature {
        guard vector.count == other.vector.count, !vector.isEmpty else { return self }
        // The same duration-weighted average that builds a signature in the
        // first place — written once, so a change to the weighting can't leave
        // enrolment and cluster-building disagreeing about what a voice is.
        guard let combined = Self.from(turns: [(vector, seconds), (other.vector, other.seconds)]) else {
            return self
        }
        // Cap the accumulated evidence. Without it a heavily-enrolled profile
        // becomes effectively immovable, and a voice that genuinely drifts —
        // a different mic, a cold — could never correct it.
        return VoiceSignature(
            vector: combined.vector,
            seconds: min(combined.seconds, Self.maxEnrolledSeconds)
        )
    }

    /// About twenty minutes of speech. Past this, more evidence stops moving
    /// the profile meaningfully anyway.
    static let maxEnrolledSeconds: Double = 1_200

    private static func normalize(_ vector: [Float]) -> [Float]? {
        var magnitude: Float = 0
        for value in vector { magnitude += value * value }
        magnitude = magnitude.squareRoot()
        guard magnitude > 0, magnitude.isFinite else { return nil }
        return vector.map { $0 / magnitude }
    }
}

/// One meeting's diarization clusters, kept so a speaker can be identified
/// later without re-listening to the audio.
///
/// Written beside the recording rather than into the store: it's derived data,
/// recomputable from audio, and it would otherwise be a schema change on every
/// tweak to how signatures are built.
struct MeetingVoiceClusters: Codable, Equatable, Sendable {
    struct Cluster: Codable, Equatable, Sendable {
        /// The display label the transcript uses — "Speaker 2".
        let label: String
        let signature: VoiceSignature
    }

    /// Bumped when the signature format changes, so stale files are ignored
    /// rather than compared against vectors that no longer mean the same thing.
    static let currentVersion = 1

    var version: Int = MeetingVoiceClusters.currentVersion
    var clusters: [Cluster]

    func cluster(labelled label: String) -> Cluster? {
        clusters.first { $0.label == label }
    }

    var isCurrent: Bool { version == Self.currentVersion }
}
