import Foundation

enum AIPromptTemplates {
    static let keychainKey = "claude_api_key"
    /// Dedicated xAI Console key. Never reuse `keychainKey`.
    static let xaiKeychainKey = "xai_api_key"

    /// Bumped whenever the built-in prompt text changes meaningfully. Persisted with
    /// MeetingInsight so we can tell which prompt generation produced a given result
    /// and offer "regenerate with newer prompt" UX later.
    static let promptVersion = "meeting.v6"

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

    /// Full rewrite used by the Reanalyze button. Does not see prior insights.
    static func reanalysisPrompt(
        transcript: String,
        calendarTitle: String,
        myName: String?,
        suppressedActionItems: [String] = [],
        suppressedFollowUps: [String] = []
    ) -> String {
        let template = PromptStore.shared.get(.meetingReanalysis, default: defaultReanalysisPrompt)
        return PromptStore.render(template, values: [
            "transcript": transcript,
            "calendarTitle": calendarTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "(none)"
                : calendarTitle,
            "myName": myName?.isEmpty == false ? myName! : "Me",
            "suppressionBlock": suppressionBlock(
                actionItems: suppressedActionItems,
                followUps: suppressedFollowUps
            ),
        ])
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
        in this meeting. Use them ONLY to find blind spots that are relevant to THIS \
        meeting's inferred purpose. Do NOT import them into the summary, action items, \
        or topics, and do NOT turn them into a generic domain questionnaire (financing, \
        environmental, engagement, timeline) unless someone in THIS meeting raised that gap.

        \(snippets)
        """
    }

    /// Wraps screen-share observations in instructions with the opposite
    /// fencing from prep context: this content IS part of the meeting and
    /// should shape the output — it just must never be attributed as speech.
    /// Empty string when there's nothing.
    static func screenObservationBlock(_ observations: String?) -> String {
        guard let observations, !observations.isEmpty else { return "" }
        return """


        SCREEN SHARE CONTENT (visible on screen, not spoken):
        The participants shared a screen during this meeting. The lines below are \
        observations of that screen at the given transcript timestamps. This content \
        IS part of the meeting — use it to inform the summary, topics, follow-up \
        questions, and action items — but never attribute it as something a person \
        said, and never quote it as speech. If the screen is a document, deck, or \
        proposal being reviewed for sending or correction, treat that as work product \
        (what the user is trying to fix), not as proof that the meeting's only topic \
        is the document's subject matter.

        \(observations)
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
        case .meetingReanalysis: defaultReanalysisPrompt
        case .meetingDeep: defaultDeepPrompt
        case .meetingDeepest: defaultDeepestPrompt
        case .screenSystem:   defaultScreenSystemPrompt
        case .screenAnalysis: defaultScreenAnalysisPrompt
        case .screenSessionSynthesis: defaultSessionSynthesisPrompt
        case .reportSystem:   defaultReportSystemPrompt
        case .reportFigureAnchors: defaultFigureAnchorPrompt
        }
    }

    // MARK: - Screen-frame analysis

    static var screenSystemPrompt: String {
        PromptStore.shared.get(.screenSystem, default: defaultScreenSystemPrompt)
    }

    static func screenAnalysisPrompt(
        frameCount: Int,
        frameManifest: String,
        recentTopics: [String],
        previousObservation: String?
    ) -> String {
        let template = PromptStore.shared.get(.screenAnalysis, default: defaultScreenAnalysisPrompt)
        return PromptStore.render(template, values: [
            "frameCount": "\(frameCount)",
            "frameManifest": frameManifest,
            "recentTopics": recentTopics.isEmpty ? "(none yet)" : recentTopics.joined(separator: ", "),
            "previousObservation": previousObservation ?? "(none — this is the first analyzed batch)",
        ])
    }

    // MARK: - Session synthesis

    static let sessionSynthesisSystemPrompt = """
        You are a meeting intelligence assistant. You fuse what was shown on \
        a shared screen with what was said while it was on screen, producing \
        a recap grounded strictly in the material you are given. You MUST \
        respond with ONLY valid JSON matching the schema in the user message — \
        no prose, no markdown, no explanation before or after.
        """

    static func sessionSynthesisPrompt(
        windowTitle: String?,
        sessionSpan: String,
        frameDescriptions: String,
        transcriptExcerpt: String
    ) -> String {
        let template = PromptStore.shared.get(.screenSessionSynthesis, default: defaultSessionSynthesisPrompt)
        return PromptStore.render(template, values: [
            "windowTitle": windowTitle?.isEmpty == false ? windowTitle! : "(untitled window)",
            "sessionSpan": sessionSpan,
            "frameDescriptions": frameDescriptions,
            "transcriptExcerpt": transcriptExcerpt,
        ])
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
            contextBlock += "\nFollow-up questions left open by prior occurrences:\n"
            for q in prep.followUps {
                contextBlock += "- \(q)\n"
            }
        }

        if !prep.previousTopics.isEmpty {
            contextBlock += "\nTopics discussed in prior occurrences: \(prep.previousTopics.joined(separator: ", "))\n"
        }

        contextBlock += """

        NONE of the above was said in the current meeting — it is background carried \
        over from prior occurrences, for reference only. Do NOT copy these questions \
        into "follow_ups", these topics into "topics", or these items into \
        "action_items": everything you output must be grounded in what is actually \
        said in the current transcript. Use this background only to recognize \
        continuity — if the discussion resolves an unresolved item or answers an open \
        question, note that in the summary.
        """

        return base + contextBlock
    }

    /// Participant block appended to the system prompt when the attendee list
    /// is known beyond just the user. Anchors "assignee" to real names so
    /// items land on the correct attendee, and lets the model apply the
    /// ownership rules (mine / unowned / 1:1 exception) reliably.
    static func rosterBlock(_ roster: MeetingRoster?) -> String {
        guard let roster, !roster.otherAttendees.isEmpty else { return "" }
        let transcriptLabel = roster.myAliases.first ?? Speaker.defaultMeLabel
        let user = roster.myName.map { "\($0) — they appear in the transcript as \"\(transcriptLabel)\"" }
            ?? "the person appearing in the transcript as \"\(transcriptLabel)\""
        return """


        MEETING PARTICIPANTS:
        The tool user is \(user). Other attendees: \(roster.otherAttendees.joined(separator: ", ")).
        When setting "assignee", use exactly "\(transcriptLabel)" or "Me" for the tool user or one of the attendee \
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
          "title": "Short descriptive meeting title (5-8 words) naming PURPOSE, not calendar subject. Omit only during rolling live analysis",
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
        - Infer the meeting's PURPOSE from what the tool user ("Me") was trying to get done — \
        updating documents, aligning language with what another speaker actually said, sending \
        a package, getting a decision — not merely the subject matter on a calendar invite or \
        a shared screen. Lead the summary with that purpose. A calendar title may be generic \
        or wrong.
        - "summary" MUST be a JSON array of section objects as shown above. Return [] if there \
        is not enough substantive content yet — never return filler sections.
        - Group related points into coherent sections. Aim for 2-5 sections with 2-6 points each. \
        Each section covers one theme or topic area from the meeting.
        - Each point's "label" is the subject (1-4 words, title case). "detail" is 1-3 sentences \
        of specific, concrete information — what was discussed, decided, or proposed.
        - Never include meta-observations about the meeting itself (e.g. "Meeting covered several topics").
        - The "intro" field is optional — include it only when a sentence of context genuinely helps \
        frame the points below it. Otherwise omit the key entirely.
        - "action_items" are every concrete commitment spoken in this meeting, whoever owns \
        it. The app stores all of them and filters the on-screen list for the tool user; \
        dossiers export per person. Include (1) tasks the user committed to or was asked to \
        take on, (2) tasks another attendee clearly owns, and (3) tasks nobody clearly owns. \
        Be selective: only concrete, deliberate commitments — never vague intentions, \
        hypotheticals, or process observations. A typical 30-minute meeting yields 3-8 \
        genuine action items; more than 12 means you are over-extracting — merge related \
        tasks and drop the marginal ones. \
        Set "assignee" to "Me" when the task is the tool user's, the other participant's \
        name when they own it, or null when ownership is genuinely unclear. \
        Set "source_quote" to a short verbatim snippet (one sentence, 5-25 words) copied from \
        the transcript that triggered this action — the exact words a speaker said, not your \
        paraphrase. This anchors the task to a specific moment in the conversation. Pick the \
        single most direct sentence; do not concatenate multiple turns.
        - "follow_ups" are, in this order: (1) questions ASKED in this meeting that were \
        not answered, (2) next questions implied by work still outstanding in THIS conversation \
        (a document to fix, a number another speaker voiced that the user's materials must match, \
        a decision that lacks an owner), (3) only then a few true blind spots. \
        Do NOT emit a generic domain questionnaire (financing status, environmental diligence, \
        engagement, timeline) unless someone in THIS meeting raised that gap. If the meeting \
        was about correcting outbound documents or aligning them with what a speaker actually \
        said, follow-ups must be about those documents and those facts. \
        DO NOT restate a summary point or an action item as a question. Quality over quantity: \
        2-5 sharp questions beat a long list. If nothing qualifies, return an empty array.
        - "topics" should include TWO types, merged into one flat array ordered by prominence: \
        (1) Theme topics: broad subjects discussed (e.g. "System Design", "Code Review Process") \
        (2) Key terms: specific proper nouns, acronyms, tools, services, platforms, libraries, \
        or named systems mentioned (e.g. "Jira", "Confluence", "Kafka", "DynamoDB", "React"). \
        Extract ALL specific named entities — these are critical for cross-meeting knowledge mapping. \
        Prefer the canonical form (e.g. "DynamoDB" not "dynamo", "Jira" not "jira").
        - If there is not enough content to produce meaningful insights, return empty arrays and \
        [] for summary. Do not generate placeholder or filler text.
        - Title: always return a 5-8 word title that names the PURPOSE (what the user was \
        trying to get done), not merely the calendar subject or a shared document's topic. \
        Omit "title" only during a rolling live pass whose user message contains PREVIOUS SUMMARY.
        - When the user message contains a PREVIOUS SUMMARY block, this is a rolling live \
        update: preserve previous action items, topics, and follow-up questions. Parse the \
        previous summary JSON, keep existing sections and points, and add new ones. Never \
        drop earlier insights unless explicitly resolved, contradicted, or revealed to be \
        owned by another attendee (per the action_items ownership rules).
        - When the user message is a fresh reanalysis or the first complete-transcript pass \
        (no PREVIOUS SUMMARY block), do not preserve any prior insights. Rewrite from this \
        transcript. Infer purpose again; a previous run may have latched onto subject matter.
        """

    private static let defaultInitialAnalysisPrompt: String = """
        Analyze the following meeting transcript and produce structured insights.

        Infer PURPOSE first: what was the tool user ("Me") trying to get done — fix a \
        document, align language with what another speaker actually said, send a package, \
        get a decision — not merely the subject on a calendar invite or a shared screen.

        TRANSCRIPT:
        {{transcript}}
        """

    private static let defaultReanalysisPrompt: String = """
        Re-analyze this meeting from scratch. Ignore any prior summary, action items, \
        follow-ups, or topics you (or another model) produced earlier. The user clicked \
        Reanalyze because those outputs did not match what the meeting was actually for.

        Calendar or stored title (may be generic or wrong — do not treat it as the purpose):
        {{calendarTitle}}

        The tool user is {{myName}}. They appear in the transcript as "Me" or under that name. \
        Your job is to serve them: what do they need to do, fix, send, or align because of \
        what was said?

        Infer PURPOSE from the conversation first:
        - If they are correcting documents, a deck, a proposal, or language sent to \
        prospects/lenders/engineers so it matches what another speaker actually voiced, \
        that IS the meeting. Lead the summary with that work, then the facts they need \
        to capture.
        - Shared-screen content is evidence of the artifact being reviewed, not automatically \
        the meeting's only topic.

        Then produce the JSON schema from your instructions:
        - title: 5-8 words naming the PURPOSE (e.g. aligning outbound documents with spoken \
        facts), not the calendar subject.
        - summary: purpose first, then decisions and the facts another speaker stated that \
        the user's materials must reflect.
        - action_items: every concrete commitment, with assignee. Include document/comms \
        work implied by the talk ("update the proposal / ROM / scope write-up so it uses \
        the numbers and wording the other speaker actually said").
        - follow_ups: unanswered questions from THIS room, then implied next questions about \
        the work product. Do not invent a due-diligence questionnaire.
        - topics: both the work product (e.g. prospect documents) and named subject-matter terms.

        TRANSCRIPT:
        {{transcript}}
        {{suppressionBlock}}
        """

    static func sectionAnalysisPrompt(
        depth: InsightDepth,
        scope: InsightScope,
        transcript: String,
        calendarTitle: String,
        myName: String?,
        currentSummary: String,
        currentActionItems: [ParsedActionItem],
        currentFollowUps: [String],
        currentTopics: [String],
        vocalCues: String,
        suppressedActionItems: [String] = [],
        suppressedFollowUps: [String] = []
    ) -> String {
        let key: PromptKey = depth == .deepest ? .meetingDeepest : .meetingDeep
        let template = PromptStore.shared.get(
            key,
            default: depth == .deepest ? defaultDeepestPrompt : defaultDeepPrompt
        )
        return PromptStore.render(template, values: [
            "section": scope.promptName,
            "transcript": transcript,
            "calendarTitle": calendarTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "(none)" : calendarTitle,
            "myName": myName?.isEmpty == false ? myName! : "Me",
            "currentSummary": currentSummary.isEmpty ? "[]" : currentSummary,
            "currentActionItems": formatActionItems(currentActionItems),
            "currentFollowUps": formatNumberedList(currentFollowUps),
            "currentTopics": formatTopics(currentTopics),
            "vocalCues": vocalCues,
            "suppressionBlock": suppressionBlock(
                actionItems: suppressedActionItems,
                followUps: suppressedFollowUps
            ),
        ])
    }

    private static let defaultDeepPrompt: String = """
        Deep re-analysis of {{section}} for this meeting. The current on-screen \
        write-up is wrong or too shallow. Rewrite {{section}} from the transcript. \
        Do not invent facts, stakeholders, or diligence questions that nobody raised.

        Calendar or stored title (hint only): {{calendarTitle}}
        Tool user: {{myName}}

        Return the full JSON schema. Put new work in {{section}}. Keep other fields \
        identical to CURRENT unless they are factually contradicted by the transcript.

        CURRENT SUMMARY:
        {{currentSummary}}

        CURRENT ACTION ITEMS:
        {{currentActionItems}}

        CURRENT FOLLOW-UPS:
        {{currentFollowUps}}

        CURRENT TOPICS:
        {{currentTopics}}

        Be more thorough than a first pass: more evidence, more specific numbers and \
        wording speakers actually used, purpose first (what {{myName}} was trying to \
        get done). 2-5 follow-ups if that is the section; no generic questionnaire.

        TRANSCRIPT:
        {{transcript}}
        {{suppressionBlock}}
        """

    private static let defaultDeepestPrompt: String = """
        Deepest re-analysis of {{section}}. Use the transcript AND the vocal-energy \
        measurements below (from the saved audio). Energy is a measured amplitude \
        ratio, not an emotion label. You may treat elevated energy as extra weight \
        that those words mattered; you may treat quiet lines as possible asides. \
        Do NOT invent frustration, excitement, sarcasm, or other feelings unless \
        the words themselves support that reading.

        Calendar or stored title (hint only): {{calendarTitle}}
        Tool user: {{myName}}

        Return the full JSON schema. Rewrite {{section}}. Keep other fields identical \
        to CURRENT unless the transcript contradicts them. Do not invent facts.

        CURRENT SUMMARY:
        {{currentSummary}}

        CURRENT ACTION ITEMS:
        {{currentActionItems}}

        CURRENT FOLLOW-UPS:
        {{currentFollowUps}}

        CURRENT TOPICS:
        {{currentTopics}}

        {{vocalCues}}

        TRANSCRIPT:
        {{transcript}}
        {{suppressionBlock}}
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
        - Generate a short, descriptive title (5-8 words max, no quotes) that names the \
        PURPOSE — what the tool user was trying to get done — not merely the calendar \
        subject or a shared document's topic. Example: "Align prospect docs with spoken facts" \
        rather than "25MW Warehouse Engineering Review" if the talk was about correcting \
        outbound materials. Return it in the "title" field.
        - Re-infer PURPOSE from the FULL transcript. The CURRENT SUMMARY is a live-analysis \
        draft and may have latched onto subject matter (a PDF on screen, a calendar title) \
        instead of purpose — rewrite it if so. Lead with purpose, then decisions and the \
        facts another speaker stated that the user's materials must reflect. Merge redundant \
        points, tighten wording, cover the full meeting arc.
        - Deduplicate action items — merge near-duplicates, remove redundant ones, \
        and keep the clearest phrasing. Include document/comms work implied by the talk. \
        Re-check ownership against the full transcript: drop any item another attendee \
        clearly owns (unless the two-person exception applies) and fix assignees that \
        don't match what was actually said.
        - Re-derive follow-up questions against the FULL transcript and THIS meeting's \
        purpose. Drop any accumulated question the transcript actually answers, that \
        overlaps an action item, or that is a generic domain questionnaire nobody raised \
        here. Unanswered in-room questions first, then outstanding work-product questions, \
        then at most a few true blind spots (including from RELATED DISCUSSIONS, when provided).
        - Consolidate topics — remove exact duplicates and merge near-duplicates, but keep both \
        theme topics (broad subjects, including the work product) AND key terms (specific names, \
        acronyms, tools, services). Order themes first by prominence, then key terms alphabetically. \
        Preserve canonical forms (e.g. "DynamoDB" not "dynamo").
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

    private static let defaultScreenSystemPrompt: String = """
        You are analyzing screenshots of content shared on screen during a live \
        meeting (slides, code, diagrams, dashboards, documents). For each image you \
        receive, produce a DETAILED description — thorough enough that a meeting \
        assistant that never sees the image can reconstruct what was shown and \
        weave it into the meeting's story.

        You MUST respond with ONLY valid JSON matching this exact schema — no prose, \
        no markdown, no explanation before or after:

        {
          "frames": [
            {
              "index": 0,
              "observation": "100-250 words: the shared CONTENT itself — substantive text, data, and values transcribed verbatim — plus what is new or different versus the previous frame",
              "content_type": "slide|code|diagram|dashboard|document|terminal|video|other",
              "key_entities": ["specific named things visible: systems, projects, tickets, people, metrics"],
              "notable_text": "short verbatim text that carries meaning beyond the OCR excerpt you were given, or null"
            }
          ]
        }

        Rules:
        - One entry per image, "index" matching the order the images were provided.
        - Each observation is 100-250 words about the CONTENT being shared — \
        the document, data, code, or slide. Transcribe the substance: real \
        numbers, table rows, chart axes and values, code identifiers and \
        signatures, dates, names, ticket IDs, metric readings — verbatim where \
        the values carry meaning. Never compress legible data into vague \
        phrases ("some metrics", "a list of items").
        - NEVER describe application chrome: menus, toolbars, side panels, \
        tab bars, viewer controls, window furniture. "The left panel shows an \
        'All Tools' menu" is worthless — that is the app, not what's being \
        shared. Name the application in at most a few words, and only when it \
        genuinely aids context ("a PDF of the Q3 contract").
        - When a previous-frame description is provided, or multiple frames \
        are in this batch, describe only what is NEW or DIFFERENT in the \
        content ("error rate now 4.1%, up from 2.3%"; "scrolled to the \
        Codesheets table: …"). Never say things are "the same" or re-describe \
        unchanged material — spend the words on what changed.
        - Never invent content you cannot actually read — describe partial \
        legibility honestly ("y-axis labels too small to read").
        - Extract key_entities in canonical form; they feed cross-meeting search.
        - If an image is unreadable or blank, say so in the observation and use \
        content_type "other".
        """

    private static let defaultScreenAnalysisPrompt: String = """
        {{frameCount}} screenshot(s) captured from a screen share during the meeting, \
        in chronological order. For context, the meeting's topics so far: {{recentTopics}}

        The most recently analyzed frame (immediately before this batch) was \
        described as: {{previousObservation}}

        For each image, on-device OCR extracted the following text (may be partial \
        or noisy — trust the image over the OCR):

        {{frameManifest}}

        Analyze each image and respond with the JSON schema from your instructions.
        """

    private static let defaultSessionSynthesisPrompt: String = """
        A screen-share session just ended during a meeting. \
        Window: "{{windowTitle}}", shown {{sessionSpan}} (elapsed meeting time).

        DETAILED FRAME DESCRIPTIONS (chronological, from screenshots of the share):
        {{frameDescriptions}}

        TRANSCRIPT AROUND THE SESSION (from 30s before it started to 30s after it ended):
        {{transcriptExcerpt}}

        Write a recap that fuses what was SHOWN with what was SAID — the story \
        of this share session as part of the meeting.

        Respond with ONLY valid JSON matching this exact schema:

        {
          "narrative": "One 120-250 word paragraph: what was presented, how it evolved across the session, and how the conversation engaged with it. Weave spoken reactions and decisions together with the on-screen content. Preserve concrete values (numbers, dates, names, identifiers) from the frames.",
          "key_moments": [{"time": "m:ss", "label": "5-12 words: what happened at this moment"}],
          "entities": ["canonical named things: systems, projects, tickets, people, metrics"]
        }

        Rules:
        - Ground every claim in the frames or the transcript above — never invent \
        content, and never present speculation as fact.
        - 3-8 key_moments. Every "time" must be a real timestamp copied from a \
        frame or transcript line above. Prefer moments where the screen content \
        changed or the discussion pivoted.
        - If the transcript is empty or unrelated, recap the screen content alone \
        and say the room did not discuss it.
        """


    // MARK: - Report figure anchoring

    static var reportSystemPrompt: String {
        PromptStore.shared.get(.reportSystem, default: defaultReportSystemPrompt)
    }

    static func figureAnchorPrompt(sectionOutline: String, frameCatalogue: String) -> String {
        let template = PromptStore.shared.get(.reportFigureAnchors, default: defaultFigureAnchorPrompt)
        return PromptStore.render(template, values: [
            "sectionOutline": sectionOutline,
            "frameCatalogue": frameCatalogue,
        ])
    }

    static let defaultReportSystemPrompt = """
        You decide which screenshots belong beside which part of a written \
        meeting report. You are strict: a screenshot earns its place only when \
        it is direct visual evidence for what a section says. You MUST respond \
        with ONLY valid JSON matching the schema in the user message — no \
        prose, no markdown, no explanation before or after.
        """

    private static let defaultFigureAnchorPrompt: String = """
        Below are the sections of a written meeting summary, and the \
        screenshots captured from the shared screen during that meeting.

        Your job is to pick the FEW screenshots that help tell the story the \
        summary tells, and say — in one line each — what they contribute to \
        it. This is a short summary report, not a gallery: a screenshot earns \
        its place only by making a point in the summary land better than the \
        words alone.

        SECTIONS
        {{sectionOutline}}

        CAPTURED SCREENSHOTS
        {{frameCatalogue}}

        Return JSON of exactly this shape:
        {"figures":[{"frame":"F3","section":"S2","caption":"one short line"}]}

        Choosing:
        - Include a screenshot ONLY when the thing a section is talking about \
        is visible in it. A screenshot from roughly the same moment is not \
        evidence of anything.
        - NEVER include one showing only the video call — participant tiles, \
        a gallery of faces, a speaker's camera, an empty meeting window.
        - At most 2 per section, and most sections should have none. \
        Returning three or four across the whole meeting is a good answer. \
        Returning an empty list is a valid answer.
        - Omit screenshots you do not choose. They are not printed. Do not \
        include them with a null section.

        Captions — the caption is the tie between picture and summary:
        - Say what the screenshot shows AND what it establishes for the \
        section. "The RDL suggestions under debate: two AI-proposed Joint \
        Pain entries, both at 10%" — the reader immediately sees why it is \
        on the page.
        - Use the real nouns from the description: the tool, the screen, the \
        field, the value. Never "a screen from the design tool".
        - NEVER describe the meeting or the call — "Zoom call in progress", \
        "during the design discussion". The reader can see it is a screen \
        share. The window, video tiles and toolbar are chrome; caption the \
        content inside them.
        - Under 20 words. Do not begin with "Screenshot of", "This shows", \
        "A view of", "The user is".
        - Use only what the description states. Invent nothing.
        - Use only the S and F identifiers given above.
        """
}
