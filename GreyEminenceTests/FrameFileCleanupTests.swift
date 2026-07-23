import XCTest
@testable import Grey_Eminence

/// Frame-file cleanup used when a frame-owning meeting is deleted but its
/// recording directory is retained for a split sibling that shares the source
/// audio (closing the orphaned-JPEG gap in MeetingDeletion).
final class FrameFileCleanupTests: XCTestCase {

    private var recordingDir: URL!

    override func setUpWithError() throws {
        recordingDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("frame-cleanup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: recordingDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: recordingDir)
    }

    /// Write a frame JPEG at `frames/<session>/<seq>.jpg` and return its path
    /// relative to the recording dir — the same shape StorageManager.writeFrame
    /// stores in ScreenShareFrame.imagePath.
    @discardableResult
    private func makeFrame(session: String, sequence: Int) throws -> String {
        let relative = "frames/\(session)/\(String(format: "%06d", sequence)).jpg"
        let url = recordingDir.appendingPathComponent(relative)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([0xFF, 0xD8, 0xFF]).write(to: url)
        return relative
    }

    private func exists(_ relative: String) -> Bool {
        FileManager.default.fileExists(atPath: recordingDir.appendingPathComponent(relative).path)
    }

    func testRemovesListedFramesAndReportsCount() throws {
        let a = try makeFrame(session: "aaaa1111", sequence: 0)
        let b = try makeFrame(session: "aaaa1111", sequence: 1)

        let removed = StorageManager.deleteFrameFiles(
            inRecordingDirectory: recordingDir, relativePaths: [a, b])

        XCTAssertEqual(removed, 2)
        XCTAssertFalse(exists(a))
        XCTAssertFalse(exists(b))
    }

    func testPrunesEmptedSessionAndFramesDirs() throws {
        let a = try makeFrame(session: "aaaa1111", sequence: 0)

        StorageManager.deleteFrameFiles(inRecordingDirectory: recordingDir, relativePaths: [a])

        let fm = FileManager.default
        XCTAssertFalse(fm.fileExists(atPath: recordingDir.appendingPathComponent("frames/aaaa1111").path),
                       "emptied session dir should be pruned")
        XCTAssertFalse(fm.fileExists(atPath: recordingDir.appendingPathComponent("frames").path),
                       "emptied frames dir should be pruned")
    }

    func testKeepsSiblingFramesAndDirsWhenOnlySomeRemoved() throws {
        let mine = try makeFrame(session: "aaaa1111", sequence: 0)
        let theirs = try makeFrame(session: "bbbb2222", sequence: 0)

        let removed = StorageManager.deleteFrameFiles(
            inRecordingDirectory: recordingDir, relativePaths: [mine])

        XCTAssertEqual(removed, 1)
        XCTAssertFalse(exists(mine))
        // A frame in a different session is untouched, so neither its session
        // dir nor the frames/ dir is pruned.
        XCTAssertTrue(exists(theirs))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: recordingDir.appendingPathComponent("frames").path))
    }

    func testAudioFilesUntouched() throws {
        // The recording dir also holds the shared audio — cleanup must not
        // touch anything outside frames/.
        let audio = recordingDir.appendingPathComponent("system.m4a")
        try Data([0x00]).write(to: audio)
        let frame = try makeFrame(session: "aaaa1111", sequence: 0)

        StorageManager.deleteFrameFiles(inRecordingDirectory: recordingDir, relativePaths: [frame])

        XCTAssertTrue(FileManager.default.fileExists(atPath: audio.path))
    }

    func testMissingFilesAreNotCounted() {
        let removed = StorageManager.deleteFrameFiles(
            inRecordingDirectory: recordingDir,
            relativePaths: ["frames/none/000000.jpg"])
        XCTAssertEqual(removed, 0)
    }
}
