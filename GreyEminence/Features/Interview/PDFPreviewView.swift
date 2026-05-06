import SwiftUI
import PDFKit

/// Inline PDF preview for attached resumes.
struct PDFPreviewView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.pageShadowsEnabled = true
        view.backgroundColor = .clear
        view.document = PDFDocument(url: url)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        // Skip the expensive PDFDocument re-init if the URL hasn't changed.
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
        }
    }
}
