import Foundation
import PencilKit

enum DrawingPersistence {
    static func data(for drawing: PKDrawing) -> Data {
        drawing.dataRepresentation()
    }

    static func drawing(from data: Data) -> PKDrawing {
        guard !data.isEmpty else { return PKDrawing() }
        return (try? PKDrawing(data: data)) ?? PKDrawing()
    }
}

