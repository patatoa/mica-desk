import SwiftData
import SwiftUI
import UIKit

struct CardView: View, Equatable {
    @Environment(\.modelContext) private var modelContext
    @Bindable var card: Card

    let descendantCount: Int
    let renderVersion: Date
    let onToggleCollapsed: () -> Void
    let onToggleCompact: () -> Void
    let onError: (Error) -> Void

    @State private var notesHeight: CGFloat = Self.minimumNotesHeight

    private static let minimumNotesHeight: CGFloat = 48
    private static let maximumNotesHeight: CGFloat = 132

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
            }
            .contentShape(Rectangle())
            .accessibilityHint("Drag across the header to move this card. Double-tap the title to toggle compact mode.")

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

            if !isCompact {
                BufferedGrowingNotesEditor(
                    text: card.bodyText,
                    height: $notesHeight,
                    minimumHeight: Self.minimumNotesHeight,
                    maximumHeight: Self.maximumNotesHeight,
                    onCommit: commitNotes
                )
                .frame(height: notesHeight)
                .background(.black.opacity(0.035), in: RoundedRectangle(cornerRadius: 6))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .gesture(blockTablePanGesture)
                .transition(.accordionFold)
                .animation(.spring(response: 0.38, dampingFraction: 0.84), value: notesHeight)
            }

            HStack {
                Button {
                    addChild()
                } label: {
                    if isCompact {
                        Image(systemName: "plus")
                            .font(.title3)
                    } else {
                        Label("Add Child", systemImage: "plus")
                    }
                }
                .buttonStyle(.borderless)
                .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                .accessibilityLabel("Add Child")

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
        .animation(.spring(response: 0.46, dampingFraction: 0.82), value: isCompact)
        .accessibilityAction(named: isCompact ? "Expand card" : "Compact card", onToggleCompact)
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

    private var isCompact: Bool {
        card.isCompact ?? false
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

    private func commitNotes(_ notes: String) {
        guard card.bodyText != notes else { return }
        card.bodyText = notes
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

/// Keeps keystrokes in UIKit, publishing to SwiftData only after a short pause or
/// when editing ends. Height changes are much less frequent than text changes, so
/// the surrounding card can animate without rebuilding on every character.
private struct BufferedGrowingNotesEditor: UIViewRepresentable {
    let text: String
    @Binding var height: CGFloat
    let minimumHeight: CGFloat
    let maximumHeight: CGFloat
    let onCommit: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> GrowingNotesTextView {
        let textView = GrowingNotesTextView()
        textView.delegate = context.coordinator
        textView.text = text
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 10, left: 6, bottom: 10, right: 6)
        textView.textContainer.lineFragmentPadding = 0
        textView.keyboardDismissMode = .interactive
        textView.accessibilityLabel = "Typed notes"
        textView.updatePlaceholder()
        context.coordinator.textView = textView
        context.coordinator.lastCommittedText = text
        context.coordinator.beginObservingLifecycle()
        context.coordinator.measureSoon()
        return textView
    }

    func updateUIView(_ textView: GrowingNotesTextView, context: Context) {
        context.coordinator.parent = self
        if !textView.isFirstResponder, textView.text != text {
            textView.text = text
            context.coordinator.lastCommittedText = text
        }
        textView.updatePlaceholder()
        context.coordinator.measureSoon()
    }

    static func dismantleUIView(_ textView: GrowingNotesTextView, coordinator: Coordinator) {
        coordinator.flush()
        coordinator.stopObservingLifecycle()
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: BufferedGrowingNotesEditor
        weak var textView: GrowingNotesTextView?
        var lastCommittedText = ""
        private var pendingCommit: DispatchWorkItem?
        private var isMeasuring = false

        init(parent: BufferedGrowingNotesEditor) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            (textView as? GrowingNotesTextView)?.updatePlaceholder()
            measureSoon()
            scheduleCommit(textView.text)
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            flush()
        }

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

        func stopObservingLifecycle() {
            NotificationCenter.default.removeObserver(self)
            pendingCommit?.cancel()
            pendingCommit = nil
        }

        func measureSoon() {
            guard !isMeasuring else { return }
            isMeasuring = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isMeasuring = false
                self.updateHeight()
            }
        }

        func flush() {
            pendingCommit?.cancel()
            pendingCommit = nil
            commit(textView?.text ?? lastCommittedText)
        }

        @objc private func flushForLifecycleChange() {
            flush()
        }

        private func updateHeight() {
            guard let textView, textView.bounds.width > 0 else { return }
            let measuredHeight = ceil(
                textView.sizeThatFits(
                    CGSize(width: textView.bounds.width, height: .greatestFiniteMagnitude)
                ).height
            )
            let targetHeight = min(max(measuredHeight, parent.minimumHeight), parent.maximumHeight)
            textView.isScrollEnabled = measuredHeight > parent.maximumHeight + 0.5

            guard abs(parent.height - targetHeight) > 0.5 else { return }
            withAnimation(.spring(response: 0.38, dampingFraction: 0.84)) {
                parent.height = targetHeight
            }
        }

        private func scheduleCommit(_ draft: String) {
            pendingCommit?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.pendingCommit = nil
                self.commit(draft)
            }
            pendingCommit = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
        }

        private func commit(_ draft: String) {
            guard draft != lastCommittedText else { return }
            lastCommittedText = draft
            parent.onCommit(draft)
        }
    }
}

private final class GrowingNotesTextView: UITextView {
    private let placeholderLabel = UILabel()

    init() {
        super.init(frame: .zero, textContainer: nil)
        placeholderLabel.text = "Typed notes (optional)"
        placeholderLabel.font = .preferredFont(forTextStyle: .body)
        placeholderLabel.adjustsFontForContentSizeCategory = true
        placeholderLabel.textColor = .tertiaryLabel
        placeholderLabel.isUserInteractionEnabled = false
        addSubview(placeholderLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let left = textContainerInset.left
        let top = textContainerInset.top
        placeholderLabel.frame = CGRect(
            x: left,
            y: top,
            width: max(0, bounds.width - left - textContainerInset.right),
            height: placeholderLabel.intrinsicContentSize.height
        )
    }

    func updatePlaceholder() {
        placeholderLabel.isHidden = !text.isEmpty
    }
}

private struct AccordionFoldModifier: AnimatableModifier {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content
            .scaleEffect(y: max(progress, 0.001), anchor: .top)
            .rotation3DEffect(
                .degrees(Double((1 - progress) * -18)),
                axis: (x: 1, y: 0, z: 0),
                anchor: .top,
                perspective: 0.7
            )
            .opacity(progress)
            .clipped()
            .compositingGroup()
    }
}

private extension AnyTransition {
    static var accordionFold: AnyTransition {
        .modifier(
            active: AccordionFoldModifier(progress: 0),
            identity: AccordionFoldModifier(progress: 1)
        )
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

