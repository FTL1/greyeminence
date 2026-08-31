import Foundation
import os

/// Session + global display names for the local/mic speaker ("Me").
///
/// The global default lives in UserDefaults (`myDisplayName`) and pre-fills
/// new recordings. A session override applies only to the current recording
/// and does not write UserDefaults unless the user chooses "Save as default".
enum SpeakerNames {
    static let globalMeDisplayNameKey = "myDisplayName"

    /// In-memory override for the current recording. Reset when a session starts.
    /// Lock-protected so mic-buffer helpers can read it off the main actor.
    private static let sessionName = OSAllocatedUnfairLock<String?>(initialState: nil)

    static var sessionMeDisplayName: String? {
        get { sessionName.withLock { $0 } }
        set { sessionName.withLock { $0 = newValue } }
    }

    static var globalMeDisplayName: String? {
        get {
            let trimmed = UserDefaults.standard.string(forKey: globalMeDisplayNameKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (trimmed?.isEmpty == false) ? trimmed : nil
        }
        set {
            let trimmed = newValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if trimmed.isEmpty {
                UserDefaults.standard.removeObject(forKey: globalMeDisplayNameKey)
            } else {
                UserDefaults.standard.set(trimmed, forKey: globalMeDisplayNameKey)
            }
        }
    }

    static func effectiveMeName(session: String?, global: String?) -> String? {
        let sessionTrimmed = session?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !sessionTrimmed.isEmpty { return sessionTrimmed }
        let globalTrimmed = global?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !globalTrimmed.isEmpty { return globalTrimmed }
        return nil
    }

    static var effectiveMeName: String? {
        effectiveMeName(session: sessionMeDisplayName, global: globalMeDisplayName)
    }

    static func resetSession() {
        sessionMeDisplayName = nil
    }

    /// Apply a session name. When `saveAsDefault` is set, also persist globally.
    static func setSessionMeName(_ name: String?, saveAsDefault: Bool) {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        sessionMeDisplayName = trimmed.isEmpty ? nil : trimmed
        if saveAsDefault {
            globalMeDisplayName = sessionMeDisplayName
        }
    }
}
