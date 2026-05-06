import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import AppKit

struct CandidateDetailView: View {
    @Bindable var candidate: Candidate
    @Query(sort: \InterviewRole.createdAt) private var roles: [InterviewRole]
    @State private var showResumeImporter = false
    @State private var resumeError: String?
    @State private var isResumeExpanded = false
    @State private var isAnalyzingResume = false

    /// File types accepted as resumes. PDF is the common case; doc/docx
    /// covered for users still on Word; plain text and markdown for the
    /// occasional copy-paste resume.
    private static let resumeContentTypes: [UTType] = [
        .pdf,
        UTType(filenameExtension: "doc") ?? .data,
        UTType(filenameExtension: "docx") ?? .data,
        .plainText,
        UTType(filenameExtension: "md") ?? .plainText,
        .rtf,
    ]

    var body: some View {
        List {
            if candidate.isArchived {
                Section {
                    Label("This candidate is archived.", systemImage: "archivebox")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Details") {
                TextField("Name", text: $candidate.name)
                TextField("Email", text: Binding(
                    get: { candidate.email ?? "" },
                    set: { candidate.email = $0.isEmpty ? nil : $0 }
                ))
                Picker("Role", selection: Binding(
                    get: { candidate.role },
                    set: { candidate.role = $0 }
                )) {
                    Text("None").tag(nil as InterviewRole?)
                    ForEach(roles) { role in
                        Text(role.fullDescription).tag(role as InterviewRole?)
                    }
                }
            }

            Section("Resume") {
                resumeRow
                if let error = resumeError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                if isResumeExpanded,
                   let url = candidate.resumeURL,
                   FileManager.default.fileExists(atPath: url.path),
                   isPDF(url) {
                    PDFPreviewView(url: url)
                        .frame(minHeight: 360, idealHeight: 480)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(.secondary.opacity(0.2), lineWidth: 0.5)
                        )
                }
            }

            if let sheet = candidate.characterSheet {
                Section {
                    CharacterSheetView(sheet: sheet)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                } header: {
                    HStack {
                        Text("Character Sheet")
                        Spacer()
                        if let analyzedAt = candidate.resumeAnalyzedAt {
                            Text("Generated \(analyzedAt.formatted(.relative(presentation: .named)))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Button {
                            Task { await reanalyzeResume() }
                        } label: {
                            if isAnalyzingResume {
                                ProgressView().controlSize(.small)
                            } else {
                                Label("Re-roll", systemImage: "dice")
                                    .font(.caption)
                            }
                        }
                        .buttonStyle(.borderless)
                        .disabled(isAnalyzingResume || candidate.resumeURL == nil)
                        .help("Re-run resume analysis")
                    }
                }
            } else if candidate.resumeFilename != nil {
                Section("Character Sheet") {
                    HStack {
                        if isAnalyzingResume {
                            ProgressView().controlSize(.small)
                            Text("Analyzing resume…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Image(systemName: "dice")
                                .foregroundStyle(.secondary)
                            Text("Not yet generated")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Generate") {
                                Task { await reanalyzeResume() }
                            }
                            .controlSize(.small)
                            .disabled(candidate.resumeURL == nil)
                        }
                    }
                }
            }

            Section("Notes") {
                TextEditor(text: Binding(
                    get: { candidate.notes ?? "" },
                    set: { candidate.notes = $0.isEmpty ? nil : $0 }
                ))
                .frame(minHeight: 60)
            }

            if !candidate.interviews.isEmpty {
                Section("Interviews (\(candidate.interviews.count))") {
                    ForEach(sortedInterviews) { interview in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(interview.meeting?.title ?? "Interview")
                                        .font(.body)
                                    if let rec = interview.overallRecommendation {
                                        Text(rec.shortLabel)
                                            .font(.caption2.weight(.bold))
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1)
                                            .background(rec.color.opacity(0.2), in: Capsule())
                                            .foregroundStyle(rec.color)
                                    }
                                }
                                HStack(spacing: 8) {
                                    Text(interview.createdAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if let gp = interview.compositeGradePoints {
                                        let grade = LetterGrade.from(gradePoints: gp)
                                        Text(grade.label)
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            Spacer()
                        }
                    }
                }
            }
        }
        .navigationTitle(candidate.name)
        .toolbar {
            ToolbarItem {
                Button {
                    candidate.isArchived.toggle()
                } label: {
                    Label(
                        candidate.isArchived ? "Unarchive" : "Archive",
                        systemImage: candidate.isArchived ? "tray.and.arrow.up" : "archivebox"
                    )
                }
            }
        }
    }

    private var sortedInterviews: [Interview] {
        candidate.interviews.sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Resume

    @ViewBuilder
    private var resumeRow: some View {
        if let filename = candidate.resumeFilename, let url = candidate.resumeURL {
            HStack(spacing: 8) {
                Image(systemName: iconName(for: url))
                    .foregroundStyle(.cyan)
                VStack(alignment: .leading, spacing: 2) {
                    Text(filename)
                        .font(.body)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let added = candidate.resumeAddedAt {
                        Text("Added \(added.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if isPDF(url) {
                    Button {
                        isResumeExpanded.toggle()
                    } label: {
                        Label(
                            isResumeExpanded ? "Hide" : "Preview",
                            systemImage: isResumeExpanded ? "chevron.up" : "eye"
                        )
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!FileManager.default.fileExists(atPath: url.path))
                }
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label("Open", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!FileManager.default.fileExists(atPath: url.path))
                Menu {
                    Button("Replace…") { showResumeImporter = true }
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                    Divider()
                    Button("Remove", role: .destructive) {
                        removeResume()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 22)
            }
        } else {
            Button {
                showResumeImporter = true
            } label: {
                Label("Attach Resume", systemImage: "doc.badge.plus")
            }
            .fileImporter(
                isPresented: $showResumeImporter,
                allowedContentTypes: Self.resumeContentTypes,
                allowsMultipleSelection: false,
                onCompletion: handleResumeImport
            )
        }
    }

    private func handleResumeImport(_ result: Result<[URL], Error>) {
        resumeError = nil
        switch result {
        case .success(let urls):
            guard let source = urls.first else { return }
            let needsScope = source.startAccessingSecurityScopedResource()
            defer { if needsScope { source.stopAccessingSecurityScopedResource() } }
            do {
                let filename = try StorageManager.shared.attachResume(
                    sourceURL: source,
                    candidateID: candidate.id,
                    replacingFilename: candidate.resumeFilename
                )
                candidate.resumeFilename = filename
                candidate.resumeAddedAt = .now
                // Replace clears any prior analysis — the new resume's
                // content may be entirely different.
                candidate.resumeSummary = nil
                candidate.characterSheetJSON = nil
                candidate.resumeAnalyzedAt = nil
                Task { await reanalyzeResume() }
            } catch {
                resumeError = "Failed to attach resume: \(error.localizedDescription)"
            }
        case .failure(let error):
            resumeError = error.localizedDescription
        }
    }

    private func removeResume() {
        if let filename = candidate.resumeFilename {
            StorageManager.shared.removeResume(candidateID: candidate.id, filename: filename)
        }
        candidate.resumeFilename = nil
        candidate.resumeAddedAt = nil
        candidate.resumeSummary = nil
        candidate.characterSheetJSON = nil
        candidate.resumeAnalyzedAt = nil
        resumeError = nil
    }

    /// Run the AI analyzer on the attached resume. Surfaces a footer
    /// indicator via the transient activity coordinator and writes
    /// `resumeSummary` + `characterSheetJSON` on completion.
    private func reanalyzeResume() async {
        guard let url = candidate.resumeURL,
              let text = ResumeTextExtractor.extractText(from: url) else { return }
        isAnalyzingResume = true
        defer { isAnalyzingResume = false }

        let analysis: ResumeAnalysis?
        do {
            analysis = try await TransientActivityCoordinator.shared.runAsync(
                "Analyzing \(candidate.name)'s resume…"
            ) {
                try await ResumeAnalyzer.analyze(resumeText: text, candidateName: candidate.name)
            }
        } catch {
            resumeError = "Resume analysis failed: \(error.localizedDescription)"
            return
        }

        guard let analysis else {
            resumeError = "Resume analysis returned no result. AI may not be configured."
            return
        }
        candidate.resumeSummary = analysis.summary
        candidate.characterSheetJSON = analysis.characterSheet.toJSON()
        candidate.resumeAnalyzedAt = .now
    }

    private func isPDF(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .pdf) == true
    }

    private func iconName(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "pdf": "doc.richtext"
        case "doc", "docx": "doc.text"
        case "md", "txt", "rtf": "doc.plaintext"
        default: "doc"
        }
    }
}
