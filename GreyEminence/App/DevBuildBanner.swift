import SwiftUI

/// Floating badge that marks a locally-built Debug run so it can't be
/// mistaken for the installed production app. Compiled out of Release
/// builds entirely — the shipped app has no code path to show this.
struct DevBuildBanner: View {
    #if DEBUG
    private static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "hammer.fill")
                .font(.system(size: 9, weight: .bold))
            Text("DEV BUILD · v\(Self.version)")
                .font(.caption2.weight(.bold))
                .kerning(0.5)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(.orange.gradient, in: Capsule())
        .allowsHitTesting(false)
        .accessibilityLabel("Development build")
    }
    #else
    var body: some View { EmptyView() }
    #endif
}
