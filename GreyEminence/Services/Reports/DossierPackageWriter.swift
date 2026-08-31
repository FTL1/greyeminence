import AppKit
import Foundation
import UniformTypeIdentifiers

enum DossierPackageWriter {
    enum Failure: LocalizedError {
        case nothingToExport
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case .nothingToExport: "Nothing is selected to put in the dossier."
            case .writeFailed(let message): message
            }
        }
    }

    @MainActor
    static func export(
        meeting: Meeting,
        library: [Meeting],
        request: DossierRequest
    ) async throws -> URL? {
        let meetings = request.includeSeries
            ? DossierFacts.relatedMeetings(to: meeting, library: library)
            : [meeting]
        let snapshots = meetings.map { DossierFacts.snapshot(meeting: $0) }
        guard !snapshots.isEmpty else { throw Failure.nothingToExport }

        let kind: String
        if request.onePagers {
            kind = "onepagers"
        } else if request.includeSeries && meetings.count > 1 {
            kind = "series-dossier"
        } else {
            kind = "dossier-\(request.audience.fileSlug)"
        }
        let suggested = ReportExportService.exportFilename(
            title: meeting.title,
            date: meeting.date,
            minutes: max(1, snapshots.map(\.durationMinutes).reduce(0, +)),
            kind: kind,
            fileExtension: "zip"
        )
        guard let destination = savePanelURL(suggestedName: suggested) else { return nil }

        var files: [(String, Data)] = []
        files.append(("README.txt", Data(readme(request: request, snapshots: snapshots).utf8)))

        if request.onePagers {
            appendOnePagers(snapshots: snapshots, request: request, into: &files)
        } else if request.includeReport {
            try await appendReport(snapshots: snapshots, request: request, into: &files)
        }

        if request.includeTranscript, !request.onePagers {
            let lines = snapshots.flatMap { snap in
                DossierFacts.filterTranscript(snap.transcript, audience: request.audience, myLabels: snap.myLabels)
            }
            if !lines.isEmpty {
                let text = TranscriptExportService.plainText(
                    title: meeting.title,
                    date: meeting.date,
                    durationLabel: snapshots.map(\.durationLabel).joined(separator: " + "),
                    lines: lines.map {
                        TranscriptExportLine(timestamp: $0.timestamp, speaker: $0.speaker, text: $0.text)
                    }
                )
                files.append(("transcript.txt", Data(text.utf8)))
            }
        }

        if request.includePromptPackage {
            let audience = request.onePagers ? DossierAudience.general : request.audience
            let prompt = DossierPromptPackage.promptMarkdown(
                snapshots: snapshots,
                audience: audience,
                includeTranscript: request.includeTranscript
            )
            let json = try DossierPromptPackage.jsonData(
                snapshots: snapshots,
                audience: audience,
                includeTranscript: request.includeTranscript
            )
            files.append(("prompt/PROMPT.md", Data(prompt.utf8)))
            files.append(("prompt/meeting.json", json))
        }

        if request.includeScreenshots {
            appendScreenshots(meetings: meetings, into: &files)
        }

        if request.includeAudio {
            try await appendAudio(meetings: meetings, request: request, into: &files)
        }

        guard files.count > 1 else { throw Failure.nothingToExport }
        try OfficeZip.store(files).write(to: destination, options: .atomic)
        LogManager.send(
            "Exported dossier (\(files.count) files, \(request.audience.displayName))",
            category: .general,
            meetingID: meeting.id
        )
        return destination
    }

    @MainActor
    private static func appendReport(
        snapshots: [DossierMeetingSnapshot],
        request: DossierRequest,
        into files: inout [(String, Data)]
    ) async throws {
        let blocks = DossierRenderer.blocks(
            snapshots: snapshots,
            audience: request.audience,
            depth: request.depth,
            includeTranscript: false
        )
        let name = "report.\(request.reportFormat.fileExtension)"
        switch request.reportFormat {
        case .markdown:
            files.append((name, Data(DossierRenderer.markdown(blocks).utf8)))
        case .txt:
            files.append((name, Data(DossierRenderer.plainText(blocks).utf8)))
        case .docx:
            files.append((name, DossierRenderer.docx(blocks)))
        case .rtf:
            files.append((name, DossierRenderer.rtf(blocks)))
        case .json:
            files.append((name, try DossierPromptPackage.jsonData(
                snapshots: snapshots,
                audience: request.audience,
                includeTranscript: request.includeTranscript
            )))
        case .pdf:
            let html = DossierRenderer.html(blocks, title: snapshots[0].title)
            let temp = FileManager.default.temporaryDirectory
                .appendingPathComponent("dossier-\(UUID().uuidString).pdf")
            try await ReportPDFRenderer.writePDF(html: html, to: temp)
            files.append((name, try Data(contentsOf: temp)))
            try? FileManager.default.removeItem(at: temp)
        }
    }

    private static func appendOnePagers(
        snapshots: [DossierMeetingSnapshot],
        request: DossierRequest,
        into files: inout [(String, Data)]
    ) {
        let depth: DossierDepth = request.depth == .detailed ? .summary : .brief
        let general = DossierRenderer.blocks(
            snapshots: snapshots,
            audience: .general,
            depth: depth,
            includeTranscript: false
        )
        files.append(("one-pagers/_general.md", Data(DossierRenderer.markdown(general).utf8)))

        var names: [String] = []
        for snap in snapshots {
            for speaker in snap.speakers where !names.contains(where: { DossierNaming.namesMatch($0, speaker) }) {
                names.append(speaker)
            }
        }
        for name in names {
            let blocks = DossierRenderer.blocks(
                snapshots: snapshots,
                audience: .person(name),
                depth: .brief,
                includeTranscript: false
            )
            files.append(("one-pagers/\(DossierNaming.slug(name)).md", Data(DossierRenderer.markdown(blocks).utf8)))
        }
    }

    @MainActor
    private static func appendScreenshots(meetings: [Meeting], into files: inout [(String, Data)]) {
        var index = 1
        for meeting in meetings {
            for frame in meeting.screenFrames.sorted(by: { $0.timestamp < $1.timestamp }) {
                let url = StorageManager.shared.frameURL(for: meeting.id, relativePath: frame.imagePath)
                guard let data = try? Data(contentsOf: url), !data.isEmpty else { continue }
                files.append((String(format: "screens/%02d.jpg", index), data))
                index += 1
                if index > 40 { return }
            }
        }
    }

    @MainActor
    private static func appendAudio(
        meetings: [Meeting],
        request: DossierRequest,
        into files: inout [(String, Data)]
    ) async throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("dossier-audio-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let prefix: (Meeting) -> String = { meeting in
            meetings.count > 1 ? "\(meeting.id.uuidString.prefix(8))-" : ""
        }

        if request.onePagers {
            for meeting in meetings {
                try copyWholeAudio(meeting: meeting, prefix: prefix(meeting), into: temp, files: &files)
            }
            return
        }

        switch request.audience {
        case .person(let name):
            for meeting in meetings {
                let url = temp.appendingPathComponent("\(prefix(meeting))\(DossierNaming.slug(name)).m4a")
                do {
                    try await DossierAudioExporter.compileSpeaker(meeting: meeting, speakerName: name, to: url)
                    files.append(("audio/\(url.lastPathComponent)", try Data(contentsOf: url)))
                } catch {
                    LogManager.send(
                        "Dossier speaker audio skipped: \(error.localizedDescription)",
                        category: .general,
                        level: .warning,
                        meetingID: meeting.id
                    )
                }
            }
        case .me:
            for meeting in meetings {
                let meName = MeetingRoster.snapshot(for: meeting).myName ?? Speaker.defaultMeLabel
                let url = temp.appendingPathComponent("\(prefix(meeting))me.m4a")
                do {
                    try await DossierAudioExporter.compileSpeaker(meeting: meeting, speakerName: meName, to: url)
                    files.append(("audio/\(url.lastPathComponent)", try Data(contentsOf: url)))
                } catch {
                    try copyWholeAudio(meeting: meeting, prefix: prefix(meeting), into: temp, files: &files)
                }
            }
        case .boss, .general:
            for meeting in meetings {
                try copyWholeAudio(meeting: meeting, prefix: prefix(meeting), into: temp, files: &files)
            }
        }
    }

    @MainActor
    private static func copyWholeAudio(
        meeting: Meeting,
        prefix: String,
        into temp: URL,
        files: inout [(String, Data)]
    ) throws {
        let folder = temp.appendingPathComponent(meeting.id.uuidString, isDirectory: true)
        let names = try DossierAudioExporter.copyWholeMeeting(meeting: meeting, into: folder)
        for relative in names {
            let filename = (relative as NSString).lastPathComponent
            let url = folder.appendingPathComponent(filename)
            if let data = try? Data(contentsOf: url) {
                files.append(("audio/\(prefix)\(filename)", data))
            }
        }
    }

    private static func readme(request: DossierRequest, snapshots: [DossierMeetingSnapshot]) -> String {
        var lines: [String] = [
            "Grey Eminence meeting dossier",
            "Audience: \(request.onePagers ? "one-pager per speaker + general" : request.audience.displayName)",
            "Depth: \(request.depth.label)",
            "Meetings: \(snapshots.count)",
            "",
            "This package copies stored notes, tasks, and transcript text. It does not invent facts.",
            "To work in a separate chatbot, upload prompt/PROMPT.md and prompt/meeting.json (and the transcript file if present).",
            "The prompt tells the model not to hallucinate and not to add questions that were not in the meeting.",
            "",
            "Audio (if included) is the saved AAC recording. A per-person file concatenates that speaker's time ranges — other voices can still be heard when they overlapped.",
            "There is no movie of the call. Screen stills are in screens/ when included.",
            "",
        ]
        for snap in snapshots {
            lines.append("- \(snap.title)  (\(snap.date.formatted(date: .abbreviated, time: .shortened)), \(snap.durationLabel))")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    @MainActor
    private static func savePanelURL(suggestedName: String) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.nameFieldStringValue = suggestedName
        panel.title = "Export meeting dossier"
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
}
