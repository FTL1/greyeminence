import CoreGraphics
import Foundation
import ImageIO
import SwiftData

/// Rebuilds `ScreenShareFrame` rows for meetings whose frame images exist on
/// disk but whose rows are gone from the store.
///
/// Why rows can vanish while images survive: launching an OLD build against
/// the store lightweight-migrates it DOWN — SwiftData silently drops every
/// row of entities the old schema doesn't know (observed 2026-07-17 when
/// v0.21.7 was launched to pick up a Sparkle update). The next new-schema
/// launch recreates the tables empty, but the JPEGs under each meeting's
/// frames/ directory are untouched — enough to reconstruct the rows.
///
/// What comes back: session grouping (per directory, with freshly minted
/// session IDs), sequence, capture time (file mtime), elapsed timestamp
/// (mtime − meeting start), OCR and dHash (recomputed). Observations and
/// recaps do NOT come back automatically — "Analyze Frames" or
/// Reanalyze → "Re-analyze screen shares" regenerates them.
///
/// Idempotent: only meetings with zero rows AND images on disk are touched;
/// once recovered, rows exist and the meeting is never touched again.
@MainActor
enum ScreenFrameRecoveryService {

    @discardableResult
    static func recoverAtLaunch(modelContext: ModelContext) async -> Int {
        let meetings = (try? modelContext.fetch(FetchDescriptor<Meeting>())) ?? []
        var recoveredTotal = 0
        for meeting in meetings where meeting.screenFrames.isEmpty {
            let framesDir = StorageManager.shared.framesDirectory(for: meeting.id)
            guard FileManager.default.fileExists(atPath: framesDir.path) else { continue }
            recoveredTotal += await recoverFrames(for: meeting, framesDir: framesDir)
        }
        if recoveredTotal > 0 {
            PersistenceGate.save(modelContext, site: "ScreenFrameRecovery", critical: false, meetingID: nil)
            LogManager.send("Recovered \(recoveredTotal) screen-frame row(s) from disk images (rows lost to a schema downgrade)", category: .screen)
        }
        return recoveredTotal
    }

    private static func recoverFrames(for meeting: Meeting, framesDir: URL) async -> Int {
        let fm = FileManager.default
        guard let sessionDirs = try? fm.contentsOfDirectory(
            at: framesDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return 0 }

        var recovered = 0
        for sessionDir in sessionDirs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let images = ((try? fm.contentsOfDirectory(
                at: sessionDir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]
            )) ?? [])
                .filter { $0.pathExtension.lowercased() == "jpg" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            guard !images.isEmpty else { continue }

            // The directory name is only the original session UUID's 8-char
            // prefix — mint a fresh ID; the grouping is what matters.
            let sessionID = UUID()
            for image in images {
                let capturedAt = (try? image.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? meeting.date
                var ocr: String?
                var hash: UInt64 = 0
                if let source = CGImageSourceCreateWithURL(image as CFURL, nil),
                   let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) {
                    hash = ScreenFrameTriage.dHash(cgImage)
                    ocr = try? await ScreenFrameTriage.recognizeText(in: cgImage)
                }
                let row = ScreenShareFrame(
                    sessionID: sessionID,
                    sequence: sequence(fromFilename: image.lastPathComponent),
                    timestamp: elapsed(capturedAt: capturedAt, meetingStart: meeting.date, duration: meeting.duration),
                    capturedAt: capturedAt,
                    imagePath: "frames/\(sessionDir.lastPathComponent)/\(image.lastPathComponent)",
                    ocrText: ocr,
                    dedupeHash: Int64(bitPattern: hash),
                    analysisState: .ocrOnly
                )
                row.meeting = meeting
                meeting.screenFrames.append(row)
                recovered += 1
            }
        }
        if recovered > 0 {
            LogManager.send("Recovered \(recovered) frame(s) for \"\(meeting.title)\" from disk", category: .screen, meetingID: meeting.id)
        }
        return recovered
    }

    // MARK: - Pure helpers (unit-testable)

    /// "000042.jpg" → 42; anything non-numeric → 0.
    nonisolated static func sequence(fromFilename name: String) -> Int {
        Int(name.split(separator: ".").first.map(String.init) ?? "") ?? 0
    }

    /// Elapsed-seconds reconstruction: capture mtime minus meeting start,
    /// clamped to [0, duration]. Mid-recording pauses are unrecoverable, so
    /// frames after a pause land slightly late — close enough for the
    /// player and transcript sync.
    nonisolated static func elapsed(capturedAt: Date, meetingStart: Date, duration: TimeInterval) -> TimeInterval {
        let raw = capturedAt.timeIntervalSince(meetingStart)
        let upper = duration > 0 ? duration : max(raw, 0)
        return min(max(raw, 0), upper)
    }
}
