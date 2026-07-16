import Foundation

/// UserDefaults keys + defaults for screen-share capture. Namespace type,
/// same pattern as `PhaseAlertSettings`.
enum ScreenShareSettings {
    /// Master switch. Off by default — first capture triggers the macOS
    /// Screen Recording permission prompt, so this is a deliberate opt-in.
    static let enabledKey = "screenShareCaptureEnabled"
    static let intervalSecondsKey = "screenShareCaptureInterval"
    static let autoDetectKey = "screenShareAutoDetectWindow"
    static let analysisEnabledKey = "screenShareVisionAnalysis"
    static let maxAnalyzedFramesKey = "screenShareMaxAnalyzedFrames"
    static let maxKeptFramesKey = "screenShareMaxKeptFrames"
    /// dHash Hamming-distance keep threshold (developer setting).
    static let changeThresholdKey = "screenShareChangeThreshold"

    static let defaultIntervalSeconds = 15.0
    static let defaultMaxAnalyzedFrames = 60
    static let defaultMaxKeptFrames = 400
    static let defaultChangeThreshold = 8

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    static var autoDetect: Bool {
        UserDefaults.standard.object(forKey: autoDetectKey) as? Bool ?? true
    }

    static var analysisEnabled: Bool {
        UserDefaults.standard.object(forKey: analysisEnabledKey) as? Bool ?? true
    }

    static var intervalSeconds: Double {
        let v = UserDefaults.standard.double(forKey: intervalSecondsKey)
        return v > 0 ? min(max(v, 5), 120) : defaultIntervalSeconds
    }

    static var maxAnalyzedFrames: Int {
        let v = UserDefaults.standard.integer(forKey: maxAnalyzedFramesKey)
        return v > 0 ? v : defaultMaxAnalyzedFrames
    }

    static var maxKeptFrames: Int {
        let v = UserDefaults.standard.integer(forKey: maxKeptFramesKey)
        return v > 0 ? v : defaultMaxKeptFrames
    }

    static var changeThreshold: Int {
        let v = UserDefaults.standard.integer(forKey: changeThresholdKey)
        return v > 0 ? min(max(v, 1), 32) : defaultChangeThreshold
    }
}
