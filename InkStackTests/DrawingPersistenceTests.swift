import PencilKit
import XCTest
@testable import InkStack

final class DrawingPersistenceTests: XCTestCase {
    func testDrawingDataRoundTripPreservesEditableStroke() throws {
        let points = [
            PKStrokePoint(
                location: CGPoint(x: 10, y: 12),
                timeOffset: 0,
                size: CGSize(width: 3, height: 3),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            ),
            PKStrokePoint(
                location: CGPoint(x: 80, y: 40),
                timeOffset: 0.15,
                size: CGSize(width: 4, height: 4),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            )
        ]
        let path = PKStrokePath(controlPoints: points, creationDate: Date())
        let stroke = PKStroke(ink: PKInk(.pen, color: .systemBlue), path: path)
        let original = PKDrawing(strokes: [stroke])

        let encoded = DrawingPersistence.data(for: original)
        let restored = DrawingPersistence.drawing(from: encoded)

        XCTAssertFalse(encoded.isEmpty)
        XCTAssertEqual(restored.strokes.count, 1)
        XCTAssertEqual(restored.strokes[0].path.count, 2)
    }

    func testMalformedDataReturnsSafeEmptyDrawing() {
        let restored = DrawingPersistence.drawing(from: Data("not a drawing".utf8))
        XCTAssertTrue(restored.strokes.isEmpty)
    }
}

