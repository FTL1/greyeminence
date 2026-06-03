import SwiftUI
import SwiftData

/// Header control for linking a *past* meeting to a calendar event after the
/// fact. Lists events near the meeting's date; linking adds the event's matched
/// attendees and records the link — but deliberately does **not** change the
/// title (the meeting already has its generated name).
struct MeetingCalendarLinkMenu: View {
    @Bindable var meeting: Meeting
    @Environment(\.modelContext) private var modelContext

    @State private var calendarService = CalendarService()
    @State private var nearbyEvents: [CalendarEvent] = []
    @State private var loaded = false
    @State private var isLoading = false

    var body: some View {
        Menu {
            // Load lazily when the menu actually opens — not on every meeting open.
            Color.clear
                .frame(width: 0, height: 0)
                .onAppear { Task { await load() } }

            Section("Events near this meeting") {
                if isLoading {
                    Text("Searching…").foregroundStyle(.secondary)
                } else if nearbyEvents.isEmpty {
                    Text("No events found near this meeting").foregroundStyle(.secondary)
                } else {
                    ForEach(nearbyEvents) { event in
                        Button {
                            link(event)
                        } label: {
                            let matched = event.linkIdentifier == meeting.calendarEventID
                            let time = event.startDate.formatted(date: .omitted, time: .shortened)
                            Text("\(matched ? "✓ " : "")\(event.title ?? "Untitled") — \(time)")
                        }
                    }
                }
            }

            if meeting.isLinkedToCalendar {
                Divider()
                UnlinkCalendarButton {
                    meeting.unlinkCalendarEvent()
                    save()
                }
            }
            Divider()
            Button("Refresh") { Task { await load(force: true) } }
        } label: {
            if meeting.isLinkedToCalendar {
                Label(meeting.calendarEventTitle ?? "Linked", systemImage: "calendar.badge.checkmark")
                    .foregroundStyle(.green)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            } else {
                Label("Link calendar event", systemImage: "calendar.badge.plus")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(meeting.isLinkedToCalendar
              ? "Linked to a calendar event — change or unlink"
              : "Link this meeting to a calendar event (adds attendees; keeps the title)")
    }

    private func load(force: Bool = false) async {
        guard force || !loaded else { return }
        isLoading = true
        if calendarService.authorizationState != .authorized {
            await calendarService.requestAccess()
        }
        nearbyEvents = await calendarService.eventsAround(date: meeting.date, minutes: 90)
        loaded = true
        isLoading = false
    }

    private func link(_ event: CalendarEvent) {
        // Post-hoc link: attendees + series only, keep the existing title.
        calendarService.linkEvent(event, to: meeting, in: modelContext, setTitle: false)
        save()
    }

    private func save() {
        PersistenceGate.save(modelContext, site: "MeetingHeaderBar.calendarLink", meetingID: meeting.id)
    }
}
