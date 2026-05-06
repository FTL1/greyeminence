import SwiftUI

/// Shared chrome for the bottom-of-window activity bars (re-processing
/// queue, transient seeds/maintenance). Centralizes the padding,
/// height, top separator, material background, and entrance/exit
/// transition that both bars use.
struct BottomActivityBarStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(alignment: .top) {
                Rectangle()
                    .fill(.separator)
                    .frame(height: 0.5)
            }
            .background(.bar)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

extension View {
    func bottomActivityBarStyle() -> some View {
        modifier(BottomActivityBarStyle())
    }
}
