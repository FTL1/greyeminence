import Foundation
import SwiftUI

enum Speaker: Codable, Hashable, Sendable {
    case me
    case other(String)

    // MARK: - Unidentified voices

    /// Label for a voice the diarizer heard but couldn't tell apart from the
    /// rest of the far side.
    static let unidentifiedLabel = "Speaker"

    /// A voice told apart from the others but not yet put to a person.
    /// Numbers are per-meeting: Speaker 2 in one meeting is not Speaker 2 in
    /// the next, which is why naming has to come from a voice profile.
    static func numbered(_ index: Int) -> Speaker { .other("\(unidentifiedLabel) \(index)") }

    /// The far side, undifferentiated.
    static let unidentified = Speaker.other(unidentifiedLabel)

    /// True for both of the above.
    ///
    /// The vocabulary lived as a string literal in six places — produced in
    /// two, matched in four, and already inconsistent about case. Owning it
    /// here means a producer constructs it and a consumer tests it through one
    /// type. Deliberately not a new `case`: `Speaker` is `Codable` and
    /// persisted, so an added case is a one-way change an older build can't
    /// decode.
    var isUnidentified: Bool {
        guard case .other(let name) = self else { return false }
        return name == Self.unidentifiedLabel
            || (name.hasPrefix(Self.unidentifiedLabel + " ")
                && Int(name.dropFirst(Self.unidentifiedLabel.count + 1)) != nil)
    }

    var displayName: String {
        switch self {
        case .me: "Me"
        case .other(let name): name
        }
    }

    var initials: String {
        switch self {
        case .me:
            return "ME"
        case .other(let name):
            let parts = name.split(separator: " ")
            if parts.count >= 2 {
                return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
            }
            return String(name.prefix(2)).uppercased()
        }
    }

    var isMe: Bool {
        if case .me = self { return true }
        return false
    }

    /// Stable color assignment based on speaker identity.
    var color: Color {
        switch self {
        case .me:
            return .blue
        case .other(let name):
            return Self.speakerColors[Self.colorIndex(for: name)]
        }
    }

    private static let speakerColors: [Color] = [
        .green,
        .orange,
        .purple,
        .pink,
        .teal,
        .indigo,
        .mint,
        .cyan,
    ]

    private static func colorIndex(for name: String) -> Int {
        // Stable hash-based color assignment so a given speaker name
        // always gets the same color within a session
        let hash = abs(name.hashValue)
        return hash % speakerColors.count
    }
}
