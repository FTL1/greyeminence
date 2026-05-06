import SwiftUI
import SwiftData
import AppKit

/// Rescore an existing interview against a different rubric (or a
/// specific phase against a different rubric) without re-recording.
/// Useful for trying a refined rubric on a past interview, or for
/// validating a new rubric design against a known transcript.
struct TranscriptTestView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Rubric.createdAt, order: .reverse) private var rubrics: [Rubric]
    @Query(sort: \Interview.createdAt, order: .reverse) private var interviews: [Interview]

    @State private var loadedTranscript: TranscriptFile?
    @State private var selectedInterview: Interview?
    @State private var selectedPhaseID: UUID?
    @State private var selectedRubric: Rubric?
    @State private var isAnalyzing = false
    @State private var analysisError: String?
    @State private var result: InterviewAnalysisResult?
    @State private var criterionEvals: [UUID: [CriterionEvaluationSnapshot]] = [:]

    private var activeRubrics: [Rubric] {
        rubrics.filter { !$0.isArchived }
    }

    /// Interviews that actually have a recorded transcript to analyze.
    /// Filters out scheduled-but-unrecorded entries (no meeting attached
    /// yet) and any with empty segments.
    private var interviewsWithTranscript: [Interview] {
        interviews.filter { interview in
            guard let meeting = interview.meeting else { return false }
            return !meeting.segments.isEmpty
        }
    }

    private var phasesForSelected: [InterviewPhase] {
        (selectedInterview?.orderedPhases ?? []).filter { $0.startedAt != nil }
    }

    private var interviewLabel: (Interview) -> String {
        { interview in
            let candidate = interview.candidate?.name ?? "Untitled"
            let dateStr = Self.dateFormatter.string(from: interview.createdAt)
            let segCount = interview.meeting?.segments.count ?? 0
            return "\(candidate) — \(dateStr) (\(segCount) seg)"
        }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            HStack(spacing: 12) {
                // Interview picker
                Picker("Interview", selection: $selectedInterview) {
                    Text("Select interview...").tag(nil as Interview?)
                    ForEach(interviewsWithTranscript) { interview in
                        Text(interviewLabel(interview))
                            .tag(interview as Interview?)
                    }
                }
                .frame(maxWidth: 280)
                .controlSize(.small)
                .onChange(of: selectedInterview) { _, interview in
                    rebuildTranscript()
                    selectedPhaseID = nil
                    // Pre-select the rubric of the first scored phase as a
                    // sensible default — common case is rescoring against
                    // the same rubric to validate prompt or schema changes.
                    selectedRubric = interview?.orderedPhases.compactMap(\.rubric).first
                }

                // Phase scope (only shown when interview has phases with
                // recorded boundaries — lets you rescore a single phase
                // rather than the whole transcript).
                if !phasesForSelected.isEmpty {
                    Picker("Phase", selection: $selectedPhaseID) {
                        Text("Whole interview").tag(nil as UUID?)
                        ForEach(phasesForSelected, id: \.id) { phase in
                            Text(phase.title).tag(phase.id as UUID?)
                        }
                    }
                    .frame(maxWidth: 180)
                    .controlSize(.small)
                    .onChange(of: selectedPhaseID) { _, _ in
                        rebuildTranscript()
                    }
                }

                Text("or")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Button {
                    loadTranscript()
                } label: {
                    Label("Load File", systemImage: "doc.badge.arrow.up")
                }
                .controlSize(.small)

                if let transcript = loadedTranscript {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(transcript.title)
                            .font(.caption.weight(.semibold))
                        Text("\(transcript.segments.count) segments · \(formatDuration(transcript.duration))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Picker("Rubric", selection: $selectedRubric) {
                    Text("Select rubric...").tag(nil as Rubric?)
                    ForEach(activeRubrics) { rubric in
                        Text(rubric.name).tag(rubric as Rubric?)
                    }
                }
                .frame(maxWidth: 250)
                .controlSize(.small)

                Button {
                    Task { await runAnalysis() }
                } label: {
                    if isAnalyzing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Rescore", systemImage: "brain")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(loadedTranscript == nil || selectedRubric == nil || isAnalyzing)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()

            if let error = analysisError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Dismiss") { analysisError = nil }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(.blue)
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
            }

            if let result {
                // Results
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(result.sectionScores, id: \.sectionID) { score in
                            testResultSection(score)
                        }

                        if !result.strengths.isEmpty {
                            signalList("Strengths", items: result.strengths, color: .green)
                        }
                        if !result.weaknesses.isEmpty {
                            signalList("Weaknesses", items: result.weaknesses, color: .orange)
                        }
                        if !result.redFlags.isEmpty {
                            signalList("Red Flags", items: result.redFlags, color: .red)
                        }

                        if !result.overallAssessment.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Overall Assessment")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(result.overallAssessment)
                                    .font(.caption)
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.vertical)
                }
            } else if loadedTranscript == nil {
                ContentUnavailableView(
                    "Load a Transcript",
                    systemImage: "doc.badge.arrow.up",
                    description: Text("Load a saved transcript file to test against rubrics")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "Ready to Analyze",
                    systemImage: "brain",
                    description: Text("Select a rubric and click Analyze to test")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Result Section

    private func testResultSection(_ score: SectionScoreSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(score.sectionTitle)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let gradeStr = score.grade, let grade = LetterGrade(rawValue: gradeStr) {
                    Text(grade.label)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(grade.color)
                }
            }

            // Per-criterion evaluations
            let evals = score.criterionEvaluations
            if !evals.isEmpty {
                ForEach(evals, id: \.signal) { eval in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: statusIcon(eval.status))
                            .font(.system(size: 10))
                            .foregroundStyle(statusColor(eval.status))
                            .frame(width: 14)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(eval.signal)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(eval.status == .notYetDiscussed ? .tertiary : .primary)
                                Spacer()
                                if eval.confidence > 0 {
                                    Text("\(Int(eval.confidence * 100))%")
                                        .font(.system(size: 9))
                                        .foregroundStyle(.secondary)
                                }
                            }

                            if let summary = eval.summary, !summary.isEmpty {
                                Text(summary)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }

                            ForEach(eval.evidence, id: \.quote) { ev in
                                HStack(spacing: 4) {
                                    if !ev.timestamp.isEmpty {
                                        Text(ev.timestamp)
                                            .font(.system(size: 9, design: .monospaced))
                                            .foregroundStyle(.tertiary)
                                    }
                                    Text("\"\(ev.quote)\"")
                                        .font(.caption)
                                        .italic()
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                .padding(.leading, 4)
                            }
                        }
                    }
                }
            }

            if !score.rationale.isEmpty {
                Text(score.rationale)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal)
    }

    // MARK: - Helpers

    private func signalList(_ title: String, items: [String], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
            ForEach(items, id: \.self) { item in
                Text("  \(item)")
                    .font(.caption)
            }
        }
        .padding(.horizontal)
    }

    private func statusIcon(_ status: CriterionStatus) -> String {
        switch status {
        case .scored: "checkmark.circle.fill"
        case .partialEvidence: "circle.dotted"
        case .notYetDiscussed: "circle"
        }
    }

    private func statusColor(_ status: CriterionStatus) -> Color {
        switch status {
        case .scored: .green
        case .partialEvidence: .yellow
        case .notYetDiscussed: .gray
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let min = Int(duration) / 60
        let sec = Int(duration) % 60
        return String(format: "%d:%02d", min, sec)
    }

    // MARK: - Load & Analyze

    private func loadTranscript() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.title = "Load Transcript"
        panel.message = "Select a saved transcript file (.getranscript.json)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            loadedTranscript = try TranscriptFile.read(from: url)
            selectedInterview = nil
            selectedPhaseID = nil
            result = nil
            criterionEvals = [:]
        } catch {
            analysisError = "Failed to load: \(error.localizedDescription)"
        }
    }

    /// Rebuild the loaded transcript from the currently selected interview,
    /// optionally scoped to one phase's `[startedAt, endedAt]` window.
    /// No-ops when no interview is selected.
    private func rebuildTranscript() {
        guard let interview = selectedInterview, let meeting = interview.meeting else {
            loadedTranscript = nil
            return
        }
        let allSegments = meeting.segments.sorted { $0.startTime < $1.startTime }
        let scoped: [TranscriptSegment]
        if let phaseID = selectedPhaseID,
           let phase = interview.phases.first(where: { $0.id == phaseID }) {
            // Phase windows are wall-clock dates, segment.startTime is
            // seconds since recording start — convert via meeting.date.
            let recordingStart = meeting.date
            let lower = phase.startedAt.map { $0.timeIntervalSince(recordingStart) } ?? -.infinity
            let upper = phase.endedAt.map { $0.timeIntervalSince(recordingStart) } ?? .infinity
            scoped = allSegments.filter { $0.startTime >= lower && $0.startTime <= upper }
        } else {
            scoped = allSegments
        }
        let snapshots = scoped.map {
            SegmentSnapshot(
                speaker: $0.speaker,
                text: $0.text,
                formattedTimestamp: $0.formattedTimestamp,
                isFinal: $0.isFinal
            )
        }
        let candidate = interview.candidate?.name ?? "Untitled"
        let phaseSuffix: String = {
            guard let phaseID = selectedPhaseID,
                  let phase = interview.phases.first(where: { $0.id == phaseID }) else { return "" }
            return " — \(phase.title)"
        }()
        loadedTranscript = TranscriptFile(
            title: "\(candidate)\(phaseSuffix)",
            date: meeting.date,
            duration: meeting.duration,
            segments: snapshots
        )
        result = nil
        criterionEvals = [:]
    }

    @MainActor
    private func runAnalysis() async {
        guard let transcript = loadedTranscript, let rubric = selectedRubric else { return }
        isAnalyzing = true
        analysisError = nil
        result = nil

        defer { isAnalyzing = false }

        guard let client = try? await AIClientFactory.makeClient() else {
            analysisError = "AI not configured. Check Settings."
            return
        }

        let rubricSnapshot = rubric.toSnapshot()
        let service = InterviewIntelligenceService(
            client: client,
            rubricContext: rubricSnapshot
        )

        do {
            // Run full analysis on the complete transcript
            if let analysisResult = try await service.performFinalInterviewAnalysis(segments: transcript.segments) {
                self.result = analysisResult
                for score in analysisResult.sectionScores {
                    criterionEvals[score.sectionID] = score.criterionEvaluations
                }
            } else {
                analysisError = "Analysis returned no results."
            }
        } catch {
            analysisError = error.localizedDescription
        }
    }
}
