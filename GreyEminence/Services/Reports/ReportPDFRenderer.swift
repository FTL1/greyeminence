import AppKit
import Foundation
import WebKit

/// Renders self-contained report HTML to a paginated PDF on disk.
///
/// Uses `WKWebView.printOperation` rather than `createPDF`. Measured
/// 2026-08-12 on the same 30-paragraph document: `createPDF` returned a
/// single page 595×2656pt — the whole scroll height as one strip, useless for
/// a report — while the print operation returned four correctly paginated
/// 612×792pt pages with the text layer intact. The print operation runs the
/// same paged-media machinery as Safari's "Export as PDF", so the template's
/// `@page` rules and `break-inside: avoid` are honoured.
///
/// The operation must be started with `runModal(for:delegate:didRun:)`, never
/// `run()`. `run()` blocks the main thread, and WebKit's printing needs main
/// run-loop turns to talk to its WebContent process, so the blocking form
/// deadlocks outright — it never returns, on documents as small as one
/// paragraph.
@MainActor
enum ReportPDFRenderer {

    enum RenderError: LocalizedError {
        case layoutFailed(String)
        case layoutTimedOut
        case printJobFailed

        var errorDescription: String? {
            switch self {
            case .layoutFailed(let reason): "Could not lay out the report: \(reason)"
            case .layoutTimedOut: "The report took too long to lay out."
            case .printJobFailed: "Could not write the PDF file."
            }
        }
    }

    /// US Letter at 72 dpi, matching `NSPrintInfo`'s point-based paper sizes.
    /// `nonisolated` so it can serve as a default argument, which Swift 6
    /// evaluates outside the actor.
    nonisolated static let letter = NSSize(width: 612, height: 792)
    nonisolated static let a4 = NSSize(width: 595, height: 842)

    /// Seconds to wait for the document — including data-URI fonts and
    /// images — to finish laying out before giving up.
    private static let layoutTimeout: Duration = .seconds(30)

    /// Render `html` to a PDF at `url`.
    ///
    /// Margins are deliberately zeroed on the print job: the template owns
    /// them through its `@page` rule. Setting both compounds them, and the
    /// content column drifts further inward on every template.
    static func writePDF(
        html: String,
        to url: URL,
        paperSize: NSSize = letter
    ) async throws {
        // `runModal(for:)` is sheet-modal, so it needs a host window. Parked
        // far offscreen and ordered to the back: never visible, never focused,
        // and `isOnScreen` stays false so the app's own screen-share window
        // picker cannot offer it as a capture candidate.
        let window = NSWindow(
            contentRect: NSRect(x: -30_000, y: -30_000, width: paperSize.width, height: paperSize.height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isExcludedFromWindowsMenu = true
        let webView = WKWebView(frame: NSRect(origin: .zero, size: paperSize))
        window.contentView?.addSubview(webView)
        window.orderBack(nil)
        defer {
            webView.removeFromSuperview()
            window.orderOut(nil)
        }

        try await load(html: html, into: webView)

        let info = NSPrintInfo()
        info.paperSize = paperSize
        info.topMargin = 0
        info.bottomMargin = 0
        info.leftMargin = 0
        info.rightMargin = 0
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url

        let operation = webView.printOperation(with: info)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        operation.view?.frame = NSRect(origin: .zero, size: paperSize)
        guard await PrintRun.start(operation, in: window) else {
            throw RenderError.printJobFailed
        }
    }

    // MARK: - Layout

    /// Load the document and wait until it is genuinely ready to print:
    /// navigation finished, web fonts resolved, and every image decoded.
    /// Printing earlier silently drops embedded faces back to the system
    /// font and can emit half-drawn figures.
    private static func load(html: String, into webView: WKWebView) async throws {
        let loader = NavigationLoader()
        webView.navigationDelegate = loader
        webView.loadHTMLString(html, baseURL: nil)
        defer { webView.navigationDelegate = nil }

        try await loader.wait(timeout: layoutTimeout)

        // `callAsyncJavaScript` awaits the promise; `evaluateJavaScript`
        // would return the pending Promise object and race the print job.
        _ = try? await webView.callAsyncJavaScript(
            """
            await document.fonts.ready;
            await Promise.all(
                Array.from(document.images)
                    .filter(image => !image.complete)
                    .map(image => new Promise(resolve => {
                        image.onload = resolve;
                        image.onerror = resolve;
                    }))
            );
            return true;
            """,
            contentWorld: .page
        )
    }

    /// Bridges the one-shot `WKNavigationDelegate` callbacks to async/await.
    /// Guards against the delegate firing twice (a failure after a finish, or
    /// two failure callbacks for one load), which would crash on a double
    /// continuation resume.
    @MainActor
    private final class NavigationLoader: NSObject, WKNavigationDelegate {
        private var continuation: CheckedContinuation<Void, Error>?
        private var outcome: Result<Void, Error>?

        /// The timeout lives here rather than in a surrounding task group:
        /// racing a group task against this MainActor-isolated, non-Sendable
        /// loader is something Swift 6's region-based isolation checker
        /// refuses to reason about.
        func wait(timeout: Duration) async throws {
            if let outcome { return try outcome.get() }
            let timeoutTask = Task { @MainActor in
                try? await Task.sleep(for: timeout)
                guard !Task.isCancelled else { return }
                self.finish(.failure(RenderError.layoutTimedOut))
            }
            defer { timeoutTask.cancel() }
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
            }
        }

        private func finish(_ result: Result<Void, Error>) {
            guard outcome == nil else { return }
            outcome = result
            continuation?.resume(with: result)
            continuation = nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            finish(.success(()))
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            finish(.failure(RenderError.layoutFailed(error.localizedDescription)))
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            finish(.failure(RenderError.layoutFailed(error.localizedDescription)))
        }
    }
}

/// Bridges `NSPrintOperation`'s sheet-modal completion callback to
/// async/await.
///
/// Lives at file scope, deliberately outside the `@MainActor` renderer:
/// AppKit delivers `printOperationDidRun` on a **background** thread — it is
/// invoked from `-[NSConcretePrintOperation _continueModalOperationToTheEnd:]`
/// on a thread of its own — so a MainActor-isolated callback traps in
/// `_checkExpectedExecutor` the moment the job finishes. A nested type would
/// inherit the enclosing actor isolation and reintroduce exactly that crash.
/// Resuming a continuation is safe from any thread.
///
/// `runModal` returns immediately and does not retain its delegate, hence the
/// deliberate self-reference: without it the handler is deallocated before the
/// job completes and the callback lands on freed memory.
private final class PrintRun: NSObject, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool, Never>?
    private var selfReference: PrintRun?

    @MainActor
    static func start(_ operation: NSPrintOperation, in window: NSWindow) async -> Bool {
        let handler = PrintRun()
        return await withCheckedContinuation { continuation in
            handler.lock.lock()
            handler.continuation = continuation
            handler.selfReference = handler
            handler.lock.unlock()
            operation.runModal(
                for: window,
                delegate: handler,
                didRun: #selector(PrintRun.printOperationDidRun(_:success:contextInfo:)),
                contextInfo: nil
            )
        }
    }

    @objc fileprivate func printOperationDidRun(
        _ operation: AnyObject?,
        success: Bool,
        contextInfo: UnsafeMutableRawPointer?
    ) {
        lock.lock()
        let pending = continuation
        continuation = nil
        // Held past the unlock: releasing the last reference to self while
        // still holding self's own lock would free the lock out from under us.
        let release = selfReference
        selfReference = nil
        lock.unlock()

        pending?.resume(returning: success)
        withExtendedLifetime(release) {}
    }
}
