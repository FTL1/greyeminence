import SwiftUI

/// Footer indicator for short one-shot background activity (seeding,
/// maintenance). Sibling of `ReProcessingStatusBar`; both can be
/// visible at once, but in practice only one fires at a time.
struct TransientActivityStatusBar: View {
    @Bindable var coordinator: TransientActivityCoordinator = .shared

    private var current: TransientActivityCoordinator.Activity? { coordinator.current }
    private var completed: TransientActivityCoordinator.Activity? { coordinator.lastCompleted }

    var body: some View {
        if current != nil || completed != nil {
            HStack(spacing: 10) {
                statusIcon
                    .frame(width: 16, height: 16)

                Text(displayLabel)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let progress = current?.progress {
                    ProgressView(value: progress.fraction)
                        .progressViewStyle(.linear)
                        .frame(width: 120)
                    Text("\(progress.completed) of \(progress.total)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)
            }
            .bottomActivityBarStyle()
            .animation(.easeOut(duration: 0.24), value: current)
            .animation(.easeOut(duration: 0.24), value: completed)
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        if let current {
            // The spinner is redundant next to a determinate bar, but keeping
            // the slot occupied stops the label jumping left when progress
            // arrives a moment after the activity starts.
            if current.progress == nil {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "arrow.trianglehead.2.clockwise")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        } else if completed != nil {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(.green)
        }
    }

    private var displayLabel: String {
        if let current { return current.label }
        if let completed { return completed.label }
        return ""
    }
}
