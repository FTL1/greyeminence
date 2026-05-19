import SwiftUI
import AppKit

struct InterviewSettingsView: View {
    @AppStorage(PhaseAlertSettings.warn1EnabledKey) private var firstWarnEnabled = true
    @AppStorage(PhaseAlertSettings.warn2EnabledKey) private var secondWarnEnabled = true
    @AppStorage(PhaseAlertSettings.overtimeEnabledKey) private var overtimeEnabled = true
    @AppStorage(PhaseAlertSettings.warn1MinutesKey) private var firstWarnMinutes = PhaseAlertSettings.defaultWarn1Minutes
    @AppStorage(PhaseAlertSettings.warn2MinutesKey) private var secondWarnMinutes = PhaseAlertSettings.defaultWarn2Minutes
    @AppStorage(PhaseAlertSettings.soundEnabledKey) private var soundEnabled = true
    @AppStorage(PhaseAlertSettings.sound5MinKey) private var firstWarnSound = PhaseAlertSettings.defaultSound5Min
    @AppStorage(PhaseAlertSettings.sound1MinKey) private var secondWarnSound = PhaseAlertSettings.defaultSound1Min
    @AppStorage(PhaseAlertSettings.soundOvertimeKey) private var overtimeSound = PhaseAlertSettings.defaultSoundOvertime

    /// macOS bundled alert sounds at `/System/Library/Sounds/`. All play
    /// reliably via `NSSound(named:)` without any extra entitlements.
    private static let soundCatalog = [
        "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero",
        "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink"
    ]

    var body: some View {
        Form {
            Section {
                Toggle("Play sound on alerts", isOn: $soundEnabled)

                alertRow(
                    title: "First warning",
                    enabled: $firstWarnEnabled,
                    minutes: $firstWarnMinutes,
                    minutesRange: 1...30,
                    sound: $firstWarnSound
                )

                alertRow(
                    title: "Second warning",
                    enabled: $secondWarnEnabled,
                    minutes: $secondWarnMinutes,
                    minutesRange: 1...10,
                    sound: $secondWarnSound
                )

                alertRow(
                    title: "Overtime alert",
                    enabled: $overtimeEnabled,
                    minutes: nil,
                    minutesRange: nil,
                    sound: $overtimeSound
                )

                Text("Per-phase alerts fire when an interview phase has the configured time remaining. Set a phase's target minutes in its template or the interview-creation modal — phases without a target are silent.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Label("Phase time-box alerts", systemImage: "timer")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .textCase(nil)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func alertRow(
        title: String,
        enabled: Binding<Bool>,
        minutes: Binding<Int>?,
        minutesRange: ClosedRange<Int>?,
        sound: Binding<String>
    ) -> some View {
        HStack {
            Toggle(title, isOn: enabled)
            Spacer()
            if let minutes, let minutesRange {
                Stepper(value: minutes, in: minutesRange) {
                    Text("\(minutes.wrappedValue) min before")
                        .monospacedDigit()
                        .foregroundStyle(enabled.wrappedValue ? .primary : .secondary)
                }
                .disabled(!enabled.wrappedValue)
                .frame(width: 180)
            }
            soundPicker(selection: sound)
                .disabled(!enabled.wrappedValue || !soundEnabled)
        }
    }

    private func soundPicker(selection: Binding<String>) -> some View {
        HStack(spacing: 4) {
            Picker("", selection: selection) {
                ForEach(Self.soundCatalog, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            .labelsHidden()
            .frame(width: 120)

            Button {
                NSSound(named: selection.wrappedValue)?.play()
            } label: {
                Image(systemName: "play.circle")
            }
            .buttonStyle(.borderless)
            .help("Preview")
        }
    }
}
