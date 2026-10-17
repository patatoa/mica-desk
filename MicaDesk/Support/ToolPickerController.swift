import PencilKit

@MainActor
final class ToolPickerController {
    static let shared = ToolPickerController()

    private let picker = PKToolPicker()
    private weak var activeCanvas: PKCanvasView?
    private let canvases = NSHashTable<PKCanvasView>.weakObjects()

    private init() { }

    func register(_ canvas: PKCanvasView) {
        guard !canvases.contains(canvas) else { return }
        canvases.add(canvas)
        // PencilKit sets the initial tool on registration and keeps every canvas
        // synchronized as the user changes style, color, width, or eraser.
        picker.addObserver(canvas)
    }

    func activate(for canvas: PKCanvasView) {
        register(canvas)
        if activeCanvas === canvas, canvas.isFirstResponder, picker.isVisible {
            return
        }
        if let activeCanvas, activeCanvas !== canvas {
            picker.setVisible(false, forFirstResponder: activeCanvas)
        }
        activeCanvas = canvas
        canvas.becomeFirstResponder()
        picker.setVisible(true, forFirstResponder: canvas)
    }

    func deactivate(_ canvas: PKCanvasView) {
        canvases.remove(canvas)
        picker.removeObserver(canvas)
        guard activeCanvas === canvas else { return }
        picker.setVisible(false, forFirstResponder: canvas)
        activeCanvas = nil
    }
}

