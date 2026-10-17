# Mica Desk — Codex implementation brief

## Your assignment

Build **MicaDesk**, a working, native, local-first **iPad app** for managing daily work as a draggable hierarchy of cards with **editable Apple Pencil handwriting**. Treat this as an **implementation task**, not a request for another plan. Create the Xcode project, implement the MVP in iterative milestones, run available builds/tests, and report what works and what requires testing on a physical iPad.

If this is an existing repository, inspect it first and preserve unrelated work. If it is empty, initialize a suitable project. Make reasonable design decisions without stopping for clarification unless truly blocked. Avoid dependencies and elaborate abstractions that do not directly serve the MVP.

## Product principle

**Capturing a thought must be faster than organizing it.** The current workflow is a fast, freeform handwritten to-do list. MicaDesk adds reorderable priorities and nested cards **without imposing fields, labels, due dates, projects, or statuses**. The hierarchy is optional and emerges as the user organizes work.

Think **a handwritten, infinitely nestable priority stack**, not Trello, Jira, or a generic Kanban clone.

## Target and stack

- **Platform:** iPad first; iPadOS 18+ is an acceptable minimum. Support portrait and landscape.
- **Language/UI:** Swift, SwiftUI.
- **Handwriting:** PencilKit, embedded using `UIViewRepresentable` around `PKCanvasView`.
- **Local persistence:** SwiftData. Do not require login, network, CloudKit, or an external service.
- **Testing:** XCTest and on-device manual test guidance.
- **Dependencies:** Apple frameworks only for MVP.
- **Project:** `MicaDesk.xcodeproj`, with a runnable `MicaDesk` app scheme. Provide a README with build/run instructions.

Use currently available Apple APIs and check deployment-target compatibility. Apple docs: `PKCanvasView`, `PKDrawing`, `PKToolPicker`, SwiftData `ModelContainer`, SwiftUI drag-and-drop.

## Core experience

The main screen is **one vertically scrolling Priority Stack**. The topmost card is the highest priority. No numerical priority field is necessary. Cards can contain typed text, handwriting, or both; **do not require a title** before the user can write.

### Required interactions

1. **Quick capture:** A prominent `+` / New Card control creates a new top-level card immediately, without a modal form. It should be ready for writing or typing in at most one additional action. New cards should appear in a predictable location (preferably at the top).
2. **Ink on the card:** An expanded card presents an inline Apple Pencil drawing surface. Writing should feel direct, with no mandatory switch to a separate document or drawing screen.
3. **Typed notes:** Optional title and body text can coexist with editable ink. Do not perform handwriting-to-text conversion automatically.
4. **Child cards:** Each card has `Add Child`. Children appear visibly nested beneath the parent and have their own independent priority ordering. Allow more than one nesting level; avoid a hard-coded two-level model.
5. **Collapse/expand:** A parent can hide or show all descendants. Collapsing must never discard content; show a child count or similar cue.
6. **Reorder:** A visible drag handle supports finger-initiated drag/drop between siblings. Persist the order immediately. Moving a parent repositions its **entire subtree**, not just its heading. For MVP, sibling reordering is required; moving a card to a different parent by dragging is **out of scope** (but structure the model so it can be added later).
7. **Scroll vs ink:** Apple Pencil is for drawing; finger gestures scroll the stack and interact with controls. Prefer `PKCanvasView.drawingPolicy = .pencilOnly` where supported. Do not make the entire card draggable, because it will conflict with editing and ink; initiate dragging from the handle.
8. **Editing tools:** Support ink, highlighting, and erasing using PencilKit's tools/tool picker. Full-page card editing may be added as a practical escape hatch for dense notes, but **must not replace inline ink**.
9. **Completion:** Cards can be marked complete without deleting them. Make completion subtle and reversible. The app should not silently reorder everything on completion.
10. **Autosave:** Edits, ink, ordering, and hierarchy survive app termination and relaunch, including after backgrounding. No explicit Save button.

### UI direction

Quiet, fast, spacious, minimal. Prefer a clean paper/card aesthetic instead of a dashboard. Large, forgiving touch targets; obvious affordances for add, collapse, complete, and drag. Use system light/dark appearance. Do not overengineer theming or animations. Avoid dialogs for routine actions. Inline ink should be large enough to write legibly; never shrink strokes down to an unusable canvas.

## Suggested data model

An `@Model Card` (or an equivalently robust SwiftData schema) with:

- `id: UUID`
- `parentID: UUID?` (nil for root cards)
- `sortIndex: Int` (ordering **among siblings**, with deterministic reindexing after drops)
- `title: String` (optional in UI, can be empty)
- `bodyText: String`
- `drawingData: Data` (serialized editable `PKDrawing`, not a raster image)
- `isCollapsed: Bool`
- `isCompleted: Bool`
- `createdAt`, `updatedAt: Date`

Use `PKDrawing.dataRepresentation()` to serialize and `PKDrawing(data:)` to restore. Use a safe empty drawing when there is no existing ink. Consider external storage for large blobs if helpful and supported for the target; avoid a separate custom database until justified.

Encapsulate hierarchy/order operations in a small testable service or store rather than duplicating them in SwiftUI view code. Validate parent relationships and guard against accidental cycles even if MVP only creates children through an explicit button. Prefer stable UUID identity and a deterministic sibling sort `(sortIndex, createdAt, id)` when indexes tie.

## Suggested source structure

Keep it straightforward (exact filenames can change):

```
MicaDesk/
  MicaDeskApp.swift
  Models/Card.swift
  Data/CardStore.swift
  Views/PriorityStackView.swift
  Views/CardView.swift
  Views/CardInkView.swift
  Views/InkEditorView.swift       # only if a larger editor is useful
  Support/DrawingPersistence.swift
MicaDeskTests/
  CardHierarchyTests.swift
  DrawingPersistenceTests.swift
README.md
```

`CardInkView` should wrap `PKCanvasView` with `UIViewRepresentable` and a coordinator/delegate. Avoid rewriting `canvasView.drawing` on every SwiftUI update, which can overwrite active strokes or trigger feedback loops. Coordinate the `PKToolPicker` with focus/the active canvas so many cards do not each display independent palettes.

For idle or collapsed cards, consider showing a lightweight preview of stored `PKDrawing`; keep active `PKCanvasView` instances limited to cards being edited if necessary for performance. Preserve editable vector ink underneath. If there is a conflict between canvas touch handling and stack scrolling, prioritize a reliable Pencil-write/finger-scroll split and document any on-device limitations.

## Implementation milestones (implement in this order)

### M1 — Runnable shell and persistence

Create the native iPad app, SwiftData model/container, main scrolling stack, create/delete/complete actions, text fields, and relaunch persistence. Seed sample cards **only in SwiftUI previews** or behind an explicit demo action; real users should start with a clean slate.

**Gate:** Build succeeds; create/edit/relaunch retains cards.

### M2 — Hierarchy and priority

Add arbitrary-depth children, expand/collapse, sibling ordering, and stable tree rendering. Add drag handles and finger drag/drop for sibling reorder. Ensure moving a parent moves its subtree logically. Keep tree mutations in testable functions.

**Gate:** Reorder root cards and grandchildren independently, collapse/expand, relaunch, and observe identical structure/order.

### M3 — PencilKit

Embed per-card inline drawing surfaces. Integrate tool picker, undo/erase where feasible, persistence of serialized drawings, background save, and restore. Handle switching among cards without overwriting content.

**Gate:** Handwrite on two different cards, scroll with a finger, draw again, kill/relaunch app, and find editable ink intact on both cards.

### M4 — Usability and hardening

Refine spacing, scroll behavior, empty states, responsive sizing, dark mode, performance, accessibility labels, and error handling. Add focused tests and README. If useful, add a large-card editor as a supplement to inline writing.

**Gate:** All acceptance tests below pass or are explicitly marked as requiring physical-device verification.

## Acceptance tests

1. Create a blank card and handwrite on it without providing any typed title.
2. Create three top-level cards; reorder them using the finger/drag handle; confirm ordering persists on relaunch.
3. Add two children to a parent; reorder only those children; confirm parents and other sibling groups do not change.
4. Add a grandchild; collapse its parent and grandparent; re-expand; confirm no card disappeared.
5. Reorder a parent card and verify all its descendants move along with it.
6. Write ink on separate cards; use pen, highlighter, and eraser; verify strokes remain editable after relaunch (not a bitmap).
7. While a card's ink area is visible, finger-scroll the main stack without leaving unintended strokes; Apple Pencil still writes normally.
8. Edit title/body and ink, background and terminate the app, reopen; verify changes are present.
9. Mark a parent complete and undo that action; preserve its descendants and their completion state unless explicitly changed.
10. Verify reasonable layout in iPad portrait/landscape and light/dark mode, including 20+ cards and several levels of nesting.

Include unit tests for ordering, insertions, deletion strategy, cycle prevention, and drawing data round-trip. Physical Apple Pencil latency, tool picker behavior, touch conflicts, and palm rejection **must be tested on a real iPad**; don't claim the simulator proves those points.

## Scope boundaries and decisions

**In the MVP:** One local priority stack; native editable ink; optional typed text; nested cards; collapse/expand; sibling drag reorder; autosave; completion; clean UI.

**Explicitly not in the MVP:** Multiple boards, Kanban columns, collaboration, accounts, CloudKit, sync, due dates, notifications, tagging, AI, handwriting recognition/search, Freeform import, OCR, cross-parent drag/drop, nested free-positioned canvases, custom stylus engine, and Mac app. Record these as possible future enhancements rather than implementing them prematurely.

**Delete behavior:** Use a confirmation for deleting a parent with children. Prefer deleting the whole subtree only after the consequence is clearly communicated; implement this intentionally and test it. A simple reversible archive could be added later, but is not required now.

**Data safety:** Save on change using an appropriate short debounce for drawing changes and flush pending edits on scene background/deactivation. Don't persist partial or corrupt drawing state. Handle malformed drawing data gracefully. Do not destroy existing data if a save fails; surface a useful diagnostic.

## Development and reporting expectations

- **Actually implement the app.** Do not stop at architecture notes or pseudo-code.
- Build/test iteratively using the installed Xcode tools. Discover an available iPad simulator and run `xcodebuild` with a valid scheme/destination. If Xcode or device signing is unavailable, explain exactly what was verified and what couldn't be run.
- Avoid speculative API usage; resolve Swift compiler errors and deployment-version warnings rather than leaving them to the user.
- Keep the project readable for a developer new to Swift but experienced in software engineering. Add concise comments for gesture integration, ordering invariants, and PencilKit lifecycle—not for trivial statements.
- Make logical, reviewable Git commits if working in a repository where commits are appropriate; do not push without being asked.
- Finish by reporting: implemented features, paths to the Xcode project, build/test commands and outcomes, any known issues, and exact steps to run on a physical iPad.

## Definition of done

The user can open MicaDesk on an iPad, immediately scribble a thought onto a card with Apple Pencil, create children, drag cards into priority order, and reopen the app later with **all handwritten notes and hierarchy intact**. **Optimize for that experience above all else.**
