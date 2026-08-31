import AppKit
import SwiftUI

/// Privacy-first feedback: pane + what you want, posted as a GitHub issue.
/// Screenshots and meeting content stay off unless you opt in. The image is
/// never uploaded by the app — you attach it yourself on GitHub.
struct FeedbackSheet: View {
    @Environment(\.dismiss) private var dismiss
    @FocusedValue(\.currentHelpPane) private var currentPane

    @State private var kind: Kind = .bug
    @State private var pane: String = ""
    @State private var details = ""
    @State private var includeScreenshot = false
    @State private var screenshotURL: URL?
    @State private var captureWarning: String?
    @State private var copyNote: String?

    enum Kind: String, CaseIterable, Identifiable {
        case bug = "Bug"
        case confusing = "Confusing"
        case feature = "Feature"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Send feedback")
                .font(.title2.weight(.semibold))
            Text("Opens a GitHub issue on FTL1/grey-conseil. Default is text only: which pane, what broke or what you want. Meeting titles, transcripts, and screenshots are not attached unless you turn that on.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker("Kind", selection: $kind) {
                ForEach(Kind.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .help("Bug = something broken. Confusing = you cannot tell what a control does. Feature = something you want.")

            TextField("Pane or control (e.g. New Recording → Live AI)", text: $pane)
                .textFieldStyle(.roundedBorder)
                .help("Which screen or control. Filled from the front window when possible. No meeting names.")

            TextEditor(text: $details)
                .font(.body)
                .frame(minHeight: 120)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(.separator)
                )
                .help("What happened, or what you want. Do not paste quotes, emails, or names unless you mean to publish them.")

            Toggle("Include a screenshot of this window (off by default)", isOn: $includeScreenshot)
                .help("Saves a picture of the front window on this Mac. The app does not upload it. You can attach it on GitHub. The image may show names or transcript text that is on screen.")
                .onChange(of: includeScreenshot) { _, on in
                    if on { captureScreenshot() } else { screenshotURL = nil; captureWarning = nil }
                }

            if let captureWarning {
                Text(captureWarning)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if let screenshotURL {
                HStack {
                    Text(screenshotURL.lastPathComponent)
                        .font(.caption)
                        .lineLimit(1)
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([screenshotURL])
                    }
                    .controlSize(.small)
                }
            }

            GroupBox("What will be sent") {
                ScrollView {
                    Text(issueBody)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 140)
            }

            if let copyNote {
                Text(copyNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                    NSApp.keyWindow?.performClose(nil)
                }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Copy text") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(issueBody, forType: .string)
                    copyNote = "Copied. Paste into the GitHub form if the browser URL is too long."
                }
                Button("Open GitHub issue") {
                    openGitHub()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 560)
        .onAppear {
            if pane.isEmpty {
                pane = inferredPane
            }
        }
    }

    private var inferredPane: String {
        if let currentPane, !currentPane.isEmpty { return currentPane }
        if let stored = UserDefaults.standard.string(forKey: "lastHelpPane"), !stored.isEmpty {
            return stored
        }
        let title = NSApp.keyWindow?.title ?? ""
        if title.localizedCaseInsensitiveContains("setting") { return "Settings" }
        if title.localizedCaseInsensitiveContains("help") { return "Help" }
        return "Main window"
    }

    private var issueTitle: String {
        let paneBit = pane.trimmingCharacters(in: .whitespacesAndNewlines)
        let short = paneBit.isEmpty ? "app" : paneBit
        return "[\(kind.rawValue)] \(short)"
    }

    private var issueBody: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        var lines: [String] = [
            "## \(kind.rawValue)",
            "",
            "**Pane:** \(FeedbackAnonymizer.scrub(pane.isEmpty ? inferredPane : pane))",
            "**App:** Grey Conseil \(version)",
            "**macOS:** \(os)",
            "**Identity:** bundle ID only (`com.ftl1.greyeminence`) — no meeting titles or transcripts were attached by default.",
            "",
            "### What",
            FeedbackAnonymizer.scrub(details).isEmpty ? "_none_" : FeedbackAnonymizer.scrub(details),
            "",
        ]
        if includeScreenshot {
            lines.append("### Screenshot")
            lines.append("Captured locally on the reporter’s Mac. **Not uploaded by the app.** Attach the file on GitHub only if it does not show private meeting content.")
            if let screenshotURL {
                lines.append("Local file: `\(screenshotURL.lastPathComponent)`")
            }
            lines.append("")
        } else {
            lines.append("_No screenshot (default)._")
            lines.append("")
        }
        lines.append("---")
        lines.append("Filed from Grey Conseil **Help → Send feedback**. Unofficial fork; not Grey Eminence.")
        return lines.joined(separator: "\n")
    }

    private func captureScreenshot() {
        captureWarning = nil
        guard let image = FeedbackCapture.keyWindowImage() else {
            captureWarning = "Could not capture the front window. Leave this off and describe the pane in text."
            includeScreenshot = false
            return
        }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("GreyConseil-feedback-\(stamp).png")
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            captureWarning = "Could not write a PNG. Leave the checkbox off."
            includeScreenshot = false
            return
        }
        do {
            try png.write(to: url)
            screenshotURL = url
            captureWarning = "Saved on this Mac only. The picture may include names or transcript text visible in the window. Attach it on GitHub yourself — Grey Conseil will not upload it."
        } catch {
            captureWarning = error.localizedDescription
            includeScreenshot = false
        }
    }

    private func openGitHub() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(issueBody, forType: .string)
        if let screenshotURL, includeScreenshot {
            NSWorkspace.shared.activateFileViewerSelecting([screenshotURL])
        }
        var comps = URLComponents(string: "https://github.com/FTL1/grey-conseil/issues/new")
        comps?.queryItems = [
            URLQueryItem(name: "title", value: issueTitle),
            URLQueryItem(name: "body", value: issueBody),
        ]
        if let url = comps?.url, url.absoluteString.count < 7000 {
            NSWorkspace.shared.open(url)
        } else if let fallback = URL(string: "https://github.com/FTL1/grey-conseil/issues/new") {
            NSWorkspace.shared.open(fallback)
            copyNote = "Issue text is on the clipboard — paste it into the GitHub form (the URL was too long)."
        }
    }
}

enum FeedbackAnonymizer {
    /// Strip emails and obvious phone numbers from text we put on GitHub.
    static func scrub(_ raw: String) -> String {
        var text = raw
        if let email = try? NSRegularExpression(pattern: #"[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}"#, options: [.caseInsensitive]) {
            text = email.stringByReplacingMatches(
                in: text,
                range: NSRange(text.startIndex..., in: text),
                withTemplate: "[email]"
            )
        }
        if let phone = try? NSRegularExpression(pattern: #"\b(?:\+?1[-.\s]?)?(?:\(?\d{3}\)?[-.\s]?)\d{3}[-.\s]?\d{4}\b"#) {
            text = phone.stringByReplacingMatches(
                in: text,
                range: NSRange(text.startIndex..., in: text),
                withTemplate: "[phone]"
            )
        }
        return text
    }
}

enum FeedbackCapture {
    @MainActor
    static func keyWindowImage() -> NSImage? {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow,
              let view = window.contentView else { return nil }
        let bounds = view.bounds
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        view.cacheDisplay(in: bounds, to: rep)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(rep)
        return image
    }
}

private struct CurrentHelpPaneKey: FocusedValueKey {
    typealias Value = String
}

extension FocusedValues {
    var currentHelpPane: String? {
        get { self[CurrentHelpPaneKey.self] }
        set { self[CurrentHelpPaneKey.self] = newValue }
    }
}
