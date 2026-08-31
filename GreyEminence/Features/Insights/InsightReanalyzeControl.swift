import SwiftUI

struct InsightReanalyzeExtra: Identifiable {
    var id: String
    var title: String
    var systemImage: String
    var action: () -> Void
}

struct InsightReanalyzeControl: View {
    var title: String = "Reanalyze"
    var scope: InsightScope
    var isBusy: Bool
    var canRevert: Bool
    var extras: [InsightReanalyzeExtra] = []
    var onRun: (InsightDepth) -> Void
    var onRevert: () -> Void
    var onViewLog: () -> Void

    var body: some View {
        if isBusy {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(scope == .full ? "Analyzing…" : scope.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } else {
            Menu {
                Button {
                    onRun(.deep)
                } label: {
                    Label("Deep", systemImage: "arrow.down.circle")
                }
                Button {
                    onRun(.deepest)
                } label: {
                    Label("Deepest (use audio energy)", systemImage: "waveform")
                }
                Button {
                    onRevert()
                } label: {
                    Label("Revert to prior", systemImage: "arrow.uturn.backward")
                }
                .disabled(!canRevert)
                Button {
                    onViewLog()
                } label: {
                    Label("View log", systemImage: "clock.arrow.circlepath")
                }
                if !extras.isEmpty {
                    Divider()
                    ForEach(extras) { extra in
                        Button {
                            extra.action()
                        } label: {
                            Label(extra.title, systemImage: extra.systemImage)
                        }
                    }
                }
            } label: {
                Label(title, systemImage: "arrow.clockwise")
                    .font(.caption)
            } primaryAction: {
                onRun(scope == .full ? .standard : .deep)
            }
            .menuStyle(.button)
            .buttonStyle(.bordered)
            .controlSize(.small)
            .fixedSize()
            .help(helpText)
        }
    }

    private var helpText: String {
        if scope == .full {
            "Click: rewrite all insights. Arrow: Deep, Deepest (audio energy), Revert, View log, re-transcribe."
        } else {
            "Click: Deep rewrite of \(scope.label). Arrow: Deep, Deepest (audio energy), Revert, View log."
        }
    }
}
