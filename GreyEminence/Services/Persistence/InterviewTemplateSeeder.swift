import Foundation
import SwiftData

/// Seeds default `InterviewTemplate` records on first run if the table is
/// empty. Idempotent — never overwrites existing templates, only fills the
/// blank-slate case so the creation modal's rail isn't empty for new users.
///
/// Strategy: ship a small set of standard loops with rubric references
/// resolved by *fuzzy name match* against the user's current rubrics. If
/// a rubric named (or close to) "System Design" exists, the seeder links
/// it; otherwise the template phase ships with `kind == .scored` and a
/// nil rubric, ready for the user to pick one in the modal. Either way,
/// the user gets shape; rubric population is best-effort.
enum InterviewTemplateSeeder {

    /// Versioned seed key. Bumped when the canonical default templates
    /// change so existing installs can be re-seeded — but only when the
    /// user hasn't customized them. See `pruneUnmodifiedLegacyTemplates`.
    private static let seedVersionKey = "interviewTemplateSeedVersion"
    private static let currentSeedVersion = 2

    /// Run the seed on a fresh install, or re-seed when the canonical
    /// defaults have changed *and* the user hasn't touched the old ones
    /// yet. Idempotent in both directions: never overwrites a user-edited
    /// template, never duplicates one.
    @MainActor
    static func seedIfEmpty(in context: ModelContext) {
        let storedVersion = UserDefaults.standard.integer(forKey: seedVersionKey)
        if storedVersion < currentSeedVersion {
            pruneUnmodifiedLegacyTemplates(in: context)
        }

        let existingCount = (try? context.fetchCount(FetchDescriptor<InterviewTemplate>())) ?? 0
        if existingCount > 0 {
            UserDefaults.standard.set(currentSeedVersion, forKey: seedVersionKey)
            return
        }

        let allRubrics = (try? context.fetch(FetchDescriptor<Rubric>())) ?? []
        let activeRubrics = allRubrics.filter { !$0.isArchived }

        for spec in defaultTemplates {
            let template = InterviewTemplate(
                name: spec.name,
                templateDescription: spec.description,
                iconName: spec.iconName,
                appliesToAnyRole: spec.appliesToAnyRole
            )
            context.insert(template)

            for (idx, phaseSpec) in spec.phases.enumerated() {
                let rubric: Rubric? = phaseSpec.rubricNameHints.flatMap { hints in
                    fuzzyMatchRubric(named: hints, in: activeRubrics)
                }
                let phase = InterviewTemplatePhase(
                    title: phaseSpec.title,
                    kind: phaseSpec.kind,
                    rubric: rubric,
                    sortOrder: idx,
                    iconName: phaseSpec.iconName,
                    targetMinutes: phaseSpec.targetMinutes
                )
                phase.template = template
                template.phases.append(phase)
            }
        }

        PersistenceGate.save(context, site: "InterviewTemplateSeeder.seedIfEmpty", critical: false)
        LogManager.send(
            "Seeded \(defaultTemplates.count) default interview template(s)",
            category: .general
        )
        UserDefaults.standard.set(currentSeedVersion, forKey: seedVersionKey)
    }

    /// Delete templates seeded by an older version *only if* the user
    /// hasn't used them — usageCount == 0 and lastUsedAt == nil. Names
    /// hard-coded to the prior canonical set so a user-renamed template
    /// won't be touched even by accident. Skips any template whose
    /// phase count or titles diverge from the legacy spec, since that
    /// signals manual edits.
    @MainActor
    private static func pruneUnmodifiedLegacyTemplates(in context: ModelContext) {
        let legacyNames: Set<String> = ["Backend Loop", "Frontend Loop"]
        let templates = (try? context.fetch(FetchDescriptor<InterviewTemplate>())) ?? []
        var removed = 0
        for template in templates where legacyNames.contains(template.name) {
            guard template.usageCount == 0, template.lastUsedAt == nil else { continue }
            context.delete(template)
            removed += 1
        }
        if removed > 0 {
            PersistenceGate.save(context, site: "InterviewTemplateSeeder.pruneLegacy", critical: false)
            LogManager.send(
                "Removed \(removed) unmodified legacy template(s) before re-seeding",
                category: .general
            )
        }
    }

    // MARK: - Specs

    private struct TemplateSpec {
        let name: String
        let description: String
        let iconName: String
        let appliesToAnyRole: Bool
        let phases: [PhaseSpec]
    }

    private struct PhaseSpec {
        let title: String
        let kind: InterviewTemplatePhaseKind
        let iconName: String?
        let targetMinutes: Int?
        /// One or more rubric-name fragments to match against existing
        /// rubrics. Order matters — earlier hints are preferred. Nil for
        /// intro/conclusion/unscored phases that never need a rubric.
        let rubricNameHints: [String]?
    }

    private static let defaultTemplates: [TemplateSpec] = [
        TemplateSpec(
            name: "Standard Interview",
            description: "A bare-bones loop you can grow into. One scored phase between an intro and a conclusion — pick the rubric in the creation sheet.",
            iconName: "list.bullet.rectangle",
            appliesToAnyRole: true,
            phases: [
                PhaseSpec(title: "Intro", kind: .intro, iconName: "person.wave.2", targetMinutes: 5, rubricNameHints: nil),
                PhaseSpec(title: "Discussion", kind: .scored, iconName: "list.clipboard", targetMinutes: 45, rubricNameHints: nil),
                PhaseSpec(title: "Conclusion", kind: .conclusion, iconName: "questionmark.bubble", targetMinutes: 5, rubricNameHints: nil)
            ]
        ),
        TemplateSpec(
            name: "Software Engineer",
            description: "Standard IC engineer loop: system design, coding, behavioral. Bookended with intro and conclusion.",
            iconName: "chevron.left.slash.chevron.right",
            appliesToAnyRole: true,
            phases: [
                PhaseSpec(title: "Intro", kind: .intro, iconName: "person.wave.2", targetMinutes: 5, rubricNameHints: nil),
                PhaseSpec(title: "System Design", kind: .scored, iconName: "rectangle.connected.to.line.below", targetMinutes: 45, rubricNameHints: ["system design"]),
                PhaseSpec(title: "Coding", kind: .scored, iconName: "chevron.left.slash.chevron.right", targetMinutes: 45, rubricNameHints: ["coding", "ai-assisted", "ai assisted", "engineering"]),
                PhaseSpec(title: "Behavioral", kind: .scored, iconName: "person.2.wave.2", targetMinutes: 30, rubricNameHints: ["behavioral", "leadership", "values"]),
                PhaseSpec(title: "Conclusion", kind: .conclusion, iconName: "questionmark.bubble", targetMinutes: 5, rubricNameHints: nil)
            ]
        ),
        TemplateSpec(
            name: "Staff Software Engineer",
            description: "Senior IC loop: two system-design rounds for breadth and depth, plus a code-review challenge and behavioral.",
            iconName: "rectangle.connected.to.line.below",
            appliesToAnyRole: true,
            phases: [
                PhaseSpec(title: "Intro", kind: .intro, iconName: "person.wave.2", targetMinutes: 5, rubricNameHints: nil),
                PhaseSpec(title: "System Design — Breadth", kind: .scored, iconName: "rectangle.connected.to.line.below", targetMinutes: 60, rubricNameHints: ["system design"]),
                PhaseSpec(title: "System Design — Deep Dive", kind: .scored, iconName: "rectangle.3.group", targetMinutes: 60, rubricNameHints: ["system design", "architecture"]),
                PhaseSpec(title: "Code Review Challenge", kind: .scored, iconName: "doc.text.magnifyingglass", targetMinutes: 45, rubricNameHints: ["code review", "review"]),
                PhaseSpec(title: "Behavioral", kind: .scored, iconName: "person.2.wave.2", targetMinutes: 30, rubricNameHints: ["behavioral", "leadership", "values"]),
                PhaseSpec(title: "Conclusion", kind: .conclusion, iconName: "questionmark.bubble", targetMinutes: 5, rubricNameHints: nil)
            ]
        ),
        TemplateSpec(
            name: "Engineering Manager",
            description: "EM loop: system design, code review, leadership / behavioral. No coding exercise — managers are evaluated on judgement, not a fresh whiteboard.",
            iconName: "person.2.wave.2",
            appliesToAnyRole: true,
            phases: [
                PhaseSpec(title: "Intro", kind: .intro, iconName: "person.wave.2", targetMinutes: 5, rubricNameHints: nil),
                PhaseSpec(title: "System Design", kind: .scored, iconName: "rectangle.connected.to.line.below", targetMinutes: 45, rubricNameHints: ["system design"]),
                PhaseSpec(title: "Code Review", kind: .scored, iconName: "doc.text.magnifyingglass", targetMinutes: 45, rubricNameHints: ["code review", "review"]),
                PhaseSpec(title: "Leadership & Behavioral", kind: .scored, iconName: "person.2.wave.2", targetMinutes: 45, rubricNameHints: ["leadership", "behavioral", "values", "management"]),
                PhaseSpec(title: "Conclusion", kind: .conclusion, iconName: "questionmark.bubble", targetMinutes: 5, rubricNameHints: nil)
            ]
        )
    ]

    // MARK: - Fuzzy matching

    /// Best-effort rubric lookup. For each hint in order:
    /// 1. Exact case-insensitive name match.
    /// 2. Substring case-insensitive match in either direction.
    /// 3. First rubric whose name shares the most whitespace-split tokens
    ///    with the hint (≥ 1 token in common).
    /// Returns nil if nothing crosses the threshold — the template phase
    /// ships rubric-less and the user picks one when they schedule.
    static func fuzzyMatchRubric(named hints: [String], in rubrics: [Rubric]) -> Rubric? {
        guard !rubrics.isEmpty else { return nil }
        for hint in hints {
            let needle = hint.lowercased()
            // Tier 1: exact match.
            if let exact = rubrics.first(where: { $0.name.lowercased() == needle }) {
                return exact
            }
            // Tier 2: substring either direction.
            if let substr = rubrics.first(where: {
                let n = $0.name.lowercased()
                return n.contains(needle) || needle.contains(n)
            }) {
                return substr
            }
            // Tier 3: token overlap.
            let needleTokens = Set(needle.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
            let scored: [(Rubric, Int)] = rubrics.map { rubric in
                let nameTokens = Set(rubric.name.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
                return (rubric, nameTokens.intersection(needleTokens).count)
            }
            if let best = scored.max(by: { $0.1 < $1.1 }), best.1 >= 1 {
                return best.0
            }
        }
        return nil
    }
}
