import Foundation
import SwiftUI

/// One-shot background activity that wants a footer indicator. The
/// re-processing queue has its own bar because its work is long and
/// progress-tracked; this coordinator handles fire-and-forget tasks
/// like rubric seeding and the startup maintenance pass — short,
/// indeterminate, and worth surfacing so the user can see the app
/// is doing something on launch.
@Observable
@MainActor
final class TransientActivityCoordinator {
    static let shared = TransientActivityCoordinator()
    private init() {}

    /// Minimum time a "running" indicator stays visible. Without this,
    /// fast tasks (e.g. a 5ms idempotent seed that no-ops) would flash
    /// faster than the user can read the label.
    private static let minimumVisibleDuration: TimeInterval = 1.0
    /// How long the "completed" checkmark stays after the activity
    /// finishes before the bar collapses.
    private static let completionVisibleDuration: TimeInterval = 2.0

    struct Activity: Identifiable, Equatable {
        let id = UUID()
        let label: String
        let startedAt: Date

        static func == (lhs: Activity, rhs: Activity) -> Bool { lhs.id == rhs.id }
    }

    private(set) var current: Activity?
    private(set) var lastCompleted: Activity?
    private var clearCompletionTask: Task<Void, Never>?

    /// Run a synchronous block of work, surfacing `label` in the footer
    /// while it runs. Use the async overload for awaitable work.
    @discardableResult
    func run<T>(_ label: String, _ work: () throws -> T) rethrows -> T {
        let activity = beginActivity(label: label)
        defer { Task { await endActivity(activity) } }
        return try work()
    }

    @discardableResult
    func runAsync<T: Sendable>(_ label: String, _ work: () async throws -> T) async rethrows -> T {
        let activity = beginActivity(label: label)
        defer { Task { await endActivity(activity) } }
        return try await work()
    }

    /// Surface a one-line "completed" notification without an associated
    /// running phase — useful for e.g. logging that maintenance found
    /// nothing to do without flashing a spinner.
    func flash(_ label: String) {
        let activity = Activity(label: label, startedAt: .now)
        clearCompletionTask?.cancel()
        current = nil
        lastCompleted = activity
        clearCompletionTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.completionVisibleDuration))
            guard let self, self.lastCompleted == activity else { return }
            self.lastCompleted = nil
        }
    }

    private func beginActivity(label: String) -> Activity {
        clearCompletionTask?.cancel()
        let activity = Activity(label: label, startedAt: .now)
        current = activity
        return activity
    }

    private func endActivity(_ activity: Activity) async {
        let elapsed = Date.now.timeIntervalSince(activity.startedAt)
        let remaining = Self.minimumVisibleDuration - elapsed
        if remaining > 0 {
            try? await Task.sleep(for: .seconds(remaining))
        }
        guard current?.id == activity.id else { return }
        current = nil
        lastCompleted = activity
        clearCompletionTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.completionVisibleDuration))
            guard let self, self.lastCompleted == activity else { return }
            self.lastCompleted = nil
        }
    }
}
