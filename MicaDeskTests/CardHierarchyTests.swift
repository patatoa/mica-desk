import SwiftData
import XCTest
@testable import MicaDesk

@MainActor
final class CardHierarchyTests: XCTestCase {
    func testNewCardsInsertAtTopAndReindexSiblings() throws {
        let (container, store) = try makeStore()
        _ = container

        let first = try store.addCard()
        let child = try store.addCard(parentID: first.id)
        let second = try store.addCard()
        let roots = try store.orderedSiblings(parentID: nil)

        XCTAssertEqual(roots.map(\.id), [second.id, first.id])
        XCTAssertEqual(roots.map(\.sortIndex), [0, 1])
        XCTAssertEqual(try store.orderedSiblings(parentID: first.id).map(\.id), [child.id])
    }

    func testReorderingChangesOnlyOneSiblingGroup() throws {
        let (container, store) = try makeStore()
        _ = container

        let parent = try store.addCard()
        let otherRoot = try store.addCard()
        let firstChild = try store.addCard(parentID: parent.id)
        let secondChild = try store.addCard(parentID: parent.id)

        try store.move(firstChild.id, before: secondChild.id)

        XCTAssertEqual(try store.orderedSiblings(parentID: parent.id).map(\.id), [firstChild.id, secondChild.id])
        XCTAssertEqual(try store.orderedSiblings(parentID: nil).map(\.id), [otherRoot.id, parent.id])
    }

    func testDeleteRemovesEntireSubtreeAndPreservesOtherCards() throws {
        let (container, store) = try makeStore()
        _ = container

        let parent = try store.addCard()
        let child = try store.addCard(parentID: parent.id)
        _ = try store.addCard(parentID: child.id)
        let survivor = try store.addCard()

        try store.deleteSubtree(rootID: parent.id)

        let remaining = try store.fetchAll()
        XCTAssertEqual(remaining.map(\.id), [survivor.id])
        XCTAssertEqual(remaining.first?.sortIndex, 0)
    }

    func testDeletingChildReindexesOnlyItsSiblingGroup() throws {
        let (container, store) = try makeStore()
        _ = container

        let parent = try store.addCard()
        let firstChild = try store.addCard(parentID: parent.id)
        let secondChild = try store.addCard(parentID: parent.id)
        let root = try store.addCard()

        try store.deleteSubtree(rootID: secondChild.id)

        XCTAssertEqual(try store.orderedSiblings(parentID: parent.id).map(\.id), [firstChild.id])
        XCTAssertEqual(firstChild.sortIndex, 0)
        XCTAssertEqual(try store.orderedSiblings(parentID: nil).map(\.id), [root.id, parent.id])
    }

    func testDeletingCardWithExternallyStoredDrawingData() throws {
        let (container, store) = try makeStore()
        _ = container

        let card = try store.addCard()
        card.drawingData = Data([0x49, 0x6E, 0x6B])
        try store.touchAndSave(card)

        try store.deleteSubtree(rootID: card.id)

        XCTAssertTrue(try store.fetchAll().isEmpty)
    }

    func testCardColorPersistsWithOtherContent() throws {
        let (container, store) = try makeStore()
        _ = container

        let card = try store.addCard()
        card.colorName = "blue"
        card.title = "Colored card"
        try store.touchAndSave(card)

        let restored = try XCTUnwrap(store.fetchAll().first)
        XCTAssertEqual(restored.colorName, "blue")
        XCTAssertEqual(restored.title, "Colored card")
    }

    func testCompactCardStatePersistsWithOtherContent() throws {
        let (container, store) = try makeStore()
        _ = container

        let card = try store.addCard()
        XCTAssertEqual(card.isCompact, true)

        try store.setCompact(card, to: false)

        let restored = try XCTUnwrap(store.fetchAll().first)
        XCTAssertEqual(restored.isCompact, false)
    }

    func testMovingParentMovesEntireSubtreeButNotOtherCards() throws {
        let (container, store) = try makeStore()
        _ = container

        let parent = try store.addCard()
        let child = try store.addCard(parentID: parent.id)
        let grandchild = try store.addCard(parentID: child.id)
        let unrelated = try store.addCard()
        let originalUnrelated = CardStore.Position(x: unrelated.positionX!, y: unrelated.positionY!)
        let originalChild = CardStore.Position(x: child.positionX!, y: child.positionY!)

        try store.moveSubtree(rootID: parent.id, byX: 125, byY: -40, in: store.fetchAll())

        XCTAssertEqual(parent.positionX, 285)
        XCTAssertEqual(parent.positionY, 60)
        XCTAssertEqual(child.positionX, originalChild.x + 125)
        XCTAssertEqual(child.positionY, originalChild.y - 40)
        XCTAssertEqual(grandchild.positionX, 425)
        XCTAssertEqual(grandchild.positionY, 900)
        XCTAssertEqual(unrelated.positionX, originalUnrelated.x)
        XCTAssertEqual(unrelated.positionY, originalUnrelated.y)
    }

    func testMissingLegacyPositionsReceiveDeterministicBoardLocations() throws {
        let (container, store) = try makeStore()
        _ = container

        let parent = Card(title: "Legacy parent")
        let child = Card(parentID: parent.id, title: "Legacy child")
        store.context.insert(parent)
        store.context.insert(child)
        try store.save()

        try store.assignMissingBoardPositions()

        XCTAssertEqual(parent.positionX, 160)
        XCTAssertEqual(parent.positionY, 100)
        XCTAssertEqual(child.positionX, 230)
        XCTAssertEqual(child.positionY, 520)
    }

    func testCyclePreventionRejectsDescendantAsParent() throws {
        let (container, store) = try makeStore()
        _ = container

        let parent = try store.addCard()
        let child = try store.addCard(parentID: parent.id)
        let grandchild = try store.addCard(parentID: child.id)

        XCTAssertThrowsError(try store.reparent(parent.id, to: grandchild.id)) { error in
            XCTAssertEqual(error as? CardStore.StoreError, .cycleDetected)
        }
        XCTAssertNil(parent.parentID)
    }

    func testCompletionDoesNotAffectDescendantsOrOrdering() throws {
        let (container, store) = try makeStore()
        _ = container

        let parent = try store.addCard()
        let child = try store.addCard(parentID: parent.id)
        try store.setCompleted(child, to: true)
        try store.setCompleted(parent, to: true)
        try store.setCompleted(parent, to: false)

        XCTAssertFalse(parent.isCompleted)
        XCTAssertTrue(child.isCompleted)
        XCTAssertEqual(child.parentID, parent.id)
        XCTAssertEqual(child.sortIndex, 0)
    }

    func testNewCardPlacementTracksScrolledViewportAndZoom() throws {
        let (container, store) = try makeStore()
        _ = container
        let viewport = CGRect(x: 800, y: 450, width: 1000, height: 700)
        for zoom in [0.25, 0.5, 1.0, 1.5] {
            let position = CardStore.newCardPosition(in: viewport, zoom: zoom)
            let card = try store.addCard(at: position)
            XCTAssertEqual(card.isCompact, true)
            XCTAssertEqual(card.positionX! * zoom, viewport.minX + 24, accuracy: 0.001)
            XCTAssertEqual(card.positionY! * zoom + 362 * zoom, viewport.maxY - 96, accuracy: 0.001)
        }
    }

    func testDragStopsAtTableEdgeAndPreservesSubtreeOffsets() throws {
        let (container, store) = try makeStore()
        _ = container
        let parent = try store.addCard()
        let child = try store.addCard(parentID: parent.id)
        let offsetX = child.positionX! - parent.positionX!
        let offsetY = child.positionY! - parent.positionY!
        try store.moveSubtree(rootID: parent.id, byX: -10000, byY: -10000, in: store.fetchAll())
        XCTAssertEqual(parent.positionX, 24)
        XCTAssertEqual(parent.positionY, 24)
        XCTAssertEqual(child.positionX! - parent.positionX!, offsetX)
        XCTAssertEqual(child.positionY! - parent.positionY!, offsetY)
    }

    func testExistingOffTableCardsAreRecoveredWithoutChangingValidTrees() throws {
        let (container, store) = try makeStore()
        _ = container
        let parent = try store.addCard()
        let child = try store.addCard(parentID: parent.id)
        let other = try store.addCard()
        parent.positionX = -80
        parent.positionY = -160
        child.positionX = -10
        child.positionY = 260
        let otherPosition = CardStore.Position(x: other.positionX!, y: other.positionY!)
        try store.recoverOffTableCards()
        XCTAssertEqual(parent.positionX, 24)
        XCTAssertEqual(parent.positionY, 24)
        XCTAssertEqual(child.positionX, 94)
        XCTAssertEqual(child.positionY, 444)
        XCTAssertEqual(other.positionX, otherPosition.x)
        XCTAssertEqual(other.positionY, otherPosition.y)
    }

    private func makeStore() throws -> (ModelContainer, CardStore) {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Card.self, configurations: configuration)
        return (container, CardStore(context: container.mainContext))
    }
}

