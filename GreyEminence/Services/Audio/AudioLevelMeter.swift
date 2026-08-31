import Foundation

/// Maps microphone RMS onto a meter that actually moves during speech.
///
/// Linear 0…1 RMS of talk is typically 0.01–0.08, so a 20-segment bar that
/// lights when `i/20 < rms` stays stuck on the first LED while a numeric
/// readout still changes. dBFS with a −50…−8 range matches a VU meter.
enum AudioLevelMeter {
    static let defaultFloorDB: Float = -50
    static let defaultCeilingDB: Float = -8

    static func dBFS(rms: Float) -> Float {
        20 * log10(max(rms, 1e-8))
    }

    /// 0 below `floorDB`, 1 at `ceilingDB`.
    static func fill(
        rms: Float,
        floorDB: Float = defaultFloorDB,
        ceilingDB: Float = defaultCeilingDB
    ) -> Float {
        let span = max(ceilingDB - floorDB, 1)
        let t = (dBFS(rms: rms) - floorDB) / span
        return min(1, max(0, t))
    }

    static func litSegments(
        rms: Float,
        count: Int,
        floorDB: Float = defaultFloorDB,
        ceilingDB: Float = defaultCeilingDB
    ) -> Int {
        guard count > 0 else { return 0 }
        let t = fill(rms: rms, floorDB: floorDB, ceilingDB: ceilingDB)
        if t <= 0 { return 0 }
        if t >= 1 { return count }
        return min(count, Int((t * Float(count)).rounded(.up)))
    }
}
