import SwiftUI

/// Choose what goes into a report before exporting it.
///
/// Everything starts ticked — leaving a part out should be a deliberate act,
/// not something you have to opt into every time.
struct ReportExportSheet: View {
    let meeting: Meeting
    /// Called with the chosen options; the caller runs the export so the
    /// sheet can dismiss immediately rather than holding a save panel open
    /// behind itself.
    let onExport: (ReportExportOptions) -> Void

    @Environment(\.dismiss) private var dismiss

    @AppStorage("reportTemplateID") private var reportTemplateID = ReportTemplateCatalog.plain.id
    @AppStorage("reportFiguresAtEnd") private var reportFiguresAtEnd = false

    @State private var selectedSections: Set<Int> = []
    @State private var includesActionItems = true
    @State private var includesFollowUps = true
    @State private var includesSharedScreens = true
    @State private var includesTranscript = false

    private var sections: [(id: Int, title: String)] {
        ReportModelBuilder.sectionTitles(for: meeting)
    }

    private var hasActionItems: Bool { !meeting.actionItems.isEmpty }
    private var hasFollowUps: Bool { !(meeting.latestInsight?.followUpQuestions.isEmpty ?? true) }
    private var hasSharedScreens: Bool { !meeting.screenFrames.isEmpty }
    private var hasTranscript: Bool { !meeting.segments.isEmpty }

    private var options: ReportExportOptions {
        ReportExportOptions(
            templateID: reportTemplateID,
            sectionIDs: selectedSections,
            includesActionItems: includesActionItems && hasActionItems,
            includesFollowUps: includesFollowUps && hasFollowUps,
            includesSharedScreens: includesSharedScreens && hasSharedScreens,
            includesTranscript: includesTranscript && hasTranscript,
            figuresAtEnd: reportFiguresAtEnd
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 460, height: 520)
        .onAppear {
            // Default to everything. Only seeded once, so reopening the sheet
            // after unticking something does not silently re-tick it.
            if selectedSections.isEmpty {
                selectedSections = Set(sections.map(\.id))
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Export Report")
                .font(.headline)

            Picker("Template", selection: $reportTemplateID) {
                ForEach(ReportTemplateCatalog.all) { template in
                    Text("\(template.name)  (\(template.code))").tag(template.id)
                }
            }
            Text(ReportTemplateCatalog.template(id: reportTemplateID).summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if hasSharedScreens {
                Picker("Screenshots", selection: $reportFiguresAtEnd) {
                    Text("Inline with the summary").tag(false)
                    Text("Collected at the end").tag(true)
                }
            }
        }
        .padding()
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if sections.isEmpty {
                    Text("This meeting has no summary yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    sectionGroup
                }
                otherGroup
            }
            .padding()
        }
    }

    private var sectionGroup: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("SUMMARY SECTIONS")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(allSectionsSelected ? "None" : "All") {
                    selectedSections = allSectionsSelected ? [] : Set(sections.map(\.id))
                }
                .buttonStyle(.link)
                .font(.caption)
            }
            ForEach(sections, id: \.id) { section in
                Toggle(isOn: binding(for: section.id)) {
                    Text(section.title)
                        .lineLimit(2)
                }
                .toggleStyle(.checkbox)
            }
        }
    }

    @ViewBuilder
    private var otherGroup: some View {
        // Only offer what this meeting actually has — a tickbox for something
        // that would print nothing is a small lie.
        if hasActionItems || hasFollowUps || hasSharedScreens || hasTranscript {
            VStack(alignment: .leading, spacing: 8) {
                Text("ALSO INCLUDE")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                if hasActionItems {
                    Toggle("Action items (\(meeting.actionItems.count))", isOn: $includesActionItems)
                        .toggleStyle(.checkbox)
                }
                if hasFollowUps {
                    let count = meeting.latestInsight?.followUpQuestions.count ?? 0
                    Toggle("Open questions (\(count))", isOn: $includesFollowUps)
                        .toggleStyle(.checkbox)
                }
                if hasSharedScreens {
                    Toggle("Shared screens", isOn: $includesSharedScreens)
                        .toggleStyle(.checkbox)
                }
                if hasTranscript {
                    Toggle(isOn: $includesTranscript) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Full transcript (\(meeting.segments.count) segments)")
                            Text("Adds many pages")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Text(summaryLine)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Export…") {
                let chosen = options
                dismiss()
                onExport(chosen)
            }
            .keyboardShortcut(.defaultAction)
            .disabled(options.isEmpty)
        }
        .padding()
    }

    private var summaryLine: String {
        if options.isEmpty { return "Nothing selected" }
        let count = selectedSections.count
        return count == sections.count
            ? "All \(sections.count) section\(sections.count == 1 ? "" : "s")"
            : "\(count) of \(sections.count) sections"
    }

    private var allSectionsSelected: Bool {
        !sections.isEmpty && selectedSections.count == sections.count
    }

    private func binding(for id: Int) -> Binding<Bool> {
        Binding(
            get: { selectedSections.contains(id) },
            set: { isOn in
                if isOn { selectedSections.insert(id) } else { selectedSections.remove(id) }
            }
        )
    }
}
