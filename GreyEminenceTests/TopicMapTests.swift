import XCTest
import SwiftUI
@testable import Grey_Eminence

/// Pure logic for the Topic Map's backbone overview and radial ego view.
@MainActor
final class TopicMapTests: XCTestCase {

    private func node(_ id: String, _ count: Int = 1) -> TopicNode {
        TopicNode(
            id: id, label: id.capitalized, meetingCount: count, meetingIDs: [],
            lastMeetingDate: nil, position: .zero, radius: 6, color: .secondary
        )
    }

    // MARK: - Backbone

    func testBackboneKeepsEachNodesStrongestEdgesAndDropsTheRest() {
        // A–B 10, A–C 9, A–E 1 ; E–F 5, E–G 4.  topK = 2.
        // A's top-2: A–B, A–C.  E's top-2: E–F, E–G.  → A–E(weight 1) is no
        // node's top edge and must NOT be backbone.
        var edges = [
            TopicEdge(sourceIndex: 0, targetIndex: 1, weight: 10), // A-B
            TopicEdge(sourceIndex: 0, targetIndex: 2, weight: 9),  // A-C
            TopicEdge(sourceIndex: 0, targetIndex: 4, weight: 1),  // A-E
            TopicEdge(sourceIndex: 4, targetIndex: 5, weight: 5),  // E-F
            TopicEdge(sourceIndex: 4, targetIndex: 6, weight: 4),  // E-G
        ]
        TopicMapViewModel.markBackbone(&edges, nodeCount: 7, topK: 2)
        XCTAssertTrue(edges[0].isBackbone)   // A-B
        XCTAssertTrue(edges[1].isBackbone)   // A-C
        XCTAssertFalse(edges[2].isBackbone)  // A-E — dropped from the skeleton
        XCTAssertTrue(edges[3].isBackbone)   // E-F
        XCTAssertTrue(edges[4].isBackbone)   // E-G
    }

    // MARK: - Ego-view neighbours

    func testSelectedNeighboursRankedCappedAndVisible() {
        let vm = TopicMapViewModel()
        var nodes = [node("a")]
        var edges: [TopicEdge] = []
        // 16 neighbours n1..n16 with descending weights 16..1.
        for i in 1...16 {
            nodes.append(node("n\(i)"))
            edges.append(TopicEdge(sourceIndex: 0, targetIndex: i, weight: 17 - i))
        }
        vm.nodes = nodes
        vm.edges = edges
        vm.selectedTopicID = "a"

        let nbs = vm.selectedNeighbours
        XCTAssertEqual(nbs.count, 16)
        XCTAssertEqual(nbs.first?.id, "n1")          // strongest first
        XCTAssertEqual(nbs.first?.weight, 16)
        XCTAssertEqual(nbs.map(\.weight), nbs.map(\.weight).sorted(by: >))  // ranked desc

        XCTAssertEqual(vm.cappedNeighbours.count, vm.neighbourCap)  // 14
        XCTAssertEqual(vm.extraNeighbourCount, 2)

        // Visible set = selected + the capped ring.
        XCTAssertEqual(vm.focusVisibleIDs.count, vm.neighbourCap + 1)
        XCTAssertTrue(vm.focusVisibleIDs.contains("a"))
        XCTAssertTrue(vm.focusVisibleIDs.contains("n1"))
        XCTAssertFalse(vm.focusVisibleIDs.contains("n16"))  // beyond the cap

        XCTAssertEqual(vm.weightToSelected("n1"), 16)
        XCTAssertNil(vm.weightToSelected("nonexistent"))
    }

    func testSpeakerTokenGroupsLocalMeAndPrettyRemotes() {
        XCTAssertEqual(TopicMapRoster.speakerToken(.me), "me")
        XCTAssertEqual(TopicMapRoster.speakerToken(.meNamed("Alex")), "me")
        XCTAssertEqual(TopicMapRoster.speakerToken(.other("Jordan")), "jordan")
        XCTAssertEqual(TopicMapRoster.speakerToken(.other("Speaker 2")), "speaker-2")
    }

    func testTopTopicsRanksByMeetingOverlap() {
        // Labels only — empty meeting lists are ignored.
        let ranked = TopicMapRoster.topTopics(
            meetingIDs: [],
            topicMeetings: ["Budget": [], "Site B": []],
            limit: 3
        )
        XCTAssertTrue(ranked.isEmpty)
    }

    func testNoSelectionMeansNoNeighbours() {
        let vm = TopicMapViewModel()
        vm.nodes = [node("a"), node("b")]
        vm.edges = [TopicEdge(sourceIndex: 0, targetIndex: 1, weight: 3)]
        XCTAssertTrue(vm.selectedNeighbours.isEmpty)
        XCTAssertTrue(vm.focusVisibleIDs.isEmpty)
    }
}
