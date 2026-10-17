import Foundation
import SwiftData

@MainActor
struct CardStore {
    struct Position: Equatable {
        var x: Double
        var y: Double
    }

    enum StoreError: LocalizedError {
        case cardNotFound
        case invalidParent
        case cycleDetected
        case crossParentMove

        var errorDescription: String? {
            switch self {
            case .cardNotFound: "The card could not be found."
            case .invalidParent: "The selected parent does not exist."
            case .cycleDetected: "A card cannot be placed inside itself or one of its descendants."
            case .crossParentMove: "Cards can only be reordered within the same parent."
            }
        }
    }

    let context: ModelContext

    func fetchAll() throws -> [Card] {
        try context.fetch(FetchDescriptor<Card>())
    }

    func orderedSiblings(parentID: UUID?, from cards: [Card]? = nil) throws -> [Card] {
        let source = try cards ?? fetchAll()
        return Self.sorted(source.filter { $0.parentID == parentID })
    }

    @discardableResult
    func addCard(parentID: UUID? = nil, at requestedPosition: Position? = nil) throws -> Card {
        let all = try fetchAll()
        if let parentID, !all.contains(where: { $0.id == parentID }) {
            throw StoreError.invalidParent
        }

        // Preserve sibling ordering for hierarchy operations, independent of table position.
        let siblings = Self.sorted(all.filter { $0.parentID == parentID })
        for (index, sibling) in siblings.enumerated() {
            sibling.sortIndex = index + 1
        }

        let position = requestedPosition ?? insertionPosition(parentID: parentID, siblings: siblings, allCards: all)
        let card = Card(
            parentID: parentID,
            sortIndex: 0,
            positionX: position.x,
            positionY: position.y
        )
        context.insert(card)
        if let parent = all.first(where: { $0.id == parentID }) {
            parent.isCollapsed = false
            parent.updatedAt = Date()
        }
        try save()
        return card
    }

    func setCompleted(_ card: Card, to completed: Bool) throws {
        card.isCompleted = completed
        card.updatedAt = Date()
        try save()
    }

    func setCollapsed(_ card: Card, to collapsed: Bool) throws {
        card.isCollapsed = collapsed
        card.updatedAt = Date()
        try save()
    }

    func setCompact(_ card: Card, to compact: Bool) throws {
        card.isCompact = compact
        card.updatedAt = Date()
        try save()
    }

    func touchAndSave(_ card: Card) throws {
        card.updatedAt = Date()
        try save()
    }

    /// Assigns deterministic coordinates to cards created by older stack-based versions.
    func assignMissingBoardPositions() throws {
        let all = try fetchAll()
        var remaining = Set(all.filter { $0.positionX == nil || $0.positionY == nil }.map(\.id))
        guard !remaining.isEmpty else { return }

        let roots = Self.sorted(all.filter { $0.parentID == nil })
        for (index, card) in roots.enumerated() where remaining.contains(card.id) {
            card.positionX = 160 + Double(index % 4) * 460
            card.positionY = 100 + Double(index / 4) * 460
            remaining.remove(card.id)
        }

        // Parents are positioned before descendants, regardless of fetch order.
        var madeProgress = true
        while !remaining.isEmpty && madeProgress {
            madeProgress = false
            for card in all where remaining.contains(card.id) {
                guard let parentID = card.parentID,
                      let parent = all.first(where: { $0.id == parentID }),
                      let parentX = parent.positionX,
                      let parentY = parent.positionY else { continue }
                let siblings = Self.sorted(all.filter { $0.parentID == parentID })
                let index = siblings.firstIndex(where: { $0.id == card.id }) ?? 0
                card.positionX = parentX + 70 + Double(index) * 430
                card.positionY = parentY + 420
                remaining.remove(card.id)
                madeProgress = true
            }
        }

        // Orphans/corrupt relationships still get a recoverable place on the table.
        for (index, cardID) in remaining.sorted(by: { $0.uuidString < $1.uuidString }).enumerated() {
            guard let card = all.first(where: { $0.id == cardID }) else { continue }
            card.positionX = 160 + Double(index % 4) * 460
            card.positionY = 100 + Double(index / 4) * 460
        }
        try save()
    }

    func moveSubtree(rootID: UUID, byX deltaX: Double, byY deltaY: Double, in cards: [Card]) throws {
        guard let root = cards.first(where: { $0.id == rootID }) else {
            throw StoreError.cardNotFound
        }
        let ids = descendantIDs(of: rootID, in: cards).union([rootID])
        let subtree = cards.filter { ids.contains($0.id) }
        let safeDeltaX = max(deltaX, 24 - (subtree.compactMap(\.positionX).min() ?? 24))
        let safeDeltaY = max(deltaY, 24 - (subtree.compactMap(\.positionY).min() ?? 24))
        for card in subtree {
            card.positionX = (card.positionX ?? 0) + safeDeltaX
            card.positionY = (card.positionY ?? 0) + safeDeltaY
        }
        root.updatedAt = Date()
        try save()
    }

    /// Recover cards placed beyond the old table origin, preserving each tree's layout.
    func recoverOffTableCards() throws {
        let all = try fetchAll()
        let allIDs = Set(all.map(\.id))
        for root in all where root.parentID == nil || !allIDs.contains(root.parentID!) {
            let ids = descendantIDs(of: root.id, in: all).union([root.id])
            let subtree = all.filter { ids.contains($0.id) }
            let shiftX = max(0, 24 - (subtree.compactMap(\.positionX).min() ?? 24))
            let shiftY = max(0, 24 - (subtree.compactMap(\.positionY).min() ?? 24))
            guard shiftX > 0 || shiftY > 0 else { continue }
            for card in subtree {
                card.positionX = (card.positionX ?? 24) + shiftX
                card.positionY = (card.positionY ?? 24) + shiftY
            }
        }
        try save()
    }

    /// The viewport is in rendered scroll-content points; card positions are unscaled.
    static func newCardPosition(in viewport: CGRect, zoom: Double) -> Position {
        let scale = max(zoom, 0.25)
        return Position(
            x: max(24, (viewport.midX - 200 * scale) / scale),
            y: max(24, (viewport.minY + 32) / scale)
        )
    }

    func move(_ movingID: UUID, before targetID: UUID) throws {
        guard movingID != targetID else { return }
        let all = try fetchAll()
        guard let moving = all.first(where: { $0.id == movingID }),
              let target = all.first(where: { $0.id == targetID }) else {
            throw StoreError.cardNotFound
        }
        guard moving.parentID == target.parentID else {
            throw StoreError.crossParentMove
        }

        var siblings = Self.sorted(all.filter { $0.parentID == moving.parentID })
        siblings.removeAll { $0.id == movingID }
        guard let targetIndex = siblings.firstIndex(where: { $0.id == targetID }) else {
            throw StoreError.cardNotFound
        }
        siblings.insert(moving, at: targetIndex)
        reindex(siblings)
        moving.updatedAt = Date()
        try save()
    }

    func move(_ movingID: UUID, after targetID: UUID) throws {
        guard movingID != targetID else { return }
        let all = try fetchAll()
        guard let moving = all.first(where: { $0.id == movingID }),
              let target = all.first(where: { $0.id == targetID }) else {
            throw StoreError.cardNotFound
        }
        guard moving.parentID == target.parentID else {
            throw StoreError.crossParentMove
        }

        var siblings = Self.sorted(all.filter { $0.parentID == moving.parentID })
        siblings.removeAll { $0.id == movingID }
        guard let targetIndex = siblings.firstIndex(where: { $0.id == targetID }) else {
            throw StoreError.cardNotFound
        }
        siblings.insert(moving, at: min(targetIndex + 1, siblings.endIndex))
        reindex(siblings)
        moving.updatedAt = Date()
        try save()
    }

    /// Kept separate from drag/drop so future cross-parent moves share the same validation.
    func reparent(_ cardID: UUID, to newParentID: UUID?) throws {
        let all = try fetchAll()
        guard let card = all.first(where: { $0.id == cardID }) else {
            throw StoreError.cardNotFound
        }
        if let newParentID {
            guard all.contains(where: { $0.id == newParentID }) else {
                throw StoreError.invalidParent
            }
            guard newParentID != cardID,
                  !descendantIDs(of: cardID, in: all).contains(newParentID) else {
                throw StoreError.cycleDetected
            }
        }

        let oldParentID = card.parentID
        card.parentID = newParentID
        card.sortIndex = Self.sorted(all.filter { $0.parentID == newParentID && $0.id != cardID }).count
        card.updatedAt = Date()
        reindex(Self.sorted(all.filter { $0.parentID == oldParentID && $0.id != cardID }))
        try save()
    }

    func deleteSubtree(rootID: UUID) throws {
        let all = try fetchAll()
        guard let root = all.first(where: { $0.id == rootID }) else {
            throw StoreError.cardNotFound
        }
        let oldParentID = root.parentID
        let ids = descendantIDs(of: rootID, in: all).union([rootID])

        // `drawingData` uses external storage and may still be a lazy fault. Resolve it
        // while the model is attached so a view finishing teardown cannot trigger a
        // fatal detached-fault read after deletion.
        for card in all where ids.contains(card.id) {
            _ = card.drawingData.count
        }
        for card in all where ids.contains(card.id) {
            context.delete(card)
        }
        reindex(Self.sorted(all.filter { $0.parentID == oldParentID && !ids.contains($0.id) }))
        try save()
    }

    func descendantIDs(of rootID: UUID, in cards: [Card]? = nil) -> Set<UUID> {
        let source: [Card]
        if let cards {
            source = cards
        } else {
            source = (try? fetchAll()) ?? []
        }
        var found = Set<UUID>()
        var frontier = [rootID]
        while let parent = frontier.popLast() {
            for child in source where child.parentID == parent && !found.contains(child.id) {
                found.insert(child.id)
                frontier.append(child.id)
            }
        }
        return found
    }

    func descendantCount(of cardID: UUID, in cards: [Card]) -> Int {
        descendantIDs(of: cardID, in: cards).count
    }

    func save() throws {
        if context.hasChanges {
            try context.save()
        }
    }

    static func sorted(_ cards: [Card]) -> [Card] {
        cards.sorted {
            if $0.sortIndex != $1.sortIndex { return $0.sortIndex < $1.sortIndex }
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    private func reindex(_ siblings: [Card]) {
        for (index, card) in siblings.enumerated() {
            card.sortIndex = index
        }
    }

    private func insertionPosition(parentID: UUID?, siblings: [Card], allCards: [Card]) -> Position {
        if let parentID,
           let parent = allCards.first(where: { $0.id == parentID }),
           let parentX = parent.positionX,
           let parentY = parent.positionY {
            return Position(
                x: parentX + 70 + Double(siblings.count) * 430,
                y: parentY + 420
            )
        }

        let rootCount = allCards.filter { $0.parentID == nil }.count
        return Position(
            x: 160 + Double(rootCount % 4) * 460,
            y: 100 + Double(rootCount / 4) * 460
        )
    }
}

