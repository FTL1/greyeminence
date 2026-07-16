import CoreGraphics
import Foundation
import ImageIO

/// Downsampled-thumbnail decoder + cache for frame JPEGs. Every UI surface
/// (toolbar popover, filmstrip, Ask rows) goes through this — full-resolution
/// decodes are reserved for explicit Copy/Open actions. NSCache is
/// thread-safe, so this is a plain Sendable class; decode work is cheap at
/// thumbnail sizes but callers may still hop off the main actor.
final class FrameThumbnailCache: @unchecked Sendable {
    static let shared = FrameThumbnailCache()

    /// Preset pixel sizes so distinct call sites share cache entries.
    enum Size: Int {
        case strip = 160   // filmstrip / Ask result rows
        case preview = 480 // toolbar popover
        case stage = 1024  // playback stage
    }

    private let cache = NSCache<NSString, CGImage>()

    private init() {
        cache.totalCostLimit = 64 * 1024 * 1024
    }

    func thumbnail(at url: URL, size: Size) -> CGImage? {
        let key = "\(url.path)|\(size.rawValue)" as NSString
        if let hit = cache.object(forKey: key) { return hit }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: size.rawValue,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        cache.setObject(image, forKey: key, cost: image.bytesPerRow * image.height)
        return image
    }

    /// Async convenience that decodes off the caller's executor.
    func thumbnail(at url: URL, size: Size) async -> CGImage? {
        await Task.detached(priority: .userInitiated) { [self] in
            thumbnail(at: url, size: size)
        }.value
    }
}
