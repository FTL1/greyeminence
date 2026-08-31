import AppKit
import AVFoundation
import CoreVideo
import Foundation

/// Builds an MP4 time-lapse from captured screen-share JPEGs. There is no
/// camera movie of the call — this is the stills, in order, at a fixed pace.
enum ScreenShareVideoExporter {
    enum Failure: LocalizedError, Sendable {
        case noFrames
        case writerFailed(String)

        var errorDescription: String? {
            switch self {
            case .noFrames: "No screen-share stills to turn into a video."
            case .writerFailed(let message): "Could not write screen video: \(message)"
            }
        }
    }

    static let defaultFrameDuration: TimeInterval = 0.4
    static let maxLongEdge = 1280
    static let maxFrames = 400

    static func write(
        imageURLs: [URL],
        to outputURL: URL,
        frameDuration: TimeInterval = defaultFrameDuration
    ) async throws {
        let urls = Array(imageURLs.prefix(maxFrames))
        guard let firstImage = urls.compactMap({ cgImage(from: $0) }).first else { throw Failure.noFrames }
        let size = evenSize(fitting: CGSize(width: firstImage.width, height: firstImage.height), maxLongEdge: maxLongEdge)

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height),
            ]
        )
        guard writer.canAdd(input) else { throw Failure.writerFailed("Could not add a video track.") }
        writer.add(input)
        guard writer.startWriting() else {
            throw Failure.writerFailed(writer.error?.localizedDescription ?? "startWriting failed")
        }
        writer.startSession(atSourceTime: .zero)

        let timescale: CMTimeScale = 600
        let step = CMTime(seconds: max(0.1, frameDuration), preferredTimescale: timescale)
        var presentation = CMTime.zero
        var appended = 0

        for url in urls {
            guard let image = cgImage(from: url),
                  let buffer = pixelBuffer(from: image, size: size) else { continue }
            var spins = 0
            while !input.isReadyForMoreMediaData {
                spins += 1
                if spins > 500 { throw Failure.writerFailed("Encoder stalled.") }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            if !adaptor.append(buffer, withPresentationTime: presentation) {
                throw Failure.writerFailed(writer.error?.localizedDescription ?? "append failed")
            }
            presentation = CMTimeAdd(presentation, step)
            appended += 1
        }
        guard appended > 0 else { throw Failure.noFrames }

        input.markAsFinished()
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            writer.finishWriting {
                if writer.status == .completed {
                    cont.resume()
                } else {
                    cont.resume(throwing: Failure.writerFailed(writer.error?.localizedDescription ?? "finishWriting failed"))
                }
            }
        }
    }

    private static func cgImage(from url: URL) -> CGImage? {
        guard let data = try? Data(contentsOf: url),
              let image = NSImage(data: data) else { return nil }
        var rect = NSRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    private static func evenSize(fitting raw: CGSize, maxLongEdge: Int) -> CGSize {
        var width = max(2, raw.width)
        var height = max(2, raw.height)
        let longest = max(width, height)
        if longest > CGFloat(maxLongEdge) {
            let scale = CGFloat(maxLongEdge) / longest
            width *= scale
            height *= scale
        }
        return CGSize(
            width: CGFloat((Int(width) / 2) * 2),
            height: CGFloat((Int(height) / 2) * 2)
        )
    }

    private static func pixelBuffer(from image: CGImage, size: CGSize) -> CVPixelBuffer? {
        let width = Int(size.width)
        let height = Int(size.height)
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32ARGB,
            [
                kCVPixelBufferCGImageCompatibilityKey: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            ] as CFDictionary,
            &buffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer = buffer else { return nil }
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: base,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                space: space,
                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
              ) else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        return pixelBuffer
    }
}
