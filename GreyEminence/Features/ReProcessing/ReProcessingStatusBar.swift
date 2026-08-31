import SwiftUI
import AppKit

/// Xcode-style activity bar anchored at the bottom of the main window.
/// Visible only when the re-processing queue has work or just finished some.
struct ReProcessingStatusBar: View {
    @Bindable var queue: ReProcessingQueue = .shared

    @State private var isHovering = false

    private var isActive: Bool {
        queue.current != nil || !queue.pending.isEmpty
    }

    private var recentlyCompleted: Bool {
        queue.lastCompleted != nil
    }

    var body: some View {
        if isActive || recentlyCompleted {
            HStack(spacing: 10) {
                statusIcon
                    .frame(width: 16, height: 16)

                textStack

                Spacer(minLength: 8)

                if queue.pending.count > 0 {
                    StatusPill(label: "+\(queue.pending.count) queued", tint: .secondary)
                }

                if isActive && isHovering {
                    if queue.current != nil {
                        Button {
                            queue.cancelCurrent()
                        } label: {
                            Image(systemName: "forward.end.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Skip this meeting (keep queue)")
                    }
                    if !queue.pending.isEmpty || queue.current != nil {
                        Button {
                            queue.cancelAll()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Cancel everything")
                    }
                }
            }
            .bottomActivityBarStyle()
            .onHover { isHovering = $0 }
            .animation(.easeOut(duration: 0.24), value: isActive)
            .animation(.easeOut(duration: 0.24), value: recentlyCompleted)
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        if let fraction = queue.current?.progressFraction {
            ProgressView(value: fraction)
                .progressViewStyle(.circular)
                .controlSize(.small)
        } else if isActive {
            ProgressView().controlSize(.small)
        } else if recentlyCompleted {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(.green)
        }
    }

    @ViewBuilder
    private var textStack: some View {
        if let job = queue.current {
            HStack(spacing: 6) {
                Text(job.title.isEmpty ? "Preparing…" : job.title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(detailText(for: job))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .monospacedDigit()
            }
        } else if !queue.pending.isEmpty {
            Text("Waiting for live recording to finish")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        } else if let done = queue.lastCompleted {
            HStack(spacing: 6) {
                Text("Upgraded")
                    .font(.caption.weight(.medium))
                Text(done.title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private func detailText(for job: ReProcessingQueue.RunningJob) -> String {
        if job.phase == .transcribing, job.chunksTotal > 0 {
            let pct = Int((job.progressFraction ?? 0) * 100)
            return "\(job.phase.stepDescription) — \(job.chunksDone)/\(job.chunksTotal) chunks (\(pct)%)"
        }
        return job.phase.stepDescription
    }
}

struct MeetingReanalysisStatusBar: View {
    @Bindable var queue: MeetingReanalysisQueue = .shared
    var onOpenMeeting: ((UUID) -> Void)?
    @Environment(\.modelContext) private var modelContext
    @State private var showFailures = false

    private var hasFailures: Bool { !queue.failures.isEmpty || queue.failedCount > 0 }

    var body: some View {
        if queue.isRunning || queue.lastError != nil || queue.lastSummary != nil {
            HStack(spacing: 10) {
                statusIcon
                Button {
                    if hasFailures { showFailures = true }
                } label: {
                    HStack(spacing: 8) {
                        statusText
                        if queue.failedCount > 0 {
                            Text("\(queue.failedCount) failed")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.orange)
                                .underline()
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!hasFailures)
                .help(hasFailures ? "Show which meetings failed and why" : "")
                Spacer(minLength: 8)
                if queue.isRunning {
                    Button {
                        queue.cancel()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Cancel remaining reanalyze jobs")
                } else {
                    Button {
                        queue.dismissBanner()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Dismiss")
                }
            }
            .bottomActivityBarStyle()
            .sheet(isPresented: $showFailures) {
                ReanalysisFailureSheet(
                    failures: queue.failures,
                    lastError: queue.lastError,
                    isRunning: queue.isRunning,
                    onRetry: {
                        let ids = queue.failures.compactMap(\.meetingID)
                        showFailures = false
                        if !ids.isEmpty {
                            queue.enqueue(ids: ids, in: modelContext)
                        }
                    },
                    onOpenMeeting: { id in
                        showFailures = false
                        onOpenMeeting?(id)
                    }
                )
            }
        }
    }

    @ViewBuilder
    private var statusText: some View {
        if let job = queue.current {
            Text("Reanalyzing \(job.index)/\(job.total): \(job.title)")
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)
        } else if !queue.pending.isEmpty {
            Text("Reanalyze queued: \(queue.pending.count)")
                .font(.caption.weight(.medium))
        } else if let summary = queue.lastSummary {
            Text(summary)
                .font(.caption.weight(.medium))
        } else if let error = queue.lastError {
            Text(error)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        if queue.isRunning {
            ProgressView().controlSize(.small)
        } else if queue.failedCount > 0 || queue.lastError != nil {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 13))
        } else {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.system(size: 13))
        }
    }
}

struct ReanalysisFailureSheet: View {
    let failures: [MeetingReanalysisQueue.Failure]
    let lastError: String?
    var isRunning: Bool = false
    var onRetry: () -> Void
    var onOpenMeeting: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss

    private var retryableCount: Int { failures.compactMap(\.meetingID).count }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Reanalyze failed", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .symbolRenderingMode(.multicolor)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)

            Divider()

            if failures.isEmpty {
                ContentUnavailableView(
                    "No failure details",
                    systemImage: "exclamationmark.triangle",
                    description: Text(lastError ?? "The last run reported a failure but did not record which meeting.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(failures) { failure in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(failure.title)
                                .font(.body.weight(.semibold))
                                .textSelection(.enabled)
                            Spacer()
                            Text(failure.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(failure.message)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .textSelection(.enabled)
                        HStack {
                            Button("Copy error") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(
                                    "\(failure.title)\n\(failure.date.formatted())\n\(failure.message)",
                                    forType: .string
                                )
                            }
                            .controlSize(.small)
                            if let meetingID = failure.meetingID {
                                Button("Open meeting") {
                                    onOpenMeeting(meetingID)
                                }
                                .controlSize(.small)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Divider()
            HStack {
                Text(failures.count == 1 ? "1 meeting failed" : "\(failures.count) meetings failed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Retry failed") { onRetry() }
                    .disabled(retryableCount == 0 || isRunning)
                    .help(isRunning ? "Wait for the current queue to finish" : "Reanalyze the meetings that failed")
                    .keyboardShortcut("r", modifiers: [.command])
                Button("Close") { dismiss() }
            }
            .padding(16)
        }
        .frame(minWidth: 520, minHeight: 360)
    }
}
