import SwiftUI

/// Canvas-drawn timeline over the full meeting duration: cyan bands for
/// share sessions, ticks at kept frames (real changes brighter than
/// visual-only churn), yellow markers for OCR-search matches, and a
/// draggable playhead. Click or drag anywhere to seek.
struct TimelineScrubber: View {
    let model: ScreenSharePlayerModel

    @State private var trackWidth: CGFloat = 0

    private static let height: CGFloat = 28

    var body: some View {
        Canvas { context, size in
            let duration = max(model.meetingDuration, 1)
            func x(_ time: TimeInterval) -> CGFloat {
                CGFloat(time / duration) * size.width
            }

            // Baseline
            context.fill(
                Path(CGRect(x: 0, y: size.height / 2 - 0.5, width: size.width, height: 1)),
                with: .color(.secondary.opacity(0.25))
            )

            // Session bands
            for session in model.sessions {
                let rect = CGRect(
                    x: x(session.startTime),
                    y: 4,
                    width: max(x(session.endTime) - x(session.startTime), 3),
                    height: size.height - 8
                )
                context.fill(
                    Path(roundedRect: rect, cornerRadius: 3),
                    with: .color(.cyan.opacity(0.22))
                )
            }

            // Frame ticks
            for frame in model.frames {
                let tick = CGRect(x: x(frame.timestamp) - 1, y: 7, width: 2, height: size.height - 14)
                let alpha = frame.isVisualOnlyChange ? 0.35 : 0.8
                context.fill(Path(tick), with: .color(.cyan.opacity(alpha)))
            }

            // OCR match markers
            for index in model.matchIndices where model.frames.indices.contains(index) {
                let cx = x(model.frames[index].timestamp)
                var diamond = Path()
                diamond.move(to: CGPoint(x: cx, y: 2))
                diamond.addLine(to: CGPoint(x: cx + 4, y: 6))
                diamond.addLine(to: CGPoint(x: cx, y: 10))
                diamond.addLine(to: CGPoint(x: cx - 4, y: 6))
                diamond.closeSubpath()
                context.fill(diamond, with: .color(.yellow))
            }

            // Playhead
            if let frame = model.currentFrame {
                let cx = x(frame.timestamp)
                context.fill(
                    Path(CGRect(x: cx - 1, y: 0, width: 2, height: size.height)),
                    with: .color(.primary.opacity(0.85))
                )
                context.fill(
                    Path(ellipseIn: CGRect(x: cx - 4, y: size.height - 9, width: 8, height: 8)),
                    with: .color(.primary)
                )
            }
        }
        .frame(height: Self.height)
        .contentShape(Rectangle())
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            trackWidth = width
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard trackWidth > 0 else { return }
                    let fraction = min(max(value.location.x / trackWidth, 0), 1)
                    model.pause()
                    model.seek(to: Double(fraction) * model.meetingDuration)
                }
        )
        .overlay(alignment: .bottomLeading) {
            Text("0:00")
                .font(.caption2)
                .fontDesign(.monospaced)
                .foregroundStyle(.tertiary)
                .offset(y: 12)
        }
        .overlay(alignment: .bottomTrailing) {
            Text(Self.format(model.meetingDuration))
                .font(.caption2)
                .fontDesign(.monospaced)
                .foregroundStyle(.tertiary)
                .offset(y: 12)
        }
        .padding(.bottom, 12)
    }

    static func format(_ time: TimeInterval) -> String {
        let total = Int(time)
        if total >= 3600 {
            return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
        }
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
