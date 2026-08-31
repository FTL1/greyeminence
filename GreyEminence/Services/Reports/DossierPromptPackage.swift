import Foundation

/// Chatbot upload pack. Filled only with stored facts. The prompt forbids
/// inventing anything that is not in `meeting.json` or the transcript file.
enum DossierPromptPackage {
    static func promptMarkdown(
        snapshots: [DossierMeetingSnapshot],
        audience: DossierAudience,
        includeTranscript: Bool
    ) -> String {
        let titles = snapshots.map(\.title).joined(separator: "; ")
        let purposeLines = snapshots.compactMap { snap -> String? in
            guard let purpose = DossierFacts.purpose(from: snap) else { return nil }
            return snapshots.count == 1 ? purpose : "\(snap.title): \(purpose)"
        }
        var body = """
        # Grounded meeting brief — do not invent

        You are working from an export of Grey Eminence. Use ONLY the files in this package.

        ## Hard rules (do not break these)
        1. DO NOT hallucinate. DO NOT invent facts, numbers, names, dates, stakeholders, commitments, or questions.
        2. If something is not in `meeting.json` and not in a transcript file in this package, say it is not in the source.
        3. Do not add financing, environmental, engagement, timeline, or other due-diligence questions unless they already appear in `follow_ups` or the transcript.
        4. Do not treat a calendar title or a shared PDF's subject as the meeting's purpose if `purpose` is present.
        5. Quotes must be copied verbatim. Never paraphrase a quote and present it as spoken words.
        6. Screen-share recaps (if present) are secondary to the transcript. Prefer the transcript when they disagree.

        ## This package
        - Meetings: \(titles)
        - Audience to help: \(audience.displayName)
        - Transcript included: \(includeTranscript ? "yes (see transcript file)" : "no — use quotes and action source_quote fields only")
        - Full structured facts: `meeting.json`

        """
        if !purposeLines.isEmpty {
            body += "## Purpose (from the app, not the calendar name)\n"
            for line in purposeLines {
                body += "- \(line)\n"
            }
            body += "\n"
        }
        body += """
        ## What to do
        Help the user follow up on the stored purpose and action items for **\(audience.displayName)**. \
        Draft document corrections, emails, or a briefing using only the facts in this package. \
        When you are unsure, quote the source field and stop.

        """
        return body
    }

    static func jsonData(
        snapshots: [DossierMeetingSnapshot],
        audience: DossierAudience,
        includeTranscript: Bool
    ) throws -> Data {
        let payload = Payload(
            grounding: Grounding(
                rule: "do_not_invent",
                source: "grey-eminence-dossier",
                audience: audience.displayName,
                generatedAt: ISO8601DateFormatter().string(from: Date())
            ),
            meetings: snapshots.map { snap in
                MeetingJSON(
                    id: snap.id.uuidString,
                    title: snap.title,
                    purpose: DossierFacts.purpose(from: snap),
                    date: ISO8601DateFormatter().string(from: snap.date),
                    duration: snap.durationLabel,
                    attendees: snap.attendees,
                    speakers: snap.speakers,
                    summary: SummarySection.parse(snap.summaryJSON).map {
                        $0.map { SectionJSON(title: $0.title, intro: $0.intro, points: $0.points.map { PointJSON(label: $0.label, detail: $0.detail) }) }
                    } ?? [],
                    actionItems: snap.actionItems.map {
                        ActionJSON(text: $0.text, assignee: $0.assignee, isCompleted: $0.isCompleted, sourceQuote: $0.sourceQuote)
                    },
                    followUps: snap.followUps,
                    topics: snap.topics,
                    screenRecaps: snap.shareNarratives.map {
                        ShareJSON(title: $0.title, span: $0.span, narrative: $0.narrative)
                    },
                    transcript: includeTranscript
                        ? snap.transcript.map { LineJSON(speaker: $0.speaker, timestamp: $0.timestamp, text: $0.text) }
                        : nil
                )
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(payload)
    }

    private struct Payload: Encodable {
        var grounding: Grounding
        var meetings: [MeetingJSON]
    }

    private struct Grounding: Encodable {
        var rule: String
        var source: String
        var audience: String
        var generatedAt: String
    }

    private struct MeetingJSON: Encodable {
        var id: String
        var title: String
        var purpose: String?
        var date: String
        var duration: String
        var attendees: [String]
        var speakers: [String]
        var summary: [SectionJSON]
        var actionItems: [ActionJSON]
        var followUps: [String]
        var topics: [String]
        var screenRecaps: [ShareJSON]
        var transcript: [LineJSON]?
    }

    private struct SectionJSON: Encodable {
        var title: String
        var intro: String?
        var points: [PointJSON]
    }

    private struct PointJSON: Encodable {
        var label: String
        var detail: String
    }

    private struct ActionJSON: Encodable {
        var text: String
        var assignee: String?
        var isCompleted: Bool
        var sourceQuote: String?
    }

    private struct ShareJSON: Encodable {
        var title: String
        var span: String
        var narrative: String
    }

    private struct LineJSON: Encodable {
        var speaker: String
        var timestamp: String
        var text: String
    }
}
