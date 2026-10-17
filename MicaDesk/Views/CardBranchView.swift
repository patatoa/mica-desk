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
    let onDragChanged: (CGPoint) -> Void
    let onDragEnded: (CGSize, CGPoint) -> Void
    let onDragCancelled: () -> Void
    let selected: Bool
    let onSelect: () -> Void
    let onFrameChanged: (CGRect) -> Void

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
            onFrameChanged: onFrameChanged
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
    let onDragChanged: (CGPoint) -> Void
    let onDragEnded: (CGSize, CGPoint) -> Void
    let onDragCancelled: () -> Void
    let onSelect: () -> Void
    let selected: Bool
    let onFrameChanged: (CGRect) -> Void
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
        return controller
    }

    func updateUIViewController(_ controller: UIHostingController<Content>, context: Context) {
        context.coordinator.onDragChanged = onDragChanged
        context.coordinator.onDragEnded = onDragEnded
        context.coordinator.onDragCancelled = onDragCancelled
        context.coordinator.onSelect = onSelect
        context.coordinator.onFrameChanged = onFrameChanged
        context.coordinator.setSelected(selected)
        controller.rootView = content()
        context.coordinator.hostView = controller.view
        DispatchQueue.main.async {
            context.coordinator.giveCardPanPriorityOverBoardScroll()
        }
    }

    static func dismantleUIViewController(_ controller: UIHostingController<Content>, coordinator: Coordinator) {
        coordinator.setSelected(false)
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
        var onDragChanged: (CGPoint) -> Void
        var onDragEnded: (CGSize, CGPoint) -> Void
        var onDragCancelled: () -> Void
        var onSelect: () -> Void
        var onFrameChanged: (CGRect) -> Void = { _ in }
        weak var hostView: UIView?
        private weak var boardScrollView: UIScrollView?
        private let pan = UIPanGestureRecognizer()
        private let tap = UITapGestureRecognizer()
        private var dragSnapshot: UIView?
        private var dragStartFrame = CGRect.zero
        private var frameDisplayLink: CADisplayLink?
        private var lastFrame = CGRect.null

        init(
            onDragChanged: @escaping (CGPoint) -> Void,
            onDragEnded: @escaping (CGSize, CGPoint) -> Void,
            onDragCancelled: @escaping () -> Void,
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
            return hostView != nil && (gestureRecognizer === pan || gestureRecognizer === tap)
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
                onDragChanged(gesture.location(in: hostView.window))
            case .ended, .cancelled:
                let location = gesture.location(in: hostView.window)
                endVisualDrag(for: hostView)
                if gesture.state == .ended {
                    onDragEnded(
                        CGSize(width: translation.x, height: translation.y),
                        location
                    )
                } else {
                    onDragCancelled()
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

