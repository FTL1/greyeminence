import SwiftUI

/// Tracks which feature affordances the user has already discovered in context,
/// so a "NEW" badge shows until they engage with it. Observable so badges clear
/// reactively the instant `markSeen` fires. Backed by UserDefaults, mirroring
/// ChangelogReadStore.
@Observable
@MainActor
final class FeatureDiscovery {
    static let shared = FeatureDiscovery()

    private static let key = "seenFeatureIDs"
    private(set) var seen: Set<String>

    private init() {
        seen = Set(UserDefaults.standard.stringArray(forKey: Self.key) ?? [])
    }

    func hasSeen(_ id: String) -> Bool { seen.contains(id) }

    func markSeen(_ id: String) {
        guard seen.insert(id).inserted else { return }
        UserDefaults.standard.set(Array(seen), forKey: Self.key)
    }
}

extension View {
    /// Overlays a small "NEW" badge on this affordance until the feature `id`
    /// is marked seen. Pair with a `FeatureDiscovery.shared.markSeen(id)` at the
    /// natural first-interaction point (e.g. when the user opens the popover or
    /// switches to the new tab) so the badge teaches in context, then retires.
    func newFeatureBadge(_ id: String, alignment: Alignment = .topTrailing) -> some View {
        modifier(NewFeatureBadge(featureID: id, alignment: alignment))
    }
}

private struct NewFeatureBadge: ViewModifier {
    let featureID: String
    let alignment: Alignment
    private let discovery = FeatureDiscovery.shared

    func body(content: Content) -> some View {
        content.overlay(alignment: alignment) {
            if !discovery.hasSeen(featureID) {
                Text("NEW")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(.red, in: Capsule())
                    .offset(x: 7, y: -6)
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityLabel("New feature")
            }
        }
    }
}
