import SwiftUI
import SwiftData

private struct SelectedMeetingIDsKey: FocusedValueKey {
    typealias Value = Set<UUID>
}

private struct ReanalyzeAllConfirmKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

private struct ReanalyzeAllCountKey: FocusedValueKey {
    typealias Value = Binding<Int>
}

private struct ReanalyzeModelContextKey: FocusedValueKey {
    typealias Value = ModelContext
}

private struct ArchiveExtractLaunchKey: FocusedValueKey {
    typealias Value = Binding<ArchiveExtractLaunch?>
}

extension FocusedValues {
    var selectedMeetingIDs: Set<UUID>? {
        get { self[SelectedMeetingIDsKey.self] }
        set { self[SelectedMeetingIDsKey.self] = newValue }
    }

    var showReanalyzeAllConfirm: Binding<Bool>? {
        get { self[ReanalyzeAllConfirmKey.self] }
        set { self[ReanalyzeAllConfirmKey.self] = newValue }
    }

    var reanalyzeAllCount: Binding<Int>? {
        get { self[ReanalyzeAllCountKey.self] }
        set { self[ReanalyzeAllCountKey.self] = newValue }
    }

    var reanalyzeModelContext: ModelContext? {
        get { self[ReanalyzeModelContextKey.self] }
        set { self[ReanalyzeModelContextKey.self] = newValue }
    }

    var archiveExtractLaunch: Binding<ArchiveExtractLaunch?>? {
        get { self[ArchiveExtractLaunchKey.self] }
        set { self[ArchiveExtractLaunchKey.self] = newValue }
    }
}

/// Scene-level Meetings menu. Must live on `WindowGroup.commands`, not on a
/// `View` — Release WMO cannot attach `.commands` to `ContentView`.
struct MeetingsReanalyzeCommands: Commands {
    @FocusedValue(\.selectedMeetingIDs) private var selectedMeetingIDs
    @FocusedValue(\.showReanalyzeAllConfirm) private var showReanalyzeAllConfirm
    @FocusedValue(\.reanalyzeAllCount) private var reanalyzeAllCount
    @FocusedValue(\.reanalyzeModelContext) private var modelContext
    @FocusedValue(\.archiveExtractLaunch) private var extractLaunch

    var body: some Commands {
        CommandMenu("Meetings") {
            Button(selectedCount <= 1
                   ? "Reanalyze Selected Meeting"
                   : "Reanalyze Selected Meetings (\(selectedCount))") {
                enqueueSelected()
            }
            .keyboardShortcut("r", modifiers: [.command, .option])
            .disabled(selectedCount == 0 || modelContext == nil)

            Button("Reanalyze All Meetings…") {
                guard let modelContext else { return }
                let ids = MeetingReanalysis.eligibleIDs(in: modelContext)
                reanalyzeAllCount?.wrappedValue = ids.count
                if ids.isEmpty {
                    TransientActivityCoordinator.shared.flash("No eligible meetings to reanalyze")
                } else {
                    showReanalyzeAllConfirm?.wrappedValue = true
                }
            }
            .disabled(modelContext == nil)

            Divider()

            Button("Cancel Reanalyze") {
                MeetingReanalysisQueue.shared.cancel()
            }
            .disabled(!MeetingReanalysisQueue.shared.isRunning)

            Divider()

            Button(selectedCount <= 1
                   ? "Export Selected Meeting…"
                   : "Export Selected Meetings (\(selectedCount))…") {
                extractSelected()
            }
            .disabled(selectedCount == 0 || extractLaunch == nil)
        }
    }

    private var selectedCount: Int { selectedMeetingIDs?.count ?? 0 }

    private func enqueueSelected() {
        guard let modelContext, let selectedMeetingIDs else { return }
        let eligible = MeetingReanalysis.eligibleIDs(in: modelContext, restrictingTo: selectedMeetingIDs)
        if eligible.isEmpty {
            TransientActivityCoordinator.shared.flash("No eligible meetings to reanalyze")
            return
        }
        MeetingReanalysisQueue.shared.enqueue(ids: eligible, in: modelContext)
    }

    private func extractSelected() {
        guard let selectedMeetingIDs, !selectedMeetingIDs.isEmpty else { return }
        extractLaunch?.wrappedValue = ArchiveExtractLaunch(
            initialScope: selectedMeetingIDs.count == 1 ? .thisMeeting : .selected,
            seedMeetingID: selectedMeetingIDs.count == 1 ? selectedMeetingIDs.first : nil,
            selectedIDs: selectedMeetingIDs,
            visibleIDs: selectedMeetingIDs
        )
    }
}

/// Hosts the “reanalyze all” confirm so it is not chained onto ContentView.body.
struct ReanalyzeAllConfirmationHost: View {
    @Binding var isPresented: Bool
    let count: Int
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .confirmationDialog(
                "Reanalyze \(count) meeting\(count == 1 ? "" : "s")?",
                isPresented: $isPresented,
                titleVisibility: .visible
            ) {
                Button("Reanalyze All") {
                    MeetingReanalysisQueue.shared.enqueueEligible(in: modelContext)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Runs one meeting at a time using your configured AI provider. Interviews, recordings in progress, and meetings with no transcript are skipped.")
            }
    }
}

struct ReanalyzeFocusedValuesHost: View {
    let selectedMeetingIDs: Set<UUID>
    @Binding var showReanalyzeAllConfirm: Bool
    @Binding var reanalyzeAllCount: Int
    @Binding var extractLaunch: ArchiveExtractLaunch?
    let modelContext: ModelContext

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .focusedSceneValue(\.selectedMeetingIDs, selectedMeetingIDs)
            .focusedSceneValue(\.showReanalyzeAllConfirm, $showReanalyzeAllConfirm)
            .focusedSceneValue(\.reanalyzeAllCount, $reanalyzeAllCount)
            .focusedSceneValue(\.reanalyzeModelContext, modelContext)
            .focusedSceneValue(\.archiveExtractLaunch, $extractLaunch)
    }
}
