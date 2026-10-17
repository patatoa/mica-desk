import SwiftData
import SwiftUI
import UIKit

/// A spatial card on the table. The filename remains stable to keep the project diff small.
struct CardBranchView: View {
    @Environment(\.modelContext) private var modelContext

    let card: Card
    let allCards: [Card]
    let position: CGPoint
    let zoom: Double
    let onDragChanged: (CGPoint, CGSize) -> Void
    let onDragEnded: (CGSize, CGPoint, @escaping () -> Void) -> Void
    let onDragCancelled: (@escaping () -> Void) -> Void
    let selected: Bool
    let onSelect: () -> Void
    let onFrameChanged: (CGRect) -> Void
    let motion: DragMotion

    private var descendantCount: Int {
        CardStore(context: modelContext).descendantCount(of: card.id, in: allCards)
    }

    private var directChildren: [Card] {
        Array(CardStore.sorted(allCards.filter { $0.parentID == card.id }).prefix(3))
    }

    var body: some View {
        NativeDraggableCard(
            onDragChanged: onDragChanged,
            onDragEnded: onDragEnded,
            onDragCancelled: onDragCancelled,
            onSelect: onSelect,
            selected: selected,
            onFrameChanged: onFrameChanged,
            cardID: card.id,
            motion: motion
        ) {
            VStack(spacing: -2) {
                CardView(card: card, descendantCount: descendantCount, selected: selected)
                .zIndex(1)

                if card.isCollapsed, !directChildren.isEmpty {
                    CollapsedChildPeeks(children: directChildren)
                        .transition(
                            .asymmetric(
                                insertion: .offset(y: -16).combined(with: .opacity),
                                removal: .offset(y: -10).combined(with: .opacity)
                            )
                        )
                }
            }
            .animation(.spring(response: 0.42, dampingFraction: 0.84), value: card.isCollapsed)
        }
        .frame(width: 400)
        .scaleEffect(zoom, anchor: .topLeading)
        .offset(x: position.x * zoom, y: position.y * zoom)
        .zIndex(Double(card.createdAt.timeIntervalSinceReferenceDate))
        .shadow(color: .black.opacity(0.07), radius: 6, y: 3)
    }
}

private struct CollapsedChildPeeks: View {
    let children: [Card]

    var body: some View {
        ZStack(alignment: .top) {
            ForEach(Array(children.enumerated().reversed()), id: \.element.id) { index, child in
                UnevenRoundedRectangle(
                    cornerRadii: RectangleCornerRadii(
                        topLeading: 2,
                        bottomLeading: 8,
                        bottomTrailing: 8,
                        topTrailing: 2
                    )
                )
                    .fill(backgroundColor(for: child.colorName))
                    .overlay {
                        UnevenRoundedRectangle(
                            cornerRadii: RectangleCornerRadii(
                                topLeading: 2,
                                bottomLeading: 8,
                                bottomTrailing: 8,
                                topTrailing: 2
                            )
                        )
                            .strokeBorder(Color.secondary.opacity(0.13))
                    }
                    .frame(width: 376 - CGFloat(index * 12), height: 10)
                    .offset(y: CGFloat(index * 5))
                    .shadow(color: .black.opacity(0.035), radius: 1, y: 1)
            }
        }
        .frame(width: 400, height: CGFloat(10 + max(0, children.count - 1) * 5))
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private func backgroundColor(for colorName: String?) -> Color {
        (CardTint(rawValue: colorName ?? "") ?? .paper).backgroundColor
    }
}

/// Moves the hosted card with a UIKit transform on every pan event. This bypasses
/// SwiftUI state/layout entirely during the gesture, then persists once at the end.
private struct NativeDraggableCard<Content: View>: UIViewControllerRepresentable {
    let onDragChanged: (CGPoint, CGSize) -> Void
    let onDragEnded: (CGSize, CGPoint, @escaping () -> Void) -> Void
    let onDragCancelled: (@escaping () -> Void) -> Void
    let onSelect: () -> Void
    let selected: Bool
    let onFrameChanged: (CGRect) -> Void
    let cardID: UUID
    let motion: DragMotion
    @ViewBuilder let content: () -> Content

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onDragChanged: onDragChanged,
            onDragEnded: onDragEnded,
            onDragCancelled: onDragCancelled,
            onSelect: onSelect
        )
    }

    func makeUIViewController(context: Context) -> UIHostingController<Content> {
        let controller = UIHostingController(rootView: content())
        controller.view.backgroundColor = .clear
        context.coordinator.install(on: controller.view)
        motion.register(controller.view, for: cardID)
        return controller
    }

    func updateUIViewController(_ controller: UIHostingController<Content>, context: Context) {
        motion.register(controller.view, for: cardID)
        context.coordinator.onDragChanged = onDragChanged
        context.coordinator.onDragEnded = onDragEnded
        context.coordinator.onDragCancelled = onDragCancelled
        context.coordinator.onSelect = onSelect
        context.coordinator.onFrameChanged = onFrameChanged
        context.coordinator.setSelected(selected)
        controller.rootView = content()
        context.coordinator.hostView = controller.view
        context.coordinator.motion = motion
        context.coordinator.cardID = cardID
        DispatchQueue.main.async {
            context.coordinator.giveCardPanPriorityOverBoardScroll()
        }
    }

    static func dismantleUIViewController(_ controller: UIHostingController<Content>, coordinator: Coordinator) {
        coordinator.setSelected(false)
        if let id = coordinator.cardID { coordinator.motion?.unregister(controller.view, for: id) }
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiViewController: UIHostingController<Content>,
        context: Context
    ) -> CGSize? {
        let width = proposal.width ?? 400
        return uiViewController.sizeThatFits(
            in: CGSize(width: width, height: .greatestFiniteMagnitude)
        )
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onDragChanged: (CGPoint, CGSize) -> Void
        var onDragEnded: (CGSize, CGPoint, @escaping () -> Void) -> Void
        var onDragCancelled: (@escaping () -> Void) -> Void
        var onSelect: () -> Void
        var onFrameChanged: (CGRect) -> Void = { _ in }
        weak var hostView: UIView?
        weak var motion: DragMotion?
        var cardID: UUID?
        private weak var boardScrollView: UIScrollView?
        private let pan = UIPanGestureRecognizer()
        private let tap = UITapGestureRecognizer()
        private var dragSnapshot: UIView?
        private var dragStartFrame = CGRect.zero
        private var frameDisplayLink: CADisplayLink?
        private var lastFrame = CGRect.null

        init(
            onDragChanged: @escaping (CGPoint, CGSize) -> Void,
            onDragEnded: @escaping (CGSize, CGPoint, @escaping () -> Void) -> Void,
            onDragCancelled: @escaping (@escaping () -> Void) -> Void,
            onSelect: @escaping () -> Void
        ) {
            self.onDragChanged = onDragChanged
            self.onDragEnded = onDragEnded
            self.onDragCancelled = onDragCancelled
            self.onSelect = onSelect
            super.init()
            pan.addTarget(self, action: #selector(handlePan(_:)))
            pan.delegate = self
            pan.minimumNumberOfTouches = 1
            pan.maximumNumberOfTouches = 1
            pan.cancelsTouchesInView = true
            pan.delaysTouchesBegan = false

            tap.addTarget(self, action: #selector(handleTap))
            tap.delegate = self
            tap.numberOfTapsRequired = 1
            tap.numberOfTouchesRequired = 1
            tap.cancelsTouchesInView = false
            tap.delaysTouchesBegan = false
        }

        func install(on view: UIView) {
            hostView = view
            view.addGestureRecognizer(pan)
            view.addGestureRecognizer(tap)
        }

        func setSelected(_ selected: Bool) {
            if selected {
                guard frameDisplayLink == nil else { return }
                lastFrame = .null
                let link = CADisplayLink(target: self, selector: #selector(reportFrame))
                link.add(to: .main, forMode: .common)
                frameDisplayLink = link
            } else {
                frameDisplayLink?.invalidate()
                frameDisplayLink = nil
                lastFrame = .null
            }
        }

        @objc private func reportFrame() {
            guard let hostView, let window = hostView.window else { return }
            // The hosting view also includes collapsed child peeks below the card.
            // Measure the paper itself after all SwiftUI and scroll transforms.
            let paper = CGRect(x: 0, y: 0, width: hostView.bounds.width,
                               height: min(362, hostView.bounds.height))
            let frame = hostView.convert(paper, to: window)
            guard frame != lastFrame, !frame.isEmpty else { return }
            lastFrame = frame
            onFrameChanged(frame)
        }

        func giveCardPanPriorityOverBoardScroll() {
            guard boardScrollView == nil, let hostView else { return }
            var ancestor = hostView.superview
            while let view = ancestor {
                if let scrollView = view as? UIScrollView {
                    scrollView.panGestureRecognizer.require(toFail: pan)
                    boardScrollView = scrollView
                    return
                }
                ancestor = view.superview
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard hostView != nil else { return false }
            if gestureRecognizer === pan, motion?.canBeginDrag == false { return false }
            return gestureRecognizer === pan || gestureRecognizer === tap
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            gestureRecognizer === tap || otherGestureRecognizer === tap
        }

        @objc private func handleTap() {
            onSelect()
        }

        @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let hostView else { return }
            let translation = gesture.translation(in: hostView.window)

            switch gesture.state {
            case .began:
                beginVisualDrag(for: hostView)
                fallthrough
            case .changed:
                UIView.performWithoutAnimation {
                    dragSnapshot?.frame = dragStartFrame.offsetBy(
                        dx: translation.x,
                        dy: translation.y
                    )
                }
                onDragChanged(gesture.location(in: hostView.window), CGSize(width: translation.x, height: translation.y))
            case .ended, .cancelled:
                let location = gesture.location(in: hostView.window)
                let finish = { [weak self, weak hostView] in
                    guard let self, let hostView else { return }
                    self.endVisualDrag(for: hostView)
                }
                if gesture.state == .ended {
                    onDragEnded(CGSize(width: translation.x, height: translation.y), location, finish)
                } else {
                    endVisualDrag(for: hostView)
                    onDragCancelled({})
                }
            default:
                break
            }
        }

        private func beginVisualDrag(for hostView: UIView) {
            guard let window = hostView.window,
                  let snapshot = hostView.snapshotView(afterScreenUpdates: false) else {
                return
            }

            dragStartFrame = hostView.convert(hostView.bounds, to: window)
            snapshot.frame = dragStartFrame
            snapshot.isUserInteractionEnabled = false
            snapshot.layer.shadowColor = UIColor.black.cgColor
            snapshot.layer.shadowOpacity = 0.2
            snapshot.layer.shadowRadius = 18
            snapshot.layer.shadowOffset = CGSize(width: 0, height: 10)
            window.addSubview(snapshot)
            dragSnapshot = snapshot
            hostView.alpha = 0.01
        }

        private func endVisualDrag(for hostView: UIView) {
            hostView.alpha = 1
            dragSnapshot?.removeFromSuperview()
            dragSnapshot = nil
        }
    }
}


/// Animates window snapshots of the affected cards and redraws the connector layer.
/// SwiftData remains untouched until the existing subtree move is committed.
@MainActor
final class DragMotion: NSObject {
    private final class WeakView {
        weak var view: UIView?
        init(_ view: UIView) { self.view = view }
    }
    private final class MovingCard {
        weak var source: UIView?
        let snapshot: UIView
        let frame: CGRect
        let originalAlpha: CGFloat

        init(source: UIView, snapshot: UIView, frame: CGRect) {
            self.source = source
            self.snapshot = snapshot
            self.frame = frame
            self.originalAlpha = source.alpha
        }
    }
    private var views: [UUID: WeakView] = [:]
    private var movingCards: [UUID: MovingCard] = [:]
    weak var connections: DragConnectionsView?
    private var spring: DragSpring?
    private var originalTransforms: [UUID: CGAffineTransform] = [:]
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var settlingSince: CFTimeInterval?
    private var completion: (() -> Void)?
    var canBeginDrag: Bool { spring == nil || settlingSince != nil }

    func register(_ view: UIView, for id: UUID) { views[id] = WeakView(view) }
    func unregister(_ view: UIView, for id: UUID) {
        if views[id]?.view === view { views[id] = nil }
    }

    func begin(root: UUID, cards: [Card], reduceMotion: Bool) {
        finishImmediately()
        var nodes: [DragSpring.Node] = []
        var parents = [root]
        var visited: Set<UUID> = [root]
        while !parents.isEmpty {
            let parent = parents.removeFirst()
            for card in cards where card.parentID == parent && visited.insert(card.id).inserted {
                nodes.append(DragSpring.Node(id: card.id, parentID: parent))
                parents.append(card.id)
                if let view = views[card.id]?.view {
                    if let window = view.window, let snapshot = view.snapshotView(afterScreenUpdates: false) {
                        let frame = view.convert(view.bounds, to: window)
                        snapshot.frame = frame
                        snapshot.isUserInteractionEnabled = false
                        let moving = MovingCard(source: view, snapshot: snapshot, frame: frame)
                        window.addSubview(snapshot)
                        view.alpha = 0.01
                        movingCards[card.id] = moving
                    } else {
                        originalTransforms[card.id] = view.transform
                    }
                }
            }
        }
        spring = DragSpring(rootID: root, nodes: nodes, reduceMotion: reduceMotion)
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func move(_ translation: CGSize) {
        guard spring != nil else { return }
        spring?.rootOffset = CGPoint(x: translation.width, y: translation.height)
        // Root and strings respond immediately, without waiting for a display tick.
        if spring?.reduceMotion == true { spring?.step(0) }
        updateViews()
    }

    func settle(cancelled: Bool, completion: @escaping () -> Void) {
        guard spring != nil else { completion(); return }
        self.completion = completion
        if cancelled { spring?.rootOffset = .zero }
        if spring?.reduceMotion == true {
            spring?.step(0)
            finishImmediately()
        } else {
            settlingSince = CACurrentMediaTime()
        }
    }

    func finishImmediately() {
        displayLink?.invalidate()
        displayLink = nil
        for moving in movingCards.values {
            moving.source?.alpha = moving.originalAlpha
            moving.snapshot.removeFromSuperview()
        }
        movingCards.removeAll()
        for (id, transform) in originalTransforms { views[id]?.view?.transform = transform }
        originalTransforms.removeAll()
        spring = nil
        lastTimestamp = 0
        settlingSince = nil
        connections?.offsets = [:]
        connections?.setNeedsDisplay()
        let action = completion
        completion = nil
        action?()
    }

    @objc private func tick(_ link: CADisplayLink) {
        guard spring != nil else { return }
        let dt = lastTimestamp == 0 ? 1.0 / 60.0 : link.timestamp - lastTimestamp
        lastTimestamp = link.timestamp
        spring?.step(CGFloat(dt))
        updateViews()
        if let settlingSince {
            let elapsed = CACurrentMediaTime() - settlingSince
            if elapsed >= 1.0 || (elapsed >= 0.32 && spring?.isSettled == true) {
                finishImmediately()
            }
        }
    }

    private func updateViews() {
        guard let spring else { return }
        var offsets = [spring.rootID: spring.rootOffset]
        for node in spring.nodes {
            offsets[node.id] = node.offset
            if let moving = movingCards[node.id] {
                moving.snapshot.frame = moving.frame.offsetBy(dx: node.offset.x, dy: node.offset.y)
                continue
            }
            guard let view = views[node.id]?.view, let parent = view.superview,
                  let window = view.window, let original = originalTransforms[node.id] else { continue }
            // Convert a screen-space vector through the actual zoomed view hierarchy.
            let zero = parent.convert(CGPoint.zero, from: window)
            let end = parent.convert(node.offset, from: window)
            view.transform = original.concatenating(CGAffineTransform(translationX: end.x - zero.x, y: end.y - zero.y))
        }
        connections?.offsets = offsets
        connections?.setNeedsDisplay()
    }
}

final class DragConnectionsView: UIView {
    var edges: [(parent: UUID, child: UUID)] = []
    var positions: [UUID: CGPoint] = [:]
    var zoom: CGFloat = 1
    var offsets: [UUID: CGPoint] = [:]

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.setStrokeColor(UIColor.secondaryLabel.withAlphaComponent(0.28).cgColor)
        context.setLineWidth(2)
        context.setLineDash(phase: 0, lengths: [6, 6])
        for edge in edges {
            guard let parent = positions[edge.parent], let child = positions[edge.child] else { continue }
            let p = offsets[edge.parent] ?? .zero
            let c = offsets[edge.child] ?? .zero
            let start = CGPoint(x: (parent.x + 200) * zoom + p.x, y: (parent.y + 175) * zoom + p.y)
            let end = CGPoint(x: (child.x + 200) * zoom + c.x, y: (child.y + 24) * zoom + c.y)
            context.move(to: start)
            context.addLine(to: end)
        }
        context.strokePath()
    }
}
