import SwiftUI

/// Post-update "What's New" moment: a short, curated set of feature highlights
/// shown once after the app updates to a version the user hasn't seen. Each row
/// can deep-link straight to the feature ("Try it"). Dismissal is recorded by
/// the presenter (ContentView) so it never re-nags.
struct WhatsNewSheet: View {
    let highlights: [FeatureHighlight]
    let version: String
    /// Invoked with the chosen highlight when the user taps "Try it". The
    /// presenter dismisses, navigates, and marks the feature discovered.
    let onTry: (FeatureHighlight) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.tint)
                Text("What's New")
                    .font(.title2.bold())
                Text("Version \(version)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 24)
            .padding(.bottom, 16)

            Divider()

            ScrollView {
                VStack(spacing: 18) {
                    ForEach(highlights) { highlight in
                        row(highlight)
                    }
                }
                .padding(20)
            }
            .frame(maxHeight: 380)

            Divider()

            Button {
                dismiss()
            } label: {
                Text("Got it")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .padding(16)
        }
        .frame(width: 460)
    }

    private func row(_ highlight: FeatureHighlight) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: highlight.systemImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(highlight.tint.gradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(highlight.title)
                    .font(.headline)
                Text(highlight.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if highlight.destination != nil {
                    Button {
                        onTry(highlight)
                    } label: {
                        Label("Try it", systemImage: "arrow.right.circle.fill")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.borderless)
                    .padding(.top, 2)
                }
            }

            Spacer(minLength: 0)
        }
    }
}
