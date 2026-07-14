import Foundation

enum AIPromptTemplates {
    static let keychainKey = "claude_api_key"

    /// Bumped whenever the built-in prompt text changes meaningfully. Persisted with
    /// MeetingInsight so we can tell which prompt generation produced a given result
    /// and offer "regenerate with newer prompt" UX later.
    static let promptVersion = "meeting.v3"

    // MARK: - Public accessors
    //
    // Each accessor consults `PromptStore` first. If the user has saved an override
    // via the developer settings, that text is used (with `{{placeholder}}` tokens
    // substituted). Otherwise the hardcoded default below is used. This gives us a
    // zero-disruption runtime editor while keeping defaults in source.

    static var systemPrompt: String {
        PromptStore.shared.get(.meetingSystem, default: defaultSystemPrompt)
    }

    static func initialAnalysisPrompt(transcript: String) -> String {
        let template = PromptStore.shared.get(.meetingInitial, default: defaultInitialAnalysisPrompt)
        return PromptStore.render(template, values: ["transcript": transcript])
    }

    static func rollingAnalysisPrompt(
        previousSummary: String,
        previousActionItems: [ParsedActionItem],
        previousFollowUps: [String],
        previousTopics: [String],
        newTranscript: String,
        suppressedActionItems: [String] = [],
        suppressedFollowUps: [String] = []
    ) -> String {
        let template = PromptStore.shared.get(.meetingRolling, default: defaultRollingAnalysisPrompt)
        return PromptStore.render(template, values: [
            "previousSummary": previousSummary,
            "previousActionItems": formatActionItems(previousActionItems),
            "previousFollowUps": formatNumberedList(previousFollowUps),
            "previousTopics": formatTopics(previousTopics),
            "newTranscript": newTranscript,
            "suppressionBlock": suppressionBlock(actionItems: suppressedActionItems, followUps: suppressedFollowUps),
        ])
    }

    static func finalCleanupPrompt(
        fullTranscript: String,
        currentSummary: String,
        currentActionItems: [ParsedActionItem],
        currentFollowUps: [String],
        currentTopics: [String],
        suppressedActionItems: [String] = [],
        suppressedFollowUps: [String] = [],
        relatedContext: String? = nil
    ) -> String {
        let template = PromptStore.shared.get(.meetingFinal, default: defaultFinalCleanupPrompt)
        return PromptStore.render(template, values: [
            "fullTranscript": fullTranscript,
            "currentSummary": currentSummary,
            "currentActionItems": formatActionItems(currentActionItems),
            "currentFollowUps": formatNumberedList(currentFollowUps),
            "currentTopics": formatTopics(currentTopics),
            "suppressionBlock": suppressionBlock(actionItems: suppressedActionItems, followUps: suppressedFollowUps),
            "relatedContext": relatedContextBlock(relatedContext),
        ])
    }

    /// Wraps retrieved snippets from other meetings in instructions that scope
    /// them to blind-spot detection only. Empty string when there's nothing —
    /// the template renders cleanly without the block.
    static func relatedContextBlock(_ snippets: String?) -> String {
        guard let snippets, !snippets.isEmpty else { return "" }
        return """


        RELATED DISCUSSIONS FROM OTHER MEETINGS:
        The snippets below come from OTHER meetings' transcripts — none of this was said \
        in this meeting. Use them ONLY to find blind spots: if they raise concerns, \
        constraints, stakeholders, decisions, or topics relevant to this meeting's purpose \
        that this meeting never touched, turn those into follow_ups. Do NOT import them \
        into the summary, action items, or topics.

        \(snippets)
        """
    }

    /// Builds a "DO NOT RE-SUGGEST" block for prompts when the user has deleted
    /// action items or follow-ups on a prior run. Returns an empty string when
    /// both lists are empty so the template renders cleanly.
    private static func suppressionBlock(actionItems: [String], followUps: [String]) -> String {
        guard !actionItems.isEmpty || !followUps.isEmpty else { return "" }
        var block = "\n\nSUPPRESSED ITEMS — DO NOT RE-SUGGEST:\nThe user has explicitly deleted the following from a prior analysis. Do NOT include these (or semantically equivalent rewordings) in `action_items` or `follow_ups`.\n"
        if !actionItems.isEmpty {
            block += "\nSuppressed action items:\n"
            for item in actionItems {
                block += "- \(item)\n"
            }
        }
        if !followUps.isEmpty {
            block += "\nSuppressed follow-up questions:\n"
            for q in followUps {
                block += "- \(q)\n"
            }
        }
        return block
    }

    /// Return the built-in default for a key. Used by the editor to show a diff /
    /// preview against the user's override, and to power "Restore to default".
    static func defaultText(for key: PromptKey) -> String {
        switch key {
        case .meetingSystem:  defaultSystemPrompt
        case .meetingInitial: defaultInitialAnalysisPrompt
        case .meetingRolling: defaultRollingAnalysisPrompt
        case .meetingFinal:   defaultFinalCleanupPrompt
        }
    }

    // MARK: - Helpers

    static func formatSegments(_ segments: [SegmentSnapshot]) -> String {
        segments
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { "[\($0.formattedTimestamp)] \($0.speaker.displayName): \($0.text)" }
            .joined(separator: "\n")
    }

    /// Enriched system prompt with the meeting roster and prep context for
    /// cross-meeting intelligence.
    static func systemPromptWithContext(prep: MeetingPrepContext?, roster: MeetingRoster? = nil) -> String {
        let base = systemPrompt + rosterBlock(roster)
        guard let prep, prep.hasContent else { return base }

        var contextBlock = "\n\nCONTEXT FROM PREVIOUS OCCURRENCES OF THIS RECURRING MEETING:\n"

        if !prep.unresolvedItems.isEmpty {
            contextBlock += "\nUnresolved action items:\n"
            for item in prep.unresolvedItems {
                let assignee = item.assignee.map { " (assigned: \($0))" } ?? ""
                contextBlock += "- \(item.text)\(assignee) [\(item.daysSinceCreated) days old]\n"
            }
        }

        if !prep.followUps.isEmpty {
            contextBlock += "\nOpen follow-up questions:\n"
            for q in prep.followUps {
                contextBlock += "- \(q)\n"
            }
        }

        if !prep.previousTopics.isEmpty {
            contextBlock += "\nPreviously discussed topics: \(prep.previousTopics.joined(separator: ", "))\n"
        }

        contextBlock += """

        Watch for any of these items being discussed or resolved during the meeting. \
        If an unresolved item is addressed, note it in the summary. If an open question \
        is answered, remove it from follow_ups.
        """

        return base + contextBlock
    }

    /// Participant block appended to the system prompt when the attendee list
    /// is known beyond just the user. Anchors "assignee" to real names so
    /// items land on the correct attendee, and lets the model apply the
    /// ownership rules (mine / unowned / 1:1 exception) reliably.
    static func rosterBlock(_ roster: MeetingRoster?) -> String {
        guard let roster, !roster.otherAttendees.isEmpty else { return "" }
        let user = roster.myName.map { "\($0) — they appear in the transcript as \"Me\"" }
            ?? "the person appearing in the transcript as \"Me\""
        return """


        MEETING PARTICIPANTS:
        The tool user is \(user). Other attendees: \(roster.otherAttendees.joined(separator: ", ")).
        When setting "assignee", use exactly "Me" for the tool user or one of the attendee \
        names above — match the person the transcript actually refers to; never invent a \
        name that isn't listed.
        """
    }

    private static func formatActionItems(_ items: [ParsedActionItem]) -> String {
        items.isEmpty
            ? "(none)"
            : items.enumerated().map { i, item in
                let assignee = item.assignee.map { " (assigned: \($0))" } ?? ""
                return "\(i + 1). \(item.text)\(assignee)"
            }.joined(separator: "\n")
    }

    private static func formatNumberedList(_ items: [String]) -> String {
        items.isEmpty
            ? "(none)"
            : items.enumerated().map { "\($0 + 1). \($1)" }.joined(separator: "\n")
    }

    private static func formatTopics(_ topics: [String]) -> String {
        topics.isEmpty ? "(none)" : topics.joined(separator: ", ")
    }

    // MARK: - Hardcoded defaults

    private static let defaultSystemPrompt: String = """
        You are a meeting intelligence assistant. Your job is to analyze meeting transcripts \
        and produce structured insights.

        You MUST respond with ONLY valid JSON matching this exact schema — no prose, no markdown, \
        no explanation before or after:

        {
          "title": "Short descriptive meeting title (5-8 words, final analysis only, omit during rolling analysis)",
          "summary": [
            {
              "title": "Section title (2-5 words, sentence case, no period)",
              "intro": "One optional sentence framing this section. Omit key if not needed.",
              "points": [
                { "label": "Subject (1-4 words)", "detail": "1-3 sentence explanation of this point." }
              ]
            }
          ],
          "action_items": [{"text": "description of action", "assignee": "person or null", "source_quote": "verbatim phrase from the transcript that triggered this item"}],
          "follow_ups": ["question that should be followed up on"],
          "topics": ["Theme Topic", "specific-tool", "ACRONYM", "PersonName"]
        }

        Rules:
        - "summary" MUST be a JSON array of section objects as shown above. Return [] if there \
        is not enough substantive content yet — never return filler sections.
        - Group related points into coherent sections. Aim for 2-5 sections with 2-6 points each. \
        Each section covers one theme or topic area from the meeting.
        - Each point's "label" is the subject (1-4 words, title case). "detail" is 1-3 sentences \
        of specific, concrete information — what was discussed, decided, or proposed.
        - Never include meta-observations about the meeting itself (e.g. "Meeting covered several topics").
        - The "intro" field is optional — include it only when a sentence of context genuinely helps \
        frame the points below it. Otherwise omit the key entirely.
        - "action_items" exist for ONE person: the tool user (the "Me" speaker in the \
        transcript). Include only (1) tasks the user personally committed to or was asked \
        to take on, and (2) tasks nobody clearly owns. Do NOT include tasks another \
        attendee clearly owns — the summary already captures what other people are doing. \
        EXCEPTION — 1:1 meetings: when exactly two people are in the meeting (the user and \
        one other person), include the other person's commitments too, and if a task is \
        definitely not the user's, set "assignee" to the other participant's name rather \
        than leaving it unowned. \
        Be selective: only concrete, deliberate commitments — never vague intentions, \
        hypotheticals, or process observations. A typical 30-minute meeting yields 3-6 \
        genuine action items; more than 8 means you are over-extracting — merge related \
        tasks and drop the marginal ones. \
        Set "assignee" to "Me" when the task is the user's, the other participant's name \
        under the 1:1 exception, or null when ownership is genuinely unclear. \
        Set "source_quote" to a short verbatim snippet (one sentence, 5-25 words) copied from \
        the transcript that triggered this action — the exact words a speaker said, not your \
        paraphrase. This anchors the task to a specific moment in the conversation. Pick the \
        single most direct sentence; do not concatenate multiple turns.
        - "follow_ups" are BLIND SPOTS: specific questions about things that were NOT \
        discussed in the meeting but are likely relevant to its purpose — the questions \
        nobody thought to ask. Look for: risks or failure modes nobody raised, stakeholders \
        or perspectives that were missing from the conversation, alternatives that went \
        unexamined, dependencies or second-order consequences of the decisions made, and \
        (when RELATED DISCUSSIONS from other meetings are provided) relevant prior context \
        this meeting overlooked. \
        Hard rules: a follow-up must NOT be answerable from the transcript — if the meeting \
        discussed it, even partially, it does not belong here. DO NOT restate a summary \
        point or an action item as a question — if a task is "Investigate X", do not emit \
        "What is X?" or "Who will investigate X?". DO NOT ask for status updates on things \
        already assigned. Avoid generic questions that could be asked of any meeting \
        ("What is the timeline?") — every question must be anchored in this meeting's \
        specific content. Quality over quantity: 2-5 sharp questions beat a long list. \
        If nothing qualifies, return an empty array.
        - "topics" should include TWO types, merged into one flat array ordered by prominence: \
        (1) Theme topics: broad subjects discussed (e.g. "System Design", "Code Review Process") \
        (2) Key terms: specific proper nouns, acronyms, tools, services, platforms, libraries, \
        or named systems mentioned (e.g. "OLP", "AIDC", "Kafka", "DynamoDB", "React"). \
        Extract ALL specific named entities — these are critical for cross-meeting knowledge mapping. \
        Prefer the canonical form (e.g. "DynamoDB" not "dynamo", "AIDC" not "aidc").
        - If there is not enough content to produce meaningful insights, return empty arrays and \
        [] for summary. Do not generate placeholder or filler text.
        - When updating a rolling analysis, ALWAYS preserve all previous action items, topics, \
        and follow-up questions. The PREVIOUS SUMMARY is a JSON array — parse it, keep all existing \
        sections and points, add new points to the relevant sections or add new sections for new topics. \
        Never drop earlier insights unless explicitly resolved, contradicted, or revealed \
        to be owned by another attendee (per the action_items ownership rules).
        """

    private static let defaultInitialAnalysisPrompt: String = """
        Analyze the following meeting transcript and produce structured insights.

        TRANSCRIPT:
        {{transcript}}
        """

    private static let defaultRollingAnalysisPrompt: String = """
        Here is your complete previous analysis of this meeting:

        PREVIOUS SUMMARY (JSON array of section objects — parse and extend this):
        {{previousSummary}}

        PREVIOUS ACTION ITEMS:
        {{previousActionItems}}

        PREVIOUS FOLLOW-UP QUESTIONS:
        {{previousFollowUps}}

        PREVIOUS TOPICS:
        {{previousTopics}}

        New transcript segments have been recorded since then. Extend your previous analysis \
        with the new content. For the summary: keep all existing sections and points, add new \
        points to relevant existing sections, and add new sections for genuinely new topics. \
        Keep ALL existing action items, follow-ups, and topics. Add new ones from the new transcript. \
        For topics: extract both theme topics AND specific key terms (proper nouns, acronyms, \
        tools, services, platforms) mentioned in the new segments.

        NEW TRANSCRIPT:
        {{newTranscript}}
        {{suppressionBlock}}
        """

    private static let defaultFinalCleanupPrompt: String = """
        The meeting has ended. Below is the full transcript and the insights accumulated \
        during live analysis. Produce a final, polished version of the insights.

        Your tasks:
        - Generate a short, descriptive title for this meeting (5-8 words max, no quotes). \
        The title should capture the main topic or purpose, e.g. "Sprint Planning - Auth Service Redesign" \
        or "Q1 Budget Review with Finance". Return it in the "title" field.
        - Produce a clean, comprehensive summary as a JSON array of section objects (same schema \
        as always). The CURRENT SUMMARY below is already in this JSON format — refine it: \
        merge redundant points, tighten wording, reorder sections by importance, remove any \
        meta-observations. Cover the full meeting arc.
        - Deduplicate action items — merge near-duplicates, remove redundant ones, \
        and keep the clearest phrasing. Re-check ownership against the full transcript: \
        drop any item another attendee clearly owns (unless the two-person exception \
        applies) and fix assignees that don't match what was actually said.
        - Re-derive the follow-up questions against the FULL transcript. Drop any \
        accumulated question the transcript actually answers or that overlaps an action \
        item, merge near-duplicates, and add new blind-spot questions now visible from \
        the complete meeting arc (and from RELATED DISCUSSIONS, when provided).
        - Consolidate topics — remove exact duplicates and merge near-duplicates, but keep both \
        theme topics (broad subjects) AND key terms (specific names, acronyms, tools, services). \
        Order themes first by prominence, then key terms alphabetically. Preserve canonical forms \
        (e.g. "DynamoDB" not "dynamo").
        - Correct any speaker attribution errors that are obvious from context.

        ACCUMULATED INSIGHTS FROM LIVE ANALYSIS:

        Summary:
        {{currentSummary}}

        Action Items:
        {{currentActionItems}}

        Follow-up Questions:
        {{currentFollowUps}}

        Topics:
        {{currentTopics}}

        FULL TRANSCRIPT:
        {{fullTranscript}}
        {{relatedContext}}
        {{suppressionBlock}}
        """
}
