import SwiftData
import SwiftUI

/// Horizontal keyframe strip beneath the player stage. Auto-follows
/// playback, click seeks, context menu carries the frame actions.
struct FilmstripView: View {
    let model: ScreenSharePlayerModel
    let meeting: Meeting

    @Environment(\.modelContext) private var modelContext
    @State private var deleteTarget: ScreenSharePlayerModel.FrameItem?
    @State private var deleteSessionTarget: UUID?

    private static let thumbSize = CGSize(width: 80, height: 50)

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 4) {
                    ForEach(Array(model.frames.enumerated()), id: \.element.id) { index, frame in
                        thumb(frame: frame, index: index)
                            .id(frame.id)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
            }
            .onChange(of: model.currentIndex) {
                guard let frame = model.currentFrame else { return }
                withAnimation(.easeInOut(duration: 0.15)) {
                    proxy.scrollTo(frame.id, anchor: .center)
                }
            }
        }
        .frame(height: Self.thumbSize.height + 8)
        .confirmationDialog(
            "Delete this frame?",
            isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } })
        ) {
            Button("Delete Frame", role: .destructive) {
                if let target = deleteTarget {
                    model.deleteFrame(target, meeting: meeting, context: modelContext)
                }
                deleteTarget = nil
            }
        } message: {
            Text("Deletes the image and its analysis. This cannot be undone.")
        }
        .confirmationDialog(
            "Delete this entire share session?",
            isPresented: Binding(get: { deleteSessionTarget != nil }, set: { if !$0 { deleteSessionTarget = nil } })
        ) {
            Button("Delete Session", role: .destructive) {
                if let target = deleteSessionTarget {
                    model.deleteSession(target, meeting: meeting, context: modelContext)
                }
                deleteSessionTarget = nil
            }
        } message: {
            Text("Deletes every frame captured in this share session. This cannot be undone.")
        }
    }

    @ViewBuilder
    private func thumb(frame: ScreenSharePlayerModel.FrameItem, index: Int) -> some View {
        let isCurrent = index == model.currentIndex
        FrameThumbView(url: frame.imageURL, size: Self.thumbSize)
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(isCurrent ? Color.accentColor : .clear, lineWidth: 2)
            )
            .overlay(alignment: .topTrailing) {
                if model.analyzingFrameIDs.contains(frame.id) {
                    ProgressView()
                        .controlSize(.mini)
                        .padding(2)
                }
            }
            .onTapGesture {
                model.select(frameID: frame.id)
            }
            .contextMenu {
                frameActions(frame)
            }
            .help("[\(frame.formattedTimestamp)] \(frame.observation ?? frame.ocrText?.components(separatedBy: "\n").first ?? "")")
    }

    @ViewBuilder
    private func frameActions(_ frame: ScreenSharePlayerModel.FrameItem) -> some View {
        Button("Copy Image") { model.copyImage(frame) }
        Button("Copy Recognized Text") { model.copyOCRText(frame) }
            .disabled(frame.ocrText?.isEmpty ?? true)
        Button("Open Image") { model.openImage(frame) }
        if frame.observation == nil {
            Button("Analyze This Frame") {
                Task { await model.analyzeNow(frame, meeting: meeting, context: modelContext) }
            }
        }
        Divider()
        Button("Delete Frame…", role: .destructive) { deleteTarget = frame }
        Button("Delete This Share Session…", role: .destructive) { deleteSessionTarget = frame.sessionID }
    }
}

/// Async cached thumbnail for one frame image.
struct FrameThumbView: View {
    let url: URL
    let size: CGSize

    @State private var image: CGImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(.quaternary)
            if let image {
                Image(decorative: image, scale: 2)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            } else {
                Image(systemName: "photo")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: size.width, height: size.height)
        .task(id: url) {
            image = await FrameThumbnailCache.shared.thumbnail(at: url, size: .strip)
        }
    }
}
