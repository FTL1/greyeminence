import AppKit
import Foundation
import PDFKit
import UniformTypeIdentifiers

/// How Archive / Meetings export is packaged. Zip keeps markdown plus optional
/// media. PDF is transcripts and intel only — audio and stills stay in Zip.
enum ArchiveExportPackage: String, CaseIterable, Identifiable, Sendable {
    case zip
    case combinedPDF
    case pdfsPerMeeting

    var id: String { rawValue }

    var menuTitle: String {
        switch self {
        case .zip: "Zip (markdown + optional media)"
        case .combinedPDF: "One PDF (page break per meeting)"
        case .pdfsPerMeeting: "One PDF per meeting"
        }
    }

    var isPDF: Bool {
        self != .zip
    }
}

/// What Archive / Meetings export includes. Transcript and intel are on by
/// default; audio, stills, and a screen-share time-lapse are Zip-only.
struct ArchiveExtractRequest: Equatable, Sendable {
    var scope: ArchiveExtractScope = .selected
    var speaker: String? = nil
    var splitBySpeaker = false
    var package: ArchiveExportPackage = .zip
    var includeTranscript = true
    var includeIntel = true
    var includeAudio = false
    var includeScreenshots = false
    var includeVideo = false

    var includesAnything: Bool {
        if package.isPDF {
            return includeTranscript || includeIntel
        }
        return includeTranscript || includeIntel || includeAudio || includeScreenshots || includeVideo
    }

    var audience: DossierAudience {
        if let speaker, !speaker.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .person(speaker)
        }
        return .general
    }
}

enum ArchiveExtractScope: String, CaseIterable, Identifiable, Sendable {
    case thisMeeting
    case thisSeries
    case thisGroup
    case selected
    case allVisible

    var id: String { rawValue }

    var menuTitle: String {
        switch self {
        case .thisMeeting: "This meeting"
        case .thisSeries: "This series"
        case .thisGroup: "This group"
        case .selected: "Selected meetings"
        case .allVisible: "All visible"
        }
    }
}

/// IDs only so Archive and Meetings can open the same sheet without passing
/// live model objects through the view tree.
struct ArchiveExtractLaunch: Identifiable, Equatable {
    let id: UUID
    var initialScope: ArchiveExtractScope
    var seriesLabel: String?
    var seedMeetingID: UUID?
    var selectedIDs: Set<UUID>
    var visibleIDs: Set<UUID>
    var groupMeetingIDs: Set<UUID>
    var initialSpeaker: String?

    init(
        initialScope: ArchiveExtractScope,
        seriesLabel: String? = nil,
        seedMeetingID: UUID? = nil,
        selectedIDs: Set<UUID>,
        visibleIDs: Set<UUID>,
        groupMeetingIDs: Set<UUID> = [],
        initialSpeaker: String? = nil
    ) {
        self.id = UUID()
        self.initialScope = initialScope
        self.seriesLabel = seriesLabel
        self.seedMeetingID = seedMeetingID
        self.selectedIDs = selectedIDs
        self.visibleIDs = visibleIDs
        self.groupMeetingIDs = groupMeetingIDs
        self.initialSpeaker = initialSpeaker
    }
}

enum ArchiveExtractPlanner {
    /// Recurring series / related-name family includes meetings that are still
    /// on the recent list, not only the Archive rows currently on screen.
    @MainActor
    static func resolveMeetings(
        scope: ArchiveExtractScope,
        seed: Meeting?,
        selected: [Meeting],
        visible: [Meeting],
        group: [Meeting],
        library: [Meeting]
    ) -> [Meeting] {
        let pool = library.filter { !$0.isInterviewMeeting }
        switch scope {
        case .thisMeeting:
            return seed.map { [$0] } ?? []
        case .selected:
            return selected.filter { !$0.isInterviewMeeting }.sorted { $0.date < $1.date }
        case .allVisible:
            return visible.filter { !$0.isInterviewMeeting }.sorted { $0.date < $1.date }
        case .thisGroup:
            return group.filter { !$0.isInterviewMeeting }.sorted { $0.date < $1.date }
        case .thisSeries:
            if let seed {
                return uniqued(DossierFacts.relatedMeetings(to: seed, library: pool) + group)
            }
            if let first = group.first {
                return uniqued(DossierFacts.relatedMeetings(to: first, library: pool) + group)
            }
            return []
        }
    }

    static func uniqueSpeakers(in snapshots: [DossierMeetingSnapshot]) -> [String] {
        var names: [String] = []
        for snap in snapshots {
            for speaker in snap.speakers where !names.contains(where: { DossierNaming.namesMatch($0, speaker) }) {
                names.append(speaker)
            }
        }
        return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    static func meetingFolderName(
        title: String,
        date: Date,
        id: UUID,
        used: inout Set<String>
    ) -> String {
        let calendar = Calendar.current
        let day = String(
            format: "%04d-%02d-%02d",
            calendar.component(.year, from: date),
            calendar.component(.month, from: date),
            calendar.component(.day, from: date)
        )
        var base = "\(day)-\(DossierNaming.slug(title))"
        if base.hasSuffix("-") { base += "meeting" }
        var name = base
        if used.contains(name) {
            name = "\(base)-\(id.uuidString.prefix(8).lowercased())"
        }
        used.insert(name)
        return name
    }

    static func suggestedFilename(
        snapshots: [DossierMeetingSnapshot],
        request: ArchiveExtractRequest,
        seriesLabel: String?
    ) -> String {
        let title: String
        if let speaker = request.speaker?.trimmingCharacters(in: .whitespacesAndNewlines), !speaker.isEmpty {
            title = speaker
        } else if let seriesLabel, !seriesLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            title = seriesLabel
        } else if snapshots.count == 1 {
            title = snapshots[0].title
        } else {
            title = "\(snapshots.count) meetings"
        }
        let date = snapshots.map(\.date).min() ?? .now
        let minutes = max(1, snapshots.map(\.durationMinutes).reduce(0, +))
        switch request.package {
        case .zip:
            return ReportExportService.exportFilename(
                title: title,
                date: date,
                minutes: minutes,
                kind: "export",
                fileExtension: "zip"
            )
        case .combinedPDF:
            return ReportExportService.exportFilename(
                title: title,
                date: date,
                minutes: minutes,
                kind: "export",
                fileExtension: "pdf"
            )
        case .pdfsPerMeeting:
            return DossierNaming.slug(title)
        }
    }

    /// Combined + per-meeting (and optional per-speaker) markdown. No media.
    static func textFiles(
        snapshots: [DossierMeetingSnapshot],
        request: ArchiveExtractRequest,
        seriesLabel: String?
    ) -> [(String, String)] {
        guard !snapshots.isEmpty else { return [] }
        let audience = request.audience
        var files: [(String, String)] = []
        files.append(("README.txt", readme(snapshots: snapshots, request: request, seriesLabel: seriesLabel)))
        files.append(("index.md", indexMarkdown(snapshots: snapshots, request: request, seriesLabel: seriesLabel)))

        if snapshots.count > 1 {
            if request.includeTranscript {
                let combined = combinedTranscript(snapshots: snapshots, audience: audience)
                if !combined.isEmpty {
                    files.append(("transcript.md", combined))
                }
            }
            if request.includeIntel {
                files.append(("intel.md", intelMarkdown(snapshots: snapshots, audience: audience)))
            }
        }

        var usedFolders: Set<String> = []
        for snap in snapshots {
            let folder = meetingFolderName(title: snap.title, date: snap.date, id: snap.id, used: &usedFolders)
            if request.includeTranscript {
                let lines = DossierFacts.filterTranscript(snap.transcript, audience: audience, myLabels: snap.myLabels)
                if !lines.isEmpty {
                    files.append((
                        "meetings/\(folder)/transcript.md",
                        TranscriptExportService.markdown(
                            title: snap.title,
                            date: snap.date,
                            durationLabel: snap.durationLabel,
                            lines: lines.map {
                                TranscriptExportLine(timestamp: $0.timestamp, speaker: $0.speaker, text: $0.text)
                            }
                        )
                    ))
                }
            }
            if request.includeIntel {
                files.append((
                    "meetings/\(folder)/intel.md",
                    intelMarkdown(snapshots: [snap], audience: audience)
                ))
            }
        }

        if request.splitBySpeaker, request.speaker == nil {
            for name in uniqueSpeakers(in: snapshots) {
                let person = DossierAudience.person(name)
                let slug = DossierNaming.slug(name)
                if request.includeTranscript {
                    let combined = combinedTranscript(snapshots: snapshots, audience: person)
                    if !combined.isEmpty {
                        files.append(("speakers/\(slug)/transcript.md", combined))
                    }
                }
                if request.includeIntel {
                    files.append(("speakers/\(slug)/intel.md", intelMarkdown(snapshots: snapshots, audience: person)))
                }
            }
        }

        return files
    }

    private static func combinedTranscript(
        snapshots: [DossierMeetingSnapshot],
        audience: DossierAudience
    ) -> String {
        var parts: [String] = []
        for snap in snapshots {
            let lines = DossierFacts.filterTranscript(snap.transcript, audience: audience, myLabels: snap.myLabels)
            guard !lines.isEmpty else { continue }
            parts.append(
                TranscriptExportService.markdown(
                    title: snap.title,
                    date: snap.date,
                    durationLabel: snap.durationLabel,
                    lines: lines.map {
                        TranscriptExportLine(timestamp: $0.timestamp, speaker: $0.speaker, text: $0.text)
                    }
                )
            )
        }
        return parts.joined(separator: "\n---\n\n")
    }

    private static func intelMarkdown(
        snapshots: [DossierMeetingSnapshot],
        audience: DossierAudience
    ) -> String {
        let blocks = DossierRenderer.blocks(
            snapshots: snapshots,
            audience: audience,
            depth: .detailed,
            includeTranscript: false
        )
        return DossierRenderer.markdown(blocks)
    }

    private static func indexMarkdown(
        snapshots: [DossierMeetingSnapshot],
        request: ArchiveExtractRequest,
        seriesLabel: String?
    ) -> String {
        var body = "# Archive export\n\n"
        if let seriesLabel, !seriesLabel.isEmpty {
            body += "**Series:** \(seriesLabel)\n\n"
        }
        body += "**Meetings:** \(snapshots.count)\n"
        body += "**Speaker:** \(request.audience.displayName)\n"
        var bits: [String] = []
        if request.includeTranscript { bits.append("transcript") }
        if request.includeIntel { bits.append("intel") }
        if request.includeAudio { bits.append("audio") }
        if request.includeScreenshots { bits.append("screen stills") }
        if request.includeVideo { bits.append("screen time-lapse") }
        body += "**Includes:** \(bits.isEmpty ? "nothing" : bits.joined(separator: ", "))\n\n"
        for snap in snapshots {
            body += "- \(snap.date.formatted(date: .abbreviated, time: .shortened)) — \(snap.title) (\(snap.durationLabel))\n"
        }
        return body + "\n"
    }

    private static func readme(
        snapshots: [DossierMeetingSnapshot],
        request: ArchiveExtractRequest,
        seriesLabel: String?
    ) -> String {
        var lines: [String] = [
            "\(AppIdentity.displayName) archive export",
            "Meetings: \(snapshots.count)",
            "Speaker: \(request.audience.displayName)",
        ]
        if let seriesLabel, !seriesLabel.isEmpty {
            lines.append("Series: \(seriesLabel)")
        }
        lines.append(contentsOf: [
            "",
            "This package copies stored transcripts and meeting intelligence. It does not invent facts.",
            "There is no camera movie of the call. video/screens.mp4 is a time-lapse of captured screen-share stills when that box was ticked.",
            "Audio for one speaker concatenates that person's time ranges — other voices can still be heard when they overlapped.",
            "",
        ])
        for snap in snapshots {
            lines.append("- \(snap.title)  (\(snap.date.formatted(date: .abbreviated, time: .shortened)), \(snap.durationLabel))")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    @MainActor
    private static func uniqued(_ meetings: [Meeting]) -> [Meeting] {
        var seen: Set<UUID> = []
        var result: [Meeting] = []
        for meeting in meetings.sorted(by: { $0.date < $1.date }) {
            if seen.insert(meeting.id).inserted {
                result.append(meeting)
            }
        }
        return result
    }
}

enum ArchiveExtractWriter {
    enum Failure: LocalizedError, Sendable {
        case nothingToExport
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case .nothingToExport: "Nothing is selected to export."
            case .writeFailed(let message): message
            }
        }
    }

    @MainActor
    static func export(
        meetings: [Meeting],
        request: ArchiveExtractRequest,
        seriesLabel: String?
    ) async throws -> URL? {
        let sorted = meetings.filter { !$0.isInterviewMeeting }.sorted { $0.date < $1.date }
        guard !sorted.isEmpty else { throw Failure.nothingToExport }
        guard request.includesAnything else { throw Failure.nothingToExport }

        let snapshots = sorted.map { DossierFacts.snapshot(meeting: $0) }
        switch request.package {
        case .zip:
            return try await exportZip(
                meetings: sorted,
                snapshots: snapshots,
                request: request,
                seriesLabel: seriesLabel
            )
        case .combinedPDF:
            return try await ArchiveExtractPDF.writeCombined(
                meetings: sorted,
                snapshots: snapshots,
                request: request,
                seriesLabel: seriesLabel
            )
        case .pdfsPerMeeting:
            if sorted.count == 1 {
                return try await ArchiveExtractPDF.writeCombined(
                    meetings: sorted,
                    snapshots: snapshots,
                    request: request,
                    seriesLabel: seriesLabel
                )
            }
            return try await ArchiveExtractPDF.writePerMeeting(
                meetings: sorted,
                snapshots: snapshots,
                request: request
            )
        }
    }

    @MainActor
    private static func exportZip(
        meetings: [Meeting],
        snapshots: [DossierMeetingSnapshot],
        request: ArchiveExtractRequest,
        seriesLabel: String?
    ) async throws -> URL? {
        let suggested = ArchiveExtractPlanner.suggestedFilename(
            snapshots: snapshots,
            request: request,
            seriesLabel: seriesLabel
        )
        guard let destination = savePanelURL(
            suggestedName: suggested,
            title: "Export transcripts and intel",
            contentTypes: [.zip]
        ) else { return nil }

        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("archive-export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        try await writePackage(
            meetings: meetings,
            snapshots: snapshots,
            request: request,
            seriesLabel: seriesLabel,
            into: temp
        )
        let folderPath = temp.path
        let destPath = destination.path
        try await Task.detached {
            try zipFolder(at: folderPath, to: destPath)
        }.value
        LogManager.send(
            "Exported \(meetings.count) meeting(s) to \(destination.lastPathComponent)",
            category: .general,
            meetingID: meetings.first?.id
        )
        return destination
    }

    @MainActor
    static func writePackage(
        meetings: [Meeting],
        snapshots: [DossierMeetingSnapshot],
        request: ArchiveExtractRequest,
        seriesLabel: String?,
        into root: URL
    ) async throws {
        let files = ArchiveExtractPlanner.textFiles(
            snapshots: snapshots,
            request: request,
            seriesLabel: seriesLabel
        )
        for (relative, text) in files {
            let url = root.appendingPathComponent(relative)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try text.write(to: url, atomically: true, encoding: .utf8)
        }

        var usedFolders: Set<String> = []
        for (index, meeting) in meetings.enumerated() {
            let snap = snapshots[index]
            let folder = ArchiveExtractPlanner.meetingFolderName(
                title: snap.title,
                date: snap.date,
                id: snap.id,
                used: &usedFolders
            )
            let meetingRoot = root.appendingPathComponent("meetings/\(folder)", isDirectory: true)
            try FileManager.default.createDirectory(at: meetingRoot, withIntermediateDirectories: true)

            if request.includeScreenshots {
                copyScreenshots(meeting: meeting, into: meetingRoot.appendingPathComponent("screens", isDirectory: true))
            }
            if request.includeAudio {
                try await copyAudio(meeting: meeting, request: request, into: meetingRoot.appendingPathComponent("audio", isDirectory: true))
            }
            if request.includeVideo {
                await copyVideo(meeting: meeting, into: meetingRoot.appendingPathComponent("video", isDirectory: true))
            }
        }
    }

    @MainActor
    private static func copyScreenshots(meeting: Meeting, into folder: URL) {
        let frames = meeting.screenFrames.sorted { $0.timestamp < $1.timestamp }
        guard !frames.isEmpty else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var index = 1
        for frame in frames {
            let src = StorageManager.shared.frameURL(for: meeting.id, relativePath: frame.imagePath)
            guard FileManager.default.fileExists(atPath: src.path) else { continue }
            let dest = folder.appendingPathComponent(String(format: "%03d.jpg", index))
            try? FileManager.default.copyItem(at: src, to: dest)
            index += 1
            if index > 400 { break }
        }
    }

    @MainActor
    private static func copyAudio(
        meeting: Meeting,
        request: ArchiveExtractRequest,
        into folder: URL
    ) async throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let speaker = request.speaker, !speaker.isEmpty {
            let url = folder.appendingPathComponent("\(DossierNaming.slug(speaker)).m4a")
            do {
                try await DossierAudioExporter.compileSpeaker(meeting: meeting, speakerName: speaker, to: url)
            } catch {
                LogManager.send(
                    "Export speaker audio skipped: \(error.localizedDescription)",
                    category: .general,
                    level: .warning,
                    meetingID: meeting.id
                )
            }
            return
        }
        do {
            _ = try DossierAudioExporter.copyWholeMeeting(meeting: meeting, into: folder)
        } catch {
            LogManager.send(
                "Export audio skipped: \(error.localizedDescription)",
                category: .general,
                level: .warning,
                meetingID: meeting.id
            )
        }
    }

    @MainActor
    private static func copyVideo(meeting: Meeting, into folder: URL) async {
        let frames = meeting.screenFrames.sorted { $0.timestamp < $1.timestamp }
        let urls = frames.compactMap { frame -> URL? in
            let url = StorageManager.shared.frameURL(for: meeting.id, relativePath: frame.imagePath)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
        guard !urls.isEmpty else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let dest = folder.appendingPathComponent("screens.mp4")
        do {
            try await ScreenShareVideoExporter.write(imageURLs: urls, to: dest)
        } catch {
            LogManager.send(
                "Export video skipped: \(error.localizedDescription)",
                category: .screen,
                level: .warning,
                meetingID: meeting.id
            )
        }
    }

    @MainActor
    fileprivate static func savePanelURL(
        suggestedName: String,
        title: String,
        contentTypes: [UTType]
    ) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = contentTypes
        panel.nameFieldStringValue = suggestedName
        panel.title = title
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    @MainActor
    fileprivate static func folderPanelURL(title: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Export"
        panel.title = title
        panel.message = "Each meeting is written as its own PDF in this folder."
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

}

/// PDF packaging for Archive export. One combined document (each meeting
/// starts on a new page) or one file per meeting.
enum ArchiveExtractPDF {
    @MainActor
    static func writeCombined(
        meetings: [Meeting],
        snapshots: [DossierMeetingSnapshot],
        request: ArchiveExtractRequest,
        seriesLabel: String?
    ) async throws -> URL? {
        let suggested = ArchiveExtractPlanner.suggestedFilename(
            snapshots: snapshots,
            request: {
                var next = request
                next.package = .combinedPDF
                return next
            }(),
            seriesLabel: seriesLabel
        )
        guard let destination = ArchiveExtractWriter.savePanelURL(
            suggestedName: suggested,
            title: "Export PDF",
            contentTypes: [.pdf]
        ) else { return nil }

        let parts = try await pdfURLs(
            meetings: meetings,
            snapshots: snapshots,
            request: request,
            seriesLabel: seriesLabel,
            includeIndex: meetings.count > 1
        )
        defer {
            for url in parts { try? FileManager.default.removeItem(at: url) }
        }
        try mergePDFs(parts, to: destination)
        LogManager.send(
            "Exported \(meetings.count) meeting(s) to \(destination.lastPathComponent)",
            category: .general,
            meetingID: meetings.first?.id
        )
        return destination
    }

    @MainActor
    static func writePerMeeting(
        meetings: [Meeting],
        snapshots: [DossierMeetingSnapshot],
        request: ArchiveExtractRequest
    ) async throws -> URL? {
        guard let folder = ArchiveExtractWriter.folderPanelURL(title: "Export one PDF per meeting") else {
            return nil
        }
        var used: Set<String> = []
        var written: [URL] = []
        for (index, meeting) in meetings.enumerated() {
            let snap = snapshots[index]
            var report = report(for: meeting, snapshot: snap, request: request)
            if report.isEmpty {
                report = placeholderReport(snapshot: snap)
            }
            let name = ArchiveExtractPlanner.meetingFolderName(
                title: snap.title,
                date: snap.date,
                id: snap.id,
                used: &used
            )
            let dest = folder.appendingPathComponent("\(name).pdf")
            try await writeReport(report, to: dest)
            written.append(dest)
        }
        guard !written.isEmpty else { throw ArchiveExtractWriter.Failure.nothingToExport }
        LogManager.send(
            "Exported \(written.count) PDF(s) into \(folder.lastPathComponent)",
            category: .general,
            meetingID: meetings.first?.id
        )
        return folder
    }

    static func mergePDFs(_ urls: [URL], to destination: URL) throws {
        let combined = PDFDocument()
        for url in urls {
            guard let doc = PDFDocument(url: url) else { continue }
            for pageIndex in 0..<doc.pageCount {
                guard let page = doc.page(at: pageIndex) else { continue }
                combined.insert(page, at: combined.pageCount)
            }
        }
        guard combined.pageCount > 0 else {
            throw ArchiveExtractWriter.Failure.nothingToExport
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        guard combined.write(to: destination) else {
            throw ArchiveExtractWriter.Failure.writeFailed("Could not write the combined PDF.")
        }
    }

    @MainActor
    static func report(
        for meeting: Meeting,
        snapshot: DossierMeetingSnapshot,
        request: ArchiveExtractRequest
    ) -> ReportModel {
        var model = ReportModelBuilder.build(
            from: meeting,
            includeTranscript: request.includeTranscript,
            dedupeTranscript: true
        )
        if !request.includeIntel {
            model.sections = []
            model.actionItems = []
            model.followUpQuestions = []
            model.topics = []
            model.shareSessions = []
        } else if let speaker = request.speaker, !speaker.isEmpty {
            model.actionItems = model.actionItems.filter {
                DossierNaming.namesMatch($0.assignee ?? "", speaker)
            }
        }
        if request.includeTranscript {
            let lines = DossierFacts.filterTranscript(
                snapshot.transcript,
                audience: request.audience,
                myLabels: snapshot.myLabels
            )
            model.transcript = lines.map {
                ReportModel.TranscriptLine(
                    speaker: $0.speaker,
                    formattedTimestamp: $0.timestamp,
                    text: $0.text
                )
            }
        } else {
            model.transcript = []
        }
        model.shareSessions = []
        return model
    }

    @MainActor
    private static func pdfURLs(
        meetings: [Meeting],
        snapshots: [DossierMeetingSnapshot],
        request: ArchiveExtractRequest,
        seriesLabel: String?,
        includeIndex: Bool
    ) async throws -> [URL] {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("archive-export-pdf-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var urls: [URL] = []
        if includeIndex {
            let indexURL = root.appendingPathComponent("index.pdf")
            try await ReportPDFRenderer.writePDF(
                html: indexHTML(snapshots: snapshots, request: request, seriesLabel: seriesLabel),
                to: indexURL
            )
            urls.append(indexURL)
        }
        var wroteContent = false
        for (index, meeting) in meetings.enumerated() {
            let snap = snapshots[index]
            var model = report(for: meeting, snapshot: snap, request: request)
            if model.isEmpty {
                model = placeholderReport(snapshot: snap)
            } else {
                wroteContent = true
            }
            let url = root.appendingPathComponent("\(index)-\(snap.id.uuidString).pdf")
            try await writeReport(model, to: url)
            urls.append(url)
        }
        if !wroteContent, meetings.isEmpty {
            throw ArchiveExtractWriter.Failure.nothingToExport
        }
        return urls
    }

    @MainActor
    private static func writeReport(_ report: ReportModel, to url: URL) async throws {
        var template = ReportTemplateCatalog.plain
        template.includesFigures = false
        template.includesShareAppendix = false
        template.includesTableOfContents = false
        template.includesActionItems = !report.actionItems.isEmpty
        template.includesFollowUps = !report.followUpQuestions.isEmpty
        template.includesTranscript = !report.transcript.isEmpty
        template.css += """
        .ge-section, .ge-appendix, .ge-transcript { break-before: auto; page-break-before: auto; }
        """
        let html = ReportHTMLRenderer.render(report, template: template)
        try await ReportPDFRenderer.writePDF(html: html, to: url)
    }

    private static func placeholderReport(snapshot: DossierMeetingSnapshot) -> ReportModel {
        ReportModel(
            meta: ReportModel.Meta(
                title: snapshot.title,
                date: snapshot.date,
                duration: snapshot.durationLabel,
                durationMinutes: snapshot.durationMinutes,
                attendees: snapshot.attendees,
                sourceApp: nil,
                generatedAt: .now
            ),
            sections: [
                ReportModel.Section(
                    id: 0,
                    title: "No stored content",
                    intro: "This meeting has no transcript or intel in the current export selection.",
                    points: [],
                    figures: []
                )
            ],
            actionItems: [],
            followUpQuestions: [],
            topics: [],
            shareSessions: [],
            transcript: []
        )
    }

    private static func indexHTML(
        snapshots: [DossierMeetingSnapshot],
        request: ArchiveExtractRequest,
        seriesLabel: String?
    ) -> String {
        var items = ""
        for snap in snapshots {
            items += "<li>\(escape(snap.date.formatted(date: .abbreviated, time: .shortened))) — \(escape(snap.title)) (\(escape(snap.durationLabel)))</li>"
        }
        var series = ""
        if let seriesLabel, !seriesLabel.isEmpty {
            series = "<p><strong>Series:</strong> \(escape(seriesLabel))</p>"
        }
        return """
        <!doctype html>
        <html><head><meta charset="utf-8">
        <style>
        @page { size: Letter; margin: 18mm; }
        body { font: 12pt/1.5 -apple-system, sans-serif; color: #111; }
        h1 { font-size: 18pt; margin: 0 0 12pt; }
        li { margin: 0 0 6pt; }
        </style></head>
        <body>
        <h1>\(escape(AppIdentity.displayName)) archive export</h1>
        \(series)
        <p><strong>Meetings:</strong> \(snapshots.count)</p>
        <p><strong>Speaker:</strong> \(escape(request.audience.displayName))</p>
        <p>Each meeting starts on a new page. This file copies stored transcripts and intelligence. It does not invent facts.</p>
        <ol>\(items)</ol>
        </body></html>
        """
    }

    private static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

private func zipFolder(at folderPath: String, to zipPath: String) throws {
    if FileManager.default.fileExists(atPath: zipPath) {
        try FileManager.default.removeItem(atPath: zipPath)
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
    process.arguments = ["-c", "-k", "--norsrc", folderPath, zipPath]
    let err = Pipe()
    process.standardError = err
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "ditto failed"
        throw ArchiveExtractWriter.Failure.writeFailed(msg.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
