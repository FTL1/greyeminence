import Foundation

/// Renders frame observations into the prompt blocks the transcript
/// intelligence receives. Pure — unit-tested without the AI service.
enum ScreenObservationFormatter {
    typealias Observation = ScreenFrameAnalysisService.FrameObservation

    /// Character budget for the final-analysis block.
    static let finalBlockCap = 3_000

    /// One observation as a prompt line: `[12:34] (slide) Roadmap slide …`,
    /// with notable verbatim text appended when present.
    static func line(for observation: Observation) -> String {
        var text = "[\(observation.formattedTimestamp)] (\(observation.contentType)) \(observation.observation)"
        if let notable = observation.notableText {
            text += " — on screen: \"\(notable)\""
        }
        return text
    }

    /// Rolling passes get only the observations that arrived since the last
    /// successfully-sent index. Returns nil when there's nothing new.
    static func rollingBlock(
        _ all: [Observation],
        afterIndex: Int
    ) -> (block: String, endIndex: Int)? {
        guard all.count > afterIndex, afterIndex >= 0 else { return nil }
        let lines = all[afterIndex...].map(line(for:)).joined(separator: "\n")
        return (lines, all.count)
    }

    /// The final pass gets the whole log: grouped by share session in
    /// chronological order, deduplicated, and capped. Over budget, middle
    /// lines are dropped from the longest sessions first — a session's first
    /// and last observations carry its narrative arc.
    static func finalBlock(_ all: [Observation]) -> String? {
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
        while rendered.count > finalBlockCap {
            guard let target = sessions.indices.max(by: { sessions[$0].count < sessions[$1].count }),
                  sessions[target].count > 2 else {
                return String(rendered.prefix(finalBlockCap))
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
            return ([header] + observations.map(line(for:))).joined(separator: "\n")
        }.joined(separator: "\n\n")
    }
}
