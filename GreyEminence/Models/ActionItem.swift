import Foundation
import SwiftData

@Model
final class ActionItem {
    var id: UUID
    var text: String
    var assignee: String?
    var isCompleted: Bool
    var createdAt: Date

    // Commitment tracking
    var dueDate: Date?
    var sourceSegmentID: UUID?

    /// Set when the user explicitly marks this item as "won't do". Distinct
    /// from `isCompleted` (done) — a dismissed item drops out of pending +
    /// stalled but isn't counted as accomplished. Nil for pending and
    /// completed items.
    var dismissedAt: Date?

    var meeting: Meeting?
    var assignedContact: Contact?

    init(text: String, assignee: String? = nil, isCompleted: Bool = false) {
        self.id = UUID()
        self.text = text
        self.assignee = assignee
        self.isCompleted = isCompleted
        self.createdAt = .now
    }

    var isDismissed: Bool { dismissedAt != nil }

    /// Build an action item from an AI-parsed result and resolve its source
    /// segment from the supplied transcript. The caller still owns attaching
    /// the item to a meeting — done separately because some flows defer the
    /// attachment until after analysis completes.
    convenience init(parsed: ParsedActionItem, sourceSegments: [TranscriptSegment]) {
        self.init(text: parsed.text, assignee: parsed.assignee)
        self.sourceSegmentID = sourceSegments.segmentID(matchingQuote: parsed.sourceQuote)
    }

    var displayAssignee: String? {
        assignedContact?.name ?? assignee
    }
}

extension ActionItem: Identifiable {}
