import AVFoundation

extension Notification.Name {
    /// Posted when a recording starts capturing the microphone. The level
    /// monitor observes this and pauses so two AVAudioEngines in the same
    /// process don't fight for the same input device (which results in
    /// silent buffers for the second one).
    static let geMicCaptureWillStart = Notification.Name("ge.mic.capture.willStart")
    static let geMicCaptureDidEnd = Notification.Name("ge.mic.capture.didEnd")
}

/// Process-wide "a recording owns the microphone" flag. The notifications
/// above only reach monitors that exist when they fire — a monitor created
/// AFTER a recording started (opening Audio settings mid-recording) missed
/// them, started a second engine on the same device, and metered silence
/// forever. New monitors consult this flag instead.
enum MicCaptureGate {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var active = false

    static var isActive: Bool {
        lock.lock(); defer { lock.unlock() }
        return active
    }

    static func set(_ value: Bool) {
        lock.lock(); active = value; lock.unlock()
    }
}

@Observable
@MainActor
final class MicLevelMonitor {
    var level: Float = 0
    var gain: Float = 1.0
    /// Why the meter isn't metering, for the settings UI. `nil` while live.
    private(set) var statusMessage: String?

    private var audioEngine: AVAudioEngine?
    private var isMonitoring = false
    private var pausedDeviceUID: String?
    private var retryTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    init() {
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: .geMicCaptureWillStart, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.pauseForRecording() }
        })
        observers.append(nc.addObserver(forName: .geMicCaptureDidEnd, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.resumeAfterRecording() }
        })
    }

    deinit {
        // observers is a stored property; notifications carry weak self so
        // expired refs no-op. Explicit removal isn't required pre-Swift 6
        // strict-actor isolation rules; left intentionally empty.
    }

    private func pauseForRecording() {
        guard isMonitoring else { return }
        pausedDeviceUID = audioEngine?.inputNode.audioUnit.flatMap(Self.currentDeviceUID(for:)) ?? ""
        stopMonitoring()
    }

    private func resumeAfterRecording() {
        guard pausedDeviceUID != nil else { return }
        let uid = pausedDeviceUID
        pausedDeviceUID = nil
        startMonitoring(deviceUID: uid?.isEmpty == false ? uid : nil)
    }

    func startMonitoring(deviceUID: String? = nil) {
        startMonitoring(deviceUID: deviceUID, isRetry: false)
    }

    private func startMonitoring(deviceUID: String?, isRetry: Bool) {
        stopMonitoring()

        // A live recording owns the input device — a second engine would
        // meter silence AND risk starving the recording's tap. Defer: the
        // capture-did-end notification resumes us.
        guard !MicCaptureGate.isActive else {
            pausedDeviceUID = deviceUID ?? ""
            statusMessage = "Level meter is paused while a recording is using the microphone"
            return
        }

        let engine = AVAudioEngine()

        if let deviceUID {
            Self.setInputDevice(uid: deviceUID, on: engine)
        }

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        guard format.sampleRate > 0, format.channelCount > 0 else {
            // USB mics can report a 0 Hz format while warming up after a
            // device switch. Retry once before declaring the meter dead.
            if isRetry {
                statusMessage = "Input device isn't producing audio — try re-selecting it"
                LogManager.send("Mic level monitor: input format still invalid after retry", category: .audio, level: .warning)
            } else {
                statusMessage = "Waiting for the input device…"
                retryTask = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(600))
                    guard let self, !Task.isCancelled else { return }
                    self.startMonitoring(deviceUID: deviceUID, isRetry: true)
                }
            }
            return
        }

        // Handler is @Sendable so the closure doesn't inherit MainActor isolation.
        // Store raw RMS (gain applied). The Settings bar maps this through
        // dBFS — a linear 0…1 scale leaves speech stuck on the first LED.
        Self.installMeterTap(on: inputNode, format: format) { [weak self] rms in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let instant = max(0, rms * self.gain)
                if instant > self.level {
                    self.level = instant
                } else {
                    self.level = max(instant, self.level * 0.82)
                }
            }
        }

        engine.prepare()
        do {
            try engine.start()
            audioEngine = engine
            isMonitoring = true
            statusMessage = nil
        } catch {
            engine.inputNode.removeTap(onBus: 0)
            statusMessage = "Level meter couldn't start: \(error.localizedDescription)"
            LogManager.send("Mic level monitor failed to start: \(error.localizedDescription)", category: .audio, level: .warning)
        }
    }

    func stopMonitoring() {
        retryTask?.cancel()
        retryTask = nil
        guard isMonitoring else { return }
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        isMonitoring = false
        level = 0
    }

    /// Installs the audio tap in a nonisolated context so the closure
    /// does not inherit MainActor isolation (which would crash on the realtime audio thread).
    private nonisolated static func installMeterTap(
        on inputNode: AVAudioInputNode,
        format: AVAudioFormat,
        handler: @escaping @Sendable (Float) -> Void
    ) {
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            handler(calculateRMS(buffer))
        }
    }

    private nonisolated static func calculateRMS(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return 0 }

        var sum: Float = 0
        for i in 0..<frameCount {
            let sample = channelData[0][i]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(frameCount))
        return rms
    }

    nonisolated private static func currentDeviceUID(for unit: AudioUnit) -> String? {
        var deviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioUnitGetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &deviceID, &size) == noErr,
              deviceID != 0 else { return nil }
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uid: Unmanaged<CFString>?
        var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &uidSize, &uid) == noErr,
              let cf = uid?.takeRetainedValue() else { return nil }
        return cf as String
    }

    private nonisolated static func setInputDevice(uid: String, on engine: AVAudioEngine) {
        var deviceID: AudioDeviceID = 0
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var uidCF = uid as CFString
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            UInt32(MemoryLayout<CFString>.size),
            &uidCF,
            &dataSize,
            &deviceID
        )

        guard status == noErr else { return }

        var inputDeviceID = deviceID
        AudioUnitSetProperty(
            engine.inputNode.audioUnit!,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &inputDeviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
    }
}
