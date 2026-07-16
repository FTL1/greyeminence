import SwiftUI

struct AudioSettingsView: View {
    @State private var audioManager = AudioSessionManager()
    @State private var monitor = MicLevelMonitor()
    @AppStorage("inputGain") private var inputGain: Double = 1.0
    @AppStorage("autoReprocessMeetings") private var autoReprocessMeetings: Bool = true
    @State private var captureSystemAudio = true

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
