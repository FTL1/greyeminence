import SwiftData
import SwiftUI

/// Time-lapse player for a finished meeting's captured screen share.
/// Collapsed: a one-line card with a mini filmstrip. Expanded: stage +
/// transport + timeline + filmstrip, kept co-visible with the transcript
/// inspector for two-way sync.
struct ScreenSharePlayerSection: View {
    @Bindable var meeting: Meeting
    /// Set by the transcript panel (timestamp tap) or an Ask deep link; the
    /// section consumes it: expand, seek, clear.
    @Binding var pendingSeekTime: TimeInterval?
    /// Player → transcript: fired with the nearest final segment's ID as the
    /// playhead crosses segment boundaries (throttled).
    var onPlayheadSegment: ((UUID) -> Void)?
    /// Set by the Reanalyze menu's "Re-analyze screen shares" item; the
    /// section consumes it: expand, wipe + redo all frame observations and
    /// recaps, clear.
    var reanalyzeSharesTrigger: Binding<Bool> = .constant(false)

    @Environment(\.modelContext) private var modelContext
    @State private var model: ScreenSharePlayerModel?
    @State private var isExpanded = false
    @State private var lastPushedSegmentID: UUID?
    @State private var lastPushAt: Date = .distantPast

    private static let miniThumbLimit = 8

    var body: some View {
        if meeting.screenFrames.isEmpty {
            EmptyView()
        } else {
            content
                .onAppear {
                    if model == nil {
                        model = ScreenSharePlayerModel(meeting: meeting)
                    }
                }
                .onDisappear {
                    model?.pause()
                }
                .onChange(of: meeting.screenFrames.count) {
                    model?.refresh(from: meeting)
                }
                .onChange(of: pendingSeekTime) {
                    guard let time = pendingSeekTime else { return }
                    isExpanded = true
                    model?.seek(to: time)
                    pendingSeekTime = nil
                }
                .onChange(of: reanalyzeSharesTrigger.wrappedValue) {
                    guard reanalyzeSharesTrigger.wrappedValue else { return }
                    reanalyzeSharesTrigger.wrappedValue = false
                    guard let model else { return }
                    withAnimation(.easeInOut(duration: 0.2)) { isExpanded = true }
                    Task { await model.reanalyzeAllShares(meeting: meeting, context: modelContext) }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if isExpanded, let model {
                expandedPlayer(model)
            } else if let model {
                miniFilmstrip(model)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.5))
        )
        .padding(.horizontal)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "play.rectangle.on.rectangle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Color.cyan.gradient, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text("Screen Share")
                .font(.headline)
            if let model {
                Text(badgeText(model))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let model, model.hasUnanalyzedFrames || model.isBulkAnalyzing {
                if model.isBulkAnalyzing {
                    HStack(spacing: 4) {
                        ProgressView()
                            .controlSize(.mini)
                        if let progress = model.bulkProgress {
                            Text("\(progress.done)/\(progress.total)")
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Button {
                        Task { await model.analyzeAllFrames(meeting: meeting, context: modelContext) }
                    } label: {
                        Label("Analyze Frames", systemImage: "brain")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Run Claude vision on frames that don't have an observation yet")
                }
            }
            Image(systemName: "chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isExpanded ? 0 : -90))
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            if !isExpanded { model?.pause() }
        }
    }

    private func badgeText(_ model: ScreenSharePlayerModel) -> String {
        let sessions = model.sessions.count
        return "\(model.frames.count) frames · \(sessions) session\(sessions == 1 ? "" : "s")"
    }

    // MARK: - Collapsed

    private func miniFilmstrip(_ model: ScreenSharePlayerModel) -> some View {
        // Evenly-sampled preview thumbs; clicking one expands + seeks.
        let step = max(1, model.frames.count / Self.miniThumbLimit)
        let sampled = stride(from: 0, to: model.frames.count, by: step)
            .prefix(Self.miniThumbLimit)
            .map { model.frames[$0] }
        return HStack(spacing: 4) {
            ForEach(sampled) { frame in
                FrameThumbView(url: frame.imageURL, size: CGSize(width: 64, height: 40))
                    .onTapGesture {
                        model.select(frameID: frame.id)
                        withAnimation(.easeInOut(duration: 0.2)) { isExpanded = true }
                    }
            }
        }
    }

    // MARK: - Expanded

    @ViewBuilder
    private func expandedPlayer(_ model: ScreenSharePlayerModel) -> some View {
        VStack(spacing: 8) {
            stage(model)
            transport(model)
            TimelineScrubber(model: model)
            FilmstripView(model: model, meeting: meeting)
            sessionRecap(model)
        }
        .onChange(of: model.currentIndex) {
            pushNearestSegment(model)
        }
    }

    /// Narrative recap for the session under the playhead; key moments seek
    /// on click. Sessions without a recap get a "Generate Recaps" backfill.
    @ViewBuilder
    private func sessionRecap(_ model: ScreenSharePlayerModel) -> some View {
        if let sessionID = model.currentFrame?.sessionID {
            if let recap = model.recapsBySession[sessionID] {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(recap.narrative)
                            .font(.callout)
                            .textSelection(.enabled)
                        ForEach(Array(recap.keyMoments.enumerated()), id: \.offset) { _, moment in
                            Button {
                                model.seek(to: moment.timestamp)
                            } label: {
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text(Self.formatElapsed(moment.timestamp))
                                        .font(.caption)
                                        .fontDesign(.monospaced)
                                        .foregroundStyle(.cyan)
                                    Text(moment.label)
                                        .font(.caption)
                                        .foregroundStyle(.primary)
                                        .multilineTextAlignment(.leading)
                                }
                            }
                            .buttonStyle(.plain)
                            .help("Jump the player to this moment")
                        }
                    }
                    .padding(.top, 4)
                } label: {
                    Label("Session recap", systemImage: "text.append")
                        .font(.caption.weight(.semibold))
                }
            } else if model.hasSessionsWithoutRecaps || model.isGeneratingRecaps {
                HStack(spacing: 6) {
                    if model.isGeneratingRecaps {
                        ProgressView().controlSize(.mini)
                        Text("Generating recaps…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Button {
                            Task { await model.generateRecaps(meeting: meeting, context: modelContext) }
                        } label: {
                            Label("Generate Recaps", systemImage: "text.append")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Synthesize a narrative recap for each share session from its analyzed frames and the transcript")
                    }
                    Spacer()
                }
            }
        }
    }

    private static func formatElapsed(_ elapsed: TimeInterval) -> String {
        String(format: "%d:%02d", Int(elapsed) / 60, Int(elapsed) % 60)
    }

    /// The stage hugs the frame image's own aspect ratio, left-aligned over
    /// the transport controls, with the frame's full observation in a
    /// scrollable panel attached to its right — no more two-line caption
    /// truncating the detailed descriptions.
    @ViewBuilder
    private func stage(_ model: ScreenSharePlayerModel) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if let frame = model.currentFrame {
                StageImageView(url: frame.imageURL, maxHeight: 340)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .contextMenu {
                        Button("Copy Image") { model.copyImage(frame) }
                        Button("Copy Recognized Text") { model.copyOCRText(frame) }
                            .disabled(frame.ocrText?.isEmpty ?? true)
                        Button("Open Image") { model.openImage(frame) }
                    }
                frameInfoPanel(frame, model: model)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.black.opacity(0.85))
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                }
                .frame(width: 420, height: 260)
            }
            Spacer(minLength: 0)
        }
    }

    /// Side panel with the frame's complete observation (scrollable,
    /// selectable), or the analysis/OCR fallback states.
    @ViewBuilder
    private func frameInfoPanel(_ frame: ScreenSharePlayerModel.FrameItem, model: ScreenSharePlayerModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(frame.formattedTimestamp)
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .foregroundStyle(.secondary)
                if let type = frame.contentType {
                    Text(type.uppercased())
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.cyan.opacity(0.15), in: Capsule())
                        .foregroundStyle(.cyan)
                }
                Spacer(minLength: 0)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    if let observation = frame.observation {
                        Text(observation)
                            .font(.caption)
                            .textSelection(.enabled)
                    } else if model.analyzingFrameIDs.contains(frame.id) {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.mini)
                            Text("Analyzing…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if let firstLine = frame.ocrText?.components(separatedBy: "\n").first, !firstLine.isEmpty {
                        Label {
                            Text(firstLine)
                                .font(.caption)
                                .italic()
                        } icon: {
                            Image(systemName: "text.viewfinder")
                                .font(.caption2)
                        }
                        .foregroundStyle(.secondary)
                    } else {
                        Text("No analysis for this frame")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(8)
        .frame(width: 260)
        .frame(maxHeight: 340)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private func transport(_ model: ScreenSharePlayerModel) -> some View {
        HStack(spacing: 10) {
            Button { model.step(-1) } label: { Image(systemName: "backward.frame.fill") }
                .buttonStyle(.plain)
                .help("Previous frame")
            Button { model.togglePlayback() } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .help(model.isPlaying ? "Pause" : "Play time-lapse")
            Button { model.step(1) } label: { Image(systemName: "forward.frame.fill") }
                .buttonStyle(.plain)
                .help("Next frame")

            Picker("Speed", selection: Bindable(model).dwell) {
                ForEach(ScreenSharePlayerModel.Dwell.allCases) { dwell in
                    Text(dwell.label).tag(dwell)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            if let frame = model.currentFrame {
                Text("\(frame.formattedTimestamp) / \(TimelineScrubber.format(model.meetingDuration))")
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .foregroundStyle(.secondary)
                Text("· \(model.currentIndex + 1)/\(model.frames.count)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            searchField(model)
        }
    }

    @ViewBuilder
    private func searchField(_ model: ScreenSharePlayerModel) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "text.magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Find on screen", text: Bindable(model).searchText)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .frame(width: 140)
                .onSubmit { model.nextMatch() }
            if !model.matchIndices.isEmpty {
                Text("\(model.matchIndices.count)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Button { model.previousMatch() } label: { Image(systemName: "chevron.up") }
                    .buttonStyle(.plain)
                Button { model.nextMatch() } label: { Image(systemName: "chevron.down") }
                    .buttonStyle(.plain)
            } else if model.searchText.count >= 2 {
                Text("0")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Transcript sync

    /// Push the nearest final segment when it changes, at most every 2s
    /// while playing — the transcript panel's own highlight does the rest.
    private func pushNearestSegment(_ model: ScreenSharePlayerModel) {
        guard let onPlayheadSegment else { return }
        let playhead = model.playhead
        let nearest = meeting.segments
            .filter(\.isFinal)
            .min(by: { abs($0.startTime - playhead) < abs($1.startTime - playhead) })
        guard let nearest, nearest.id != lastPushedSegmentID else { return }
        if model.isPlaying && Date().timeIntervalSince(lastPushAt) < 2 { return }
        lastPushedSegmentID = nearest.id
        lastPushAt = Date()
        onPlayheadSegment(nearest.id)
    }
}

/// Aspect-fit stage image at higher resolution than the strip thumbs.
/// Sizes itself to the image's own aspect ratio, capped at `maxHeight` —
/// no letterboxing canvas around it.
private struct StageImageView: View {
    let url: URL
    let maxHeight: CGFloat

    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 2)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: maxHeight)
            } else {
                ZStack {
                    Color.black.opacity(0.85)
                    ProgressView()
                        .controlSize(.small)
                }
                .frame(width: 420, height: min(260, maxHeight))
            }
        }
        .task(id: url) {
            image = await FrameThumbnailCache.shared.thumbnail(at: url, size: .stage)
        }
    }
}
