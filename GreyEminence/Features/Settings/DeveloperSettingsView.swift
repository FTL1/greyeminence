import SwiftUI
import SwiftData

struct DeveloperSettingsView: View {
    @AppStorage("developerToolsEnabled") private var developerToolsEnabled = false
    @State private var showPromptEditor = false
    @Environment(\.modelContext) private var modelContext
    @State private var debugInfo: DebugInfo?

    var body: some View {
        Form {
            Section {
                Toggle("Enable developer tools", isOn: $developerToolsEnabled)
                Text("Shows the Activity Log in the sidebar and deduplication debug tools in the transcript view.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Label("Developer Tools", systemImage: "hammer")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .textCase(nil)
            }

            if developerToolsEnabled {
                Section {
                    Button {
                        showPromptEditor = true
                    } label: {
                        HStack {
                            Label("Edit AI Prompts", systemImage: "text.quote")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    Text("Override the prompts sent to Claude for meeting analysis. Changes take effect on the next AI call. Clearing an override restores the built-in default.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Label("AI Prompts", systemImage: "text.quote")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .textCase(nil)
                }

                if let info = debugInfo {
                    Section {
                        LabeledContent("Database") {
                            HStack(spacing: 6) {
                                Text(info.databasePath)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Button {
                                    NSWorkspace.shared.selectFile(
                                        info.databasePath,
                                        inFileViewerRootedAtPath: (info.databasePath as NSString).deletingLastPathComponent
                                    )
                                } label: {
                                    Image(systemName: "folder")
                                        .font(.caption)
                                }
                                .buttonStyle(.plain)
                                .help("Reveal in Finder")
                            }
                        }

                        LabeledContent("Database Size") {
                            Text(info.formattedDatabaseSize)
                        }

                        LabeledContent("Recordings") {
                            Text(info.formattedRecordingsSize)
                        }

                        LabeledContent("Backups") {
                            Text(info.formattedBackupsSize)
                        }

                        LabeledContent("Total Storage") {
                            Text(info.formattedTotalSize)
                                .fontWeight(.medium)
                        }
                    } header: {
                        Label("Storage", systemImage: "internaldrive")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .textCase(nil)
                    }

                    Section {
                        LabeledContent("Meetings") { Text("\(info.meetingCount)") }
                        LabeledContent("Transcript Segments") { Text("\(info.segmentCount)") }
                        LabeledContent("Insights") { Text("\(info.insightCount)") }
                        LabeledContent("Action Items") { Text("\(info.actionItemCount)") }
                        LabeledContent("Contacts") { Text("\(info.contactCount)") }
                        LabeledContent("Interviews") { Text("\(info.interviewCount)") }
                        LabeledContent("Candidates") { Text("\(info.candidateCount)") }
                    } header: {
                        Label("Data Counts", systemImage: "number")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .textCase(nil)
                    }

                    Section {
                        LabeledContent("Schema") { Text(info.schemaVersion) }
                        LabeledContent("Build") { Text(info.buildInfo) }
                        LabeledContent("macOS") { Text(info.osVersion) }
                        LabeledContent("Seed Version") { Text("\(info.seedVersion)") }
                    } header: {
                        Label("Environment", systemImage: "gearshape.2")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .textCase(nil)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Developer")
        .task(id: developerToolsEnabled) {
            guard developerToolsEnabled else {
                debugInfo = nil
                return
            }
            // Counts first so the pane fills in immediately, then the sizes
            // once the filesystem walk finishes.
            let base = DebugInfo.gather(context: modelContext)
            debugInfo = base
            debugInfo = await base.withMeasuredSizes()
        }
        .sheet(isPresented: $showPromptEditor) {
            NavigationStack {
                DeveloperPromptEditorView()
                    .frame(minWidth: 780, minHeight: 560)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") {
                                showPromptEditor = false
                            }
                        }
                    }
            }
        }
    }
}

// MARK: - Debug Info

private struct DebugInfo {
    let databasePath: String
    let databaseSize: Int64
    var recordingsSize: Int64
    var backupsSize: Int64
    let meetingCount: Int
    let segmentCount: Int
    let insightCount: Int
    let actionItemCount: Int
    let contactCount: Int
    let interviewCount: Int
    let candidateCount: Int
    let schemaVersion: String
    let buildInfo: String
    let osVersion: String
    let seedVersion: Int

    var formattedDatabaseSize: String { Self.formatBytes(databaseSize) }
    var formattedRecordingsSize: String { Self.formatBytes(recordingsSize) }
    var formattedBackupsSize: String { Self.formatBytes(backupsSize) }
    var formattedTotalSize: String { Self.formatBytes(databaseSize + recordingsSize + backupsSize) }

    @MainActor
    /// Counts and paths now; the two directory sizes are measured off the
    /// main actor and folded in by `withMeasuredSizes`.
    static func gather(context: ModelContext) -> DebugInfo {
        let storage = StorageManager.shared

        // Database path & size — ask the live ModelContainer where its
        // store actually lives instead of guessing. SwiftData does not
        // place named configurations under our custom appSupportURL —
        // it uses `<applicationSupport>/<bundleID>/<config-name>.store`
        // by default, so the legacy guess-the-path code came up empty
        // and reported 0 bytes.
        let configURL = context.container.configurations.first?.url
        let actualPath = configURL?.path ?? ""
        let dbSize = Self.fileSize(atPath: actualPath)
            + Self.fileSize(atPath: actualPath + "-wal")
            + Self.fileSize(atPath: actualPath + "-shm")

        // Sizes are filled in afterwards, off the main actor — see `gather`.
        let recordingsSize: Int64 = 0
        let backupsSize: Int64 = 0

        // Model counts
        func count<T: PersistentModel>(_ type: T.Type) -> Int {
            (try? context.fetchCount(FetchDescriptor<T>())) ?? 0
        }

        let bundle = Bundle.main
        let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "?"

        return DebugInfo(
            databasePath: actualPath,
            databaseSize: dbSize,
            recordingsSize: recordingsSize,
            backupsSize: backupsSize,
            meetingCount: count(Meeting.self),
            segmentCount: count(TranscriptSegment.self),
            insightCount: count(MeetingInsight.self),
            actionItemCount: count(ActionItem.self),
            contactCount: count(Contact.self),
            interviewCount: count(Interview.self),
            candidateCount: count(Candidate.self),
            schemaVersion: {
                let v = context.container.schema.version
                return "V\(v.major).\(v.minor).\(v.patch)"
            }(),
            buildInfo: "\(version) (\(build))",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            seedVersion: UserDefaults.standard.integer(forKey: "interviewSeedVersion")
        )
    }

    private static func fileSize(atPath path: String) -> Int64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        return (attrs?[.size] as? Int64) ?? 0
    }

    /// Walking the recordings tree means enumerating every chunk of every
    /// meeting — thousands of files and gigabytes — so it never runs on the
    /// actor that draws the window.
    /// Measure the two directory sizes away from the main actor and return a
    /// filled-in copy.
    nonisolated func withMeasuredSizes() async -> DebugInfo {
        let recordings = StorageManager.shared.recordingsURL
        let backups = StoreBackupService.backupDirectory
        let sizes = await Task.detached(priority: .utility) {
            (DebugInfo.directorySize(at: recordings), DebugInfo.directorySize(at: backups))
        }.value
        var copy = self
        copy.recordingsSize = sizes.0
        copy.backupsSize = sizes.1
        return copy
    }

    nonisolated static func directorySize(at url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else {
            return 0
        }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
