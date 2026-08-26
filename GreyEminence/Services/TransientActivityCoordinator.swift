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

    /// Countable progress for an activity that knows how much work it has.
    /// Optional because most transient work is genuinely indeterminate — a
    /// spinner is the honest indicator for a maintenance sweep, and a fake
    /// bar would be worse than none.
    struct Progress: Equatable {
        var completed: Int
        var total: Int

        var fraction: Double {
            total > 0 ? min(1, Double(completed) / Double(total)) : 0
        }
    }

    struct Activity: Identifiable, Equatable {
        let id = UUID()
        let label: String
        let startedAt: Date
        var progress: Progress?

        /// Identity only. Progress ticks reassign `current` many times a
        /// second, and equality drives the bar's appear/disappear animation —
        /// comparing progress too would re-animate the whole bar on every tick.
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

    /// Report progress for whatever is currently running.
    ///
    /// Addressed to "the running activity" rather than to a handle because
    /// only one transient activity is ever in flight — the re-processing
    /// queue, which genuinely overlaps, has its own bar. A late tick from a
    /// finished activity lands after `current` is nil and is dropped.
    func setProgress(completed: Int, total: Int) {
        guard current != nil, total > 0 else { return }
        current?.progress = Progress(completed: completed, total: total)
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
