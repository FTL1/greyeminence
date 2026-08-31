import XCTest
import SwiftData
import AppKit
import PDFKit
@testable import Grey_Eminence

@MainActor
final class ArchiveExtractTests: XCTestCase {
    func testSuggestedFilenameUsesSeriesAndExportKind() {
        let snap = sampleSnapshot(title: "Standup", date: date(2026, 3, 12))
        let zip = ArchiveExtractPlanner.suggestedFilename(
            snapshots: [snap],
            request: ArchiveExtractRequest(),
            seriesLabel: "Weekly Standup"
        )
        XCTAssertTrue(zip.contains("Weekly Standup"))
        XCTAssertTrue(zip.hasSuffix("-export.zip"))

        var pdfRequest = ArchiveExtractRequest()
        pdfRequest.package = .combinedPDF
        let pdf = ArchiveExtractPlanner.suggestedFilename(
            snapshots: [snap],
            request: pdfRequest,
            seriesLabel: "Weekly Standup"
        )
        XCTAssertTrue(pdf.hasSuffix("-export.pdf"))
    }

    func testPDFPackageIgnoresMediaToggles() {
        var request = ArchiveExtractRequest()
        request.package = .combinedPDF
        request.includeTranscript = false
        request.includeIntel = false
        request.includeAudio = true
        XCTAssertFalse(request.includesAnything)
        request.includeTranscript = true
        XCTAssertTrue(request.includesAnything)
    }

    func testMergePDFsConcatenatesPages() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("export-pdf-merge-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        func blankPDF(named name: String) throws -> URL {
            let url = dir.appendingPathComponent(name)
            let doc = PDFDocument()
            doc.insert(PDFPage(), at: 0)
            XCTAssertTrue(doc.write(to: url))
            return url
        }
        let a = try blankPDF(named: "a.pdf")
        let b = try blankPDF(named: "b.pdf")
        let dest = dir.appendingPathComponent("combined.pdf")
        try ArchiveExtractPDF.mergePDFs([a, b], to: dest)
        let combined = try XCTUnwrap(PDFDocument(url: dest))
        XCTAssertEqual(combined.pageCount, 2)
    }

    func testMeetingFolderNameIsDatePlusSlugAndUniquifies() {
        var used: Set<String> = []
        let a = ArchiveExtractPlanner.meetingFolderName(
            title: "Weekly Standup",
            date: date(2026, 3, 12),
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            used: &used
        )
        let b = ArchiveExtractPlanner.meetingFolderName(
            title: "Weekly Standup",
            date: date(2026, 3, 12),
            id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            used: &used
        )
        XCTAssertEqual(a, "2026-03-12-weekly-standup")
        XCTAssertTrue(b.hasPrefix("2026-03-12-weekly-standup-"))
        XCTAssertNotEqual(a, b)
    }

    func testTextFilesFilterToOneSpeaker() {
        let request = ArchiveExtractRequest(
            speaker: "Jordan",
            includeTranscript: true,
            includeIntel: true
        )
        let files = ArchiveExtractPlanner.textFiles(
            snapshots: [sampleSnapshot()],
            request: request,
            seriesLabel: nil
        )
        let byPath = Dictionary(uniqueKeysWithValues: files)
        let transcript = byPath["meetings/2026-08-18-north-campus-engineering-scope-review/transcript.md"]
            ?? byPath.first { $0.key.hasSuffix("/transcript.md") }?.value
        XCTAssertNotNil(transcript)
        XCTAssertTrue(transcript!.contains("Jordan"))
        XCTAssertTrue(transcript!.contains("25 megawatts"))
        XCTAssertFalse(transcript!.contains("I'll update the ROM"))

        let intel = files.first { $0.0.hasSuffix("/intel.md") }?.1 ?? ""
        XCTAssertTrue(intel.contains("Send drawings"))
        XCTAssertFalse(intel.contains("Fix the ROM"))
    }

    func testSplitBySpeakerWritesPerPersonFolders() {
        var request = ArchiveExtractRequest()
        request.splitBySpeaker = true
        request.includeTranscript = true
        request.includeIntel = true
        let files = ArchiveExtractPlanner.textFiles(
            snapshots: [sampleSnapshot()],
            request: request,
            seriesLabel: "North Campus"
        )
        let paths = Set(files.map(\.0))
        XCTAssertTrue(paths.contains("speakers/jordan/transcript.md"))
        XCTAssertTrue(paths.contains("speakers/alex/transcript.md"))
        let jordan = files.first { $0.0 == "speakers/jordan/transcript.md" }?.1 ?? ""
        XCTAssertTrue(jordan.contains("25 megawatts"))
        XCTAssertFalse(jordan.contains("I'll update the ROM"))
    }

    func testCombinedTranscriptOnlyWhenSeveralMeetings() {
        let one = ArchiveExtractPlanner.textFiles(
            snapshots: [sampleSnapshot()],
            request: ArchiveExtractRequest(),
            seriesLabel: nil
        )
        XCTAssertFalse(one.map(\.0).contains("transcript.md"))

        let two = ArchiveExtractPlanner.textFiles(
            snapshots: [sampleSnapshot(), sampleSnapshot(title: "Standup", date: date(2026, 3, 12))],
            request: ArchiveExtractRequest(),
            seriesLabel: "Exec series"
        )
        XCTAssertTrue(two.map(\.0).contains("transcript.md"))
        XCTAssertTrue(two.map(\.0).contains("intel.md"))
        XCTAssertTrue(two.map(\.0).contains("index.md"))
        let index = two.first { $0.0 == "index.md" }?.1 ?? ""
        XCTAssertTrue(index.contains("Exec series"))
        XCTAssertTrue(index.contains("**Meetings:** 2"))
    }

    func testResolveThisSeriesIncludesLibrarySiblings() throws {
        let context = try makeContext()
        let series = UUID()
        let a = Meeting(title: "Exec Standup")
        a.seriesID = series
        a.seriesTitle = "Weekly Standup"
        a.date = date(2026, 1, 8)
        let b = Meeting(title: "Exec Standup")
        b.seriesID = series
        b.seriesTitle = "Weekly Standup"
        b.date = date(2026, 8, 20)
        let other = Meeting(title: "Unrelated")
        context.insert(a)
        context.insert(b)
        context.insert(other)

        let resolved = ArchiveExtractPlanner.resolveMeetings(
            scope: .thisSeries,
            seed: a,
            selected: [a],
            visible: [a],
            group: [a],
            library: [a, b, other]
        )
        XCTAssertEqual(Set(resolved.map(\.id)), Set([a.id, b.id]))
    }

    func testArchiveCatalogIncludesRecentMeetings() throws {
        let context = try makeContext()
        let recent = Meeting(title: "Weekly Standup")
        recent.date = Date()
        let old = Meeting(title: "Old standup")
        old.date = date(2024, 1, 8)
        context.insert(recent)
        context.insert(old)
        let cutoff = MeetingLibrary.recentCutoff(now: Date(), calendar: Calendar(identifier: .gregorian))
        XCTAssertTrue(MeetingLibrary.isOnMeetingsList(recent, cutoff: cutoff))
        XCTAssertFalse(MeetingLibrary.isOnMeetingsList(old, cutoff: cutoff))
        XCTAssertTrue(MeetingLibrary.isLibrary(recent))
        XCTAssertTrue(MeetingLibrary.isLibrary(old))
    }

    func testFilingRemovesAMeetingFromTheRecentList() throws {
        let context = try makeContext()
        let meeting = Meeting(title: "Weekly Standup")
        meeting.date = Date()
        context.insert(meeting)
        let cutoff = MeetingLibrary.recentCutoff()
        XCTAssertTrue(MeetingLibrary.isOnMeetingsList(meeting, cutoff: cutoff))
        MeetingLibrary.setArchived([meeting], true, in: context)
        XCTAssertTrue(meeting.isArchived)
        XCTAssertFalse(MeetingLibrary.isOnMeetingsList(meeting, cutoff: cutoff))
        XCTAssertTrue(MeetingLibrary.isLibrary(meeting))
        MeetingLibrary.setArchived([meeting], false, in: context)
        XCTAssertTrue(MeetingLibrary.isOnMeetingsList(meeting, cutoff: cutoff))
    }

    func testResolveThisGroupDoesNotExpandTheSeries() throws {
        let context = try makeContext()
        let series = UUID()
        let a = Meeting(title: "Exec Standup")
        a.seriesID = series
        a.seriesTitle = "Weekly Standup"
        a.date = date(2026, 1, 8)
        let b = Meeting(title: "Exec Standup")
        b.seriesID = series
        b.seriesTitle = "Weekly Standup"
        b.date = date(2026, 8, 20)
        context.insert(a)
        context.insert(b)

        let resolved = ArchiveExtractPlanner.resolveMeetings(
            scope: .thisGroup,
            seed: a,
            selected: [],
            visible: [a],
            group: [a],
            library: [a, b]
        )
        XCTAssertEqual(resolved.map(\.id), [a.id])
    }

    func testWritePackageCreatesTranscriptAndIntel() async throws {
        let context = try makeContext()
        let meeting = Meeting(title: "Weekly Standup")
        meeting.date = date(2026, 3, 12)
        meeting.duration = 47 * 60
        meeting.status = .completed
        context.insert(meeting)
        let alex = TranscriptSegment(
            speaker: .meNamed("Alex"),
            text: "I'll update the ROM.",
            startTime: 20,
            endTime: 24,
            isFinal: true
        )
        alex.meeting = meeting
        meeting.segments.append(alex)
        let jordan = TranscriptSegment(
            speaker: .other("Jordan"),
            text: "It is 25 megawatts not 40.",
            startTime: 12,
            endTime: 16,
            isFinal: true
        )
        jordan.meeting = meeting
        meeting.segments.append(jordan)
        let insight = MeetingInsight(
            summary: #"[{"title":"Documents","intro":"Alex is correcting outbound scope language.","points":[{"label":"ROM","detail":"Update numbers Jordan voiced."}]}]"#,
            followUpQuestions: ["Does the write-up use Jordan's 25MW figure?"],
            topics: ["ROM"]
        )
        insight.meeting = meeting
        meeting.insights.append(insight)

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("extract-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        var request = ArchiveExtractRequest()
        request.includeTranscript = true
        request.includeIntel = true
        let snap = DossierFacts.snapshot(meeting: meeting)
        try await ArchiveExtractWriter.writePackage(
            meetings: [meeting],
            snapshots: [snap],
            request: request,
            seriesLabel: "Weekly Standup",
            into: root
        )

        let transcript = root.appendingPathComponent("meetings/2026-03-12-weekly-standup/transcript.md")
        let intel = root.appendingPathComponent("meetings/2026-03-12-weekly-standup/intel.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: transcript.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: intel.path))
        let transcriptText = try String(contentsOf: transcript, encoding: .utf8)
        XCTAssertTrue(transcriptText.contains("I'll update the ROM."))
        XCTAssertTrue(transcriptText.contains("25 megawatts"))
        let intelText = try String(contentsOf: intel, encoding: .utf8)
        XCTAssertTrue(intelText.contains("ROM") || intelText.contains("25MW") || intelText.contains("Documents"))
        XCTAssertTrue(intelText.contains("does not add facts"))
    }

    func testScreenShareVideoWritesMp4() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("extract-video-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let jpeg = try tinyJPEG()
        let frameA = dir.appendingPathComponent("a.jpg")
        let frameB = dir.appendingPathComponent("b.jpg")
        try jpeg.write(to: frameA)
        try jpeg.write(to: frameB)
        let movie = dir.appendingPathComponent("screens.mp4")
        do {
            try await ScreenShareVideoExporter.write(
                imageURLs: [frameA, frameB],
                to: movie,
                frameDuration: 0.2
            )
        } catch {
            throw XCTSkip("Video encoder unavailable: \(error.localizedDescription)")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: movie.path))
        let size = try FileManager.default.attributesOfItem(atPath: movie.path)[.size] as? NSNumber
        XCTAssertGreaterThan(size?.intValue ?? 0, 100)
    }

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Meeting.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private func sampleSnapshot(
        title: String = "North Campus Engineering Scope Review",
        date: Date? = nil
    ) -> DossierMeetingSnapshot {
        DossierMeetingSnapshot(
            id: UUID(),
            title: title,
            generatedTitle: "Align prospect docs",
            date: date ?? self.date(2026, 8, 18),
            durationLabel: "47m",
            durationMinutes: 47,
            attendees: ["Alex", "Jordan"],
            speakers: ["Alex", "Jordan"],
            myLabels: ["Alex", "Me"],
            summaryJSON: """
            [{"title":"Documents","intro":"Alex is correcting outbound scope language.","points":[{"label":"ROM","detail":"Update numbers Jordan voiced."}]}]
            """,
            actionItems: [
                DossierAction(text: "Fix the ROM", assignee: "Me", isCompleted: false, sourceQuote: "I'll update the ROM"),
                DossierAction(text: "Send drawings", assignee: "Jordan", isCompleted: false, sourceQuote: "I can send the drawings"),
            ],
            followUps: ["Does the write-up use Jordan's 25MW figure?"],
            topics: ["prospect documents", "ROM"],
            shareNarratives: [],
            transcript: [
                DossierLine(speaker: "Jordan", timestamp: "0:12", text: "It is 25 megawatts not 40.", isMe: false),
                DossierLine(speaker: "Alex", timestamp: "0:20", text: "I'll update the ROM.", isMe: true),
            ]
        )
    }

    private func tinyJPEG() throws -> Data {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 32,
            pixelsHigh: 32,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.red.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 32, height: 32)).fill()
        NSGraphicsContext.restoreGraphicsState()
        guard let data = rep.representation(using: .jpeg, properties: [:]) else {
            throw XCTSkip("Could not encode a test JPEG")
        }
        return data
    }
}
