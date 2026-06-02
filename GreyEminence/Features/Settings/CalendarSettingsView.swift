import SwiftUI

struct CalendarSettingsView: View {
    @AppStorage("calendarIntegration") private var calendarIntegration = true
    @AppStorage(GraphConfig.enabledKey) private var graphEnabled = false

    @State private var graphAuth = GraphAuthService.shared
    @State private var calendarService = CalendarService()
    @State private var allCalendars: [CalendarChoice] = []
    @State private var disabledIDs: Set<String> = CalendarSelection.disabledIDs()

    private var eventKitCalendars: [CalendarChoice] {
        allCalendars.filter { $0.source == .eventKit }
    }
    private var graphCalendars: [CalendarChoice] {
        allCalendars.filter { $0.source == .microsoftGraph }
    }

    var body: some View {
        Form {
            // MARK: - Local (EventKit)
            Section {
                Toggle("Auto-detect calendar events", isOn: $calendarIntegration)
                Text("Reads calendars synced to macOS (Calendar app) to auto-name recordings and match attendees.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if eventKitCalendars.isEmpty {
                    Text("No macOS calendars detected. If your work/Teams calendar is missing, add the account in System Settings → Internet Accounts (Calendars enabled), or connect Microsoft 365 below.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    matchSubheader
                    calendarToggleList(eventKitCalendars)
                }
            } header: {
                Label("On this Mac", systemImage: "menubar.dock.rectangle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .textCase(nil)
            }

            // MARK: - Microsoft 365 (Graph)
            Section {
                if graphAuth.isConnected {
                    connectedRows
                } else {
                    disconnectedRows
                }
            } header: {
                Label("Microsoft 365 / Teams", systemImage: "calendar.badge.plus")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .textCase(nil)
            } footer: {
                Text("Pulls your Outlook/Teams calendar directly over the network — useful when your work calendar isn't synced to macOS. Read-only; you can disconnect anytime.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task { await reload() }
    }

    private func reload() async {
        await calendarService.requestAccess()
        allCalendars = await calendarService.availableCalendars()
        disabledIDs = CalendarSelection.disabledIDs()
    }

    private func connectAndReload() {
        Task {
            await graphAuth.connect()
            await reload()
        }
    }

    // MARK: - Calendar selection rows

    private var matchSubheader: some View {
        Text("Match these calendars")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func calendarToggleList(_ choices: [CalendarChoice]) -> some View {
        ForEach(choices) { choice in
            Toggle(isOn: binding(for: choice)) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(choice.title)
                    Text(choice.account)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func binding(for choice: CalendarChoice) -> Binding<Bool> {
        Binding(
            get: { !disabledIDs.contains(choice.id) },
            set: { isOn in
                CalendarSelection.setEnabled(isOn, id: choice.id)
                if isOn { disabledIDs.remove(choice.id) } else { disabledIDs.insert(choice.id) }
            }
        )
    }

    // MARK: - Connected

    @ViewBuilder
    private var connectedRows: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 1) {
                Text(graphAuth.connectedName ?? "Connected")
                    .font(.body)
                if let email = graphAuth.connectedEmail {
                    Text(email)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }

        if graphAuth.needsReconnect {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Reconnect needed — your Microsoft sign-in expired.")
                    .font(.caption)
                Spacer()
                Button("Reconnect") { connectAndReload() }
                    .controlSize(.small)
            }
        }

        Toggle("Include Microsoft 365 events when matching", isOn: $graphEnabled)

        if graphEnabled && !graphCalendars.isEmpty {
            matchSubheader
            calendarToggleList(graphCalendars)
        }

        Button("Disconnect", role: .destructive) {
            graphAuth.disconnect()
            allCalendars = allCalendars.filter { $0.source != .microsoftGraph }
        }
        .controlSize(.small)
    }

    // MARK: - Disconnected

    @ViewBuilder
    private var disconnectedRows: some View {
        if GraphConfig.isConfigured {
            Button {
                connectAndReload()
            } label: {
                HStack {
                    if graphAuth.isConnecting {
                        ProgressView().controlSize(.small)
                    }
                    Text(graphAuth.isConnecting ? "Connecting…" : "Connect Microsoft 365")
                }
            }
            .disabled(graphAuth.isConnecting)
        } else {
            HStack(spacing: 6) {
                Image(systemName: "wrench.and.screwdriver")
                    .foregroundStyle(.secondary)
                Text("Setup required: a Microsoft app client ID hasn't been configured in this build yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        if let error = graphAuth.lastError {
            Text(error)
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
