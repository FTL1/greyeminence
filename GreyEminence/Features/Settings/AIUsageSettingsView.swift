import SwiftData
import SwiftUI

/// Read-only view over the AI usage ledger: 30-day totals broken down by
/// purpose, with estimated cost where the model family is known.
struct AIUsageSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var groups: [AIUsageAggregator.GroupRollup] = []
    @State private var grandTotals: AIUsageAggregator.Totals?
    @State private var eventCount = 0

    var body: some View {
        Form {
            totalsSection
            breakdownSection
        }
        .formStyle(.grouped)
        .task { refresh() }
    }

    private var totalsSection: some View {
        Section {
            if let grandTotals, eventCount > 0 {
                LabeledContent("Input tokens") {
                    Text(grandTotals.totalInputSideTokens.formatted())
                        .fontDesign(.monospaced)
                }
                LabeledContent("Output tokens") {
                    Text(grandTotals.outputTokens.formatted())
                        .fontDesign(.monospaced)
                }
                LabeledContent("Estimated cost") {
                    Text(costLabel(grandTotals))
                        .fontDesign(.monospaced)
                }
                LabeledContent("API calls") {
                    Text("\(eventCount)")
                        .fontDesign(.monospaced)
                }
            } else {
                Text("No AI calls recorded in the last 30 days.")
                    .foregroundStyle(.secondary)
            }
            Text("Estimates use current published per-token prices — actual billing can differ (Bedrock pricing, tier discounts). Calls on unrecognized models are counted in tokens but not in cost. Usage events are kept for 90 days.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Label("Last 30 Days", systemImage: "chart.bar")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .textCase(nil)
        }
    }

    private var breakdownSection: some View {
        Section {
            if groups.isEmpty {
                Text("Nothing to break down yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(groups, id: \.group) { rollup in
                LabeledContent {
                    Text(usageLabel(rollup.totals))
                        .fontDesign(.monospaced)
                        .fontWeight(.semibold)
                } label: {
                    Text(rollup.group.displayName)
                        .fontWeight(.semibold)
                }
                // Purpose detail only when the group has more than one
                // contributor — a lone purpose would just repeat the line.
                if rollup.purposes.count > 1 {
                    ForEach(rollup.purposes, id: \.purpose) { entry in
                        LabeledContent {
                            Text(usageLabel(entry.totals))
                                .fontDesign(.monospaced)
                                .foregroundStyle(.secondary)
                        } label: {
                            Text(entry.purpose.displayName)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 16)
                        }
                    }
                }
            }
        } header: {
            Label("Where It Went", systemImage: "list.bullet.rectangle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .textCase(nil)
        }
    }

    private func usageLabel(_ totals: AIUsageAggregator.Totals) -> String {
        "\(AIUsageAggregator.compactTokens(totals.totalInputSideTokens)) in / \(AIUsageAggregator.compactTokens(totals.outputTokens)) out  \(costLabel(totals))"
    }

    private func costLabel(_ totals: AIUsageAggregator.Totals) -> String {
        guard totals.estimatedCost > 0 else {
            return totals.pricedEverything ? "$0.00" : "tokens only"
        }
        let approx = totals.pricedEverything ? "~" : ">"
        return String(format: "%@$%.2f", approx, totals.estimatedCost)
    }

    private func refresh() {
        let cutoff = Date().addingTimeInterval(-30 * 24 * 60 * 60)
        let descriptor = FetchDescriptor<AIUsageEvent>(
            predicate: #Predicate { $0.timestamp >= cutoff }
        )
        let events = (try? modelContext.fetch(descriptor)) ?? []
        let lines = events.map(AIUsageAggregator.Line.init(event:))
        let settings = TrajectorSettings.load()
        eventCount = events.count
        grandTotals = AIUsageAggregator.totals(lines, settings: settings)
        groups = AIUsageAggregator.byGroup(lines, settings: settings)
    }
}
