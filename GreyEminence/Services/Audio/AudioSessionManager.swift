import AppKit
import AVFoundation
import CoreAudio

@Observable
@MainActor
final class AudioSessionManager {
    enum PermissionStatus: Sendable {
        case unknown
        case granted
        case denied
    }

    var micPermission: PermissionStatus = .unknown
    var screenRecordingPermission: PermissionStatus = .unknown
    var availableInputDevices: [AudioDevice] = []
    var selectedInputDevice: AudioDevice? {
        didSet {
            guard oldValue != selectedInputDevice else { return }
            persistSelectedDevice()
        }
    }

    nonisolated static let preferredUIDKey = "audio.preferredInputDeviceUID"
    nonisolated static let preferredNameKey = "audio.preferredInputDeviceName"

    struct AudioDevice: Identifiable, Hashable, Sendable {
        let id: AudioDeviceID
        let name: String
        let uid: String
    }

    func checkPermissions() async {
        await checkMicPermission()
        await checkScreenRecordingPermission()
    }

    func checkMicPermission() async {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            micPermission = .granted
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            micPermission = granted ? .granted : .denied
        case .denied, .restricted:
            micPermission = .denied
        @unknown default:
            micPermission = .unknown
        }
    }

    func checkScreenRecordingPermission() async {
        let report = await ScreenCapturePermission.probe(requestIfNeeded: false)
        screenRecordingPermission = report.isEffectivelyGranted ? .granted : .denied
    }

    /// Each ad-hoc DMG is a new TCC identity. Opening the pane is the only
    /// recovery when status is already `.denied`.
    nonisolated static func openMicrophonePrivacySettings() {
        openPrivacyPane("Privacy_Microphone")
    }

    nonisolated static func openSystemAudioPrivacySettings() {
        openPrivacyPane("Privacy_AudioCapture")
    }

    nonisolated static func openScreenRecordingPrivacySettings() {
        openPrivacyPane("Privacy_ScreenCapture")
    }

    /// Tahoe has no handler for `x-apple.systemsettings:…Privacy_AudioCapture`
    /// (LaunchServices shows “Search App Store”). Sequoia+ also merged
    /// System Audio into Screen & System Audio Recording.
    nonisolated static func privacyURLCandidates(for pane: String) -> [String] {
        switch pane {
        case "Privacy_AudioCapture":
            return privacyURLCandidates(for: "Privacy_ScreenCapture")
        case "Privacy_Notifications":
            return [
                "x-apple.systempreferences:com.apple.Notifications-Settings.extension",
                "x-apple.systempreferences:com.apple.Notifications",
                "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension",
            ]
        default:
            return [
                "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?\(pane)",
                "x-apple.systempreferences:com.apple.preference.security?\(pane)",
                "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension",
            ]
        }
    }

    nonisolated static func openPrivacyPane(_ pane: String) {
        for string in privacyURLCandidates(for: pane) {
            guard let url = URL(string: string) else { continue }
            if NSWorkspace.shared.urlForApplication(toOpen: url) != nil {
                NSWorkspace.shared.open(url)
                return
            }
        }
    }

    func enumerateInputDevices() {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &dataSize
        )
        guard status == noErr else { return }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &dataSize,
            &deviceIDs
        )
        guard status == noErr else { return }

        availableInputDevices = deviceIDs.compactMap { deviceID in
            guard hasInputStreams(deviceID),
                  !isAggregateDevice(deviceID) else { return nil }
            guard let name = deviceName(deviceID), let uid = deviceUID(deviceID) else { return nil }
            return AudioDevice(id: deviceID, name: name, uid: uid)
        }

        selectedInputDevice = Self.pickPreferredDevice(from: availableInputDevices, builtInCheck: isBuiltIn)
    }

    /// Resolve which device to use given the persisted preference, falling
    /// through name match → built-in → first available. Public so the
    /// recording path can call it without holding an `AudioSessionManager`.
    nonisolated static func pickPreferredDevice(
        from devices: [AudioDevice],
        builtInCheck: (AudioDeviceID) -> Bool
    ) -> AudioDevice? {
        guard !devices.isEmpty else { return nil }
        let defaults = UserDefaults.standard
        if let uid = defaults.string(forKey: preferredUIDKey),
           let match = devices.first(where: { $0.uid == uid }) {
            return match
        }
        if let name = defaults.string(forKey: preferredNameKey),
           let match = devices.first(where: { $0.name == name }) {
            return match
        }
        if let builtIn = devices.first(where: { builtInCheck($0.id) }) {
            return builtIn
        }
        return devices.first
    }

    private func persistSelectedDevice() {
        let defaults = UserDefaults.standard
        if let device = selectedInputDevice {
            defaults.set(device.uid, forKey: Self.preferredUIDKey)
            defaults.set(device.name, forKey: Self.preferredNameKey)
        } else {
            defaults.removeObject(forKey: Self.preferredUIDKey)
            defaults.removeObject(forKey: Self.preferredNameKey)
        }
    }

    private func isBuiltIn(_ deviceID: AudioDeviceID) -> Bool {
        var transportType: UInt32 = 0
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, &transportType)
        return status == noErr && transportType == kAudioDeviceTransportTypeBuiltIn
    }

    private func isAggregateDevice(_ deviceID: AudioDeviceID) -> Bool {
        var transportType: UInt32 = 0
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, &transportType)
        guard status == noErr else { return false }
        return transportType == kAudioDeviceTransportTypeAggregate
            || transportType == kAudioDeviceTransportTypeVirtual
    }

    private func hasInputStreams(_ deviceID: AudioDeviceID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &dataSize)
        return status == noErr && dataSize > 0
    }

    private func deviceName(_ deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: CFString = "" as CFString
        var dataSize = UInt32(MemoryLayout<CFString>.size)
        let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, &name)
        return status == noErr ? name as String : nil
    }

    private func deviceUID(_ deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uid: CFString = "" as CFString
        var dataSize = UInt32(MemoryLayout<CFString>.size)
        let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, &uid)
        return status == noErr ? uid as String : nil
    }
}
