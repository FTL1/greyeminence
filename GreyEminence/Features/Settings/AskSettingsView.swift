import SwiftUI
import SwiftData

struct AskSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("embeddingProvider") private var embeddingProviderRaw = EmbeddingProvider.nlEmbedding.rawValue
    @AppStorage("askSnippetCount") private var askSnippetCount: Int = 15
    @AppStorage("askContextWindow") private var askContextWindow: Int = 2
    @AppStorage("lastReindexAt") private var lastReindexAt: Double = 0

    @State private var reindexTotal = 0
    @State private var reindexDone = 0
    @State private var isReindexing = false
    @State private var embeddingCount = 0
    @State private var coverage = Coverage(indexed: 0, total: 0)
    @State private var showReindexPrompt = false
    @State private var previousProviderRaw: String?
    @State private var reindexError: String?
    @State private var describedProfiles: [AWSCredentialLoader.ProfileInfo] = []
    @State private var isTestingTitan = false
    @State private var titanTest: TestResult?

    @AppStorage(TitanEmbeddingService.profileKey) private var embeddingProfile: String = ""
    @AppStorage(TitanEmbeddingService.regionKey) private var embeddingRegion: String = ""

    enum TestResult {
        case success(String)
        case failure(String)
    }

    private var provider: EmbeddingProvider {
        EmbeddingProvider(rawValue: embeddingProviderRaw) ?? .nlEmbedding
    }

    /// How much of the index the *currently selected* method has produced.
    /// The headline count includes records from every method ever used, so on
    /// its own it hides exactly the problem this pane needs to show.
    struct Coverage {
        let indexed: Int
        let total: Int

        var label: String {
            total == 0 ? "\(indexed)" : "\(indexed) of \(total)"
        }
    }

    var body: some View {
        Form {
            Section {
                Picker("Method", selection: $embeddingProviderRaw) {
                    ForEach(EmbeddingProvider.allCases) { option in
                        Text(option.label)
                            .tag(option.rawValue)
                    }
                }
                .onChange(of: embeddingProviderRaw) { previous, _ in
                    // Vectors from different models aren't comparable, and a
                    // search only consults records embedded by the current
                    // one — so until the index is rebuilt, Ask finds nothing.
                    // Say so at the moment of the switch rather than letting
                    // it look like the search broke.
                    previousProviderRaw = previous
                    coverage = currentModelCoverage()
                    showReindexPrompt = coverage.indexed == 0
                }

                Text(provider.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !provider.isAvailable {
                    Label(provider.unavailableReason, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                if provider == .titan {
                    titanAccountControls
                }

                LabeledContent("Indexed items") {
                    Text("\(embeddingCount)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Indexed with this method") {
                    Text(coverage.label)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(coverage.indexed == 0 ? .orange : .secondary)
                }
                LabeledContent("Last reindex") {
                    Text(lastReindexAt > 0
                         ? Date(timeIntervalSince1970: lastReindexAt).formatted(date: .abbreviated, time: .shortened)
                         : "Never")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let reindexError {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(reindexError)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .textSelection(.enabled)
                    }
                }
                HStack {
                    Button(isReindexing ? "Reindexing…" : "Reindex all meetings") {
                        Task { await reindexAll() }
                    }
                    .disabled(isReindexing || !provider.isAvailable)
                    if isReindexing && reindexTotal > 0 {
                        ProgressView(value: Double(reindexDone), total: Double(reindexTotal))
                            .frame(width: 120)
                        Text("\(reindexDone)/\(reindexTotal) meetings")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                Text("Embeddings are stored in a separate database from your meetings so wiping or re-indexing can't corrupt your main store.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let failure = EmbeddingStore.initFailureMessage {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Embedding store can't open: \(failure)")
                                .font(.caption)
                                .foregroundStyle(.orange)
                            Button("Rebuild embedding store") {
                                rebuildStore()
                            }
                            .controlSize(.small)
                        }
                    }
                }
            } header: {
                Label("Index", systemImage: "rectangle.stack")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .textCase(nil)
            }

            Section {
                Stepper(
                    "Snippets sent to LLM: \(askSnippetCount)",
                    value: $askSnippetCount,
                    in: 3...50,
                    step: 1
                )
                Stepper(
                    "Transcript lead-in (segments before each chunk): \(askContextWindow)",
                    value: $askContextWindow,
                    in: 0...10,
                    step: 1
                )
                Text("Each ranked snippet is now a paragraph-sized chunk that already includes surrounding turns. The lead-in adds extra segments before the chunk for cases where the answer hinges on what was said just before. Both settings cost more tokens.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Label("Synthesis", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .textCase(nil)
            }

            Section {
                HStack {
                    Button(isMaintaining ? "Cleaning…" : "Run cleanup now") {
                        Task { await runMaintenance() }
                    }
                    .disabled(isMaintaining)
                    if let summary = maintenanceSummary {
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Text("Removes orphan embeddings, prunes stale segment chunks left behind by older re-processing runs, clears stuck analysis flags, and backfills the conversation context for legacy tasks. Runs automatically once per day at launch — this button forces it now.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Label("Maintenance", systemImage: "wrench.and.screwdriver")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .textCase(nil)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            embeddingCount = EmbeddingStore.shared?.count() ?? 0
            coverage = currentModelCoverage()
            AWSCredentialLoader.restoreAccess()
            describedProfiles = AWSCredentialLoader.describedProfiles()
        }
        .alert("Rebuild the search index?", isPresented: $showReindexPrompt) {
            Button("Rebuild now") {
                Task { await reindexAll() }
            }
            Button("Switch back", role: .cancel) {
                if let previousProviderRaw { embeddingProviderRaw = previousProviderRaw }
                coverage = currentModelCoverage()
            }
            Button("Later", role: .destructive) {}
        } message: {
            Text("\(provider.shortLabel) hasn't indexed anything yet, and Ask only searches what the selected method produced — until it's rebuilt, questions will come back empty.\n\n\(rebuildEstimate)")
        }
    }

    /// What rebuilding actually entails, in the terms someone deciding would
    /// want: how long, and whether it costs money.
    private var rebuildEstimate: String {
        switch provider {
        case .nlEmbedding:
            "Runs on-device: no network, no cost, a few minutes."
        case .titan:
            "Runs through Bedrock on the AWS profile selected above. Roughly 5.4M tokens for a full index — cents at Titan's rate — and a handful of minutes. Test the connection first."
        case .voyage:
            "Not available."
        }
    }

    private func currentModelCoverage() -> Coverage {
        guard let store = EmbeddingStore.shared else { return Coverage(indexed: 0, total: 0) }
        let total = store.count()
        let identifier = provider.makeService().modelIdentifier
        return Coverage(indexed: store.count(forModel: identifier), total: total)
    }

    @State private var isMaintaining = false
    @State private var maintenanceSummary: String?

    private func rebuildStore() {
        do {
            try EmbeddingStore.resetOnDisk()
            embeddingCount = EmbeddingStore.shared?.count() ?? 0
        } catch {
            // resetOnDisk surfaced the error; user can retry from the
            // banner that's still visible.
        }
    }

    /// Which AWS account the embedding model runs on.
    ///
    /// Its own profile because it need not be the analysis account: a role
    /// scoped to the Anthropic models can't invoke Titan at all, and the
    /// answer is usually a second account rather than a policy change. Left
    /// blank it follows Settings → AI, so a single-account setup shows one
    /// line and needs no decision.
    @ViewBuilder
    private var titanAccountControls: some View {
        Picker("AWS profile", selection: $embeddingProfile) {
            Text("Same as AI settings (\(fallbackProfile))").tag("")
            ForEach(usableProfiles) { info in
                Text("\(info.name) — \(info.kind.reason)").tag(info.name)
            }
        }
        .onChange(of: embeddingProfile) { _, profile in
            titanTest = nil
            // A profile usually declares its own region; adopting it saves
            // the most common misconfiguration, which is a valid account
            // pointed at a region the model isn't enabled in.
            if !profile.isEmpty, let detected = AWSCredentialLoader.loadRegion(profile: profile) {
                embeddingRegion = detected
            }
        }

        Picker("Region", selection: $embeddingRegion) {
            Text("Same as AI settings (\(fallbackRegion))").tag("")
            Text("US East (N. Virginia)").tag("us-east-1")
            Text("US East (Ohio)").tag("us-east-2")
            Text("US West (Oregon)").tag("us-west-2")
            Text("EU (Ireland)").tag("eu-west-1")
            Text("EU (Frankfurt)").tag("eu-central-1")
            Text("EU (Paris)").tag("eu-west-3")
            Text("Asia Pacific (Tokyo)").tag("ap-northeast-1")
            Text("Asia Pacific (Sydney)").tag("ap-southeast-2")
        }
        .onChange(of: embeddingRegion) { titanTest = nil }

        if !unusableProfiles.isEmpty {
            // Naming these is the point. They were previously offered in the
            // picker and failed with "profile not found" at the first request,
            // which reads as a bug in the app rather than a property of the
            // profile.
            Text("Not selectable: \(unusableProfiles.map { "\($0.name) (\($0.kind.reason))" }.joined(separator: ", ")).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        HStack(spacing: 8) {
            Button(isTestingTitan ? "Testing…" : "Test connection") {
                Task { await testTitan() }
            }
            .disabled(isTestingTitan)

            switch titanTest {
            case .success(let detail):
                Label(detail, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            case .failure(let detail):
                Label(detail, systemImage: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
            case nil:
                Text("Embeds one short string. Confirms the account can invoke Titan before you commit to a full rebuild.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var usableProfiles: [AWSCredentialLoader.ProfileInfo] {
        describedProfiles.filter(\.isSupported)
    }

    private var unusableProfiles: [AWSCredentialLoader.ProfileInfo] {
        describedProfiles.filter { !$0.isSupported }
    }

    private var fallbackProfile: String {
        UserDefaults.standard.string(forKey: "awsProfile") ?? "default"
    }

    private var fallbackRegion: String {
        UserDefaults.standard.string(forKey: "awsRegion") ?? "us-east-1"
    }

    @MainActor
    private func testTitan() async {
        isTestingTitan = true
        defer { isTestingTitan = false }

        let service = TitanEmbeddingService()
        let where_ = "\(service.resolvedProfile) · \(service.resolvedRegion)"
        guard service.isAvailable else {
            titanTest = .failure("No AWS profiles this app can authenticate as.")
            return
        }
        // Catch an unusable profile before spending a request on it — most
        // often the inherited one, when Settings → AI points at something the
        // loader can't follow either.
        if let info = describedProfiles.first(where: { $0.name == service.resolvedProfile }), !info.isSupported {
            titanTest = .failure("Profile \(info.name) \(info.kind.reason).")
            return
        }
        if let vector = await service.embed("Grey Eminence search index probe") {
            titanTest = .success("\(vector.count)-dim vector from \(where_)")
        } else {
            // The provider's own message is already in the log with the
            // profile and region attached; point at it rather than paraphrase.
            titanTest = .failure("Couldn't embed with \(where_) — see the Activity Log for the exact error.")
        }
    }

    @MainActor
    private func runMaintenance() async {
        isMaintaining = true
        defer {
            isMaintaining = false
            embeddingCount = EmbeddingStore.shared?.count() ?? 0
        }
        let report = MaintenanceService.runStartupMaintenance(modelContext: modelContext, force: true)
        maintenanceSummary = report.summary
    }

    @MainActor
    private func reindexAll() async {
        guard let store = EmbeddingStore.shared else { return }
        let provider = EmbeddingProvider(rawValue: embeddingProviderRaw) ?? .nlEmbedding
        let service = provider.makeService()
        isReindexing = true
        reindexError = nil
        defer {
            isReindexing = false
            embeddingCount = store.count()
            coverage = currentModelCoverage()
        }
        let indexer = EmbeddingIndexer(store: store, service: service)
        let outcome = await indexer.reindexAll(mainContext: modelContext) { done, total in
            reindexDone = done
            reindexTotal = total
        }
        switch outcome {
        case .completed:
            reindexError = nil
            lastReindexAt = Date.now.timeIntervalSince1970
        case .unavailable(let message), .aborted(let message):
            reindexError = message
        }
    }
}
