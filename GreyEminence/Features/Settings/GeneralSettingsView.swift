import SwiftUI
import SwiftData
import Sparkle

struct GeneralSettingsView: View {
    var updater: SPUUpdater?
    @ObservedObject private var updateViewModel: CheckForUpdatesViewModel
    @Environment(\.modelContext) private var modelContext
    @AppStorage("autoStartRecording") private var autoStart = false
    @AppStorage("showMenuBarIcon") private var showMenuBar = true
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("stalledThresholdDays") private var stalledThresholdDays = 7
    @AppStorage("appFontSize") private var appFontSize = "medium"
    @AppStorage("myContactID") private var myContactIDString = ""
    @AppStorage(SpeakerNames.globalMeDisplayNameKey) private var myDisplayName = ""
    /// 0 = unlimited (default). >0 means delete audio for any completed
    /// meeting older than that many days. Transcripts always stay.
    @AppStorage("recordingRetentionDays") private var recordingRetentionDays = 0
    @AppStorage("autoMergeSameSpeaker") private var autoMergeSameSpeaker = true
    @AppStorage("autoMergeMaxWindowSeconds") private var autoMergeMaxWindowSeconds = 15
    @AppStorage("autoMergePauseSeconds") private var autoMergePauseSeconds = 4.0
    @AppStorage("autoMergeSettingsVersion") private var autoMergeSettingsVersion = 0
    @Query(sort: \Contact.name) private var contacts: [Contact]
    @Query private var allMeetings: [Meeting]
    @State private var lastRetentionResult: String?

    init(updater: SPUUpdater?) {
        self.updater = updater
        if let updater {
            self._updateViewModel = ObservedObject(wrappedValue: CheckForUpdatesViewModel(updater: updater))
        } else {
            self._updateViewModel = ObservedObject(wrappedValue: CheckForUpdatesViewModel())
        }
    }

    private var myContact: Contact? {
        guard let id = UUID(uuidString: myContactIDString) else { return nil }
        return contacts.first { $0.id == id }
    }

    var body: some View {
        Form {
            Section {
                Picker("My Profile", selection: $myContactIDString) {
                    Text("Not set").tag("")
                    ForEach(contacts.filter { !$0.isArchived }) { contact in
                        Text(contact.name).tag(contact.id.uuidString)
                    }
                }
                .helpTip(.settingsMyProfile)
                if let contact = myContact {
                    HStack(spacing: 6) {
                        Text(contact.initials)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 18, height: 18)
                            .background(contact.avatarColor.gradient, in: Circle())
                        Text(contact.name)
                            .font(.caption)
                        if let email = contact.email {
                            Text(email)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Text("This identifies you in meetings and interviews. The local speaker label will be attributed to this contact.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("My display name", text: $myDisplayName)
                    .helpTip(.settingsDisplayName)
                Text("Pre-fills the local/mic speaker label on new recordings (instead of \"Me\"). Renaming during a meeting overrides this for that session only unless you choose Save as Default.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Label("My Profile", systemImage: "person.circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .textCase(nil)
            }

            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .helpTip(.settingsLaunchAtLogin)
                Toggle("Show menu bar icon", isOn: $showMenuBar)
                    .helpTip(.settingsMenuBar)
            } header: {
                Label("Startup", systemImage: "power")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .textCase(nil)
            }

            Section {
                Picker("Text Size", selection: $appFontSize) {
                    Text("Extra Small").tag("xSmall")
                    Text("Small").tag("small")
                    Text("Medium (Default)").tag("medium")
                    Text("Large").tag("large")
                    Text("Extra Large").tag("xLarge")
                }
                .helpTip(.settingsTextSize)
            } header: {
                Label("Appearance", systemImage: "textformat.size")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .textCase(nil)
            }

            Section {
                Toggle("Auto-merge same-speaker fragments", isOn: $autoMergeSameSpeaker)
                    .helpTip(.settingsAutoMerge)
                if autoMergeSameSpeaker {
                    Picker("Maximum group length", selection: $autoMergeMaxWindowSeconds) {
                        Text("10 seconds").tag(10)
                        Text("15 seconds").tag(15)
                        Text("20 seconds").tag(20)
                        Text("30 seconds").tag(30)
                    }
                    Picker("Break on pause longer than", selection: $autoMergePauseSeconds) {
                        Text("2 seconds").tag(2.0)
                        Text("3 seconds").tag(3.0)
                        Text("4 seconds").tag(4.0)
                        Text("5 seconds").tag(5.0)
                    }
                }
                Text("Joins consecutive lines from the same person when nobody else talks in between, up to the window or a long pause — whichever comes first. Near-duplicate ASR crumbs are collapsed, not repeated. Undo is in the transcript ⋯ menu. Does not run while recording.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Label("Transcript", systemImage: "text.bubble")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .textCase(nil)
            }

            Section {
                Toggle("Watch for meetings (auto-record when a call starts)", isOn: $autoStart)
                    .helpTip(.watchForMeetings)
                Text("When on, the app waits for Teams, Zoom, Meet, Slack, Webex, or FaceTime and records that call. Discord asks first. It does not capture your mic 24/7. Stop all (top of the window) turns this off and cancels live AI. Full text: Help → Controls and options.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()

                Toggle(
                    "Auto-delete audio after a retention period",
                    isOn: Binding(
                        get: { recordingRetentionDays > 0 },
                        set: { recordingRetentionDays = $0 ? max(recordingRetentionDays, 30) : 0 }
                    )
                )
                .helpTip(.settingsRetention)
                if recordingRetentionDays > 0 {
                    Stepper(
                        "Keep audio for \(recordingRetentionDays) day\(recordingRetentionDays == 1 ? "" : "s")",
                        value: $recordingRetentionDays,
                        in: 1...365
                    )
                }
                Text("Transcripts and meeting rows always stay. Only the (large) audio files are removed for completed meetings older than the threshold. Sweep runs at app launch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Button("Run cleanup now") { runRetentionNow() }
                        .controlSize(.small)
                        .disabled(recordingRetentionDays == 0)
                    if let last = lastRetentionResult {
                        Text(last)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Label("Recording", systemImage: "record.circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .textCase(nil)
            }

            Section {
                Stepper(
                    "Stalled threshold: \(stalledThresholdDays) day\(stalledThresholdDays == 1 ? "" : "s")",
                    value: $stalledThresholdDays,
                    in: 1...90
                )
                .helpTip(.settingsStalled)
                Text("Action items older than this are flagged as stalled in the Tasks view.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Label("Tasks", systemImage: "checkmark.circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .textCase(nil)
            }

            Section {
                LabeledContent("App") {
                    Text(AppIdentity.displayName)
                }
                Text("Unofficial fork of Grey Eminence. Not Matt Purdon’s product. No warranty. Use at your own risk. Lawful use only — you are responsible for consent and recording laws. The name: Help → Why Grey Conseil (éminence grise + Verne’s Conseil).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String
                     ?? "Copyright © 2026 Matthew Purdon. Unofficial Grey Conseil portions under the same license.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LabeledContent("Version") {
                    HStack(spacing: 8) {
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0")
                        if let lastCheck = updateViewModel.lastUpdateCheckDate {
                            Text("Last checked \(lastCheck, format: .relative(presentation: .named))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Button("Check for Updates") {
                    updater?.checkForUpdates()
                }
                .disabled(!updateViewModel.canCheckForUpdates)
                .helpTip(.settingsCheckUpdates)
            } header: {
                Label("About", systemImage: "info.circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .textCase(nil)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            if autoMergeSettingsVersion < 1 {
                if autoMergePauseSeconds <= 2.0 { autoMergePauseSeconds = 4.0 }
                if autoMergeMaxWindowSeconds <= 10 { autoMergeMaxWindowSeconds = 15 }
                autoMergeSettingsVersion = 1
            }
        }
    }

    private func runRetentionNow() {
        guard recordingRetentionDays > 0 else { return }
        var ages: [UUID: Date] = [:]
        for m in allMeetings where m.status == .completed {
            ages[m.id] = m.date.addingTimeInterval(m.duration)
        }
        let result = StorageManager.shared.purgeRecordingsOlderThan(
            days: recordingRetentionDays,
            meetingFinishedAt: ages
        )
        if result.count > 0 {
            let mb = Double(result.bytes) / 1_048_576
            lastRetentionResult = "Removed \(result.count) recording(s), freed \(String(format: "%.1f", mb)) MB"
        } else {
            lastRetentionResult = "Nothing to remove."
        }
    }
}
