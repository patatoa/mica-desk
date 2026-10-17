import SwiftData
import SwiftUI
import PencilKit
import UIKit

struct CardView: View {
    @Bindable var card: Card
    let descendantCount: Int
    let selected: Bool

    private var drawing: PKDrawing { DrawingPersistence.drawing(from: card.drawingData) }
    private var showsDrawing: Bool {
        card.compactFace == "drawing" || (card.compactFace == nil && !drawing.strokes.isEmpty)
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if showsDrawing {
                InkPreview(data: card.drawingData)
                    .padding(16)
            } else {
                ViewThatFits(in: .vertical) {
                    ForEach([64.0, 48.0, 36.0], id: \.self) { size in
                        Text(card.title)
                            .font(.system(size: size, weight: .medium))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(card.title)
                        .font(.system(size: 28, weight: .medium))
                        .lineLimit(8)
                }
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(24)
            }
            if card.isCollapsed && descendantCount > 0 {
                Image(systemName: "square.stack.3d.down.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(12)
            }
        }
        .frame(width: 400, height: 362)
        .background((CardTint(rawValue: card.colorName ?? "") ?? .paper).backgroundColor, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.13), lineWidth: selected ? 4 : 1)
        }
        .opacity(card.isCompleted ? 0.68 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(card.title.isEmpty ? "Untitled card" : card.title)
        .accessibilityValue("\(card.isCompleted ? "Completed" : "Incomplete"), \(showsDrawing ? "drawing" : "title") face, \(descendantCount) descendants")
    }
}

private struct InkPreview: View {
    let data: Data
    @State private var image: UIImage?

    var body: some View {
        GeometryReader { geometry in
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .allowsHitTesting(false)
        .onAppear(perform: updateImage)
        .onChange(of: data) { _, _ in updateImage() }
    }

    private func updateImage() {
        let drawing = DrawingPersistence.drawing(from: data)
        let bounds = drawing.bounds.insetBy(dx: -8, dy: -8)
        image = drawing.strokes.isEmpty || bounds.isEmpty ? nil : drawing.image(from: bounds, scale: 1)
    }
}

enum CardTint: String, CaseIterable, Identifiable {
    case paper, blue, green, yellow, pink, gray

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var swatchColor: Color {
        switch self {
        case .paper: .secondary
        case .blue: .blue
        case .green: .green
        case .yellow: .yellow
        case .pink: .pink
        case .gray: .gray
        }
    }

    var backgroundColor: Color {
        switch self {
        case .paper: Color(uiColor: .secondarySystemGroupedBackground)
        case .blue: Color(uiColor: Self.opaqueBlend(.systemBlue))
        case .green: Color(uiColor: Self.opaqueBlend(.systemGreen))
        case .yellow: Color(uiColor: Self.opaqueBlend(.systemYellow))
        case .pink: Color(uiColor: Self.opaqueBlend(.systemPink))
        case .gray: Color(uiColor: Self.opaqueBlend(.systemGray))
        }
    }

    /// Matches the former 16% translucent tint while producing a fully opaque
    /// dynamic color, so the table grid cannot show through the card.
    private static func opaqueBlend(_ foreground: UIColor) -> UIColor {
        UIColor { traits in
            let foreground = foreground.resolvedColor(with: traits)
            let background = UIColor.secondarySystemGroupedBackground.resolvedColor(with: traits)
            var foregroundRed = CGFloat.zero
            var foregroundGreen = CGFloat.zero
            var foregroundBlue = CGFloat.zero
            var foregroundAlpha = CGFloat.zero
            var backgroundRed = CGFloat.zero
            var backgroundGreen = CGFloat.zero
            var backgroundBlue = CGFloat.zero
            var backgroundAlpha = CGFloat.zero
            foreground.getRed(&foregroundRed, green: &foregroundGreen, blue: &foregroundBlue, alpha: &foregroundAlpha)
            background.getRed(&backgroundRed, green: &backgroundGreen, blue: &backgroundBlue, alpha: &backgroundAlpha)
            let amount: CGFloat = 0.16
            return UIColor(
                red: foregroundRed * amount + backgroundRed * (1 - amount),
                green: foregroundGreen * amount + backgroundGreen * (1 - amount),
                blue: foregroundBlue * amount + backgroundBlue * (1 - amount),
                alpha: 1
            )
        }
    }
}

