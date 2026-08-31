import Foundation
import os.log
import AppKit
import UniformTypeIdentifiers

struct LogEntry: Identifiable {
    let id = UUID()
    let timestamp = Date()
    let category: Category
    let level: Level
    let message: String
    let detail: String?

    enum Category: String, CaseIterable, Identifiable {
        case audio
        case transcription
        case ai
        case screen
        case obsidian
        case update
        case general
        case ui

        var id: String { rawValue }
    }

    enum Level: String, CaseIterable, Identifiable {
        case debug
        case info
        case warning
        case error

        var id: String { rawValue }
    }
}

@Observable
@MainActor
final class LogManager {
    static let shared = LogManager()

    private(set) var entries: [LogEntry] = []
    private var maxEntries: Int { DevLog.isEnabled ? 8_000 : 1_000 }



    private static let osLog = OSLog(subsystem: "com.greyeminence.app", category: "GreyEminence")
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    private let systemLogURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent(AppIdentity.dataFolderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("system.log")
    }()

    private init() {}

    func log(
        _ message: String,
        category: LogEntry.Category = .general,
        level: LogEntry.Level = .info,
        detail: String? = nil,
        meetingID: UUID? = nil
    ) {
        let entry = LogEntry(category: category, level: level, message: message, detail: detail)
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }

        if level == .debug, !DevLog.isEnabled { return }

        let osType: OSLogType = level == .error ? .error : level == .warning ? .default : .info
        os_log("%{public}s [%{public}s] %{public}s", log: LogManager.osLog, type: osType, category.rawValue, level.rawValue, message)

        let line = formatLine(message: message, category: category, level: level, detail: detail)
        if let meetingID {
            appendToMeetingLog(meetingID: meetingID, line: line)
        }
        appendToFile(url: systemLogURL, line: line)
    }

    /// Nonisolated entry point for actor-isolated callers.
    nonisolated static func send(
        _ message: String,
        category: LogEntry.Category = .general,
        level: LogEntry.Level = .info,
        detail: String? = nil,
        meetingID: UUID? = nil
    ) {
        Task { @MainActor in
            LogManager.shared.log(message, category: category, level: level, detail: detail, meetingID: meetingID)
        }
    }

    func clear() {
        entries.removeAll()
    }

    // MARK: - Private

    private func formatLine(message: String, category: LogEntry.Category, level: LogEntry.Level, detail: String?) -> String {
        let ts = LogManager.dateFormatter.string(from: Date())
        var line = "[\(ts)] [\(category.rawValue)] [\(level.rawValue)] \(message)"
        if let detail { line += "\n  \(detail)" }
        return line + "\n"
    }

    private func appendToMeetingLog(meetingID: UUID, line: String) {
        let base = StorageManager.shared.recordingDirectory(for: meetingID)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let url = base.appendingPathComponent("meeting.log")
        appendToFile(url: url, line: line)
    }

    private func appendToFile(url: URL, line: String) {
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: url.path) {
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            }
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }

    func exportJSON() throws -> URL {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let payload: [String: Any] = [
            "exportedAt": iso.string(from: Date()),
            "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?",
            "build": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?",
            "bundleID": AppIdentity.bundleID,
            "devMode": DevLog.isEnabled,
            "entries": entries.map { entry -> [String: Any] in
                var row: [String: Any] = [
                    "timestamp": iso.string(from: entry.timestamp),
                    "category": entry.category.rawValue,
                    "level": entry.level.rawValue,
                    "message": entry.message,
                ]
                if let detail = entry.detail { row["detail"] = detail }
                return row
            },
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("GreyConseil-devlog-\(stamp).json")
        try data.write(to: url, options: .atomic)
        return url
    }
}

enum DevLog {
    static let verboseDefaultsKey = "devModeVerboseLogging"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: verboseDefaultsKey)
    }

    static func ui(_ message: String, detail: String? = nil, level: LogEntry.Level = .debug) {
        guard isEnabled || level != .debug else { return }
        LogManager.send(message, category: .ui, level: level, detail: detail)
    }
}

enum DevLogExporter {
    @MainActor
    static func presentSavePanel() throws {
        let temp = try LogManager.shared.exportJSON()
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = temp.lastPathComponent
        panel.allowedContentTypes = [.json]
        panel.title = "Export Grey Conseil debug log"
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: temp, to: dest)
        NSWorkspace.shared.activateFileViewerSelecting([dest])
    }
}
