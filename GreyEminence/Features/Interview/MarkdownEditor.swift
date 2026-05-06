import SwiftUI
import AppKit

/// SwiftUI wrapper around `NSTextView` that exposes both the text and the
/// current selection range, so callers can build toolbars that wrap the
/// selected text with markdown markers (bold, italic, code, etc.). Plain
/// SwiftUI `TextEditor` doesn't expose selection, which is why this wrap
/// is necessary.
struct MarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let textView = scroll.documentView as! NSTextView
        textView.delegate = context.coordinator
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.allowsUndo = true
        textView.isRichText = false
        textView.string = text
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text {
            // Preserve the user's cursor position when the binding mutates
            // from outside (e.g., a toolbar button rewrote the string).
            let range = textView.selectedRange()
            textView.string = text
            let safeLocation = min(range.location, text.count)
            textView.setSelectedRange(NSRange(location: safeLocation, length: 0))
        }
        if textView.selectedRange() != selectedRange
            && selectedRange.location <= text.count
            && NSMaxRange(selectedRange) <= text.count {
            textView.setSelectedRange(selectedRange)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownEditor
        init(_ parent: MarkdownEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            parent.selectedRange = tv.selectedRange()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.selectedRange = tv.selectedRange()
        }
    }
}
