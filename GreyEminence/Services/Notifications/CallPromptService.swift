// @preconcurrency: CI's older SDK lacks Sendable annotations on
// UNNotificationSettings, so awaiting `notificationSettings()` from
// MainActor-isolated code is rejected there but accepted locally. Same
// treatment as ScreenCaptureKit in ScreenShareCaptureService.
@preconcurrency import UserNotifications

/// Asks whether to record a detected call.
///
/// Used for apps that hold the microphone outside of an actual conversation —
/// Discord keeps the input device for as long as you are connected to a voice
/// channel, so starting on our own would record you sitting in an empty
/// channel. Nothing in the Core Audio process flags distinguishes the two
/// cases, so we ask.
///
/// The prompt is a system notification rather than in-app UI because the user
/// is by definition in another app when it fires.
@MainActor
final class CallPromptService: NSObject {
    static let shared = CallPromptService()

    private nonisolated(unsafe) let center = UNUserNotificationCenter.current()

    private let categoryID = "com.greyeminence.call-detected"
    private let notificationID = "com.greyeminence.call-detected.prompt"
    private let startActionID = "START_RECORDING"
    private let ignoreActionID = "IGNORE_CALL"

    /// Invoked on the main actor when the user chooses to record.
    var onStartRequested: (() -> Void)?

    private override init() {
        super.init()
    }

    /// Registers the notification category, takes delegate ownership, and
    /// makes sure we actually hold notification authorization — the prompt is
    /// the only way Discord calls get recorded, so a silent denial would make
    /// the feature look broken.
    func configure() {
        let start = UNNotificationAction(
            identifier: startActionID,
            title: "Start Recording",
            options: [.foreground]
        )
        let ignore = UNNotificationAction(
            identifier: ignoreActionID,
            title: "Not Now",
            options: []
        )
        let category = UNNotificationCategory(
            identifier: categoryID,
            actions: [start, ignore],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
        center.delegate = self

        Task { await ensureAuthorization() }
    }

    /// Requests authorization if it has never been asked for, and reports the
    /// outcome. Returns true when we may post.
    /// Reads only the status, never the settings object itself: the object is
    /// not Sendable on every SDK we build against, and the status is a plain
    /// enum that crosses isolation cleanly.
    private nonisolated func currentAuthorizationStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }

    @discardableResult
    func ensureAuthorization() async -> Bool {
        switch await currentAuthorizationStatus() {
        case .notDetermined:
            let granted = (try? await center.requestAuthorization(
                options: [.alert, .sound]
            )) ?? false
            LogManager.send(
                "Notification authorization \(granted ? "granted" : "denied")",
                category: .audio,
                level: granted ? .info : .warning
            )
            return granted
        case .denied:
            LogManager.send(
                "Notifications are denied for Grey Eminence — call prompts cannot appear. "
                    + "Enable them in System Settings › Notifications.",
                category: .audio,
                level: .warning
            )
            return false
        default:
            return true
        }
    }

    /// Posts the prompt. Replaces any prompt already on screen — there is only
    /// ever one call in question.
    func promptToRecord(appName: String) {
        center.removeDeliveredNotifications(withIdentifiers: [notificationID])

        let content = UNMutableNotificationContent()
        content.title = "\(appName) call detected"
        content.body = "Start recording this call?"
        content.categoryIdentifier = categoryID
        content.sound = .default
        // Deliberately NOT .timeSensitive — that interruption level requires
        // the Time Sensitive Notifications entitlement, and without it the
        // request is rejected outright and the prompt never appears.

        // Delivery failure is logged, not surfaced: the in-app prompt bar is
        // always shown alongside this, so a missing notification degrades the
        // convenience path rather than the feature.
        Task { [weak self] in
            guard let self, await ensureAuthorization() else { return }
            do {
                try await center.add(UNNotificationRequest(
                    identifier: notificationID,
                    content: content,
                    trigger: nil          // deliver immediately
                ))
                LogManager.send("Call prompt posted for \(appName)", category: .audio)
            } catch {
                LogManager.send(
                    "Call prompt could not be posted: \(error.localizedDescription)",
                    category: .audio,
                    level: .warning
                )
            }
        }
    }

    /// Pulls the prompt once it is moot (the call ended, or recording began).
    func dismissPrompt() {
        center.removeDeliveredNotifications(withIdentifiers: [notificationID])
    }
}

extension CallPromptService: UNUserNotificationCenterDelegate {

    /// Show the banner even when Grey Eminence happens to be frontmost.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let action = response.actionIdentifier
        // Tapping the body counts as "yes" — the only affirmative action.
        let wantsRecording = action == startActionID
            || action == UNNotificationDefaultActionIdentifier
        guard wantsRecording else {
            LogManager.send("Call prompt dismissed without recording", category: .audio)
            return
        }
        await MainActor.run {
            LogManager.send("Call prompt accepted — starting recording", category: .audio)
            CallPromptService.shared.onStartRequested?()
        }
    }
}
