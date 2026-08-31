import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

/// Pure frame-triage helpers: perceptual hashing (change detection), the
/// keep/drop decision, and OCR. Nonisolated statics so the capture actor can
/// call them and unit tests can exercise them without any capture machinery.
enum ScreenFrameTriage {

    // MARK: - dHash

    /// 64-bit difference hash: downscale to 9×8 grayscale, set bit i when
    /// pixel[x] > pixel[x+1] in its row. Robust against JPEG artifacts and
    /// small cursor movement; layout changes flip many bits.
    static func dHash(_ image: CGImage) -> UInt64 {
        let width = 9, height = 8
        var pixels = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return 0 }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var hash: UInt64 = 0
        var bit = 0
        for y in 0..<height {
            for x in 0..<(width - 1) {
                if pixels[y * width + x] > pixels[y * width + x + 1] {
                    hash |= 1 << UInt64(bit)
                }
                bit += 1
            }
        }
        return hash
    }

    static func hammingDistance(_ a: UInt64, _ b: UInt64) -> Int {
        (a ^ b).nonzeroBitCount
    }

    /// Keep rule: the first frame of a session always survives; later frames
    /// survive only when they differ enough from the last KEPT frame.
    static func shouldKeep(hash: UInt64, lastKeptHash: UInt64?, threshold: Int) -> Bool {
        guard let last = lastKeptHash else { return true }
        return hammingDistance(hash, last) >= threshold
    }

    // MARK: - Blank capture

    /// True when the image is a near-uniform white or black field — the usual
    /// result of capturing a compositor overlay or a window whose contents
    /// never made it into the screenshot. Those frames are not meeting content.
    static func isBlankCapture(_ image: CGImage) -> Bool {
        let width = 16, height = 16
        var pixels = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return false }
        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var minValue = 255
        var maxValue = 0
        var sum = 0
        for pixel in pixels {
            let value = Int(pixel)
            if value < minValue { minValue = value }
            if value > maxValue { maxValue = value }
            sum += value
        }
        let range = maxValue - minValue
        let mean = sum / pixels.count
        return range <= 8 && (mean >= 247 || mean <= 8)
    }

    static func isBlankJPEG(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return true
        }
        return isBlankCapture(image)
    }

    // MARK: - Visual-only change

    /// True when two OCR texts are near-identical (≥ 95% line overlap) —
    /// the hash moved but the words didn't, which is the signature of video
    /// playback or animation. Such frames are kept but deprioritized for
    /// vision analysis.
    static func isVisualOnlyChange(previousOCR: String?, currentOCR: String?) -> Bool {
        let prev = ocrLines(previousOCR)
        let curr = ocrLines(currentOCR)
        // Text appearing or disappearing entirely is a real change.
        guard !prev.isEmpty || !curr.isEmpty else { return true }  // no text either side: purely visual
        guard !prev.isEmpty, !curr.isEmpty else { return false }
        let union = prev.union(curr).count
        let intersection = prev.intersection(curr).count
        guard union > 0 else { return true }
        return Double(intersection) / Double(union) >= 0.95
    }

    // MARK: - Share-ended placeholder

    /// Lowercased phrases that mark the placeholder screen Teams leaves in
    /// the pop-out window after the presenter stops sharing. The default for
    /// callers with no app profile, and the source `ShareAppProfiles.teams`
    /// reuses rather than restating.
    static let shareEndedPhrases: [String] = [
        "content sharing has ended",
        "sharing is paused",
    ]

    /// True when the OCR shows a share-ended placeholder rather than real
    /// content. Text-based on purpose — the placeholder renders at any
    /// window size and in light or dark mode, so image hashing can't pin it
    /// down. Requires the screen to be otherwise nearly empty (placeholder
    /// screens carry only a title bar, the message, and a button) so a
    /// document that merely quotes the phrase doesn't end the session.
    static func isShareEndedPlaceholder(
        ocrText: String?,
        phrases: [String] = shareEndedPhrases
    ) -> Bool {
        // Empty OCR yields an empty set, and `.contains` on it is already
        // false — no separate emptiness guard needed.
        let lines = ocrLines(ocrText)
        guard lines.count <= 5 else { return false }
        return lines.contains { line in
            phrases.contains { line.contains($0) }
        }
    }

    private static func ocrLines(_ text: String?) -> Set<String> {
        guard let text else { return [] }
        return Set(
            text.split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                .filter { !$0.isEmpty }
        )
    }

    // MARK: - OCR

    /// Maximum characters of recognized text retained per frame.
    static let ocrCharacterCap = 4_000

    /// Recognize on-screen text, top-to-bottom. `.accurate` because frames
    /// arrive every ≥5s (latency is irrelevant) and `.fast` is materially
    /// worse on code and dense slides. Language correction off so
    /// identifiers, tickets, and code aren't "fixed" into prose.
    static func recognizeText(in image: CGImage) async throws -> String? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false

        let handler = VNImageRequestHandler(cgImage: image)
        try handler.perform([request])

        guard let observations = request.results, !observations.isEmpty else { return nil }
        let lines = observations
            .sorted { $0.boundingBox.midY > $1.boundingBox.midY }  // Vision origin is bottom-left
            .compactMap { $0.topCandidates(1).first?.string }
        guard !lines.isEmpty else { return nil }
        let joined = lines.joined(separator: "\n")
        return String(joined.prefix(ocrCharacterCap))
    }

    // MARK: - Scaling

    /// Re-encode a JPEG so its pixel count fits `targetPixelCount` — the
    /// vision-payload copy. Disk keeps the original capture; this only trims
    /// what goes over the wire (image tokens scale with pixels). Any decode
    /// or encode failure returns the original data — a bigger payload, never
    /// a lost frame.
    static func downscaledJPEG(_ jpegData: Data, targetPixelCount: Int, quality: Double = 0.7) -> Data {
        guard let source = CGImageSourceCreateWithData(jpegData as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Double,
              let height = properties[kCGImagePropertyPixelHeight] as? Double,
              width > 0, height > 0 else {
            return jpegData
        }
        let originalSize = CGSize(width: width, height: height)
        let target = scaledSize(for: originalSize, targetPixelCount: targetPixelCount)
        guard target != originalSize else { return jpegData }

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(max(target.width, target.height)),
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let scaled = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            return jpegData
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return jpegData }
        CGImageDestinationAddImage(
            destination, scaled,
            [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return jpegData }
        return output as Data
    }

    /// Pixel size that keeps `width*height` at or under `targetPixelCount`
    /// while preserving aspect ratio. Never upscales.
    static func scaledSize(for size: CGSize, targetPixelCount: Int) -> CGSize {
        let pixels = size.width * size.height
        guard pixels > CGFloat(targetPixelCount), pixels > 0 else { return size }
        let scale = (CGFloat(targetPixelCount) / pixels).squareRoot()
        return CGSize(
            width: (size.width * scale).rounded(.down),
            height: (size.height * scale).rounded(.down)
        )
    }
}
