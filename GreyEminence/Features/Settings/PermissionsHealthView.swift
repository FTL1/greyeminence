import AppKit
import SwiftUI

/// Developer pane: every permission and credential Grey Conseil uses.
struct PermissionsHealthView: View {
    @State private var report: PermissionsHealth.Report?
    @State private var running = false
    @State private var validating = false
    @State private var copyNote: String?
    @State private var validationNotes: [String: String] = [:]

    var body: some View {
        Section {
            Text("Ad-hoc DMGs reset TCC. This list is this binary, not an older Grey Conseil in Applications. Refresh after granting in System Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let report {
                Text(report.summary)
                    .foregroundStyle(report.problemCount == 0 ? .green : .orange)
                Text("\(report.okCount) ok · \(report.warningCount) warning · \(report.problemCount) missing/denied")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button {
                    refresh(requestCapture: false)
                } label: {
                    if running {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Refresh")
                    }
                }
                .disabled(running || validating)

                Button("Request missing") {
                    Task {
                        running = true
                        await PermissionsHealth.requestMissing()
                        report = await PermissionsHealth.snapshot(requestCaptureIfNeeded: false)
                        running = false
                    }
                }
                .disabled(running || validating)

                Button("Validate AI keys") {
                    Task { await validateKeys() }
                }
                .disabled(running || validating)

                Button("Copy report") {
                    guard let report else { return }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(report.logText, forType: .string)
                    copyNote = "Copied permissions report"
                }
                .disabled(report == nil)
            }

            if validating {
                Text("Pinging Anthropic / xAI…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let copyNote {
                Text(copyNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let report {
                ForEach(report.items) { item in
                    permissionRow(item)
                }

                LabeledContent("Bundle ID") {
                    Text(report.bundleID).font(.caption).textSelection(.enabled)
                }
                LabeledContent("Path") {
                    Text(report.bundlePath)
                        .font(.caption)
                        .textSelection(.enabled)
                        .lineLimit(3)
                }
                LabeledContent("Signing") {
                    Text(report.signing)
                        .font(.caption)
                        .textSelection(.enabled)
                }
            }
        } header: {
            Label("Permissions", systemImage: "lock.shield")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .textCase(nil)
        }
        .task {
            if report == nil {
                refresh(requestCapture: false)
            }
        }
    }

    @ViewBuilder
    private func permissionRow(_ item: PermissionsHealth.Item) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: icon(for: rowVerdict(item)))
                    .foregroundStyle(color(for: rowVerdict(item)))
                Text(item.title)
                Spacer()
                Text(displayVerdict(item))
                    .font(.caption)
                    .foregroundStyle(color(for: rowVerdict(item)))
            }
            Text(displayDetail(item))
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            HStack {
                if item.privacyPane != nil {
                    Button("Open System Settings") {
                        openPane(item.privacyPane)
                    }
                    .font(.caption)
                }
                if item.id == "systemAudio" {
                    Button("Test tap") {
                        replaceItem(PermissionsHealth.probeSystemAudioTap())
                    }
                    .font(.caption)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func rowVerdict(_ item: PermissionsHealth.Item) -> PermissionsHealth.Verdict {
        guard let note = validationNotes[item.id] else { return item.verdict }
        return note.hasPrefix("valid") ? .ok : .denied
    }

    private func displayVerdict(_ item: PermissionsHealth.Item) -> String {
        if let note = validationNotes[item.id] {
            return note.hasPrefix("valid") ? "validated" : "invalid"
        }
        return item.verdict.label
    }

    private func displayDetail(_ item: PermissionsHealth.Item) -> String {
        if let note = validationNotes[item.id] {
            return "\(item.detail) · \(note)"
        }
        return item.detail
    }

    private func icon(for verdict: PermissionsHealth.Verdict) -> String {
        switch verdict {
        case .ok: "checkmark.circle.fill"
        case .denied, .missing: "xmark.circle.fill"
        case .notDetermined, .warning: "exclamationmark.triangle.fill"
        case .skipped: "minus.circle"
        }
    }

    private func color(for verdict: PermissionsHealth.Verdict) -> Color {
        switch verdict {
        case .ok: .green
        case .denied, .missing: .red
        case .notDetermined, .warning: .orange
        case .skipped: .secondary
        }
    }

    private func openPane(_ pane: String?) {
        guard let pane else { return }
        AudioSessionManager.openPrivacyPane(pane)
    }

    private func replaceItem(_ item: PermissionsHealth.Item) {
        guard var report else { return }
        if let idx = report.items.firstIndex(where: { $0.id == item.id }) {
            report.items[idx] = item
        } else {
            report.items.append(item)
        }
        self.report = report
    }

    private func refresh(requestCapture: Bool) {
        running = true
        copyNote = nil
        Task {
            report = await PermissionsHealth.snapshot(requestCaptureIfNeeded: requestCapture)
            running = false
        }
    }

    private func validateKeys() async {
        validating = true
        copyNote = nil
        validationNotes = await PermissionsHealth.validateStoredKeys()
        validating = false
    }
}
