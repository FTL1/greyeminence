import SwiftUI
import SwiftData
import AppKit

struct ArchiveExtractSheet: View {
    let launch: ArchiveExtractLaunch
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Meeting.date, order: .reverse) private var library: [Meeting]

    @State private var request = ArchiveExtractRequest()
    @State private var isExporting = false
    @State private var errorMessage: String?

    private var pool: [Meeting] {
        library.filter { !$0.isInterviewMeeting }
    }

    private var seed: Meeting? {
        if let id = launch.seedMeetingID {
            return pool.first { $0.id == id }
        }
        return nil
    }

    private var resolvedMeetings: [Meeting] {
        ArchiveExtractPlanner.resolveMeetings(
            scope: request.scope,
            seed: seed,
            selected: pool.filter { launch.selectedIDs.contains($0.id) },
            visible: pool.filter { launch.visibleIDs.contains($0.id) },
            group: pool.filter { launch.groupMeetingIDs.contains($0.id) },
            library: pool
        )
    }

    private var snapshots: [DossierMeetingSnapshot] {
        resolvedMeetings.map { DossierFacts.snapshot(meeting: $0) }
    }

    private var speakers: [String] {
        ArchiveExtractPlanner.uniqueSpeakers(in: snapshots)
    }

    private var seriesCount: Int {
        if !launch.groupMeetingIDs.isEmpty {
            return ArchiveExtractPlanner.resolveMeetings(
                scope: .thisSeries,
                seed: seed,
                selected: [],
                visible: [],
                group: pool.filter { launch.groupMeetingIDs.contains($0.id) },
                library: pool
            ).count
        }
        if let seed {
            return DossierFacts.relatedMeetings(to: seed, library: pool).count
        }
        return 0
    }

    private var seriesTitle: String {
        if let label = launch.seriesLabel?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty {
            return label
        }
        if let seed {
            return MeetingListGrouping.displayLabel(for: seed)
        }
        return "This series"
    }

    private var screenshotCount: Int {
        resolvedMeetings.reduce(0) { $0 + $1.screenFrames.count }
    }

    private var audioCount: Int {
        resolvedMeetings.filter { meeting in
            let id = meeting.audioSourceMeetingID ?? meeting.id
            return !AudioFileWriter.existingChunkURLs(base: StorageManager.shared.micAudioURL(for: id)).isEmpty
                || !AudioFileWriter.existingChunkURLs(base: StorageManager.shared.systemAudioURL(for: id)).isEmpty
        }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Export transcripts and intel")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .disabled(isExporting)
                Button(isExporting ? "Exporting…" : "Export") {
                    runExtract()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canExtract)
            }
            .padding()
            Divider()
            if isExporting {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Exporting \(resolvedMeetings.count) meeting\(resolvedMeetings.count == 1 ? "" : "s")…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            Form {
                Section {
                    Picker("Scope", selection: $request.scope) {
                        if seed != nil {
                            Text("This meeting").tag(ArchiveExtractScope.thisMeeting)
                        }
                        if seriesCount > 1 {
                            Text("\(seriesTitle) (\(seriesCount))").tag(ArchiveExtractScope.thisSeries)
                        }
                        if !launch.groupMeetingIDs.isEmpty, launch.initialScope == .thisGroup {
                            Text("\(launch.seriesLabel ?? "This group") (\(launch.groupMeetingIDs.count))")
                                .tag(ArchiveExtractScope.thisGroup)
                        }
                        if !launch.selectedIDs.isEmpty {
                            Text("Selected (\(launch.selectedIDs.count))").tag(ArchiveExtractScope.selected)
                        }
                        if !launch.visibleIDs.isEmpty {
                            Text("All visible (\(launch.visibleIDs.count))").tag(ArchiveExtractScope.allVisible)
                        }
                    }
                    Picker("Speaker", selection: speakerBinding) {
                        Text("Everyone").tag("")
                        ForEach(speakers, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    if request.speaker == nil, request.package == .zip {
                        Toggle("One folder per speaker", isOn: $request.splitBySpeaker)
                    }
                } header: {
                    Text("What to export")
                } footer: {
                    Text(scopeFooter)
                }

                Section {
                    Picker("Package", selection: $request.package) {
                        ForEach(ArchiveExportPackage.allCases) { package in
                            Text(package.menuTitle).tag(package)
                        }
                    }
                } header: {
                    Text("Format")
                } footer: {
                    Text(packageFooter)
                }

                Section {
                    Toggle("Transcripts", isOn: $request.includeTranscript)
                    Toggle("Intel (summary, actions, questions, topics)", isOn: $request.includeIntel)
                    if request.package == .zip {
                        Toggle("Audio file", isOn: $request.includeAudio)
                        Toggle("Screen captures", isOn: $request.includeScreenshots)
                        Toggle("Video (screen-share time-lapse)", isOn: $request.includeVideo)
                    }
                } header: {
                    Text("Include")
                } footer: {
                    Text(mediaFooter)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .disabled(isExporting)
        }
        .frame(minWidth: 540, minHeight: 520)
        .onAppear {
            request.scope = launch.initialScope
            request.speaker = launch.initialSpeaker
            if request.scope == .thisSeries, seriesCount < 2 {
                request.scope = seed != nil ? .thisMeeting : (launch.visibleIDs.isEmpty ? .selected : .allVisible)
            }
            if request.scope == .selected, launch.selectedIDs.isEmpty {
                request.scope = launch.visibleIDs.isEmpty ? .thisMeeting : .allVisible
            }
            if request.scope == .thisGroup, launch.groupMeetingIDs.isEmpty {
                request.scope = .allVisible
            }
        }
        .onChange(of: request.scope) { _, _ in
            if let speaker = request.speaker,
               !speakers.contains(where: { DossierNaming.namesMatch($0, speaker) }) {
                request.speaker = nil
            }
        }
    }

    private var canExtract: Bool {
        !isExporting && request.includesAnything && !resolvedMeetings.isEmpty
    }

    private var scopeFooter: String {
        let count = resolvedMeetings.count
        if count == 0 {
            return "Nothing in this scope. Select meetings or pick a different scope."
        }
        if request.scope == .thisSeries {
            return "\(count) meeting\(count == 1 ? "" : "s") in this series, including any still on the recent list."
        }
        if request.scope == .thisGroup {
            return "\(count) meeting\(count == 1 ? "" : "s") in \(launch.seriesLabel ?? "this group")."
        }
        return "\(count) meeting\(count == 1 ? "" : "s") will be exported."
    }

    private var packageFooter: String {
        switch request.package {
        case .zip:
            return "Markdown plus optional audio, stills, and a screen-share time-lapse."
        case .combinedPDF:
            return "One PDF. Each meeting starts on a new page."
        case .pdfsPerMeeting:
            return resolvedMeetings.count <= 1
                ? "One PDF for this meeting."
                : "One PDF file per meeting in a folder you choose."
        }
    }

    private var mediaFooter: String {
        if request.package.isPDF {
            return "Audio, screen stills, and time-lapse stay in Zip."
        }
        var parts: [String] = []
        parts.append("\(audioCount) of \(resolvedMeetings.count) have saved audio.")
        parts.append("\(screenshotCount) screen still\(screenshotCount == 1 ? "" : "s") across the set.")
        parts.append("Video is a time-lapse of those stills. There is no camera movie of the call.")
        return parts.joined(separator: " ")
    }

    private var speakerBinding: Binding<String> {
        Binding(
            get: { request.speaker ?? "" },
            set: { request.speaker = $0.isEmpty ? nil : $0 }
        )
    }

    private func runExtract() {
        guard canExtract else { return }
        isExporting = true
        errorMessage = nil
        let meetings = resolvedMeetings
        let request = request
        let seriesLabel: String? = {
            switch request.scope {
            case .thisSeries, .thisGroup: return seriesTitle
            default: return launch.seriesLabel
            }
        }()
        Task { @MainActor in
            defer { isExporting = false }
            do {
                if let url = try await ArchiveExtractWriter.export(
                    meetings: meetings,
                    request: request,
                    seriesLabel: seriesLabel
                ) {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                    dismiss()
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
