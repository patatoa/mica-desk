import PencilKit

@MainActor
final class ToolPickerController {
    static let shared = ToolPickerController()

    private let picker = PKToolPicker()
    private weak var activeCanvas: PKCanvasView?

    private init() { }

    func activate(for canvas: PKCanvasView) {
        if activeCanvas === canvas, canvas.isFirstResponder, picker.isVisible {
            return
        }
        if let activeCanvas, activeCanvas !== canvas {
            picker.setVisible(false, forFirstResponder: activeCanvas)
            picker.removeObserver(activeCanvas)
        }
        activeCanvas = canvas
        picker.addObserver(canvas)
        canvas.becomeFirstResponder()
        picker.setVisible(true, forFirstResponder: canvas)
    }

    func deactivate(_ canvas: PKCanvasView) {
        guard activeCanvas === canvas else { return }
        picker.setVisible(false, forFirstResponder: canvas)
        picker.removeObserver(canvas)
        activeCanvas = nil
    }
}

