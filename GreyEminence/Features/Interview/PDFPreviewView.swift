import SwiftUI
import PDFKit

/// Embedded PDF preview backed by PDFKit's `PDFView`. Used in the
/// candidate detail screen to show an attached resume inline rather
/// than handing it off to Preview. Read-only, scroll-paginated,
/// with the standard PDFKit zoom/scroll controls inherited from AppKit.
struct PDFPreviewView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        // Inset the page contents slightly so the doc doesn't hug the
        // edges of the inspector panel.
        view.pageShadowsEnabled = true
        view.backgroundColor = .clear
        view.document = PDFDocument(url: url)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        // Reload only when the URL actually changes — comparing the
        // existing document's URL avoids an expensive PDFDocument
        // re-init on every SwiftUI redraw.
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
        }
    }
}
