import Foundation
import SwiftData

/// Token usage decoded from one API response.
struct AIUsage: Sendable, Equatable {
    var inputTokens: Int
    var outputTokens: Int
    var cacheReadTokens: Int
    var cacheWriteTokens: Int

    /// Best-effort decode of the `usage` object from a raw messages-API
    /// response body (the direct API and Bedrock speak the same JSON).
    /// Returns nil when the response carries no usage — never throws, a
    /// missing ledger entry must not fail the AI call it describes.
    static func decode(fromResponseBody data: Data) -> AIUsage? {
        struct Envelope: Decodable {
            let usage: UsageBlock?
        }
        struct UsageBlock: Decodable {
            let input_tokens: Int?
            let output_tokens: Int?
            let cache_read_input_tokens: Int?
            let cache_creation_input_tokens: Int?
        }
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              let usage = envelope.usage else {
            return nil
        }
        return AIUsage(
            inputTokens: usage.input_tokens ?? 0,
            outputTokens: usage.output_tokens ?? 0,
            cacheReadTokens: usage.cache_read_input_tokens ?? 0,
            cacheWriteTokens: usage.cache_creation_input_tokens ?? 0
        )
    }
}

/// Task-local attribution for AI calls: set once at the call site via
/// `AIUsageContext.attribute(...)` and read by the API clients when they
/// record usage. Task-locals propagate through `AIRetry.run` (a plain loop)
/// and `withTimeout` (a task group), so there is zero signature ripple.
struct AIUsageContext: Sendable {
    var purpose: AIUsagePurpose
    var meetingID: UUID?

    @TaskLocal static var current: AIUsageContext?

    /// Run `operation` attributed to `purpose`/`meetingID` — unless an outer
    /// call site already attributed it. Outermost wins: a reanalysis pass
    /// wraps the whole intelligence service, and its `.reanalysis` label
    /// must not be overwritten by the service's own initial/final labels.
    // T is Sendable for the sake of CI's older Swift toolchain, which
    // can't prove the result stays on the caller's isolation.
    static func attribute<T: Sendable>(
        _ purpose: AIUsagePurpose,
        meetingID: UUID? = nil,
        isolation: isolated (any Actor)? = #isolation,
        operation: () async throws -> T
    ) async rethrows -> T {
        if current != nil {
            return try await operation()
        }
        return try await $current.withValue(
            AIUsageContext(purpose: purpose, meetingID: meetingID),
            operation: operation,
            isolation: isolation
        )
    }
}

/// Collects usage events into the SwiftData store. Configured with the
/// container at launch; events recorded before that are buffered so nothing
/// is dropped. `record()` is nonisolated so the API clients can call it
/// from any context without hopping actors on the request path.
@MainActor
final class UsageRecorder {
    static let shared = UsageRecorder()

    private var container: ModelContainer?
    private var buffer: [PendingEvent] = []

    struct PendingEvent: Sendable {
        let timestamp: Date
        let purpose: AIUsagePurpose
        let meetingID: UUID?
        let modelIdentifier: String
        let usage: AIUsage
    }

    private init() {}

    func configure(container: ModelContainer) {
        self.container = container
        let buffered = buffer
        buffer = []
        for event in buffered {
            insert(event)
        }
    }

    /// Record one call's usage. Static + nonisolated (same pattern as
    /// `LogManager.send`) so the API clients can call it from any context.
    /// Attribution comes from the caller's task-local `AIUsageContext`;
    /// unattributed paths land as `.other` — an event is never dropped for
    /// missing context.
    nonisolated static func record(modelIdentifier: String, usage: AIUsage) {
        let context = AIUsageContext.current
        let event = PendingEvent(
            timestamp: .now,
            purpose: context?.purpose ?? .other,
            meetingID: context?.meetingID,
            modelIdentifier: modelIdentifier,
            usage: usage
        )
        Task { @MainActor in
            shared.store(event)
        }
    }

    private func store(_ event: PendingEvent) {
        guard container != nil else {
            buffer.append(event)
            return
        }
        insert(event)
    }

    private func insert(_ event: PendingEvent) {
        guard let context = container?.mainContext else { return }
        let row = AIUsageEvent(
            timestamp: event.timestamp,
            meetingID: event.meetingID,
            purpose: event.purpose,
            modelIdentifier: event.modelIdentifier,
            inputTokens: event.usage.inputTokens,
            outputTokens: event.usage.outputTokens,
            cacheReadTokens: event.usage.cacheReadTokens,
            cacheWriteTokens: event.usage.cacheWriteTokens
        )
        context.insert(row)
        PersistenceGate.save(context, site: "UsageRecorder", critical: false, meetingID: event.meetingID)
    }
}
