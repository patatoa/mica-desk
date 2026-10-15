import PencilKit
import SwiftUI

struct CardInkView: UIViewRepresentable {
    @Binding var drawingData: Data
    var onSaveRequested: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> InkCanvasContainer {
        let container = InkCanvasContainer()
        let canvas = container.canvas
        canvas.delegate = context.coordinator
        canvas.drawing = DrawingPersistence.drawing(from: drawingData)
        canvas.drawingPolicy = .pencilOnly
        canvas.isScrollEnabled = false
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.accessibilityLabel = "Handwriting canvas"

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.activateTools))
        tap.cancelsTouchesInView = false
        canvas.addGestureRecognizer(tap)

        // Keep one-finger movement inside a card from bubbling up to the board's
        // scroll view. Pencil touches remain available to PencilKit, and two-finger
        // pinches remain available to the board zoom gesture.
        let fingerPan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.absorbFingerPan))
        fingerPan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        fingerPan.minimumNumberOfTouches = 1
        fingerPan.maximumNumberOfTouches = 1
        canvas.addGestureRecognizer(fingerPan)
        container.toolsButton.addTarget(
            context.coordinator,
            action: #selector(Coordinator.activateTools),
            for: .touchUpInside
        )
        context.coordinator.canvas = canvas
        context.coordinator.lastPublishedData = drawingData
        context.coordinator.beginObservingLifecycle()
        return container
    }

    func updateUIView(_ container: InkCanvasContainer, context: Context) {
        let canvas = container.canvas
        context.coordinator.parent = self
        // `updateUIView` also runs for every board drag frame. Never serialize the
        // PKDrawing here; that made moving one card scale with every visible canvas.
        // The coordinator already records the last drawing it published.
        if drawingData != context.coordinator.lastPublishedData {
            canvas.drawing = DrawingPersistence.drawing(from: drawingData)
            context.coordinator.lastPublishedData = drawingData
        }
    }

    static func dismantleUIView(_ container: InkCanvasContainer, coordinator: Coordinator) {
        // The owning SwiftData model may already be deleted when teardown runs.
        // Never write through its binding from dismantleUIView.
        coordinator.cancelPendingSave()
        NotificationCenter.default.removeObserver(coordinator)
        ToolPickerController.shared.deactivate(container.canvas)
    }

    @MainActor
    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: CardInkView
        weak var canvas: PKCanvasView?
        var lastPublishedData = Data()
        private var pendingSave: DispatchWorkItem?

        init(parent: CardInkView) {
            self.parent = parent
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            publishDrawing(DrawingPersistence.data(for: canvasView.drawing))
        }

        func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
            ToolPickerController.shared.activate(for: canvasView)
        }

        @objc func activateTools() {
            guard let canvas else { return }
            ToolPickerController.shared.activate(for: canvas)
        }

        @objc func absorbFingerPan() {}

        func beginObservingLifecycle() {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(flushForLifecycleChange),
                name: UIApplication.willResignActiveNotification,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(flushForLifecycleChange),
                name: UIApplication.didEnterBackgroundNotification,
                object: nil
            )
        }

        @objc private func flushForLifecycleChange() {
            flush()
        }

        func flush() {
            let hadPendingSave = pendingSave != nil
            pendingSave?.cancel()
            pendingSave = nil
            if hadPendingSave {
                parent.onSaveRequested()
            }
        }

        func cancelPendingSave() {
            pendingSave?.cancel()
            pendingSave = nil
        }

        private func publishDrawing(_ data: Data) {
            guard data != lastPublishedData else { return }
            lastPublishedData = data
            // Keep the binding current while its card is alive; debounce only the disk save.
            parent.drawingData = data

            pendingSave?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.pendingSave = nil
                self.parent.onSaveRequested()
            }
            pendingSave = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
        }
    }
}

final class InkCanvasContainer: UIView {
    let canvas = PKCanvasView()
    let toolsButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear

        canvas.translatesAutoresizingMaskIntoConstraints = false
        addSubview(canvas)

        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: "pencil.tip.crop.circle")
        configuration.baseForegroundColor = .secondaryLabel
        configuration.background.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.8)
        configuration.background.cornerRadius = 16
        toolsButton.configuration = configuration
        toolsButton.accessibilityLabel = "Show drawing tools"
        toolsButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(toolsButton)

        NSLayoutConstraint.activate([
            canvas.leadingAnchor.constraint(equalTo: leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: trailingAnchor),
            canvas.topAnchor.constraint(equalTo: topAnchor),
            canvas.bottomAnchor.constraint(equalTo: bottomAnchor),
            toolsButton.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            toolsButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            toolsButton.widthAnchor.constraint(equalToConstant: 32),
            toolsButton.heightAnchor.constraint(equalToConstant: 32)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

