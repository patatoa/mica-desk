import SwiftData
import SwiftUI

struct PriorityStackView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var cards: [Card]

    @State private var errorMessage: String?
    @State private var showingAbout = false
    @State private var selectedID: UUID?
    @State private var selectedCardFrame: SelectedCardFrame?

    private struct SelectedCardFrame {
        let id: UUID
        let frame: CGRect
    }
    @State private var editingCard: EditingCard?
    @State private var showingColors = false

    private struct EditingCard: Identifiable {
        let id: UUID
    }
    @State private var pendingDeletion: PendingDeletion?
    @State private var cardsPendingDeletion = Set<UUID>()
    @State private var trashFrame = CGRect.null
    @State private var activeDragID: UUID?
    @State private var isTrashTargeted = false
    @State private var tableViewport = TableViewport()
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
        min(max(boardZoom * liveMagnification, 0.25), 1.5)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { viewport in
                ScrollView([.horizontal, .vertical]) {
                    ZStack(alignment: .topLeading) {
                        TableGrid(spacing: 40 * renderedZoom)
                        Color.clear.contentShape(Rectangle())
                            .onTapGesture { selectedID = nil; showingColors = false }

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
                                selected: selectedID == card.id,
                                onSelect: { selectedID = card.id; showingColors = false },
                                onFrameChanged: { frame in
                                    if selectedID == card.id {
                                        selectedCardFrame = SelectedCardFrame(id: card.id, frame: frame)
                                    }
                                }
                            )
                            .accessibilityAction(named: "Select") { selectedID = card.id }
                            .accessibilityAction(named: "Edit") { selectedID = card.id; editingCard = EditingCard(id: card.id) }
                            .accessibilityAction(named: "Add Child") { addChild(card) }
                            .accessibilityAction(named: "Change Color") { selectedID = card.id; showingColors = true }
                            .accessibilityAction(named: card.isCompleted ? "Mark incomplete" : "Mark complete") { toggleCompleted(card) }
                            .accessibilityAction(named: "Delete") { requestDeletion(card.id) }
                            .id(card.id)
                            .transition(cardTransition(for: card, from: position))
                        }
                    }
                    .frame(
                        width: max(viewport.size.width, boardSize.width * renderedZoom),
                        height: max(viewport.size.height, boardSize.height * renderedZoom),
                        alignment: .topLeading
                    )
                }
                .overlay {
                    GeometryReader { proxy in
                        if let card = visibleCards.first(where: { $0.id == selectedID }),
                           let measured = selectedCardFrame, measured.id == card.id,
                           activeDragID == nil {
                            let viewportFrame = proxy.frame(in: .global)
                            let cardFrame = measured.frame.offsetBy(dx: -viewportFrame.minX, dy: -viewportFrame.minY)
                            if cardFrame.intersects(CGRect(origin: .zero, size: proxy.size)) {
                                cardToolbar(card)
                                    .position(toolbarPosition(for: cardFrame, in: proxy.size))
                            }
                        }
                    }
                }
                .scrollIndicators(.visible)
                .onScrollGeometryChange(for: CGRect.self) { geometry in
                    geometry.visibleRect
                } action: { _, rect in
                    tableViewport.rect = rect
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
            .navigationTitle("Desk")
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button(action: { setZoom(boardZoom - 0.125) }) {
                        Image(systemName: "minus.magnifyingglass")
                    }
                    .disabled(boardZoom <= 0.25)
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
                    Button {
                        showingAbout = true
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("About Mica Desk")
                }
            }
            .sheet(item: $editingCard) { item in
                if let card = cards.first(where: { $0.id == item.id }) {
                    CardEditor(card: card, onError: show)
                }
            }
            .sheet(isPresented: $showingAbout) {
                NavigationStack {
                    VStack(spacing: 16) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 44))
                            .foregroundStyle(.tint)
                        Text("Mica Desk").font(.title.bold())
                        Text("Patatoa 2026")
                            .foregroundStyle(.secondary)
                    }
                    .padding(32)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingAbout = false }
                        }
                    }
                }
                .presentationDetents([.medium])
            }
            .overlay(alignment: .bottomLeading) {
                Button(action: addRootCard) {
                    Image(systemName: "plus")
                        .font(.title2.weight(.semibold))
                        .frame(width: 52, height: 52)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                .accessibilityLabel("New Card")
                .padding()
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
                        .background {
                            RaisedTrashTarget(isTargeted: isTrashTargeted)
                        }
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
        .onDisappear { selectedID = nil; showingColors = false }
        .task {
            do {
                try CardStore(context: modelContext).assignMissingBoardPositions()
                try CardStore(context: modelContext).recoverOffTableCards()
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
            let position = CardStore.newCardPosition(in: tableViewport.rect, zoom: renderedZoom)
            let card = try CardStore(context: modelContext).addCard(at: position)
            card.compactFace = "drawing"
            try CardStore(context: modelContext).save()
            selectedID = card.id
            editingCard = EditingCard(id: card.id)
        } catch {
            show(error)
        }
    }

    private func addChild(_ parent: Card) {
        do {
            let child = try CardStore(context: modelContext).addCard(parentID: parent.id)
            child.compactFace = "drawing"
            try CardStore(context: modelContext).save()
            selectedID = child.id
            editingCard = EditingCard(id: child.id)
        } catch { show(error) }
    }

    private func toggleCompleted(_ card: Card) {
        do { try CardStore(context: modelContext).setCompleted(card, to: !card.isCompleted) }
        catch { show(error) }
    }

    private func toolbarPosition(for card: CGRect, in viewport: CGSize) -> CGPoint {
        let size = CGSize(width: 176, height: 44)
        let gap: CGFloat = 8
        let margin: CGFloat = 8
        let candidates = [
            CGPoint(x: card.midX, y: card.minY - gap - size.height / 2),
            CGPoint(x: card.midX, y: card.maxY + gap + size.height / 2),
            CGPoint(x: card.minX - gap - size.width / 2, y: card.midY),
            CGPoint(x: card.maxX + gap + size.width / 2, y: card.midY)
        ]
        func clamp(_ value: CGFloat, extent: CGFloat, limit: CGFloat) -> CGFloat {
            let minimum = margin + extent / 2
            let maximum = max(minimum, limit - margin - extent / 2)
            return min(max(value, minimum), maximum)
        }
        let positions = candidates.map { point in
            CGPoint(x: clamp(point.x, extent: size.width, limit: viewport.width),
                    y: clamp(point.y, extent: size.height, limit: viewport.height))
        }
        func overlap(_ point: CGPoint) -> CGFloat {
            let frame = CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                               width: size.width, height: size.height)
            let intersection = frame.intersection(card)
            return intersection.isNull ? 0 : intersection.width * intersection.height
        }
        // Prefer above, then below, then either side. If the card fills the
        // viewport, choose the constrained position with the least overlap.
        return positions.min { overlap($0) < overlap($1) } ?? .zero
    }

    private func cardToolbar(_ card: Card) -> some View {
        HStack(spacing: 0) {
            Button { editingCard = EditingCard(id: card.id) } label: { Image(systemName: "pencil") }
                .accessibilityLabel("Edit")
            Button { addChild(card) } label: { Image(systemName: "plus") }
                .accessibilityLabel("Add Child")
            Button { showingColors.toggle() } label: { Image(systemName: "paintpalette") }
                .accessibilityLabel("Change Color")
                .popover(isPresented: $showingColors) {
                    HStack {
                        ForEach(CardTint.allCases) { tint in
                            Button {
                                card.colorName = tint == .paper ? nil : tint.rawValue
                                do { try CardStore(context: modelContext).touchAndSave(card) } catch { show(error) }
                                showingColors = false
                            } label: {
                                Image(systemName: "circle.fill").foregroundStyle(tint.swatchColor).frame(width: 44, height: 44)
                            }.accessibilityLabel(tint.title)
                        }
                    }.padding().presentationCompactAdaptation(.popover)
                }
            Menu {
                Button(card.isCompleted ? "Mark incomplete" : "Mark complete", systemImage: card.isCompleted ? "circle" : "checkmark.circle") { toggleCompleted(card) }
                if CardStore(context: modelContext).descendantCount(of: card.id, in: cards) > 0 {
                    Button(card.isCollapsed ? "Expand children" : "Collapse children", systemImage: card.isCollapsed ? "chevron.down" : "chevron.right") { toggleCollapsed(card) }
                }
                Button("Delete", systemImage: "trash", role: .destructive) { requestDeletion(card.id) }
            } label: { Image(systemName: "ellipsis") }
                .accessibilityLabel("More")
        }
        .buttonStyle(CardToolbarButtonStyle())
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
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
            selectedID = cardID
            showingColors = false
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
        if let selectedID, deletedIDs.contains(selectedID) { self.selectedID = nil; showingColors = false }

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
            boardZoom = min(max(value, 0.25), 1.5)
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

/// The toolbar observes the viewport without storing scroll frames for every card.
@Observable
private final class TableViewport {
    var rect = CGRect.zero
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

/// The live drag snapshot lives in the window. Raise a matching trash label into
/// that same window so the red target remains visible above the dragged paper.
private struct RaisedTrashTarget: UIViewRepresentable {
    let isTargeted: Bool

    func makeUIView(context: Context) -> TargetAnchor {
        TargetAnchor()
    }

    func updateUIView(_ view: TargetAnchor, context: Context) {
        view.isTargeted = isTargeted
        view.setNeedsLayout()
    }

    static func dismantleUIView(_ view: TargetAnchor, coordinator: ()) {
        view.raisedView.removeFromSuperview()
    }

    final class TargetAnchor: UIView {
        var isTargeted = false
        let controller = UIHostingController(rootView: TrashDropZone(isDragging: true, isTargeted: true))
        var raisedView: UIView { controller.view }

        override func layoutSubviews() {
            super.layoutSubviews()
            guard isTargeted, let window else {
                raisedView.removeFromSuperview()
                return
            }
            raisedView.backgroundColor = .clear
            raisedView.isUserInteractionEnabled = false
            raisedView.frame = convert(bounds, to: window)
            window.addSubview(raisedView)
            window.bringSubviewToFront(raisedView)
        }
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



private struct CardToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.frame(width: 44, height: 44)
            .contentShape(Rectangle()).opacity(configuration.isPressed ? 0.5 : 1)
    }
}

private struct CardEditor: View {
    private enum Side { case front, notes }
    private enum Field { case title, notes }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Bindable var card: Card
    let onError: (Error) -> Void
    @State private var side: Side = .front
    @FocusState private var focusedField: Field?

    private var tint: CardTint { CardTint(rawValue: card.colorName ?? "") ?? .paper }
    private var face: Binding<String> {
        Binding(get: {
            card.compactFace ?? (DrawingPersistence.drawing(from: card.drawingData).strokes.isEmpty ? "title" : "drawing")
        }, set: { card.compactFace = $0; save() })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Spacer()
                Button("Done") { focusedField = nil; save(); dismiss() }
                    .fontWeight(.semibold)
                    .frame(minWidth: 64, minHeight: 44)
                    .accessibilityLabel("Done editing card")
            }

            Group {
                if side == .front {
                    TextField("Title (optional)", text: $card.title)
                        .textFieldStyle(.plain)
                        .lineLimit(1)
                        .focused($focusedField, equals: .title)
                        .accessibilityLabel("Card title")
                } else {
                    Text(card.title.isEmpty ? "Untitled card" : card.title)
                        .foregroundStyle(card.title.isEmpty ? .secondary : .primary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .font(.title2.weight(.semibold))
            .frame(minHeight: 44)

            HStack(spacing: 12) {
                Text("On desk:").font(.subheadline).foregroundStyle(.secondary)
                Picker("Show on desk", selection: face) {
                    Text("Title").tag("title")
                    Text("Drawing").tag("drawing")
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 280)
                .accessibilityLabel("Show on desk")
                Spacer(minLength: 0)
            }
            .opacity(side == .front ? 1 : 0)
            .allowsHitTesting(side == .front)
            .accessibilityHidden(side != .front)

            ZStack(alignment: .topLeading) {
                // Keep the same live canvas and undo manager through flips. Its
                // coordinates are never rescaled or rehydrated on a side change.
                CardInkView(
                    drawingData: Binding(get: { card.drawingData }, set: {
                        card.drawingData = $0
                        card.updatedAt = Date()
                    }),
                    onSaveRequested: save,
                    isActive: side == .front
                )
                .opacity(side == .front ? 1 : 0)
                .allowsHitTesting(side == .front)
                .accessibilityHidden(side != .front)

                if side == .notes {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notes").font(.headline)
                        ZStack(alignment: .topLeading) {
                            if card.bodyText.isEmpty {
                                Text("Add notes…")
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 8)
                                    .allowsHitTesting(false)
                                    .accessibilityHidden(true)
                            }
                            TextEditor(text: $card.bodyText)
                                .scrollContentBackground(.hidden)
                                .focused($focusedField, equals: .notes)
                                .accessibilityLabel("Notes")
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                Spacer()
                Button {
                    focusedField = nil
                    save()
                    side = side == .front ? .notes : .front
                } label: {
                    Label(side == .front ? "Flip to Notes" : "Flip to Front", systemImage: "rectangle.portrait.rotate")
                        .frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(tint.backgroundColor)
        .presentationBackground(tint.backgroundColor)
        .onChange(of: card.title) { _, _ in save() }
        .onChange(of: card.bodyText) { _, _ in save() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { save() } }
        .onDisappear { save() }
    }

    private func save() {
        do { try CardStore(context: context).touchAndSave(card) } catch { onError(error) }
    }
}
