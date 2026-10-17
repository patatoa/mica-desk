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
    let onToggleCollapsed: () -> Void
    let onToggleCompact: () -> Void
    let onError: (Error) -> Void

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
            onDoubleTap: onToggleCompact
        ) {
            VStack(spacing: -2) {
                CardView(
                    card: card,
                    descendantCount: descendantCount,
                    renderVersion: card.updatedAt,
                    onToggleCollapsed: onToggleCollapsed,
                    onToggleCompact: onToggleCompact,
                    onError: onError
                )
                .equatable()
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
    let onDoubleTap: () -> Void
    @ViewBuilder let content: () -> Content

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onDragChanged: onDragChanged,
            onDragEnded: onDragEnded,
            onDragCancelled: onDragCancelled,
            onDoubleTap: onDoubleTap
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
        context.coordinator.onDoubleTap = onDoubleTap
        controller.rootView = content()
        context.coordinator.hostView = controller.view
        DispatchQueue.main.async {
            context.coordinator.giveCardPanPriorityOverBoardScroll()
        }
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
        var onDoubleTap: () -> Void
        weak var hostView: UIView?
        private weak var boardScrollView: UIScrollView?
        private let pan = UIPanGestureRecognizer()
        private let doubleTap = UITapGestureRecognizer()
        private let headerHeight: CGFloat = 68
        private var dragSnapshot: UIView?
        private var dragStartFrame = CGRect.zero

        init(
            onDragChanged: @escaping (CGPoint) -> Void,
            onDragEnded: @escaping (CGSize, CGPoint) -> Void,
            onDragCancelled: @escaping () -> Void,
            onDoubleTap: @escaping () -> Void
        ) {
            self.onDragChanged = onDragChanged
            self.onDragEnded = onDragEnded
            self.onDragCancelled = onDragCancelled
            self.onDoubleTap = onDoubleTap
            super.init()
            pan.addTarget(self, action: #selector(handlePan(_:)))
            pan.delegate = self
            pan.minimumNumberOfTouches = 1
            pan.maximumNumberOfTouches = 1
            pan.cancelsTouchesInView = true
            pan.delaysTouchesBegan = false

            doubleTap.addTarget(self, action: #selector(handleDoubleTap))
            doubleTap.delegate = self
            doubleTap.numberOfTapsRequired = 2
            doubleTap.numberOfTouchesRequired = 1
            doubleTap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
            doubleTap.cancelsTouchesInView = false
            doubleTap.delaysTouchesBegan = false
        }

        func install(on view: UIView) {
            hostView = view
            view.addGestureRecognizer(pan)
            view.addGestureRecognizer(doubleTap)
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
            guard let hostView else { return false }
            let location = gestureRecognizer.location(in: hostView)
            if gestureRecognizer === doubleTap {
                // Use the broad title region while keeping the completion and
                // descendant controls dedicated to their normal button actions.
                return location.y <= headerHeight
                    && location.x >= 56
                    && location.x <= hostView.bounds.width - 56
            }
            return gestureRecognizer === pan && location.y <= headerHeight
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            gestureRecognizer === doubleTap || otherGestureRecognizer === doubleTap
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard gestureRecognizer === doubleTap, let hostView else { return true }

            // Buttons keep their native double-tap behavior, and text notes/canvases
            // keep selection, scrolling, and PencilKit gestures. The title remains a
            // valid folding surface; editing is ended when the double tap resolves.
            var view = touch.view
            while let current = view, current !== hostView {
                if current is UIButton || current is UITextView || current is UIScrollView {
                    return false
                }
                view = current.superview
            }
            return true
        }

        @objc private func handleDoubleTap() {
            hostView?.endEditing(true)
            onDoubleTap()
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

