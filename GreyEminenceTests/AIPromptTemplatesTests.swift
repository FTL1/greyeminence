import XCTest
@testable import Grey_Eminence

/// Built-in meeting-intelligence prompts: Reanalyze must be a purpose-first
/// rewrite, not a replay of the live first-pass / rolling-preserve path.
final class AIPromptTemplatesTests: XCTestCase {

    func testPromptVersionIsMeetingV4() {
        XCTAssertEqual(AIPromptTemplates.promptVersion, "meeting.v6")
    }

    func testReanalysisPromptSubstitutesPlaceholders() {
        let prompt = AIPromptTemplates.reanalysisPrompt(
            transcript: "UNIQUE_TRANSCRIPT_BODY",
            calendarTitle: "Engineering Scope Review",
            myName: "Alex"
        )
        XCTAssertTrue(prompt.contains("UNIQUE_TRANSCRIPT_BODY"))
        XCTAssertTrue(prompt.contains("Engineering Scope Review"))
        XCTAssertTrue(prompt.contains("Alex"))
        XCTAssertFalse(prompt.contains("{{transcript}}"))
        XCTAssertFalse(prompt.contains("{{calendarTitle}}"))
        XCTAssertFalse(prompt.contains("{{myName}}"))
        XCTAssertFalse(prompt.contains("{{suppressionBlock}}"))
    }

    func testReanalysisPromptTreatsCalendarTitleAsHintNotPurpose() {
        let prompt = AIPromptTemplates.reanalysisPrompt(
            transcript: "x",
            calendarTitle: "Engineering Scope Review",
            myName: "Alex"
        )
        let lower = prompt.lowercased()
        XCTAssertTrue(lower.contains("may be generic or wrong"))
        XCTAssertTrue(lower.contains("from scratch"))
        XCTAssertTrue(lower.contains("purpose"))
        XCTAssertTrue(lower.contains("due-diligence"))
        XCTAssertFalse(prompt.contains("PREVIOUS SUMMARY"))
    }

    func testReanalysisPromptIncludesSuppressionBlock() {
        let prompt = AIPromptTemplates.reanalysisPrompt(
            transcript: "x",
            calendarTitle: "T",
            myName: "Me",
            suppressedActionItems: ["old task"],
            suppressedFollowUps: ["Who owns financing?"]
        )
        XCTAssertTrue(prompt.contains("DO NOT RE-SUGGEST"))
        XCTAssertTrue(prompt.contains("old task"))
        XCTAssertTrue(prompt.contains("Who owns financing?"))
    }

    func testSystemPromptGatesPreserveOnPreviousSummary() {
        let system = AIPromptTemplates.defaultText(for: .meetingSystem)
        XCTAssertTrue(system.contains("PREVIOUS SUMMARY"))
        XCTAssertTrue(system.lowercased().contains("do not preserve any prior insights"))
        XCTAssertTrue(system.lowercased().contains("generic domain questionnaire"))
        XCTAssertTrue(system.lowercased().contains("infer the meeting's purpose"))
    }

    func testInitialPromptAsksForPurpose() {
        let initial = AIPromptTemplates.initialAnalysisPrompt(transcript: "hello from alex")
        XCTAssertTrue(initial.lowercased().contains("purpose"))
        XCTAssertTrue(initial.contains("hello from alex"))
    }

    func testFinalCleanupRewritesWrongSubjectLatch() {
        let prompt = AIPromptTemplates.finalCleanupPrompt(
            fullTranscript: "t",
            currentSummary: "[]",
            currentActionItems: [],
            currentFollowUps: [],
            currentTopics: []
        )
        let lower = prompt.lowercased()
        XCTAssertTrue(lower.contains("re-infer"))
        XCTAssertTrue(lower.contains("latched") || lower.contains("purpose"))
        XCTAssertTrue(lower.contains("generic domain questionnaire"))
    }

    func testRelatedContextBlockDoesNotLicenseGenericQuestionnaire() {
        let block = AIPromptTemplates.relatedContextBlock("- [Other] financing")
        XCTAssertTrue(block.contains("generic domain questionnaire"))
        XCTAssertTrue(block.contains("financing"))
    }

    func testScreenBlockTreatsDocumentsAsWorkProduct() {
        let block = AIPromptTemplates.screenObservationBlock("PDF of a 25MW warehouse")
        XCTAssertTrue(block.lowercased().contains("work product"))
        XCTAssertTrue(block.contains("PDF of a 25MW warehouse"))
    }

    func testDeepSectionPromptRewritesOnlyThatSection() {
        let prompt = AIPromptTemplates.sectionAnalysisPrompt(
            depth: .deep,
            scope: .followUps,
            transcript: "UNIQUE_BODY",
            calendarTitle: "Scope Review",
            myName: "Alex",
            currentSummary: "[]",
            currentActionItems: [],
            currentFollowUps: ["Old question"],
            currentTopics: [],
            vocalCues: ""
        )
        let lower = prompt.lowercased()
        XCTAssertTrue(prompt.contains("UNIQUE_BODY"))
        XCTAssertTrue(lower.contains("follow-up questions only") || lower.contains("follow-up"))
        XCTAssertTrue(lower.contains("do not invent"))
        XCTAssertFalse(prompt.contains("{{section}}"))
    }

    func testDeepestPromptIncludesVocalCuesAndForbidsInventedEmotion() {
        let prompt = AIPromptTemplates.sectionAnalysisPrompt(
            depth: .deepest,
            scope: .summary,
            transcript: "x",
            calendarTitle: "T",
            myName: "Me",
            currentSummary: "[]",
            currentActionItems: [],
            currentFollowUps: [],
            currentTopics: [],
            vocalCues: "VOCAL ENERGY (measured"
        )
        let lower = prompt.lowercased()
        XCTAssertTrue(prompt.contains("VOCAL ENERGY"))
        XCTAssertTrue(lower.contains("frustration") || lower.contains("emotion"))
        XCTAssertTrue(lower.contains("do not invent"))
    }

    func testMeetingReanalysisKeyIsWired() {
        let text = AIPromptTemplates.defaultText(for: .meetingReanalysis)
        XCTAssertFalse(text.isEmpty)
        XCTAssertTrue(text.contains("{{transcript}}"))
        XCTAssertTrue(text.contains("{{calendarTitle}}"))
        XCTAssertTrue(text.contains("{{myName}}"))
        XCTAssertTrue(text.contains("{{suppressionBlock}}"))
        XCTAssertEqual(
            PromptKey.meetingReanalysis.placeholders,
            ["transcript", "calendarTitle", "myName", "suppressionBlock"]
        )
    }
}
