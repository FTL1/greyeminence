import AVFoundation
import CoreGraphics
import Foundation
import Security
@preconcurrency import ScreenCaptureKit

/// Probe + policy for Screen Recording / system-audio TCC.
/// Settings can show ON for an older copy while this binary is still denied.
enum ScreenCapturePermission {
    struct Report: Sendable {
        var capturedAt: Date
        var bundleID: String
        var bundlePath: String
        var teamID: String?
        var signingSummary: String
        var designatedRequirement: String?
        var cgPreflight: Bool
        var shareableContentOK: Bool
        var shareableContentError: String?
        var excludingDesktopOK: Bool
        var excludingDesktopError: String?
        var micStatus: String
        var requestedThisRun: Bool

        var isEffectivelyGranted: Bool {
            cgPreflight || shareableContentOK || excludingDesktopOK
        }

        var summary: String {
            if isEffectivelyGranted {
                if cgPreflight {
                    return "Screen Recording looks granted (CGPreflight)."
                }
                return "Screen Recording looks granted (ScreenCaptureKit succeeded)."
            }
            return "Screen Recording is not granted to this binary."
        }

        var logText: String {
            var lines: [String] = []
            lines.append("Grey Conseil capture-permissions probe")
            lines.append("time: \(capturedAt.formatted(.iso8601))")
            lines.append("bundleID: \(bundleID)")
            lines.append("bundlePath: \(bundlePath)")
            lines.append("teamID: \(teamID ?? "(none / ad-hoc)")")
            lines.append("signing: \(signingSummary)")
            if let designatedRequirement {
                lines.append("designatedRequirement: \(designatedRequirement)")
            }
            lines.append("CGPreflightScreenCaptureAccess: \(cgPreflight)")
            lines.append("SCShareableContent.current: \(shareableContentOK ? "ok" : (shareableContentError ?? "failed"))")
            lines.append("SCShareableContent.excludingDesktopWindows: \(excludingDesktopOK ? "ok" : (excludingDesktopError ?? "failed"))")
            lines.append("microphone: \(micStatus)")
            lines.append("requestedThisRun: \(requestedThisRun)")
            lines.append("verdict: \(summary)")
            if !isEffectivelyGranted {
                lines.append("note: System Settings can show Grey Conseil as ON for a different copy. Each ad-hoc DMG is a new identity — grant Screen Recording AND System Audio Recording to THIS app, then quit and reopen.")
            } else if !cgPreflight {
                lines.append("note: CGPreflight is false but ScreenCaptureKit worked. Treat as granted; do not show the permission-off banner.")
            }
            return lines.joined(separator: "\n")
        }
    }

    /// Never latch a TCC denial when the OS says this process already has
    /// Screen Recording. Transient SCK failures are common during the prompt.
    static func shouldLatchDenial(
        preflightGranted: Bool,
        consecutiveFailures: Int,
        error: Error
    ) -> Bool {
        if preflightGranted { return false }
        if consecutiveFailures < 2 { return false }
        if isLikelyTCCDenial(error) { return consecutiveFailures >= 2 }
        return consecutiveFailures >= 4
    }

    static func isLikelyTCCDenial(_ error: Error) -> Bool {
        let ns = error as NSError
        let text = [ns.localizedDescription, ns.localizedFailureReason]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
        if text.contains("declin") || text.contains("not grant") || text.contains("tcc")
            || text.contains("permission") || text.contains("not authorized") {
            return true
        }
        // SCStreamError.userDeclined is typically -3801 / 3801.
        if ns.domain.lowercased().contains("screencapture") || ns.domain.lowercased().contains("scstream") {
            if ns.code == -3801 || ns.code == 3801 || ns.code == -3802 || ns.code == 3802 {
                return true
            }
        }
        return false
    }

    @MainActor
    static func probe(requestIfNeeded: Bool) async -> Report {
        let bundle = Bundle.main
        let signing = signingInfo()
        var requested = false
        let preflightBefore = CGPreflightScreenCaptureAccess()
        if requestIfNeeded, !preflightBefore {
            requested = true
            _ = CGRequestScreenCaptureAccess()
        }
        let preflight = CGPreflightScreenCaptureAccess()

        let current = await shareableContentCurrent()
        let excluding = await shareableContentExcludingDesktop()

        let report = Report(
            capturedAt: Date(),
            bundleID: bundle.bundleIdentifier ?? "(unknown)",
            bundlePath: bundle.bundleURL.path,
            teamID: signing.teamID,
            signingSummary: signing.summary,
            designatedRequirement: signing.requirement,
            cgPreflight: preflight,
            shareableContentOK: current.ok,
            shareableContentError: current.error,
            excludingDesktopOK: excluding.ok,
            excludingDesktopError: excluding.error,
            micStatus: micStatusText(),
            requestedThisRun: requested
        )
        LogManager.send(
            report.summary,
            category: .screen,
            level: report.isEffectivelyGranted ? .info : .warning,
            detail: report.logText
        )
        return report
    }

    static func micStatusText() -> String {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: "authorized"
        case .denied: "denied"
        case .restricted: "restricted"
        case .notDetermined: "notDetermined"
        @unknown default: "unknown"
        }
    }

    static func probeSigningSummary() -> String {
        signingInfo().summary
    }

    private static func shareableContentCurrent() async -> (ok: Bool, error: String?) {
        do {
            _ = try await SCShareableContent.current
            return (true, nil)
        } catch {
            return (false, describe(error))
        }
    }

    private static func shareableContentExcludingDesktop() async -> (ok: Bool, error: String?) {
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
            return (true, nil)
        } catch {
            return (false, describe(error))
        }
    }

    private static func describe(_ error: Error) -> String {
        let ns = error as NSError
        return "\(ns.domain) code=\(ns.code) \(ns.localizedDescription)"
    }

    private static func signingInfo() -> (teamID: String?, summary: String, requirement: String?) {
        var code: SecCode?
        guard SecCodeCopySelf(SecCSFlags(), &code) == errSecSuccess, let code else {
            return (nil, "SecCodeCopySelf failed", nil)
        }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, SecCSFlags(), &staticCode) == errSecSuccess,
              let staticCode else {
            return (nil, "SecCodeCopyStaticCode failed", nil)
        }
        var info: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(staticCode, flags, &info) == errSecSuccess,
              let dict = info as? [String: Any] else {
            return (nil, "SecCodeCopySigningInformation failed", nil)
        }
        let team = dict[kSecCodeInfoTeamIdentifier as String] as? String
        let identifier = dict[kSecCodeInfoIdentifier as String] as? String
        let requirement = dict[kSecCodeInfoDesignatedRequirement as String].map { String(describing: $0) }
        let summary: String
        if let team, !team.isEmpty {
            summary = "Developer ID team \(team)" + (identifier.map { " id=\($0)" } ?? "")
        } else {
            summary = "ad-hoc or unsigned" + (identifier.map { " id=\($0)" } ?? "")
        }
        return (team, summary, requirement)
    }
}
