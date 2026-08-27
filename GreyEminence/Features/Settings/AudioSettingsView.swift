import SwiftData
import SwiftUI

struct AudioSettingsView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var audioManager = AudioSessionManager()
    @State private var monitor = MicLevelMonitor()
    @AppStorage("inputGain") private var inputGain: Double = 1.0
    @AppStorage("autoReprocessMeetings") private var autoReprocessMeetings: Bool = true
    @State private var captureSystemAudio = true

    @State private var isRepairing = false
    @State private var repairDone = 0
    @State private var repairTotal = 0
    @State private var repairCandidates = 0
    @State private var repairSummary: String?
    @State private var repairResettable = 0

    @MainActor
    private func resetSpeakers() {
        let meetings = (try? modelContext.fetch(FetchDescriptor<Meeting>())) ?? []
        var reverted = 0
        for meeting in meetings where SpeakerRepairService.canResetLabels(meeting) {
            if SpeakerRepairService.resetLabels(for: meeting, in: modelContext) > 0 { reverted += 1 }
        }
        repairSummary = reverted == 0
            ? "Nothing to undo."
            : "Restored the previous labels in \(reverted) meeting\(reverted == 1 ? "" : "s")."
        refreshRepairCounts()
    }

    @MainActor
    private func refreshRepairCounts() {
        repairCandidates = SpeakerRepairService.candidates(in: modelContext).count
        let meetings = (try? modelContext.fetch(FetchDescriptor<Meeting>())) ?? []
        repairResettable = meetings.count { SpeakerRepairService.canResetLabels($0) }
    }

    @MainActor
    private func repairSpeakers() async {
        isRepairing = true
        repairSummary = nil
        defer {
            isRepairing = false
            refreshRepairCounts()
        }
        let result = await SpeakerRepairService.repairAll(in: modelContext) { done, total in
            repairDone = done
            repairTotal = total
        }
        repairSummary = result.repaired == 0
            ? "Nothing to change — the voices in those meetings couldn't be told apart."
            : "Separated speakers in \(result.repaired) meeting\(result.repaired == 1 ? "" : "s")."
            + (result.skipped > 0 ? " \(result.skipped) skipped — see the Activity Log." : "")
    }

    var body: some View {
        Form {
            Section {
                Picker("Input Device", selection: $audioManager.selectedInputDevice) {
                    ForEach(audioManager.availableInputDevices) { device in
                        Text(device.name).tag(device as AudioSessionManager.AudioDevice?)
                    }
                }

                HStack {
                    Text("Input Gain")
                    Slider(value: $inputGain, in: 0.25...4.0)
                    Text(String(format: "%.1fx", inputGain))
                        .font(.caption)
                        .fontDesign(.monospaced)
                        .frame(width: 36)
                }

                // Isolated subview: `monitor.level` updates on every audio
                // buffer, and reading it in THIS body re-rendered the whole
                // form dozens of times a second — rebuilding the Input Device
                // picker's menu items while the menu was open and wedging the
                // app in an orphaned menu-tracking loop.
                MicLevelMeter(monitor: monitor)
            } header: {
                Label("Microphone", systemImage: "mic")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .textCase(nil)
            }

            Section {
                Toggle(isOn: $captureSystemAudio) {
                    VStack(alignment: .leading) {
                        Text("Capture system audio (speaker output)")
                        Text("Requires Screen Recording permission")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if captureSystemAudio {
                    Text("System audio will be captured and transcribed as \"Other\" speaker.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Label("System Audio", systemImage: "speaker.wave.2")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .textCase(nil)
            }

            Section {
                Toggle("Re-transcribe meetings after recording", isOn: $autoReprocessMeetings)
                Text("Live transcription uses a fast model (FluidAudio Parakeet). When a meeting ends, the audio is re-transcribed in the background with WhisperKit large-v3, and AI insights + embeddings are rebuilt on the upgraded transcript. Re-processing pauses automatically while another recording is in progress.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("First run downloads the large-v3 model (~1.5 GB).")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } header: {
                Label("High-accuracy re-transcription", systemImage: "waveform.badge.checkmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .textCase(nil)
            }

            Section {
                HStack {
                    Button(isRepairing ? "Identifying…" : "Identify speakers in older meetings") {
                        Task { await repairSpeakers() }
                    }
                    .disabled(isRepairing || repairCandidates == 0)
                    if isRepairing, repairTotal > 0 {
                        ProgressView(value: Double(repairDone), total: Double(repairTotal))
                            .frame(width: 120)
                        Text("\(repairDone)/\(repairTotal)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                if repairResettable > 0 {
                    HStack {
                        Button("Undo speaker separation") {
                            resetSpeakers()
                        }
                        .disabled(isRepairing)
                        Text("Restores the labels \(repairResettable) meeting\(repairResettable == 1 ? "" : "s") had before. Lines you renamed yourself are left as they are.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if let repairSummary {
                    Text(repairSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(repairCandidates == 0
                     ? "Every meeting with audio still on disk has its speakers separated."
                     : "\(repairCandidates) meeting\(repairCandidates == 1 ? "" : "s") were transcribed before speakers were told apart, so everyone but you shows as \"Speaker\". This listens to the audio again and separates the voices — the words and timings don't change, only who each line is attributed to. It doesn't re-transcribe, so it's far quicker than re-processing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Meetings whose audio has already been cleared by the retention setting can't be repaired. Voices are numbered per meeting — \"Speaker 1\" in one isn't the same person as in another.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } header: {
                Label("Speaker separation", systemImage: "person.2.wave.2")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .textCase(nil)
            }

            Section {
                LabeledContent("Audio Format") {
                    Text("AAC (.m4a)")
                }
                LabeledContent("Transcription Input") {
                    Text("16kHz mono Float32")
                }
                LabeledContent("Storage Location") {
                    Text("~/Library/Application Support/GreyEminence/Recordings")
                        .font(.caption)
                        .fontDesign(.monospaced)
                }
            } header: {
                Label("Recording Format", systemImage: "waveform")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .textCase(nil)
            }
        }
        .formStyle(.grouped)
        .onAppear { refreshRepairCounts() }
        .task {
            await audioManager.checkMicPermission()
            audioManager.enumerateInputDevices()
        }
        .onDisappear {
            monitor.stopMonitoring()
        }
        .onChange(of: audioManager.selectedInputDevice) { _, newDevice in
            guard let newDevice else { return }
            monitor.startMonitoring(deviceUID: newDevice.uid)
        }
        .onChange(of: inputGain, initial: true) { _, newGain in
            monitor.gain = Float(newGain)
        }
    }
}

/// Level bars in their own view so the per-buffer `level` updates only
/// invalidate this subtree — never the surrounding form and its picker.
private struct MicLevelMeter: View {
    let monitor: MicLevelMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 2) {
                Text("Level")
                    .font(.caption)
                ForEach(0..<20, id: \.self) { i in
                    Rectangle()
                        .fill(i < 14 ? .green : (i < 17 ? .yellow : .red))
                        .frame(width: 8, height: 12)
                        .opacity(Double(i) / 20.0 < Double(monitor.level) ? 1.0 : 0.2)
                }
                Text(String(format: "%.3f", monitor.level))
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .foregroundStyle(.secondary)
            }
            .opacity(monitor.statusMessage == nil ? 1 : 0.4)

            if let status = monitor.statusMessage {
                Label(status, systemImage: "pause.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }
}
