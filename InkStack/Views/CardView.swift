import SwiftData
import SwiftUI

struct CardView: View, Equatable {
    @Environment(\.modelContext) private var modelContext
    @Bindable var card: Card

    let descendantCount: Int
    let renderVersion: Date
    let onToggleCollapsed: () -> Void
    let onError: (Error) -> Void

    @FocusState private var focusedField: Field?
    private enum Field {
        case body
    }

    static func == (lhs: CardView, rhs: CardView) -> Bool {
        lhs.card.id == rhs.card.id
            && lhs.descendantCount == rhs.descendantCount
            && lhs.renderVersion == rhs.renderVersion
    }

    private var blockTablePanGesture: some Gesture {
        // A card owns one-finger drags within its bounds. Interactive children still
        // receive taps and PencilKit keeps its own pencil-only recognizers.
        DragGesture(minimumDistance: 8)
            .onChanged { _ in }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button(action: toggleComplete) {
                    Image(systemName: card.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(card.isCompleted ? Color.secondary : Color.accentColor)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(card.isCompleted ? "Mark incomplete" : "Mark complete")

                BufferedTitleField(
                    title: card.title,
                    isCompleted: card.isCompleted,
                    onCommit: commitTitle
                )
                .frame(maxWidth: .infinity, minHeight: 44)

                if descendantCount > 0 {
                    Button(action: onToggleCollapsed) {
                        HStack(spacing: 4) {
                            Image(systemName: card.isCollapsed ? "chevron.right" : "chevron.down")
                            Text("\(descendantCount)")
                                .font(.caption.monospacedDigit())
                        }
                        .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(card.isCollapsed ? "Expand \(descendantCount) descendants" : "Collapse \(descendantCount) descendants")
                }

                Image(systemName: "line.3.horizontal")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .accessibilityLabel("Move card")
                    .accessibilityHint("Drag anywhere across the card header to move it, or drag to the trash target to delete")
            }
            .contentShape(Rectangle())

            ZStack(alignment: .topLeading) {
                if card.bodyText.isEmpty && focusedField != .body {
                    Text("Typed notes (optional)")
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 9)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $card.bodyText)
                    .focused($focusedField, equals: .body)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 3)
                    .accessibilityLabel("Typed notes")
            }
            .frame(minHeight: 42, maxHeight: 72)
            .background(.black.opacity(0.035), in: RoundedRectangle(cornerRadius: 5))
            .gesture(blockTablePanGesture)

            CardInkView(
                drawingData: Binding(
                    get: { card.drawingData },
                    set: {
                        card.drawingData = $0
                        card.updatedAt = Date()
                    }
                ),
                onSaveRequested: saveDrawing
            )
            .frame(height: 230)
            .background(selectedTint.backgroundColor, in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.secondary.opacity(0.12))
            }
            .accessibilityHint("Write with Apple Pencil. Tap to show drawing tools.")

            HStack {
                Button("Add Child", systemImage: "plus") {
                    addChild()
                }
                .buttonStyle(.borderless)
                .frame(minHeight: 44)

                Spacer()

                Menu {
                    ForEach(CardTint.allCases) { tint in
                        Button {
                            setTint(tint)
                        } label: {
                            Label(tint.title, systemImage: tint == selectedTint ? "checkmark.circle.fill" : "circle.fill")
                        }
                    }
                } label: {
                    Image(systemName: "circle.fill")
                        .foregroundStyle(selectedTint.swatchColor)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Card color, \(selectedTint.title)")
            }
            .gesture(blockTablePanGesture)
        }
        .padding(12)
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .background(selectedTint.backgroundColor, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.secondary.opacity(card.isCompleted ? 0.07 : 0.13))
        }
        .opacity(card.isCompleted ? 0.68 : 1)
        .onChange(of: focusedField) { oldValue, newValue in
            if oldValue != nil && oldValue != newValue {
                markEdited()
                saveContext()
            }
        }
    }

    private func addChild() {
        do {
            try CardStore(context: modelContext).addCard(parentID: card.id)
        } catch {
            onError(error)
        }
    }

    private func toggleComplete() {
        do {
            try CardStore(context: modelContext).setCompleted(card, to: !card.isCompleted)
        } catch {
            onError(error)
        }
    }

    private var selectedTint: CardTint {
        CardTint(rawValue: card.colorName ?? "") ?? .paper
    }

    private func setTint(_ tint: CardTint) {
        card.colorName = tint == .paper ? nil : tint.rawValue
        saveEdits()
    }

    private func saveEdits() {
        markEdited()
        saveContext()
    }

    private func commitTitle(_ title: String) {
        guard card.title != title else { return }
        card.title = title
        markEdited()
        saveContext()
    }

    private func markEdited() {
        card.updatedAt = Date()
    }

    private func saveContext() {
        do {
            try CardStore(context: modelContext).save()
        } catch {
            onError(error)
        }
    }

    private func saveDrawing() {
        do {
            // Drawing changes already updated the live model. Avoid retaining/touching
            // a Card here because a delayed save may coincide with deletion teardown.
            try CardStore(context: modelContext).save()
        } catch {
            onError(error)
        }
    }
}

/// UIKit owns the editing buffer, so keystrokes never invalidate the SwiftUI card tree.
private struct BufferedTitleField: UIViewRepresentable {
    let title: String
    let isCompleted: Bool
    let onCommit: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCommit: onCommit)
    }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.delegate = context.coordinator
        field.font = .preferredFont(forTextStyle: .headline)
        field.adjustsFontForContentSizeCategory = true
        field.placeholder = "Optional title"
        field.returnKeyType = .done
        field.borderStyle = .none
        field.clearButtonMode = .whileEditing
        field.accessibilityLabel = "Card title"
        field.accessibilityHint = "Tap to edit, or drag across the card header to move the card"
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.onCommit = onCommit
        if !field.isFirstResponder, field.text != title {
            field.text = title
        }
        let attributes: [NSAttributedString.Key: Any] = isCompleted
            ? [.strikethroughStyle: NSUnderlineStyle.single.rawValue]
            : [:]
        field.defaultTextAttributes = attributes.merging([
            .font: UIFont.preferredFont(forTextStyle: .headline),
            .foregroundColor: UIColor.label
        ]) { _, new in new }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var onCommit: (String) -> Void

        init(onCommit: @escaping (String) -> Void) {
            self.onCommit = onCommit
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            onCommit(textField.text ?? "")
        }
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

