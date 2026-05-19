import Foundation
import SwiftUI
import AppKit

/// `@AppStorage` keys + defaults shared between `PhaseTimerService` and
/// `InterviewSettingsView`. Centralized so a rename in one place can't
/// silently desync the picker UI from the timer's reads.
enum PhaseAlertSettings {
    static let warn1MinutesKey = "phaseAlertWarn1Minutes"
    static let warn2MinutesKey = "phaseAlertWarn2Minutes"
    static let warn1EnabledKey = "phaseAlert5MinEnabled"
    static let warn2EnabledKey = "phaseAlert1MinEnabled"
    static let overtimeEnabledKey = "phaseAlertOvertimeEnabled"
    static let soundEnabledKey = "phaseAlertSoundEnabled"
    static let sound1MinKey = "phaseAlertSound1Min"
    static let sound5MinKey = "phaseAlertSound5Min"
    static let soundOvertimeKey = "phaseAlertSoundOvertime"

    static let defaultWarn1Minutes = 5
    static let defaultWarn2Minutes = 1
    static let defaultSound1Min = "Hero"
    static let defaultSound5Min = "Tink"
    static let defaultSoundOvertime = "Funk"
}

@Observable
@MainActor
final class PhaseTimerService {
    enum AlertKind: Hashable {
        case warning(minutesLeft: Int)
        case overtime
    }

    struct Alert: Identifiable, Equatable {
        let id = UUID()
        let kind: AlertKind
        let phaseTitle: String
        let firedAt: Date
    }

    private(set) var currentAlert: Alert?

    private weak var activePhase: InterviewPhase?
    private var firedThresholds: Set<AlertKind> = []
    private var tickTimer: Timer?

    /// Pass `nil` to detach (interview ended, unscored phase active).
    func bind(to phase: InterviewPhase?) {
        // Rebinding to the same phase preserves fired-threshold state so a
        // re-render doesn't re-fire alerts.
        if phase?.id == activePhase?.id { return }

        activePhase = phase
        firedThresholds.removeAll()
        currentAlert = nil
        stopTimer()

        guard let phase, phase.targetMinutes != nil, phase.startedAt != nil else { return }
        startTimer()
    }

    func dismissCurrentAlert() {
        currentAlert = nil
    }

    // MARK: - Tick loop

    private func startTimer() {
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            // Timer fires on the main run loop; bounce onto MainActor.
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
        // `.common` so the timer keeps ticking while menus / sheets are open
        // — same pattern as the global elapsed clock.
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    private func stopTimer() {
        tickTimer?.invalidate()
        tickTimer = nil
    }

    private func tick() {
        guard let phase = activePhase,
              let target = phase.targetMinutes,
              let startedAt = phase.startedAt else {
            stopTimer()
            return
        }

        let defaults = UserDefaults.standard
        let warn1Minutes = defaults.integer(forKey: PhaseAlertSettings.warn1MinutesKey)
            .nonZeroOrDefault(PhaseAlertSettings.defaultWarn1Minutes)
        let warn2Minutes = defaults.integer(forKey: PhaseAlertSettings.warn2MinutesKey)
            .nonZeroOrDefault(PhaseAlertSettings.defaultWarn2Minutes)
        let elapsed = Date().timeIntervalSince(startedAt)
        let remaining = TimeInterval(target * 60) - elapsed
        let warn1 = TimeInterval(warn1Minutes * 60)
        let warn2 = TimeInterval(warn2Minutes * 60)
        let warn1Kind: AlertKind = .warning(minutesLeft: warn1Minutes)
        let warn2Kind: AlertKind = .warning(minutesLeft: warn2Minutes)

        // Order matters: crossing 1m also crosses 5m. Each threshold fires
        // at most once per phase activation.
        if defaults.boolOrTrue(forKey: PhaseAlertSettings.warn1EnabledKey),
           remaining <= warn1, remaining > warn2, !firedThresholds.contains(warn1Kind) {
            fire(warn1Kind, phaseTitle: phase.title)
        }
        if defaults.boolOrTrue(forKey: PhaseAlertSettings.warn2EnabledKey),
           remaining <= warn2, remaining > 0, !firedThresholds.contains(warn2Kind) {
            fire(warn2Kind, phaseTitle: phase.title)
        }
        if defaults.boolOrTrue(forKey: PhaseAlertSettings.overtimeEnabledKey),
           remaining <= 0, !firedThresholds.contains(.overtime) {
            fire(.overtime, phaseTitle: phase.title)
        }
    }

    private func fire(_ kind: AlertKind, phaseTitle: String) {
        firedThresholds.insert(kind)
        currentAlert = Alert(kind: kind, phaseTitle: phaseTitle, firedAt: .now)

        if UserDefaults.standard.boolOrTrue(forKey: PhaseAlertSettings.soundEnabledKey) {
            playSound(for: kind)
        }
        LogManager.shared.log(logMessage(for: kind, phaseTitle: phaseTitle), category: .ai, level: .info)
    }

    private func playSound(for kind: AlertKind) {
        let defaults = UserDefaults.standard
        guard defaults.boolOrTrue(forKey: PhaseAlertSettings.soundEnabledKey) else { return }
        let name: String
        switch kind {
        case .warning(let minutes) where minutes <= 1:
            name = defaults.string(forKey: PhaseAlertSettings.sound1MinKey) ?? PhaseAlertSettings.defaultSound1Min
        case .warning:
            name = defaults.string(forKey: PhaseAlertSettings.sound5MinKey) ?? PhaseAlertSettings.defaultSound5Min
        case .overtime:
            name = defaults.string(forKey: PhaseAlertSettings.soundOvertimeKey) ?? PhaseAlertSettings.defaultSoundOvertime
        }
        NSSound(named: name)?.play()
    }

    private func logMessage(for kind: AlertKind, phaseTitle: String) -> String {
        switch kind {
        case .warning(let minutes): return "Phase '\(phaseTitle)': \(minutes) minute\(minutes == 1 ? "" : "s") remaining"
        case .overtime:             return "Phase '\(phaseTitle)': time budget exhausted"
        }
    }
}

private extension Int {
    /// Treat the @AppStorage-missing case (Int returns 0) as the supplied default
    /// so first-launch users don't get 0-minute warnings.
    func nonZeroOrDefault(_ fallback: Int) -> Int { self == 0 ? fallback : self }
}

private extension UserDefaults {
    /// @AppStorage Bool defaults are sticky once written but absent on first launch
    /// — treat "not yet set" as `true` for the alert toggles we want on by default.
    func boolOrTrue(forKey key: String) -> Bool {
        object(forKey: key) == nil ? true : bool(forKey: key)
    }
}
