import SwiftUI

struct ActionItemsSection: View {
    let items: [ActionItem]
    var onOpenWorkspace: (() -> Void)?
    var reanalyzeControl: InsightReanalyzeControl? = nil
    var onDelete: ((ActionItem) -> Void)?
    var onMove: ((IndexSet, Int) -> Void)? = nil
    var onModify: ((ActionItem, String) -> Void)? = nil
    var onResearch: ((ActionItem) -> Void)? = nil
    @State private var isExpanded = true
    @State private var selectedID: UUID?
    @State private var editing: ActionItem?
    @State private var draft = ""

    private var pendingItems: [ActionItem] { items.filter { !$0.isCompleted } }
    private var pendingCount: Int { pendingItems.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(Color.orange.gradient, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                            .onTapGesture {
                                if let onOpenWorkspace {
                                    onOpenWorkspace()
                                } else {
                                    withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
                                }
                            }
                            .help("Open Tasks — organize action items")
                        Text("Action Items")
                            .font(.subheadline.weight(.semibold))
                        if pendingCount > 0 {
                            Text("\(pendingCount)")
                                .font(.caption2).fontWeight(.bold)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(.orange.opacity(0.2), in: Capsule())
                                .foregroundStyle(.orange)
                        }
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 0 : -90))
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if pendingCount > 0 {
                    CopyButton(
                        label: "Copy",
                        help: "Copy unresolved action items",
                        html: { RichClipboard.listHTML(Self.plainItems(pendingItems)) }
                    ) {
                        Self.plainText(items: pendingItems)
                    }
                }
                if let reanalyzeControl {
                    reanalyzeControl
                }
            }

            if isExpanded {
                List {
                    ForEach(items) { item in
                        InsightItemChrome(
                            isSelected: selectedID == item.id,
                            onSelect: { selectedID = item.id },
                            copyText: item.text,
                            onModify: onModify == nil ? nil : {
                                draft = item.text
                                editing = item
                            },
                            onDelete: onDelete == nil ? nil : { onDelete?(item) },
                            onResearch: onResearch == nil ? nil : { onResearch?(item) }
                        ) {
                            ActionItemRow(item: item, onDelete: onDelete)
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
                .frame(height: CGFloat(max(items.count, 1) * 52))
                .help("Click to select. Right-click to modify, research, or delete. Drag to reorder.")
            }
        }
        .padding(.horizontal)
        .sheet(item: $editing) { item in
            InsightEditSheet(
                title: "Modify action item",
                text: $draft,
                onCancel: { editing = nil },
                onSave: {
                    onModify?(item, draft)
                    editing = nil
                }
            )
        }
    }

    private static func plainItems(_ items: [ActionItem]) -> [String] {
        items.map { item in
            if let who = item.displayAssignee, !who.isEmpty {
                return "[\(who)] \(item.text)"
            }
            return item.text
        }
    }

    private static func plainText(items: [ActionItem]) -> String {
        plainItems(items).map { "- \($0)" }.joined(separator: "\n")
    }
}

struct LiveActionItemsSection: View {
    let items: [ActionItem]
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(Color.orange.gradient, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    Text("Action Items")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(items.count)")
                        .font(.caption2).fontWeight(.bold)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.orange.opacity(0.2), in: Capsule())
                        .foregroundStyle(.orange)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(items) { item in
                        HStack(spacing: 8) {
                            Image(systemName: "circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.text)
                                    .font(.body)
                                if let assignee = item.displayAssignee {
                                    Text(assignee)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
    }
}
