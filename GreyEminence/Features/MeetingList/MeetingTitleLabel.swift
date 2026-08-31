import SwiftData
import SwiftUI

/// Click (header) or double-click (list) the meeting name to rename it.
struct MeetingTitleLabel: View {
    @Bindable var meeting: Meeting
    @Binding var isEditing: Bool
    var font: Font
    var weight: Font.Weight
    /// Header: a single click starts editing. List rows keep a single click
    /// for selection; double-click or the Rename menu starts editing.
    var singleClickStartsEditing: Bool

    @Environment(\.modelContext) private var modelContext
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if isEditing {
                field
            } else {
                Text(meeting.title)
                    .font(font)
                    .fontWeight(weight)
                    .lineLimit(1)
                    .help(singleClickStartsEditing ? "Click to rename" : "Double-click to rename")
                    .onTapGesture(count: singleClickStartsEditing ? 1 : 2) {
                        beginEditing()
                    }
            }
        }
        .onChange(of: isEditing) { _, editing in
            if editing {
                draft = meeting.title
                focused = true
            }
        }
        .onChange(of: focused) { _, on in
            if !on, isEditing {
                commit()
            }
        }
    }

    @ViewBuilder
    private var field: some View {
        if singleClickStartsEditing {
            TextField("Session name", text: $draft)
                .textFieldStyle(.roundedBorder)
                .font(font)
                .fontWeight(weight)
                .focused($focused)
                .onSubmit { commit() }
                .onExitCommand { cancel() }
                .onAppear { armField() }
        } else {
            TextField("Session name", text: $draft)
                .textFieldStyle(.plain)
                .font(font)
                .fontWeight(weight)
                .focused($focused)
                .onSubmit { commit() }
                .onExitCommand { cancel() }
                .onAppear { armField() }
        }
    }

    private func armField() {
        draft = meeting.title
        focused = true
    }

    private func beginEditing() {
        draft = meeting.title
        isEditing = true
        focused = true
    }

    private func cancel() {
        draft = meeting.title
        isEditing = false
    }

    private func commit() {
        isEditing = false
        focused = false
        guard meeting.renameDisplayTitle(draft) else { return }
        PersistenceGate.save(modelContext, site: "Meeting.renameDisplayTitle", meetingID: meeting.id)
        GrokLibrary.upsert(meeting)
    }
}
