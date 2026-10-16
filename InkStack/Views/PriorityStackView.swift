import SwiftData
import SwiftUI

struct PriorityStackView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var cards: [Card]

    @State private var errorMessage: String?
    @State private var pendingDeletion: PendingDeletion?
    @State private var cardsPendingDeletion = Set<UUID>()
    @State private var trashFrame = CGRect.null
    @State private var activeDragID: UUID?
    @State private var isTrashTargeted = false
    @State private var newCardScrollRequest: UUID?
    @GestureState private var liveMagnification = 1.0
    // Keep the original persistence key so existing installs retain their zoom setting.
    @AppStorage("stackZoom") private var boardZoom = 1.0

    private struct PendingDeletion {
        let cardID: UUID
        let descendantCount: Int
    }

    private var visibleCards: [Card] {
        cards.filter { !cardsPendingDeletion.contains($0.id) && isVisible($0) }.sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    private var displayedPositions: [UUID: CGPoint] {
        var result: [UUID: CGPoint] = [:]
        for (index, card) in visibleCards.enumerated() {
            let point = CGPoint(
                x: card.positionX ?? 160 + Double(index % 4) * 460,
                y: card.positionY ?? 100 + Double(index / 4) * 460
            )
            result[card.id] = point
        }
        return result
    }

    private var boardSize: CGSize {
        let positions = displayedPositions.values
        return CGSize(
            width: max(2200, (positions.map(\.x).max() ?? 0) + 620),
            height: max(1600, (positions.map(\.y).max() ?? 0) + 620)
        )
    }

    private var renderedZoom: Double {
        min(max(boardZoom * liveMagnification, 0.625), 1.5)
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView([.horizontal, .vertical]) {
                    ZStack(alignment: .topLeading) {
                        TableGrid(spacing: 40 * renderedZoom)

                        HierarchyConnections(
                            cards: visibleCards,
                            positions: displayedPositions,
                            zoom: renderedZoom
                        )

                        if cards.isEmpty {
                            ContentUnavailableView {
                                Label("An empty table", systemImage: "rectangle.on.rectangle.angled")
                            } description: {
                                Text("Add a card, write a thought, then place it wherever it belongs.")
                            } actions: {
                                Button("New Card", systemImage: "plus", action: addRootCard)
                                    .buttonStyle(.borderedProminent)
                            }
                            .frame(width: 520, height: 420)
                            .offset(x: 120, y: 80)
                        }

                        ForEach(visibleCards) { card in
                            let position = displayedPositions[card.id] ?? CGPoint(x: 160, y: 100)
                            CardBranchView(
                                card: card,
                                allCards: cards,
                                position: position,
                                zoom: renderedZoom,
                                onDragChanged: { location in
                                    updateDrag(cardID: card.id, globalLocation: location)
                                },
                                onDragEnded: { translation, location in
                                    finishDrag(cardID: card.id, translation: translation, globalLocation: location)
                                    endDrag()
                                },
                                onDragCancelled: endDrag,
                                onToggleCollapsed: {
                                    toggleCollapsed(card)
                                },
                                onToggleCompact: {
                                    toggleCompact(card)
                                },
                                onError: show
                            )
                            .id(card.id)
                            .transition(cardTransition(for: card, from: position))
                        }
                    }
                    .frame(
                        width: boardSize.width * renderedZoom,
                        height: boardSize.height * renderedZoom,
                        alignment: .topLeading
                    )
                }
                .scrollIndicators(.visible)
                .onChange(of: newCardScrollRequest) { _, cardID in
                    guard let cardID else { return }
                    Task { @MainActor in
                        await Task.yield()
                        withAnimation { proxy.scrollTo(cardID, anchor: .center) }
                        newCardScrollRequest = nil
                    }
                }
                .highPriorityGesture(
                    MagnifyGesture(minimumScaleDelta: 0.005)
                        .updating($liveMagnification) { value, state, _ in
                            state = value.magnification
                        }
                        .onEnded { value in
                            setZoom(boardZoom * value.magnification)
                        }
                )
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Table")
            .toolbar {
                ToolbarItemGroup(placement: .secondaryAction) {
                    Button(action: { setZoom(boardZoom - 0.125) }) {
                        Image(systemName: "minus.magnifyingglass")
                    }
                    .disabled(boardZoom <= 0.625)
                    .accessibilityLabel("Zoom out table")

                    Text("\(Int((renderedZoom * 100).rounded()))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Table zoom \(Int((renderedZoom * 100).rounded())) percent")

                    Button(action: { setZoom(boardZoom + 0.125) }) {
                        Image(systemName: "plus.magnifyingglass")
                    }
                    .disabled(boardZoom >= 1.5)
                    .accessibilityLabel("Zoom in table")
                }

                ToolbarItem(placement: .primaryAction) {
                    Button(action: addRootCard) {
                        Label("New Card", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityHint("Adds a blank card to the table")
                }
            }
            .overlay(alignment: .bottom) {
                VStack(spacing: 8) {
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.callout)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(.red, in: Capsule())
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                            .accessibilityLabel("Error: \(errorMessage)")
                    }

                    if !cards.isEmpty {
                        TrashDropZone(
                            isDragging: activeDragID != nil,
                            isTargeted: isTrashTargeted
                        )
                        .onGeometryChange(for: CGRect.self) { proxy in
                            proxy.frame(in: .global)
                        } action: { frame in
                            trashFrame = frame
                        }
                    }
                }
                .padding()
            }
            .confirmationDialog(
                deletionTitle,
                isPresented: Binding(
                    get: { pendingDeletion != nil },
                    set: { if !$0 { pendingDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete Card and Descendants", role: .destructive) {
                    guard let cardID = pendingDeletion?.cardID else { return }
                    pendingDeletion = nil
                    deleteAfterDragFinishes(cardID)
                }
                Button("Cancel", role: .cancel) { pendingDeletion = nil }
            } message: {
                Text("This permanently removes the entire subtree. This cannot be undone.")
            }
        }
        .task {
            do {
                try CardStore(context: modelContext).assignMissingBoardPositions()
            } catch {
                show(error)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                do {
                    try CardStore(context: modelContext).save()
                } catch {
                    show(error)
                }
            }
        }
    }

    private func isVisible(_ card: Card) -> Bool {
        var parentID = card.parentID
        var visited = Set<UUID>()
        while let id = parentID {
            guard visited.insert(id).inserted,
                  let parent = cards.first(where: { $0.id == id }) else {
                return false
            }
            if parent.isCollapsed { return false }
            parentID = parent.parentID
        }
        return true
    }

    private func addRootCard() {
        do {
            let card = try CardStore(context: modelContext).addCard()
            newCardScrollRequest = card.id
        } catch {
            show(error)
        }
    }

    private func toggleCollapsed(_ card: Card) {
        do {
            try withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                try CardStore(context: modelContext).setCollapsed(card, to: !card.isCollapsed)
            }
        } catch {
            show(error)
        }
    }

    private func toggleCompact(_ card: Card) {
        do {
            try withAnimation(.spring(response: 0.46, dampingFraction: 0.82)) {
                try CardStore(context: modelContext).setCompact(card, to: !(card.isCompact ?? false))
            }
        } catch {
            show(error)
        }
    }

    private func cardTransition(for card: Card, from position: CGPoint) -> AnyTransition {
        guard let parentID = card.parentID,
              let parentPosition = displayedPositions[parentID] else {
            return .opacity.combined(with: .scale(scale: 0.94))
        }

        let rawX = (parentPosition.x - position.x) * renderedZoom
        let rawY = (parentPosition.y - position.y) * renderedZoom
        let distance = hypot(rawX, rawY)
        let scale = distance > 140 ? 140 / distance : 1
        let tuck = AnyTransition.offset(x: rawX * scale, y: rawY * scale)
            .combined(with: .scale(scale: 0.88))
            .combined(with: .opacity)
        return .asymmetric(insertion: tuck, removal: tuck)
    }

    private func finishDrag(cardID: UUID, translation: CGSize, globalLocation: CGPoint) {
        if trashFrame.contains(globalLocation) {
            requestDeletion(cardID)
            return
        }

        do {
            try CardStore(context: modelContext).moveSubtree(
                rootID: cardID,
                byX: translation.width / renderedZoom,
                byY: translation.height / renderedZoom,
                in: cards
            )
        } catch {
            show(error)
        }
    }

    private func updateDrag(cardID: UUID, globalLocation: CGPoint) {
        if activeDragID != cardID {
            activeDragID = cardID
        }
        let targeted = trashFrame.contains(globalLocation)
        if isTrashTargeted != targeted {
            isTrashTargeted = targeted
        }
    }

    private func endDrag() {
        activeDragID = nil
        isTrashTargeted = false
    }

    private var deletionTitle: String {
        guard let pendingDeletion else { return "Delete this card?" }
        return "Delete this card and all \(pendingDeletion.descendantCount) descendants?"
    }

    private func requestDeletion(_ cardID: UUID) {
        guard cards.contains(where: { $0.id == cardID }) else { return }
        let count = CardStore(context: modelContext).descendantCount(of: cardID, in: cards)
        if count > 0 {
            pendingDeletion = PendingDeletion(cardID: cardID, descendantCount: count)
        } else {
            deleteAfterDragFinishes(cardID)
        }
    }

    private func deleteAfterDragFinishes(_ cardID: UUID) {
        let store = CardStore(context: modelContext)
        guard cards.contains(where: { $0.id == cardID }) else { return }
        let deletedIDs = store.descendantIDs(of: cardID, in: cards).union([cardID])

        // SwiftData detaches deleted models immediately. Remove every affected view
        // first so SwiftUI/PencilKit cannot read a lazy drawing fault during teardown.
        withAnimation(.easeOut(duration: 0.12)) {
            cardsPendingDeletion.formUnion(deletedIDs)
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            do {
                try store.deleteSubtree(rootID: cardID)
            } catch {
                cardsPendingDeletion.subtract(deletedIDs)
                show(error)
            }
        }
    }

    private func setZoom(_ value: Double) {
        withAnimation(.easeOut(duration: 0.18)) {
            boardZoom = min(max(value, 0.625), 1.5)
        }
    }

    private func show(_ error: Error) {
        withAnimation { errorMessage = error.localizedDescription }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            withAnimation { errorMessage = nil }
        }
    }
}

private struct TableGrid: View {
    let spacing: CGFloat

    var body: some View {
        Canvas { context, size in
            var path = Path()
            stride(from: 0, through: size.width, by: spacing).forEach { x in
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
            stride(from: 0, through: size.height, by: spacing).forEach { y in
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(path, with: .color(.secondary.opacity(0.055)), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

private struct HierarchyConnections: View {
    let cards: [Card]
    let positions: [UUID: CGPoint]
    let zoom: Double

    var body: some View {
        Canvas { context, _ in
            for card in cards {
                guard let parentID = card.parentID,
                      let parent = positions[parentID],
                      let child = positions[card.id] else { continue }
                var path = Path()
                path.move(to: CGPoint(x: (parent.x + 200) * zoom, y: (parent.y + 175) * zoom))
                path.addLine(to: CGPoint(x: (child.x + 200) * zoom, y: (child.y + 24) * zoom))
                context.stroke(path, with: .color(.secondary.opacity(0.28)), style: StrokeStyle(lineWidth: 2, dash: [6, 6]))
            }
        }
        .allowsHitTesting(false)
    }
}

private struct TrashDropZone: View {
    let isDragging: Bool
    let isTargeted: Bool

    var body: some View {
        Label("Drag here to delete", systemImage: isTargeted ? "trash.fill" : "trash")
            .font(.callout.weight(.semibold))
            .foregroundStyle(isTargeted ? .white : .secondary)
            .padding(.horizontal, 18)
            .frame(minHeight: 48)
            .background(isTargeted ? Color.red : Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isTargeted ? Color.red : Color.secondary.opacity(isDragging ? 0.45 : 0.2))
            }
            .shadow(color: .black.opacity(isDragging ? 0.12 : 0.04), radius: 8, y: 3)
            .scaleEffect(isTargeted ? 1.06 : 1)
            .animation(.easeOut(duration: 0.12), value: isTargeted)
            .accessibilityHint("Drag a card handle here to delete that card")
    }
}

#Preview {
    PriorityStackView()
        .modelContainer(PreviewData.container)
}

