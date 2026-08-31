import SwiftUI
import AppKit

/// Shared select / right-click / drag chrome for intelligence rows.
struct InsightItemChrome<Content: View>: View {
    let isSelected: Bool
    var onSelect: () -> Void
    var copyText: String? = nil
    var onModify: (() -> Void)?
    var onDelete: (() -> Void)?
    var onResearch: (() -> Void)?
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.45) : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
            .onTapGesture { onSelect() }
            .contextMenu {
                if let onModify {
                    Button("Modify…") { onModify() }
                }
                if let onResearch {
                    Button("Research…") { onResearch() }
                }
                if let copyText {
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(copyText, forType: .string)
                    }
                }
                if (onModify != nil || onResearch != nil || copyText != nil), onDelete != nil {
                    Divider()
                }
                if let onDelete {
                    Button("Delete", role: .destructive) { onDelete() }
                }
            }
    }
}

struct InsightEditSheet: View {
    let title: String
    @Binding var text: String
    var onCancel: () -> Void
    var onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            TextEditor(text: $text)
                .font(.body)
                .frame(minHeight: 120)
                .border(Color.primary.opacity(0.12), width: 1)
            HStack {
                Button("Cancel", action: onCancel)
                Spacer()
                Button("Save") { onSave() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 420, height: 240)
    }
}

enum InsightReorder {
    static func move<T>(_ items: inout [T], from source: IndexSet, to destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
    }
}
