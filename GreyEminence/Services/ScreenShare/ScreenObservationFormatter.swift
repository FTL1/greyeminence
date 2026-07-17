import Foundation
import SwiftData

/// Renders frame observations into the prompt blocks the transcript
/// intelligence receives. Pure — unit-tested without the AI service.
enum ScreenObservationFormatter {
    typealias Observation = ScreenFrameAnalysisService.FrameObservation

    /// One session's synthesized narrative, snapshotted for rendering.
    struct NarrativeSnapshot: Sendable {
        let windowTitle: String?
        let startTime: TimeInterval
        let endTime: TimeInterval
        let narrative: String
        let keyMoments: [ShareSessionSummary.KeyMoment]
    }

    /// Final block built from a meeting's persisted state: session narratives
    /// where synthesis succeeded, per-frame observation lines only for
    /// sessions without a summary. Used by the stop path (after the synthesis
    /// sweep) and both re-analysis paths.
    @MainActor
    static func finalBlock(for meeting: Meeting) -> String? {
        let summaries = meeting.sessionSummaries
        let covered = Set(summaries.map(\.sessionID))
        let narratives = summaries.map { summary in
            NarrativeSnapshot(
                windowTitle: summary.windowTitle,
                startTime: summary.startTime,
                endTime: summary.endTime,
                narrative: summary.narrative,
                keyMoments: summary.keyMoments
            )
        }
        let fallback = observations(fromFrames: meeting.screenFrames.filter { !covered.contains($0.sessionID) })
        return finalBlock(narratives: narratives, fallbackFrames: fallback)
    }

    /// Narrative paragraphs + key moments, then per-frame lines for sessions
    /// that never got a recap. Capped at `finalBlockCap` — the fallback block
    /// absorbs the squeeze first (narratives are the point of M4).
    static func finalBlock(narratives: [NarrativeSnapshot], fallbackFrames: [Observation]) -> String? {
        guard !narratives.isEmpty else { return finalBlock(fallbackFrames) }

        let sorted = narratives.sorted { $0.startTime < $1.startTime }
        let narrativeText = sorted.enumerated()
            .map { index, narrative in renderNarrative(narrative, index: index) }
            .joined(separator: "\n\n")

        var parts = [narrativeText]
        if !fallbackFrames.isEmpty {
            let remaining = finalBlockCap - narrativeText.count - 60
            if remaining > 200, let fallbackBlock = finalBlock(fallbackFrames, cap: remaining) {
                parts.append("Shares without a recap — per-frame observations:\n\(fallbackBlock)")
            }
        }
        let rendered = parts.joined(separator: "\n\n")
        return rendered.count > finalBlockCap ? String(rendered.prefix(finalBlockCap)) : rendered
    }

    private static func renderNarrative(_ narrative: NarrativeSnapshot, index: Int) -> String {
        let title = narrative.windowTitle.map { " — \"\($0)\"" } ?? ""
        let span = "\(format(narrative.startTime))–\(format(narrative.endTime))"
        var text = "Share session \(index + 1)\(title) (\(span)):\n\(narrative.narrative)"
        if !narrative.keyMoments.isEmpty {
            let moments = narrative.keyMoments
                .map { "[\(format($0.timestamp))] \($0.label)" }
                .joined(separator: "; ")
            text += "\nKey moments: \(moments)"
        }
        return text
    }

    private static func format(_ elapsed: TimeInterval) -> String {
        String(format: "%d:%02d", Int(elapsed) / 60, Int(elapsed) % 60)
    }

    /// Persisted rows → prompt observations. Frames without observations are
    /// skipped.
    @MainActor
    static func observations(fromFrames frames: [ScreenShareFrame]) -> [Observation] {
        frames.compactMap { row in
            guard let text = row.observation, !text.isEmpty else { return nil }
            return Observation(
                frameID: row.id,
                timestamp: row.timestamp,
                formattedTimestamp: row.formattedTimestamp,
                sessionID: row.sessionID,
                observation: text,
                contentType: row.contentTypeRaw ?? "other",
                keyEntities: row.keyEntities,
                notableText: nil
            )
        }
    }

    /// Character budget for the final-analysis block.
    static let finalBlockCap = 6_000

    /// Observation characters per line in rolling passes — full detailed
    /// descriptions would blow up every rolling prompt; the final pass gets
    /// the detail via session narratives / the final block instead.
    static let rollingObservationCap = 240

    /// One observation as a prompt line: `[12:34] (slide) Roadmap slide …`,
    /// with notable verbatim text appended when present. Pass
    /// `maxObservationChars` to truncate the description (rolling passes).
    static func line(for observation: Observation, maxObservationChars: Int? = nil) -> String {
        var body = observation.observation
        if let cap = maxObservationChars, body.count > cap {
            body = String(body.prefix(cap)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
        }
        var text = "[\(observation.formattedTimestamp)] (\(observation.contentType)) \(body)"
        if let notable = observation.notableText {
            text += " — on screen: \"\(notable)\""
        }
        return text
    }

    /// Rolling passes get only the observations that arrived since the last
    /// successfully-sent index, truncated — the running analysis needs the
    /// gist, not the full transcription. Returns nil when there's nothing new.
    static func rollingBlock(
        _ all: [Observation],
        afterIndex: Int
    ) -> (block: String, endIndex: Int)? {
        guard all.count > afterIndex, afterIndex >= 0 else { return nil }
        let lines = all[afterIndex...]
            .map { line(for: $0, maxObservationChars: rollingObservationCap) }
            .joined(separator: "\n")
        return (lines, all.count)
    }

    /// The final pass gets the whole log: grouped by share session in
    /// chronological order, deduplicated, and capped. Over budget, middle
    /// lines are dropped from the longest sessions first — a session's first
    /// and last observations carry its narrative arc.
    static func finalBlock(_ all: [Observation], cap: Int = finalBlockCap) -> String? {
        guard !all.isEmpty else { return nil }

        var bySession: [UUID: [Observation]] = [:]
        for observation in all {
            bySession[observation.sessionID, default: []].append(observation)
        }
        var sessions: [[Observation]] = bySession.values.map { session in
            session.sorted { $0.timestamp < $1.timestamp }
        }
        sessions.sort { ($0.first?.timestamp ?? 0) < ($1.first?.timestamp ?? 0) }
        sessions = sessions.map { session in
            var seen = Set<String>()
            return session.filter { seen.insert($0.observation).inserted }
        }

        var rendered = render(sessions)
        while rendered.count > cap {
            guard let target = sessions.indices.max(by: { sessions[$0].count < sessions[$1].count }),
                  sessions[target].count > 2 else {
                return String(rendered.prefix(cap))
            }
            sessions[target].remove(at: sessions[target].count / 2)
            rendered = render(sessions)
        }
        return rendered
    }

    private static func render(_ sessions: [[Observation]]) -> String {
        sessions.enumerated().map { index, observations in
            let start = observations.first?.formattedTimestamp ?? "0:00"
            let end = observations.last?.formattedTimestamp ?? start
            let header = "Share session \(index + 1) (\(start)–\(end)):"
            return ([header] + observations.map { line(for: $0) }).joined(separator: "\n")
        }.joined(separator: "\n\n")
    }
}
