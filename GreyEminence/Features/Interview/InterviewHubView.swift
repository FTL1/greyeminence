import SwiftUI
import SwiftData
import AppKit

struct InterviewHubView: View {
    @Environment(\.modelContext) private var modelContext
    var interviewViewModel: InterviewRecordingViewModel
    @Binding var selectedInterview: Interview?
    @Binding var showInspector: Bool
    @Binding var inspectorWidth: CGFloat?

    @State private var activeTab: InterviewHubTab = .interviews

    enum InterviewHubTab: String, CaseIterable {
        case interviews = "Interviews"
        case setup = "New Interview"
        case candidates = "Candidates"
        case rubrics = "Rubrics"
        case test = "Test"
    }

    var body: some View {
        if interviewViewModel.isInterviewActive {
            liveInterviewLayout
        } else {
            VStack(spacing: 0) {
                Picker("", selection: $activeTab) {
                    ForEach(InterviewHubTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)

                Group {
                    switch activeTab {
                    case .interviews:
                        InterviewListView(selectedInterview: $selectedInterview, showInspector: $showInspector, inspectorWidth: $inspectorWidth)
                            .id("interviewList")
                    case .setup:
                        InterviewSetupView(interviewViewModel: interviewViewModel)
                    case .candidates:
                        CandidateListView()
                    case .rubrics:
                        RubricListView()
                    case .test:
                        TranscriptTestView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .onChange(of: selectedInterview) { _, interview in
                if interview != nil {
                    activeTab = .interviews
                }
            }
        }
    }

    // MARK: - Live Interview Layout

    private var liveInterviewLayout: some View {
        GeometryReader { geo in
            let defaultWidth = geo.size.width * 0.32
            let width = inspectorWidth ?? defaultWidth
            let clampedWidth = min(max(width, 220), geo.size.width * 0.50)

            VStack(spacing: 0) {
                // Shared header — full width, above both panels
                InterviewLiveHeader(
                    interviewViewModel: interviewViewModel,
                    modelContext: modelContext
                )

                Divider()

                // Content: main panel + right panel side by side
                HStack(spacing: 0) {
                    LiveInterviewIntelligenceView(interviewViewModel: interviewViewModel)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if showInspector {
                        panelDragHandle(containerWidth: geo.size.width)
                        LiveInterviewView(interviewViewModel: interviewViewModel)
                            .frame(width: clampedWidth)
                    }
                }
            }
        }
    }

    private func panelDragHandle(containerWidth: CGFloat) -> some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 6)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let newWidth = (inspectorWidth ?? containerWidth * 0.32) - value.translation.width
                        inspectorWidth = min(max(newWidth, 220), containerWidth * 0.50)
                    }
            )
            .overlay { Divider() }
    }
}

// MARK: - Shared Full-Width Header

private struct InterviewLiveHeader: View {
    var interviewViewModel: InterviewRecordingViewModel
    var modelContext: ModelContext
    @Query(sort: \Rubric.createdAt, order: .reverse) private var allRubrics: [Rubric]
    @State private var addPhasePopoverVisible = false

    private var phases: [InterviewPhase] {
        interviewViewModel.interview?.orderedPhases ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top row: candidate + AI status + End button
            HStack(spacing: 8) {
                if let candidate = interviewViewModel.interview?.candidate {
                    Text(candidate.initials)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(candidate.avatarColor.gradient, in: Circle())
                    Text(candidate.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                AIActivityIndicator(state: interviewViewModel.rubricAnalysisState)

                Button {
                    interviewViewModel.stopInterview(in: modelContext)
                } label: {
                    Label("End Interview", systemImage: "stop.circle.fill")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.small)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            // Phase nav strip — chips for each planned phase + transition controls
            if !phases.isEmpty {
                Divider()
                phaseNavStrip
            }
        }
        .background(.bar)
    }

    // MARK: - Phase Nav

    private var phaseNavStrip: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(phases, id: \.id) { phase in
                        phaseChip(phase)
                    }
                }
                .padding(.horizontal, 8)
            }

            Spacer(minLength: 4)

            // Transition controls
            Button {
                interviewViewModel.advancePhase(in: modelContext)
            } label: {
                Label("Next", systemImage: "arrow.right.circle")
                    .font(.caption)
            }
            .controlSize(.small)
            .help("Close active phase and advance to next")

            Menu {
                Button("End Active Phase") {
                    interviewViewModel.endActivePhase(in: modelContext)
                }
                Divider()
                Section("Add ad-hoc phase") {
                    ForEach(allRubrics.filter { !$0.isArchived }) { rubric in
                        Button(rubric.name) {
                            interviewViewModel.addAdHocPhase(
                                title: rubric.name,
                                rubric: rubric,
                                in: modelContext
                            )
                        }
                    }
                    Divider()
                    Button("Unscored Discussion") {
                        interviewViewModel.addAdHocPhase(
                            title: "Discussion",
                            rubric: nil,
                            in: modelContext
                        )
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .controlSize(.small)
            .help("More phase actions")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }

    private func phaseChip(_ phase: InterviewPhase) -> some View {
        let isActive = phase.status == .active
        let isCompleted = phase.status == .completed
        let isSkipped = phase.status == .skipped
        let icon: String = {
            if isActive { return "circle.fill" }
            if isCompleted { return "checkmark.circle.fill" }
            if isSkipped { return "minus.circle" }
            return "circle"
        }()
        let color: Color = {
            if isActive { return .cyan }
            if isCompleted { return .green }
            if isSkipped { return .secondary }
            return .secondary
        }()
        return HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(color)
            Text(phase.title)
                .font(.system(size: 10, weight: isActive ? .bold : .medium))
                .foregroundStyle(isActive ? .primary : .secondary)
                .lineLimit(1)
            if phase.rubric == nil {
                Image(systemName: "bubble.left")
                    .font(.system(size: 7))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            isActive
                ? Color.cyan.opacity(0.15)
                : Color.secondary.opacity(0.06),
            in: RoundedRectangle(cornerRadius: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(isActive ? .cyan : .clear, lineWidth: 1)
        )
        .contextMenu {
            if phase.status == .planned {
                Button("Skip") {
                    interviewViewModel.skipPhase(phase, in: modelContext)
                }
            }
        }
    }
}
