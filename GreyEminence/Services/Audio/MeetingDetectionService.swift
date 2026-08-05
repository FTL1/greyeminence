import AppKit
import AVFoundation
import CoreAudio
import Foundation

/// Watches for other apps using the microphone (Teams call, Zoom, Meet-in-browser,
/// FaceTime, etc.) and signals when a meeting likely started or ended. We only poll
/// when enabled, so there is no cost when the user has auto-start disabled.
///
/// The service is driven by explicit `noteStart`/`noteStop` calls from
/// `RecordingViewModel` so it understands whether the current recording is
/// auto-started (and should auto-stop when the call ends) or manually started
/// (user is in control — stay out of the way).
@Observable
@MainActor
final class MeetingDetectionService {
    enum Mode {
        case disabled
        case armedForStart
        case trackingAutoRun
        case passive
    }

    enum Origin {
        case manual
        case auto
    }

    /// A process other than us that currently has an active input IOProc.
    struct MicHolder: Sendable, Equatable {
        let pid: pid_t
        let bundleID: String?
        let appName: String?
        /// The same process is also running output IO — i.e. it is playing
        /// audio, not just listening.
        let outputRunning: Bool
    }

    private(set) var mode: Mode = .disabled
    private(set) var externalMicInUse: Bool = false

    /// Everything holding the mic as of the last poll. Read by
    /// `RecordingViewModel` to stamp source-app provenance on the meeting.
    private(set) var currentHolders: [MicHolder] = []

    private let startDebounce: TimeInterval = 10
    private let stopDebounce: TimeInterval = 60
    private let pollInterval: TimeInterval = 5

    private var timer: Timer?
    private var inUseSince: Date?
    private var clearSince: Date?
    /// Set when the user manually stops mid-call. Blocks auto-start until the
    /// external mic-in-use signal has cleared, so we don't re-record the same
    /// meeting they just told us to stop recording.
    private var waitingForMicClear: Bool = false

    /// Signature of the last logged holder set, so the 5s poll logs only when
    /// the picture actually changes.
    private var lastHolderIdentity: String?

    /// True once we've asked about the current hold, so an ignored prompt
    /// doesn't reappear every poll. Cleared when the mic goes quiet.
    private var hasPromptedForCurrentHold = false

    var onStartRequested: (() -> Void)?
    var onStopRequested: (() -> Void)?
    /// Raised instead of `onStartRequested` for apps that hold the mic
    /// outside of calls — the UI asks the user.
    var onConfirmationRequested: ((MicHolder) -> Void)?

    func enable(currentlyRecording: Bool) {
        guard mode == .disabled else { return }
        mode = currentlyRecording ? .passive : .armedForStart
        resetTimings()
        startTimer()
        LogManager.send("Meeting auto-detection enabled", category: .audio)
    }

    func disable() {
        mode = .disabled
        timer?.invalidate()
        timer = nil
        resetTimings()
        waitingForMicClear = false
        if externalMicInUse { externalMicInUse = false }
        LogManager.send("Meeting auto-detection disabled", category: .audio)
    }

    func noteStart(_ origin: Origin) {
        guard mode != .disabled else { return }
        mode = (origin == .auto) ? .trackingAutoRun : .passive
        // Recording now — don't ask again about the hold we just acted on.
        hasPromptedForCurrentHold = true
        resetTimings()
    }

    func noteStop(_ origin: Origin) {
        guard mode != .disabled else { return }
        mode = .armedForStart
        waitingForMicClear = (origin == .manual) && queryMicInUse()
        resetTimings()
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
    }

    private func resetTimings() {
        inUseSince = nil
        clearSince = nil
    }

    private func tick() {
        guard mode != .disabled else { return }
        let holders = snapshotHolders()
        currentHolders = holders
        let inUse = !holders.isEmpty
        if externalMicInUse != inUse {
            externalMicInUse = inUse
        }
        // Leaving the channel (or ending the call) re-arms the prompt, so the
        // next call asks again.
        if !inUse { hasPromptedForCurrentHold = false }

        switch mode {
        case .armedForStart:
            handleArmed(holders: holders)
        case .trackingAutoRun:
            // Deliberately keyed off mic-held only, never voice activity: a
            // long silence mid-call must not end the recording.
            handleTracking(inUse: inUse)
        case .passive, .disabled:
            break
        }
    }

    private func handleArmed(holders: [MicHolder]) {
        if waitingForMicClear {
            if holders.isEmpty { waitingForMicClear = false }
            return
        }
        let decision = Self.startDecision(for: holders)
        guard let holder = decision.holder else {
            inUseSince = nil
            return
        }
        clearSince = nil
        if inUseSince == nil { inUseSince = Date() }
        guard let since = inUseSince else { return }
        let debounce = decision.debounce ?? startDebounce
        guard Date().timeIntervalSince(since) >= debounce else { return }

        let who = holder.appName ?? holder.bundleID ?? "another app"
        switch decision {
        case .start:
            LogManager.send("Auto-detected meeting start (\(who))", category: .audio)
            onStartRequested?()
        case .confirm:
            // Once per hold: an ignored prompt must not come back every poll.
            guard !hasPromptedForCurrentHold else { return }
            hasPromptedForCurrentHold = true
            LogManager.send("Asking whether to record \(who) call", category: .audio)
            onConfirmationRequested?(holder)
        case .none:
            break
        }
    }

    /// What to do about the current set of mic holders.
    ///
    /// Pure so the policy can be tested without Core Audio. Apps whose profile
    /// sets `requiresConfirmation` produce `.confirm`; everything else
    /// produces `.start` on mic-held alone, exactly as before profiles existed.
    enum StartDecision: Equatable {
        case none
        case start(holder: MicHolder, debounce: TimeInterval?)
        case confirm(holder: MicHolder, debounce: TimeInterval?)

        var holder: MicHolder? {
            switch self {
            case .none: nil
            case .start(let holder, _), .confirm(let holder, _): holder
            }
        }

        var debounce: TimeInterval? {
            switch self {
            case .none: nil
            case .start(_, let debounce), .confirm(_, let debounce): debounce
            }
        }
    }

    static func startDecision(for holders: [MicHolder]) -> StartDecision {
        // A holder that can start on its own wins over one that needs asking,
        // so a Teams call still auto-records while Discord sits in a channel.
        var pendingConfirmation: StartDecision?
        for holder in holders {
            guard let profile = MeetingAppRegistry.profile(for: holder.bundleID) else {
                return .start(holder: holder, debounce: nil)  // unknown app — default policy
            }
            if profile.requiresConfirmation {
                if pendingConfirmation == nil {
                    pendingConfirmation = .confirm(
                        holder: holder, debounce: profile.startDebounceOverride
                    )
                }
                continue
            }
            return .start(holder: holder, debounce: profile.startDebounceOverride)
        }
        return pendingConfirmation ?? .none
    }

    private func handleTracking(inUse: Bool) {
        if !inUse {
            inUseSince = nil
            if clearSince == nil { clearSince = Date() }
            guard let since = clearSince else { return }
            if Date().timeIntervalSince(since) >= stopDebounce {
                LogManager.send("Auto-detected meeting end (mic clear for \(Int(stopDebounce))s)", category: .audio)
                onStopRequested?()
            }
        } else {
            clearSince = nil
        }
    }

    private func queryMicInUse() -> Bool {
        !snapshotHolders().isEmpty
    }

    /// Every process *other than us* with an active input IOProc, along with
    /// whether it is also running output IO. Uses Core Audio HAL's per-process
    /// APIs (macOS 14.4+), which see HAL-direct clients like Microsoft Teams
    /// and Zoom that `AVCaptureDevice.isInUseByAnotherApplication` misses
    /// entirely.
    ///
    /// Polled rather than observed: property listeners for the `IsRunning*`
    /// selectors are documented as unreliable, and we already tick on a timer.
    ///
    /// Safe to call when disabled — `RecordingViewModel` uses it for a
    /// one-shot read when a recording is started manually.
    func snapshotHolders() -> [MicHolder] {
        let myPID = getpid()
        var listAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &listAddress, 0, nil, &dataSize
        ) == noErr, dataSize > 0 else {
            return []
        }

        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var processObjects = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &listAddress, 0, nil, &dataSize, &processObjects
        ) == noErr else {
            return []
        }

        var pidAddress = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyPID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var inputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunningInput,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var outputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunningOutput,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var holders: [MicHolder] = []
        for processObject in processObjects {
            var pid: pid_t = 0
            var pidSize = UInt32(MemoryLayout<pid_t>.size)
            guard AudioObjectGetPropertyData(
                processObject, &pidAddress, 0, nil, &pidSize, &pid
            ) == noErr, pid != myPID else { continue }

            var running: UInt32 = 0
            var runningSize = UInt32(MemoryLayout<UInt32>.size)
            guard AudioObjectGetPropertyData(
                processObject, &inputAddress, 0, nil, &runningSize, &running
            ) == noErr, running == 1 else { continue }

            var outputRunning: UInt32 = 0
            var outputSize = UInt32(MemoryLayout<UInt32>.size)
            // A failed read means "we don't know", which we treat as not
            // playing — the conservative reading for a gate that starts
            // recordings.
            let outputOK = AudioObjectGetPropertyData(
                processObject, &outputAddress, 0, nil, &outputSize, &outputRunning
            ) == noErr

            let app = NSRunningApplication(processIdentifier: pid)
            holders.append(MicHolder(
                pid: pid,
                bundleID: app?.bundleIdentifier,
                appName: MeetingAppRegistry.displayName(
                    for: app?.bundleIdentifier,
                    fallback: app?.localizedName
                ),
                outputRunning: outputOK && outputRunning == 1
            ))
        }

        logHolderChange(holders)
        return holders
    }

    /// Logs only on transitions — the poll runs every 5s and would otherwise
    /// flood the activity log for the entire length of a call.
    private func logHolderChange(_ holders: [MicHolder]) {
        let identity = holders
            .map { "\($0.bundleID ?? "pid \($0.pid)")\($0.outputRunning ? "+out" : "")" }
            .sorted()
            .joined(separator: ", ")
        guard identity != lastHolderIdentity else { return }
        lastHolderIdentity = identity
        if holders.isEmpty {
            LogManager.send("Meeting detector: no other app holding the mic", category: .audio)
        } else {
            LogManager.send("Meeting detector sees input IO from \(identity)", category: .audio)
        }
    }
}
