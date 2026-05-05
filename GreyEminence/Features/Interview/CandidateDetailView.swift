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
                Image(systemName: iconName(for: filename))
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
        resumeError = nil
    }

    private func isPDF(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "pdf"
    }

    private func iconName(for filename: String) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf": return "doc.richtext"
        case "doc", "docx": return "doc.text"
        case "md", "txt", "rtf": return "doc.plaintext"
        default: return "doc"
        }
    }
}
