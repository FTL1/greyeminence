import Foundation
import SwiftUI
import AppKit

/// Per-phase time-box tracking and alerting for the live interview view.
///
/// Watches the active phase's `targetMinutes` against wall-clock elapsed
/// since `startedAt`, fires one-shot alerts when the configured thresholds
/// are crossed (defaults: 5 min before, 1 min before, overtime), and
/// exposes a `currentAlert` the live view renders as a banner.
///
/// Thresholds reset every time a new phase activates — switching phases
/// gives the interviewer a fresh budget. Phases with no `targetMinutes`
/// (intro, unscored discussion) silently no-op.
@Observable
@MainActor
final class PhaseTimerService {
    /// The kind of threshold that fired. `.warning` minutes is the lead
    /// time (5 = "5 minutes left"); `.overtime` is the single moment the
    /// budget hit zero.
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

    /// Last alert that fired for the current phase. The live view shows a
    /// banner while this is non-nil; clearing dismisses the banner.
    private(set) var currentAlert: Alert?

    private weak var activePhase: InterviewPhase?
    private var firedThresholds: Set<AlertKind> = []
    private var tickTimer: Timer?

    /// Bind the service to a new active phase. Pass `nil` when the
    /// interview ends or an unscored phase activates — the service stops
    /// ticking and clears any visible alert.
    func bind(to phase: InterviewPhase?) {
        // Same phase rebinding (e.g. re-render) is a no-op so we don't
        // wipe alert state mid-flight.
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

        let elapsed = Date().timeIntervalSince(startedAt)
        let targetSeconds = TimeInterval(target * 60)
        let remaining = targetSeconds - elapsed

        let warn1 = TimeInterval(UserDefaults.standard.integer(forKey: "phaseAlertWarn1Minutes")
            .nonZeroOrDefault(5) * 60)
        let warn2 = TimeInterval(UserDefaults.standard.integer(forKey: "phaseAlertWarn2Minutes")
            .nonZeroOrDefault(1) * 60)

        let warn1Enabled = UserDefaults.standard.boolOrTrue(forKey: "phaseAlert5MinEnabled")
        let warn2Enabled = UserDefaults.standard.boolOrTrue(forKey: "phaseAlert1MinEnabled")
        let overtimeEnabled = UserDefaults.standard.boolOrTrue(forKey: "phaseAlertOvertimeEnabled")

        // Order matters: crossing 1m also crosses 5m, but we fire each
        // threshold at most once, and only when remaining drops past it.
        let warn1Kind: AlertKind = .warning(minutesLeft: UserDefaults.standard.integer(forKey: "phaseAlertWarn1Minutes").nonZeroOrDefault(5))
        let warn2Kind: AlertKind = .warning(minutesLeft: UserDefaults.standard.integer(forKey: "phaseAlertWarn2Minutes").nonZeroOrDefault(1))

        if warn1Enabled, remaining <= warn1, remaining > warn2, !firedThresholds.contains(warn1Kind) {
            fire(warn1Kind, phaseTitle: phase.title)
        }
        if warn2Enabled, remaining <= warn2, remaining > 0, !firedThresholds.contains(warn2Kind) {
            fire(warn2Kind, phaseTitle: phase.title)
        }
        if overtimeEnabled, remaining <= 0, !firedThresholds.contains(.overtime) {
            fire(.overtime, phaseTitle: phase.title)
        }
    }

    private func fire(_ kind: AlertKind, phaseTitle: String) {
        firedThresholds.insert(kind)
        currentAlert = Alert(kind: kind, phaseTitle: phaseTitle, firedAt: .now)

        if UserDefaults.standard.boolOrTrue(forKey: "phaseAlertSoundEnabled") {
            playSound(for: kind)
        }
        LogManager.shared.log(logMessage(for: kind, phaseTitle: phaseTitle), category: .ai, level: .info)
    }

    private func playSound(for kind: AlertKind) {
        let name: String
        switch kind {
        case .warning(let minutes) where minutes <= 1: name = "Hero"
        case .warning:                                 name = "Tink"
        case .overtime:                                name = "Funk"
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
