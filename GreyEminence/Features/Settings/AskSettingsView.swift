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

    var body: some View {
        Form {
            Section {
                Picker("Provider", selection: $embeddingProviderRaw) {
                    ForEach(EmbeddingProvider.allCases) { provider in
                        Text(provider.label).tag(provider.rawValue)
                    }
                }
                if let provider = EmbeddingProvider(rawValue: embeddingProviderRaw), !provider.isAvailable {
                    Text("This provider isn't implemented yet — falling back to on-device for searches.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                LabeledContent("Indexed items") {
                    Text("\(embeddingCount)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Last reindex") {
                    Text(lastReindexAt > 0
                         ? Date(timeIntervalSince1970: lastReindexAt).formatted(date: .abbreviated, time: .shortened)
                         : "Never")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button(isReindexing ? "Reindexing…" : "Reindex all meetings") {
                        Task { await reindexAll() }
                    }
                    .disabled(isReindexing)
                    if isReindexing && reindexTotal > 0 {
                        ProgressView(value: Double(reindexDone), total: Double(reindexTotal))
                            .frame(width: 120)
                        Text("\(reindexDone)/\(reindexTotal)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                Text("Embeddings are stored in a separate database from your meetings so wiping or re-indexing can't corrupt your main store.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        .onAppear { embeddingCount = EmbeddingStore.shared?.count() ?? 0 }
    }

    @State private var isMaintaining = false
    @State private var maintenanceSummary: String?

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
        guard service.isAvailable else { return }

        isReindexing = true
        defer {
            isReindexing = false
            embeddingCount = store.count()
        }
        let indexer = EmbeddingIndexer(store: store, service: service)
        await indexer.reindexAll(mainContext: modelContext) { done, total in
            reindexDone = done
            reindexTotal = total
        }
        lastReindexAt = Date.now.timeIntervalSince1970
    }
}
