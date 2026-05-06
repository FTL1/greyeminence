import SwiftUI
import SwiftData

struct RubricSectionEditorView: View {
    @Bindable var section: RubricSection
    @Environment(\.modelContext) private var modelContext
    var onDelete: () -> Void

    @State private var isExpanded = true
    @State private var newCriterionText = ""
    @State private var newBonusLabel = ""
    @State private var newBonusExpected = "yes"
    @State private var newBonusValue = 1
    @State private var showInstructionsEditor = false

    private var sortedCriteria: [RubricCriterion] {
        section.criteria.sorted { $0.sortOrder < $1.sortOrder }
    }

    private var sortedBonuses: [RubricBonusSignal] {
        section.bonusSignals.sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        Section(isExpanded: $isExpanded) {
            // Section config
            TextField("Description", text: $section.sectionDescription, axis: .vertical)
                .lineLimit(2...4)
                .font(.caption)

            candidateInstructionsRow

            // Criteria
            if !sortedCriteria.isEmpty {
                ForEach(sortedCriteria) { criterion in
                    CriterionRow(
                        criterion: criterion,
                        onDelete: {
                            section.criteria.removeAll { $0.id == criterion.id }
                            modelContext.delete(criterion)
                        }
                    )
                }
            }

            // Add criterion
            HStack {
                TextField("Add criterion...", text: $newCriterionText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addCriterion() }
                Button("Add") { addCriterion() }
                    .controlSize(.small)
                    .disabled(newCriterionText.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            // Bonus signals
            if !sortedBonuses.isEmpty {
                Divider()
                Text("Bonus / Penalty Signals")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                ForEach(sortedBonuses) { signal in
                    HStack(spacing: 6) {
                        Image(systemName: signal.bonusValue >= 0 ? "plus.circle" : "minus.circle")
                            .font(.caption)
                            .foregroundStyle(signal.bonusValue >= 0 ? .blue : .orange)
                        TextField("Label", text: Binding(
                            get: { signal.label },
                            set: { signal.label = $0 }
                        ))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text("expect:")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        TextField("", text: Binding(
                            get: { signal.expectedAnswer },
                            set: { signal.expectedAnswer = $0 }
                        ))
                        .frame(width: 50)
                        .textFieldStyle(.roundedBorder)
                        Stepper("", value: Binding(
                            get: { signal.bonusValue },
                            set: { signal.bonusValue = $0 }
                        ), in: -5...5)
                        .labelsHidden()
                        Text("\(signal.bonusValue > 0 ? "+" : "")\(signal.bonusValue)")
                            .font(.caption)
                            .fontDesign(.monospaced)
                            .foregroundStyle(signal.bonusValue >= 0 ? .blue : .orange)
                            .frame(width: 28, alignment: .trailing)
                        Button {
                            section.bonusSignals.removeAll { $0.id == signal.id }
                            modelContext.delete(signal)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Add bonus signal
            HStack(spacing: 6) {
                TextField("Add bonus signal...", text: $newBonusLabel)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onSubmit { addBonusSignal() }
                TextField("expect", text: $newBonusExpected)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 50)
                Stepper("", value: $newBonusValue, in: -5...5)
                    .labelsHidden()
                Text("\(newBonusValue > 0 ? "+" : "")\(newBonusValue)")
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .frame(width: 28, alignment: .trailing)
                Button("Add") { addBonusSignal() }
                    .controlSize(.small)
                    .disabled(newBonusLabel.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            HStack(spacing: 6) {
                TextField("Section title", text: $section.title)
                    .font(.subheadline.weight(.semibold))
                    .textCase(nil)
                    .fixedSize()
                Text("(\(Int(section.weight.rounded()))%)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(nil)
                Spacer()
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Compact row that summarizes the candidate brief and opens the
    /// full markdown editor sheet on click. Replaces the cramped inline
    /// TextField — long briefs need a real editor.
    @ViewBuilder
    private var candidateInstructionsRow: some View {
        let instructions = section.candidateInstructions ?? ""
        let trimmed = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasContent = !trimmed.isEmpty

        Button {
            showInstructionsEditor = true
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: hasContent ? "doc.text.fill" : "doc.text")
                    .foregroundStyle(hasContent ? .cyan : .secondary)
                    .font(.caption)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(hasContent ? "Candidate Brief" : "Add Candidate Brief")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                    if hasContent {
                        Text(previewSnippet(trimmed))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.tail)
                            .multilineTextAlignment(.leading)
                    } else {
                        Text("Markdown brief you'll paste into the candidate's chat — problem statement, scenario, expected deliverable.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer()
                Image(systemName: "pencil")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
        .sheet(isPresented: $showInstructionsEditor) {
            MarkdownEditorSheet(
                text: Binding(
                    get: { section.candidateInstructions ?? "" },
                    set: { section.candidateInstructions = $0.isEmpty ? nil : $0 }
                ),
                title: "Candidate Brief",
                subtitle: section.title.isEmpty ? nil : section.title
            )
        }
    }

    /// Strip markdown markers and collapse whitespace for a clean
    /// one-line preview snippet shown in the section editor row.
    private func previewSnippet(_ markdown: String) -> String {
        markdown
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: ">", with: "")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func addCriterion() {
        let text = newCriterionText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        let criterion = RubricCriterion(signal: text, sortOrder: section.criteria.count)
        criterion.section = section
        section.criteria.append(criterion)
        newCriterionText = ""
    }

    private func addBonusSignal() {
        let label = newBonusLabel.trimmingCharacters(in: .whitespaces)
        guard !label.isEmpty else { return }
        let signal = RubricBonusSignal(
            label: label,
            expectedAnswer: newBonusExpected,
            bonusValue: newBonusValue,
            sortOrder: section.bonusSignals.count
        )
        signal.section = section
        section.bonusSignals.append(signal)
        newBonusLabel = ""
        newBonusExpected = "yes"
        newBonusValue = 1
    }
}

// MARK: - Criterion Row with Guidance Accordion

/// One criterion in a rubric section, plus its accordion of audience-tagged
/// guidance bullets. Bullets can be directed at the human interviewer
/// (display-only), the LLM scorer (appended to the AI prompt), or both.
private struct CriterionRow: View {
    @Bindable var criterion: RubricCriterion
    @Environment(\.modelContext) private var modelContext
    var onDelete: () -> Void

    @State private var isExpanded = false
    @State private var newBulletText = ""
    @State private var newBulletAudience: GuidanceAudience = .both

    private var sortedGuidance: [CriterionGuidance] {
        criterion.guidance.sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 6) {
                Image(systemName: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.green)
                TextField("Signal", text: Binding(
                    get: { criterion.signal },
                    set: { criterion.signal = $0 }
                ))
                .font(.body)
                Spacer()
                Button {
                    isExpanded.toggle()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                        if !sortedGuidance.isEmpty {
                            Text("\(sortedGuidance.count)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Add notes")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.1), in: Capsule())
                }
                .buttonStyle(.plain)
                .help("Show scoring guidance for this criterion")
                Button {
                    onDelete()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            if isExpanded {
                guidancePanel
                    .padding(.leading, 18)
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var guidancePanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(sortedGuidance) { bullet in
                HStack(alignment: .top, spacing: 4) {
                    audienceBadge(bullet: bullet)
                    TextField("Guidance", text: Binding(
                        get: { bullet.text },
                        set: { bullet.text = $0 }
                    ), axis: .vertical)
                    .lineLimit(1...3)
                    .font(.caption)
                    .textFieldStyle(.plain)
                    Spacer()
                    Button {
                        criterion.guidance.removeAll { $0.id == bullet.id }
                        modelContext.delete(bullet)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Add-bullet row
            HStack(spacing: 4) {
                audienceMenu(
                    selection: $newBulletAudience,
                    label: {
                        Image(systemName: newBulletAudience.symbolName)
                            .font(.caption2)
                            .foregroundStyle(.cyan)
                            .frame(width: 18, height: 18)
                            .background(Color.secondary.opacity(0.1), in: Capsule())
                    }
                )
                TextField("Add a bullet (e.g., \"Look for incremental design\" or \"Score lower if they jump straight to ERD\")", text: $newBulletText, axis: .vertical)
                    .lineLimit(1...3)
                    .font(.caption)
                    .textFieldStyle(.plain)
                    .onSubmit { addBullet() }
                Button("Add") { addBullet() }
                    .controlSize(.small)
                    .disabled(newBulletText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.top, 2)

            HStack(spacing: 8) {
                legendItem(.interviewer)
                legendItem(.llm)
                legendItem(.both)
            }
            .padding(.top, 4)
        }
    }

    private func audienceBadge(bullet: CriterionGuidance) -> some View {
        audienceMenu(
            selection: Binding(
                get: { bullet.audience },
                set: { bullet.audience = $0 }
            ),
            label: {
                Image(systemName: bullet.audience.symbolName)
                    .font(.caption2)
                    .foregroundStyle(audienceColor(bullet.audience))
                    .frame(width: 18, height: 18)
                    .background(audienceColor(bullet.audience).opacity(0.15), in: Capsule())
            }
        )
        .help("Audience: \(bullet.audience.label)")
    }

    private func audienceMenu<L: View>(
        selection: Binding<GuidanceAudience>,
        @ViewBuilder label: () -> L
    ) -> some View {
        Menu {
            Picker("Audience", selection: selection) {
                ForEach(GuidanceAudience.allCases, id: \.self) { audience in
                    Label(audience.label, systemImage: audience.symbolName)
                        .tag(audience)
                }
            }
        } label: {
            label()
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func legendItem(_ audience: GuidanceAudience) -> some View {
        HStack(spacing: 3) {
            Image(systemName: audience.symbolName)
                .font(.system(size: 8))
            Text(audience.label)
                .font(.caption2)
        }
        .foregroundStyle(audienceColor(audience))
    }

    private func audienceColor(_ audience: GuidanceAudience) -> Color {
        switch audience {
        case .interviewer: .blue
        case .llm: .purple
        case .both: .cyan
        }
    }

    private func addBullet() {
        let text = newBulletText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        let bullet = CriterionGuidance(
            text: text,
            audience: newBulletAudience,
            sortOrder: criterion.guidance.count
        )
        bullet.criterion = criterion
        criterion.guidance.append(bullet)
        newBulletText = ""
    }
}
