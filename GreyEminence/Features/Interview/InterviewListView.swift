import SwiftUI
import SwiftData

struct InterviewListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Interview.createdAt, order: .reverse) private var interviews: [Interview]
    var interviewViewModel: InterviewRecordingViewModel
    @Binding var selectedInterview: Interview?
    @Binding var showInspector: Bool
    @Binding var inspectorWidth: CGFloat?
    @State private var searchText = ""
    @State private var showCreationSheet = false

    private var filteredInterviews: [Interview] {
        let active = interviews.filter { $0.status != .archived }
        if searchText.isEmpty { return active }
        let query = searchText.lowercased()
        return active.filter {
            ($0.candidate?.name.lowercased().contains(query) ?? false) ||
            ($0.candidate?.role?.displayTitle.lowercased().contains(query) ?? false) ||
            ($0.rubric?.name.lowercased().contains(query) ?? false)
        }
    }

    var body: some View {
        NavigationSplitView {
            List(filteredInterviews, selection: $selectedInterview) { interview in
                InterviewRowView(interview: interview, interviewViewModel: interviewViewModel)
                    .tag(interview)
                    .contextMenu {
                        if interview.status == .completed {
                            Button("Archive") {
                                interview.status = .archived
                            }
                        }
                        Button("Delete", role: .destructive) {
                            if selectedInterview == interview { selectedInterview = nil }
                            modelContext.delete(interview)
                        }
                    }
            }
            .searchable(text: $searchText, placement: .sidebar, prompt: "Search interviews")
            .navigationTitle("Interviews")
            .navigationSplitViewColumnWidth(min: 280, ideal: 300)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showCreationSheet = true
                    } label: {
                        Label("New Interview", systemImage: "plus")
                    }
                    .disabled(interviewViewModel.isInterviewActive)
                    .help(interviewViewModel.isInterviewActive
                          ? "Finish the current interview before scheduling another"
                          : "Schedule a new interview")
                    .keyboardShortcut("n", modifiers: .command)
                }
            }
            .overlay {
                if interviews.isEmpty {
                    ContentUnavailableView {
                        Label("No Interviews", systemImage: "person.badge.shield.checkmark")
                    } description: {
                        Text("Click + to schedule an interview")
                    } actions: {
                        Button("Schedule Interview") { showCreationSheet = true }
                            .buttonStyle(.borderedProminent)
                            .tint(.cyan)
                            .disabled(interviewViewModel.isInterviewActive)
                    }
                } else if filteredInterviews.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
            .sheet(isPresented: $showCreationSheet) {
                InterviewCreationSheet(
                    interviewViewModel: interviewViewModel,
                    onScheduled: { interview in
                        selectedInterview = interview
                    }
                )
            }
        } detail: {
            if let interview = selectedInterview {
                InterviewScorecardView(interview: interview, interviewViewModel: interviewViewModel)
            } else {
                ContentUnavailableView(
                    "No Interview Selected",
                    systemImage: "person.badge.shield.checkmark",
                    description: Text("Select an interview to view the scorecard")
                )
            }
        }
    }
}

// MARK: - Row View

private struct InterviewRowView: View {
    let interview: Interview
    var interviewViewModel: InterviewRecordingViewModel

    /// The active phase when *this row's* interview is the one actively
    /// recording — used to drive the inline timer pill. Nil for every
    /// other row (and for completed/scheduled interviews).
    private var liveActivePhase: InterviewPhase? {
        guard interviewViewModel.isInterviewActive,
              interviewViewModel.interview?.id == interview.id else { return nil }
        return interview.activePhase
    }

    var body: some View {
        HStack(spacing: 10) {
            // Candidate avatar
            if let candidate = interview.candidate {
                Text(candidate.initials)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(candidate.avatarColor.gradient, in: Circle())
            } else {
                Image(systemName: "person.fill")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Color.gray.gradient, in: Circle())
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(interview.candidate?.name ?? "Unknown Candidate")
                        .font(.body)

                    if let rec = interview.overallRecommendation {
                        Text(rec.shortLabel)
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(rec.color.opacity(0.2), in: Capsule())
                            .foregroundStyle(rec.color)
                    }

                    if interview.interruptedAt != nil, interview.status == .scheduled {
                        Text("Interrupted")
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.18), in: Capsule())
                            .foregroundStyle(.orange)
                            .help("This interview was interrupted on a previous launch. Click Start to resume.")
                    }
                }

                HStack(spacing: 6) {
                    if let role = interview.candidate?.role {
                        Text(role.displayTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    rowTimestamp
                    if let phase = liveActivePhase,
                       phase.targetMinutes != nil, phase.startedAt != nil {
                        InterviewListPhaseTimerPill(phase: phase)
                    }
                }

                if let gp = interview.compositeGradePoints {
                    let grade = LetterGrade.from(gradePoints: gp)
                    Text("Grade: \(grade.label)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    /// Compact "Coding · 02:15 left" / "+01:30 over" pill for the row of
    /// whichever interview is currently recording. Lets you glance at the
    /// list without opening the live view to know if the active phase is
    /// running long.
    private struct InterviewListPhaseTimerPill: View {
        let phase: InterviewPhase

        var body: some View {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                if let target = phase.targetMinutes, let startedAt = phase.startedAt {
                    let remaining = TimeInterval(target * 60) - context.date.timeIntervalSince(startedAt)
                    let isOver = remaining <= 0
                    let label: String = isOver
                        ? "+" + Self.mmss(-remaining) + " over"
                        : Self.mmss(remaining) + " left"
                    HStack(spacing: 3) {
                        Image(systemName: isOver ? "exclamationmark.triangle.fill" : "clock")
                            .font(.system(size: 8, weight: .semibold))
                        Text(phase.title)
                            .font(.caption2.weight(.semibold))
                        Text(label)
                            .font(.caption2.monospacedDigit())
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .foregroundStyle(isOver ? Color.white : Color.cyan)
                    .background(
                        isOver ? Color.red.opacity(0.85) : Color.cyan.opacity(0.12),
                        in: Capsule()
                    )
                }
            }
        }

        private static func mmss(_ seconds: TimeInterval) -> String {
            let s = Int(seconds.rounded(.down))
            return String(format: "%02d:%02d", s / 60, s % 60)
        }
    }

    /// Show the planned slot when one was picked; fall back to the
    /// creation timestamp for older / ad-hoc interviews. A small "Scheduled"
    /// prefix disambiguates the two.
    @ViewBuilder
    private var rowTimestamp: some View {
        if let scheduledAt = interview.scheduledAt {
            HStack(spacing: 3) {
                Image(systemName: "calendar")
                    .font(.system(size: 9))
                Text(scheduledAt.formatted(date: .abbreviated, time: .shortened))
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        } else {
            Text(interview.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}
