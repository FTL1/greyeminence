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

                Spacer(minLength: 8)
            }
            .bottomActivityBarStyle()
            .animation(.easeOut(duration: 0.24), value: current)
            .animation(.easeOut(duration: 0.24), value: completed)
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        if current != nil {
            ProgressView().controlSize(.small)
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
