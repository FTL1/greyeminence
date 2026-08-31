import AVFoundation
import Contacts
import CoreAudio
import EventKit
import Foundation
import UserNotifications

/// One-shot snapshot of every grant Grey Conseil actually needs: TCC,
/// calendar, Microsoft 365, AI keys, recordings folder, Sparkle feed.
enum PermissionsHealth {
    enum Verdict: String, Sendable {
        case ok
        case denied
        case missing
        case notDetermined
        case warning
        case skipped

        var isProblem: Bool {
            self == .denied || self == .missing
        }

        var label: String {
            switch self {
            case .ok: "ok"
            case .denied: "denied"
            case .missing: "missing"
            case .notDetermined: "not determined"
            case .warning: "warning"
            case .skipped: "skipped"
            }
        }
    }

    struct Item: Identifiable, Sendable {
        let id: String
        let title: String
        let verdict: Verdict
        let detail: String
        /// System Settings privacy pane suffix, e.g. `Privacy_Microphone`.
        let privacyPane: String?
        let canValidate: Bool
    }

    struct Report: Sendable {
        var capturedAt: Date
        var bundleID: String
        var bundlePath: String
        var signing: String
        var items: [Item]
        var identityNote: String

        var problemCount: Int { items.filter { $0.verdict.isProblem }.count }
        var warningCount: Int { items.filter { $0.verdict == .warning || $0.verdict == .notDetermined }.count }
        var okCount: Int { items.filter { $0.verdict == .ok }.count }

        var summary: String {
            if problemCount == 0, warningCount == 0 {
                return "All checked permissions look granted."
            }
            if problemCount == 0 {
                return "\(warningCount) item(s) need attention (not determined or warning)."
            }
            return "\(problemCount) missing/denied, \(warningCount) warning."
        }

        var logText: String {
            var lines: [String] = []
            lines.append("Grey Conseil permissions")
            lines.append("time: \(capturedAt.formatted(.iso8601))")
            lines.append("bundleID: \(bundleID)")
            lines.append("bundlePath: \(bundlePath)")
            lines.append("signing: \(signing)")
            lines.append("verdict: \(summary)")
            for item in items {
                lines.append("- \(item.title): \(item.verdict.label) — \(item.detail)")
            }
            lines.append(identityNote)
            return lines.joined(separator: "\n")
        }
    }

    static func verdict(fromMicrophone status: AVAuthorizationStatus) -> Verdict {
        switch status {
        case .authorized: return .ok
        case .denied, .restricted: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .warning
        }
    }

    static func verdict(fromCalendar status: EKAuthorizationStatus) -> Verdict {
        switch status {
        case .fullAccess, .authorized: return .ok
        case .denied, .restricted, .writeOnly: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .warning
        }
    }

    static func verdict(fromContacts status: CNAuthorizationStatus) -> Verdict {
        switch status {
        case .authorized: return .ok
        case .denied, .restricted: return .denied
        case .notDetermined: return .notDetermined
        default:
            // macOS 15+ limited contacts access (rawValue 4).
            return status.rawValue == 4 ? .ok : .warning
        }
    }

    static func keyItem(id: String, title: String, key: String?) -> Item {
        let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            return Item(
                id: id,
                title: title,
                verdict: .missing,
                detail: "No key in Keychain",
                privacyPane: nil,
                canValidate: false
            )
        }
        let tail = trimmed.suffix(4)
        return Item(
            id: id,
            title: title,
            verdict: .ok,
            detail: "saved (…\(tail))",
            privacyPane: nil,
            canValidate: true
        )
    }

    @MainActor
    static func snapshot(requestCaptureIfNeeded: Bool = false) async -> Report {
        let bundle = Bundle.main
        let signing = ScreenCapturePermission.probeSigningSummary()
        let screen = await ScreenCapturePermission.probe(requestIfNeeded: requestCaptureIfNeeded)

        var items: [Item] = []

        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        items.append(Item(
            id: "microphone",
            title: "Microphone",
            verdict: verdict(fromMicrophone: micStatus),
            detail: ScreenCapturePermission.micStatusText(),
            privacyPane: "Privacy_Microphone",
            canValidate: false
        ))

        items.append(Item(
            id: "screen",
            title: "Screen Recording",
            verdict: screen.isEffectivelyGranted ? .ok : (screen.cgPreflight ? .warning : .denied),
            detail: screen.summary,
            privacyPane: "Privacy_ScreenCapture",
            canValidate: false
        ))

        items.append(probeSystemAudioTap())

        items.append(Item(
            id: "calendar",
            title: "Calendar",
            verdict: verdict(fromCalendar: EKEventStore.authorizationStatus(for: .event)),
            detail: calendarDetail(),
            privacyPane: "Privacy_Calendars",
            canValidate: false
        ))

        items.append(Item(
            id: "contacts",
            title: "Contacts",
            verdict: verdict(fromContacts: CNContactStore.authorizationStatus(for: .contacts)),
            detail: contactsDetail(),
            privacyPane: "Privacy_Contacts",
            canValidate: false
        ))

        items.append(await notificationsItem())
        items.append(microsoft365Item())
        items.append(contentsOf: await activeAIItems())
        items.append(recordingsFolderItem())
        items.append(await updatesFeedItem())

        let identityNote = "Each ad-hoc DMG is a new TCC identity. System Settings can show Grey Conseil ON for an older copy while this binary is denied."

        return Report(
            capturedAt: Date(),
            bundleID: bundle.bundleIdentifier ?? "(unknown)",
            bundlePath: bundle.bundleURL.path,
            signing: signing,
            items: items,
            identityNote: identityNote
        )
    }

    @MainActor
    static func requestMissing() async {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        }
        if EKEventStore.authorizationStatus(for: .event) == .notDetermined {
            _ = try? await EKEventStore().requestFullAccessToEvents()
        }
        if CNContactStore.authorizationStatus(for: .contacts) == .notDetermined {
            _ = try? await CNContactStore().requestAccess(for: .contacts)
        }
        if await notificationStatusRaw() == UNAuthorizationStatus.notDetermined.rawValue {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        }
        _ = await ScreenCapturePermission.probe(requestIfNeeded: true)
    }

    static func validateStoredKeys() async -> [String: String] {
        switch AIProvider.current() {
        case .xai:
            guard let key = try? KeychainHelper.get(AIPromptTemplates.xaiKeychainKey),
                  !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return ["xai": "failed: no key in Keychain"]
            }
            return ["xai": await pingXAI(apiKey: key)]
        case .anthropic:
            guard let key = try? KeychainHelper.get(AIPromptTemplates.keychainKey),
                  !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return ["anthropic": "failed: no key in Keychain"]
            }
            return ["anthropic": await pingAnthropic(apiKey: key)]
        case .bedrock:
            return [:]
        }
    }

    /// Only the provider selected in Settings → AI. Unused keys (Anthropic
    /// when Grok is active, etc.) are not missing — they are not required.
    static func activeAIItems(
        current: AIProvider,
        anthropicKey: String?,
        xaiKey: String?
    ) -> [Item] {
        switch current {
        case .xai:
            return [keyItem(id: "xai", title: "xAI (Grok)", key: xaiKey)]
        case .anthropic:
            return [keyItem(id: "anthropic", title: "Anthropic API", key: anthropicKey)]
        case .bedrock:
            return []
        }
    }

    private static func activeAIItems() async -> [Item] {
        let current = AIProvider.current()
        var items = activeAIItems(
            current: current,
            anthropicKey: try? KeychainHelper.get(AIPromptTemplates.keychainKey),
            xaiKey: try? KeychainHelper.get(AIPromptTemplates.xaiKeychainKey)
        )
        if current == .bedrock {
            items.append(await bedrockItem())
        }
        return items
    }

    private static func pingAnthropic(apiKey: String) async -> String {
        do {
            let model = UserDefaults.standard.string(forKey: "claudeModel") ?? AIClientFactory.defaultClaudeModel
            let client = ClaudeAPIClient(apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines), model: model)
            _ = try await client.sendMessage(system: "Reply with exactly: OK", userContent: "Reply OK", maxTokens: 16)
            return "valid (\(model))"
        } catch {
            return "failed: \(error.localizedDescription)"
        }
    }

    private static func pingXAI(apiKey: String) async -> String {
        do {
            let model = AIClientFactory.selectedModel(for: .xai)
            let client = XAIAPIClient(apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines), model: model)
            _ = try await client.sendMessage(system: "Reply with exactly: OK", userContent: "Reply OK", maxTokens: 16)
            return "valid (\(model))"
        } catch {
            return "failed: \(error.localizedDescription)"
        }
    }

    private static func calendarDetail() -> String {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .authorized: "full access"
        case .writeOnly: "write-only — Grey Conseil needs full access"
        case .denied: "denied"
        case .restricted: "restricted"
        case .notDetermined: "not determined"
        @unknown default: "unknown"
        }
    }

    private static func contactsDetail() -> String {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized: "authorized"
        case .denied: "denied"
        case .restricted: "restricted"
        case .notDetermined: "not determined"
        default:
            CNContactStore.authorizationStatus(for: .contacts).rawValue == 4 ? "limited" : "unknown"
        }
    }

    /// `UNNotificationSettings` is not Sendable. Copy the status code only.
    private static func notificationStatusRaw() async -> Int {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus.rawValue)
            }
        }
    }

    private static func notificationsItem() async -> Item {
        let raw = await notificationStatusRaw()
        let verdict: Verdict
        let detail: String
        switch UNAuthorizationStatus(rawValue: raw) {
        case .authorized, .provisional, .ephemeral:
            verdict = .ok
            detail = "authorized"
        case .denied:
            verdict = .denied
            detail = "denied"
        case .notDetermined:
            verdict = .notDetermined
            detail = "not determined"
        default:
            verdict = .warning
            detail = "unknown"
        }
        return Item(
            id: "notifications",
            title: "Notifications",
            verdict: verdict,
            detail: detail,
            privacyPane: "Privacy_Notifications",
            canValidate: false
        )
    }

    @MainActor
    private static func microsoft365Item() -> Item {
        let graph = GraphAuthService.shared
        if !GraphConfig.isConfigured {
            return Item(
                id: "microsoft365",
                title: "Microsoft 365",
                verdict: .missing,
                detail: "No client ID — paste one in Settings → Calendar, then Connect",
                privacyPane: nil,
                canValidate: false
            )
        }
        if graph.needsReconnect {
            return Item(
                id: "microsoft365",
                title: "Microsoft 365",
                verdict: .warning,
                detail: graph.lastError ?? "reconnect needed",
                privacyPane: nil,
                canValidate: false
            )
        }
        if graph.isConnected {
            return Item(
                id: "microsoft365",
                title: "Microsoft 365",
                verdict: .ok,
                detail: graph.connectedEmail ?? "connected",
                privacyPane: nil,
                canValidate: false
            )
        }
        return Item(
            id: "microsoft365",
            title: "Microsoft 365",
            verdict: .skipped,
            detail: "not connected (optional)",
            privacyPane: nil,
            canValidate: false
        )
    }

    private static func bedrockItem() async -> Item {
        let provider = AIProvider.current()
        guard provider == .bedrock else {
            return Item(
                id: "bedrock",
                title: "AWS Bedrock",
                verdict: .skipped,
                detail: "current AI provider is \(provider.displayName)",
                privacyPane: nil,
                canValidate: false
            )
        }
        do {
            let profile = UserDefaults.standard.string(forKey: "awsProfile") ?? "default"
            AWSCredentialLoader.restoreAccess()
            _ = try await AWSCredentialLoader.loadCredentials(profile: profile)
            return Item(
                id: "bedrock",
                title: "AWS Bedrock",
                verdict: .ok,
                detail: "credentials loaded (\(profile))",
                privacyPane: nil,
                canValidate: false
            )
        } catch {
            return Item(
                id: "bedrock",
                title: "AWS Bedrock",
                verdict: .missing,
                detail: error.localizedDescription,
                privacyPane: nil,
                canValidate: false
            )
        }
    }

    private static func recordingsFolderItem() -> Item {
        let url = StorageManager.shared.recordingsURL
        let probe = url.appendingPathComponent(".permissions-probe-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try Data("ok".utf8).write(to: probe, options: .atomic)
            try FileManager.default.removeItem(at: probe)
            return Item(
                id: "recordings",
                title: "Recordings folder",
                verdict: .ok,
                detail: url.path,
                privacyPane: nil,
                canValidate: false
            )
        } catch {
            return Item(
                id: "recordings",
                title: "Recordings folder",
                verdict: .denied,
                detail: error.localizedDescription,
                privacyPane: nil,
                canValidate: false
            )
        }
    }

    private static func updatesFeedItem() async -> Item {
        let feed = AppIdentity.updatesFeedURL
        guard let url = URL(string: feed) else {
            return Item(
                id: "updates",
                title: "Check for Updates feed",
                verdict: .missing,
                detail: "invalid URL",
                privacyPane: nil,
                canValidate: false
            )
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let http = response as? HTTPURLResponse
            let code = http?.statusCode ?? 0
            if (200..<400).contains(code) {
                return Item(
                    id: "updates",
                    title: "Check for Updates feed",
                    verdict: .ok,
                    detail: "HTTP \(code) \(feed)",
                    privacyPane: nil,
                    canValidate: false
                )
            }
            return Item(
                id: "updates",
                title: "Check for Updates feed",
                verdict: .missing,
                detail: "HTTP \(code) \(feed)",
                privacyPane: nil,
                canValidate: false
            )
        } catch {
            return Item(
                id: "updates",
                title: "Check for Updates feed",
                verdict: .warning,
                detail: error.localizedDescription,
                privacyPane: nil,
                canValidate: false
            )
        }
    }

    /// Creating a process tap is the only public check for System Audio TCC.
    /// Skip while a recording owns the mic so we don't glitch capture.
    /// On Sequoia/Tahoe this is the same Settings pane as Screen Recording.
    static func probeSystemAudioTap() -> Item {
        if MicCaptureGate.isActive {
            return Item(
                id: "systemAudio",
                title: "System Audio",
                verdict: .skipped,
                detail: "not probed while a recording is using the mic",
                privacyPane: "Privacy_AudioCapture",
                canValidate: false
            )
        }
        let desc = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        desc.uuid = UUID()
        desc.name = "GreyConseil Permissions Probe"
        desc.isPrivate = true
        var tapID: AudioObjectID = kAudioObjectUnknown
        let status = AudioHardwareCreateProcessTap(desc, &tapID)
        if tapID != kAudioObjectUnknown {
            _ = AudioHardwareDestroyProcessTap(tapID)
        }
        if status == noErr {
            return Item(
                id: "systemAudio",
                title: "System Audio",
                verdict: .ok,
                detail: "process tap created",
                privacyPane: "Privacy_AudioCapture",
                canValidate: false
            )
        }
        return Item(
            id: "systemAudio",
            title: "System Audio",
            verdict: .denied,
            detail: "AudioHardwareCreateProcessTap status \(status) — grant System Audio Recording for this binary",
            privacyPane: "Privacy_AudioCapture",
            canValidate: false
        )
    }
}
