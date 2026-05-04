import Foundation
import os
@preconcurrency import KeychainAccess

enum KeychainHelper {
    /// Data protection keychain — no password prompts for the owning app.
    private static let keychain = Keychain(service: "com.greyeminence.app")
        .accessibility(.afterFirstUnlockThisDeviceOnly)

    /// `KeychainHelper.get` is called concurrently from `RecordingViewModel`,
    /// `ReProcessingQueue`, `TopicMapView` and Settings — sometimes from
    /// different actors. Guard the cache with an unfair lock so the
    /// dictionary mutations can't tear or return wrong values.
    private static let cache = OSAllocatedUnfairLock<[String: String]>(initialState: [:])

    static func get(_ key: String) throws -> String? {
        if let cached = cache.withLock({ $0[key] }) { return cached }
        let value = try keychain.get(key)
        if let value {
            cache.withLock { $0[key] = value }
        }
        return value
    }

    static func set(_ value: String, key: String) throws {
        try keychain.set(value, key: key)
        cache.withLock { $0[key] = value }
    }

    static func remove(_ key: String) throws {
        try keychain.remove(key)
        cache.withLock { $0.removeValue(forKey: key) }
    }
}
