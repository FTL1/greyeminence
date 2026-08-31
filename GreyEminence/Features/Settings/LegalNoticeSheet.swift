import SwiftUI

/// First-launch (and Help) acknowledgement: unofficial fork, no warranty,
/// lawful-use-only. Stored so we do not nag every launch after Accept.
struct LegalNoticeSheet: View {
    var onAccept: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Grey Conseil")
                .font(.title2.weight(.semibold))
            Text("Unofficial fork of Grey Eminence. Not Matt Purdon’s product.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("The name is homage: Grey Eminence is éminence grise (the unofficial counselor). Grey Conseil keeps the grey and borrows Conseil — counsel, and Verne’s servant in Twenty Thousand Leagues Under the Sea. Help → Why Grey Conseil.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("NO WARRANTY. USE AT YOUR OWN RISK.")
                        .font(.headline)
                    Text("This software is provided AS IS, without warranty of any kind. Recordings, transcripts, and AI output can be wrong or missing. Do not treat this app as a legal hold or the sole record of a meeting.")
                    Text("LAWFUL USE ONLY — YOU ARE RESPONSIBLE.")
                        .font(.headline)
                    Text("Use this software only in a manner that is lawful where you use it, including consent and notice rules for recording calls, workplace and privacy law, and the rules of Teams / Zoom / Meet. Shipping this app does not grant permission to record anyone. It is up to you to know and follow those rules.")
                    Text("Check for Updates uses github.com/\(AppIdentity.githubRepoPath), not Grey Eminence’s update feed.")
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
            }

            HStack {
                Link("Full disclaimer", destination: HelpDocLink.disclaimer)
                Spacer()
                Button("I understand — continue") {
                    onAccept()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520, height: 420)
    }
}

private enum HelpDocLink {
    /// Placeholder URL; the button in Help opens the bundled doc. This sheet
    /// is self-contained so first launch works before Help is used.
    static let disclaimer = URL(string: "https://github.com/\(AppIdentity.githubRepoPath)/blob/feature/speaker-session-rename/docs/DISCLAIMER.md")!
}
