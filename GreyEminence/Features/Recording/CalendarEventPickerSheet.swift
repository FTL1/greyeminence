import SwiftUI
import EventKit

/// Presented at record-start when more than one calendar event falls within the
/// match window. Lets the user pick which meeting this recording belongs to (or
/// skip linking entirely). On selection the chosen event's title and attendees
/// are applied to the in-progress recording.
struct CalendarEventPickerSheet: View {
    let events: [EKEvent]
    let onPick: (EKEvent) -> Void
    let onSkip: () -> Void

    @Environment(\.dismiss) private var dismiss
    /// `nil` until something is chosen; `noneTag` means "link later".
    @State private var selectedID: String?

    private let noneTag = "__none__"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Which meeting is this?")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text("Link this recording to a calendar event to use its title and attendees. You can change or remove this later from the toolbar.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(events, id: \.calendarItemIdentifier) { event in
                        row(
                            id: event.calendarItemIdentifier,
                            title: event.title ?? "Untitled event",
                            subtitle: event.startDate.formatted(date: .omitted, time: .shortened),
                            systemImage: "calendar"
                        )
                    }
                    row(
                        id: noneTag,
                        title: "None / link later",
                        subtitle: "Record without linking to a calendar event",
                        systemImage: "calendar.badge.minus"
                    )
                }
            }
            .frame(maxHeight: 300)

            HStack {
                Spacer()
                Button("Cancel") {
                    onSkip()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Link") {
                    if let id = selectedID,
                       id != noneTag,
                       let event = events.first(where: { $0.calendarItemIdentifier == id }) {
                        onPick(event)
                    } else {
                        onSkip()
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(selectedID == nil)
            }
        }
        .padding(20)
        .frame(width: 440)
        .onAppear {
            // Pre-select the event nearest to now (events arrive sorted by proximity).
            selectedID = events.first?.calendarItemIdentifier
        }
    }

    private func row(id: String, title: String, subtitle: String, systemImage: String) -> some View {
        let isSelected = selectedID == id
        return Button {
            selectedID = id
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                isSelected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
