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

    /// Run the seed once per fresh install. No-op if any template already
    /// exists — protects against re-seeding after the user archives or
    /// deletes them.
    @MainActor
    static func seedIfEmpty(in context: ModelContext) {
        let existingCount = (try? context.fetchCount(FetchDescriptor<InterviewTemplate>())) ?? 0
        guard existingCount == 0 else { return }

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
            name: "Backend Loop",
            description: "Standard backend-engineer loop: system design, coding, behavioral. Bookended with intro and conclusion.",
            iconName: "server.rack",
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
            name: "Frontend Loop",
            description: "Standard frontend loop: UI build, code review, behavioral. Bookended with intro and conclusion.",
            iconName: "rectangle.on.rectangle.angled",
            appliesToAnyRole: true,
            phases: [
                PhaseSpec(title: "Intro", kind: .intro, iconName: "person.wave.2", targetMinutes: 5, rubricNameHints: nil),
                PhaseSpec(title: "UI Build", kind: .scored, iconName: "rectangle.on.rectangle.angled", targetMinutes: 60, rubricNameHints: ["ui", "frontend", "front-end"]),
                PhaseSpec(title: "Code Review", kind: .scored, iconName: "doc.text.magnifyingglass", targetMinutes: 30, rubricNameHints: ["code review", "review"]),
                PhaseSpec(title: "Behavioral", kind: .scored, iconName: "person.2.wave.2", targetMinutes: 30, rubricNameHints: ["behavioral", "leadership", "values"]),
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
