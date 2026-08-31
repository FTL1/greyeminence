import SwiftUI

/// In-meeting Find (⌘F). Library Find stays on ⇧⌘F / the sidebar.
@Observable
@MainActor
final class MeetingFindController {
    var query = ""
    var includeTranscript = true
    var focusNonce = 0
    var transcriptStepNonce = 0
    var transcriptStepDelta = 1

    func requestFocus() {
        focusNonce += 1
    }

    func resetForMeetingChange() {
        query = ""
        transcriptStepNonce = 0
        transcriptStepDelta = 1
    }

    func nextTranscriptMatch() {
        transcriptStepDelta = 1
        transcriptStepNonce += 1
    }

    func previousTranscriptMatch() {
        transcriptStepDelta = -1
        transcriptStepNonce += 1
    }
}

private struct MeetingFindQueryKey: EnvironmentKey {
    static let defaultValue = ""
}

extension EnvironmentValues {
    var meetingFindQuery: String {
        get { self[MeetingFindQueryKey.self] }
        set { self[MeetingFindQueryKey.self] = newValue }
    }
}

/// Body text that lights up `query` when the in-meeting find field is active.
struct HighlightedBody: View {
    let text: String
    var query: String = ""
    var font: Font = .body
    var color: Color = .primary
    var strikethrough: Bool = false
    var italic: Bool = false

    var body: some View {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        Group {
            if needle.isEmpty {
                Text(text)
            } else {
                Text(TranscriptTextHighlight.attributed(text, query: needle))
            }
        }
        .font(italic ? font.italic() : font)
        .foregroundStyle(color)
        .strikethrough(strikethrough)
    }
}
