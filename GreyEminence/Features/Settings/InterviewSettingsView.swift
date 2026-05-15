import SwiftUI

/// Interview-flow preferences. Currently scoped to per-phase time-box
/// alerts; this is the natural home for future interview-runtime
/// settings (auto-advance, sound choice, transcript display tweaks, ...).
struct InterviewSettingsView: View {
    @AppStorage("phaseAlert5MinEnabled") private var firstWarnEnabled = true
    @AppStorage("phaseAlert1MinEnabled") private var secondWarnEnabled = true
    @AppStorage("phaseAlertOvertimeEnabled") private var overtimeEnabled = true
    @AppStorage("phaseAlertWarn1Minutes") private var firstWarnMinutes = 5
    @AppStorage("phaseAlertWarn2Minutes") private var secondWarnMinutes = 1
    @AppStorage("phaseAlertSoundEnabled") private var soundEnabled = true

    var body: some View {
        Form {
            Section {
                Toggle("Play sound on alerts", isOn: $soundEnabled)

                HStack {
                    Toggle("First warning", isOn: $firstWarnEnabled)
                    Spacer()
                    Stepper(value: $firstWarnMinutes, in: 1...30) {
                        Text("\(firstWarnMinutes) min before")
                            .monospacedDigit()
                            .foregroundStyle(firstWarnEnabled ? .primary : .secondary)
                    }
                    .disabled(!firstWarnEnabled)
                    .frame(width: 200)
                }

                HStack {
                    Toggle("Second warning", isOn: $secondWarnEnabled)
                    Spacer()
                    Stepper(value: $secondWarnMinutes, in: 1...10) {
                        Text("\(secondWarnMinutes) min before")
                            .monospacedDigit()
                            .foregroundStyle(secondWarnEnabled ? .primary : .secondary)
                    }
                    .disabled(!secondWarnEnabled)
                    .frame(width: 200)
                }

                Toggle("Overtime alert", isOn: $overtimeEnabled)

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
}
