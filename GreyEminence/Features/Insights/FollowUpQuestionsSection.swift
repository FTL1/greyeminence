import SwiftUI

struct FollowUpQuestionsSection: View {
    let questions: [String]
    var onOpenWorkspace: (() -> Void)?
    var reanalyzeControl: InsightReanalyzeControl? = nil
    var onDelete: ((Int) -> Void)?
    var onMove: ((IndexSet, Int) -> Void)? = nil
    var onModify: ((Int, String) -> Void)? = nil
    var onResearch: ((String) -> Void)? = nil
    @Environment(\.meetingFindQuery) private var findQuery
    @State private var isExpanded = true
    @State private var selectedIndex: Int?
    @State private var editingIndex: Int?
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "questionmark.bubble")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(Color.teal.gradient, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                            .onTapGesture {
                                if let onOpenWorkspace {
                                    onOpenWorkspace()
                                } else {
                                    withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
                                }
                            }
                            .help("Open Questions — create and organize follow-ups")
                        Text("Follow-up Questions")
                            .font(.subheadline.weight(.semibold))
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 0 : -90))
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if !questions.isEmpty {
                    CopyButton(
                        label: "Copy",
                        help: "Copy all follow-up questions",
                        html: { RichClipboard.listHTML(questions) }
                    ) {
                        questions.enumerated()
                            .map { "\($0.offset + 1). \($0.element)" }
                            .joined(separator: "\n")
                    }
                }
                if let reanalyzeControl {
                    reanalyzeControl
                }
            }

            if isExpanded {
                List {
                    ForEach(Array(questions.enumerated()), id: \.offset) { index, question in
                        InsightItemChrome(
                            isSelected: selectedIndex == index,
                            onSelect: { selectedIndex = index },
                            copyText: question,
                            onModify: onModify == nil ? nil : {
                                draft = question
                                editingIndex = index
                            },
                            onDelete: onDelete == nil ? nil : { onDelete?(index) },
                            onResearch: onResearch == nil ? nil : { onResearch?(question) }
                        ) {
                            HStack(alignment: .top, spacing: 8) {
                                Text("\(index + 1).")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20, alignment: .trailing)
                                HighlightedBody(text: question, query: findQuery, font: .body)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                    .onMove { source, dest in
                        onMove?(source, dest)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollDisabled(true)
                .frame(height: CGFloat(max(questions.count, 1) * 40))
                .help("Click to select. Right-click to modify, research, or delete. Drag to reorder.")
            }
        }
        .padding(.horizontal)
        .sheet(isPresented: Binding(
            get: { editingIndex != nil },
            set: { if !$0 { editingIndex = nil } }
        )) {
            InsightEditSheet(
                title: "Modify follow-up",
                text: $draft,
                onCancel: { editingIndex = nil },
                onSave: {
                    if let editingIndex {
                        onModify?(editingIndex, draft)
                    }
                    self.editingIndex = nil
                }
            )
        }
    }
}
