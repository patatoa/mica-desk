# Mica Desk — Card Editor: Front & Back

**Implementation handoff for Codex**  
**Version:** 1.0 · **Date:** 2026-10-17  
**Status:** Design direction approved for implementation  
**Recommended agent:** Terra · Medium effort  
**Target:** Existing Mica Desk iPad app, not a new project

> **Your assignment:** Implement this focused refinement of the **existing Edit Card view**. The previous card/board UX redesign is already working and should be treated as the baseline. Inspect the actual Swift code and current persistence model before changing anything. Build the feature; do not respond with another plan. Do not rewrite the board, the card model, or the drawing engine.

## 1. Why this change

The redesigned desk has succeeded: at **26% zoom**, cards feel like small colored pieces of paper with either typed titles or handwriting and with very little chrome. The remaining **Edit Card sheet** still looks like a generic form: gray panel, bordered title input, separate white drawing rectangle, explanatory labels, and a notes section *below the fold*, with no visible indication that the editor scrolls.

**Design intent:** Opening a card should feel like picking up and unfolding that very card. Its color, content, and informal character should carry into the editor. A subtle nod to the physical front and back of a notecard is welcome. Avoid literal skeuomorphic embellishments (paper grain, curled corners, ring binders, dramatic 3D spins).

**Core metaphor:**

- **On the desk:** A small, freely draggable card showing its **chosen preview face** (typed title **or** drawing).
- **Editor, front:** The card enlarged into a colored writing surface with an editable title and generous PencilKit ink area.
- **Editor, back:** The same colored card turned over to reveal an immediately visible, editable **Notes** area.

These concepts are deliberately separate: **front/back of the editor is navigation; Title/Drawing is the persisted *desk preview* preference.** Flipping to Notes must never switch the desk preview preference or affect what the board displays.

## 2. Visual references

Consult these files in `references/` (included in handoff bundle):

- **`card_front_back_mockup.png`** — approved *conceptual* front/back design; inspiration for soft colored surfaces, large drawing area, and the bottom Flip button. Not a requirement to reproduce all decorative elements.
- **`current_editor.png`** — screenshot of current utilitarian editor with white ink canvas, gray panel, and hidden notes below the fold.
- **`current_desk.png`** — screenshot of successful post-redesign board at 26% zoom; preserve its look and behavior.
- **`MICA_DESK_CARD_UX_REDESIGN.md`** — earlier card/gesture redesign; this document **supplements it** and replaces only its focused editor presentation. Actual current source takes precedence over stale architecture assumptions.

## 3. Scope boundaries

**In scope:** Edit Card sheet layout and styling, front/back display state, discoverable notes, editor title presentation, PencilKit surface integration, sensible keyboard/focus behavior, accessibility, and tests for persistence and state separation.

**Out of scope:** New data schema for note content, board layout, zooming, spatial movement, selection toolbar, parent/child connections, color palette redesign, the compact card renderer, completion/deletion, a custom PencilKit stroke engine, note rich-text formatting, and synchronization.

**Avoid feature creep:** Do not build a separate app-wide design system, document viewer, physical card animation engine, or new notes data layer for this change.

## 4. Desired appearance

### 4.1 The editor is an enlarged *card*, not a form

- Keep the existing centered iPad editor/sheet presentation (or the closest native equivalent already in the app) so the desk remains visible, dimmed behind it.
- The **entire interior surface** of the editor adopts the **current card's pastel color**. The title, drawing area, and notes side sit on that same surface, with no large gray outer container and no white drawing rectangle.
- Retain restrained rounding, a mild sense of elevation, and generous padding. Shadows and corner radii should be subtle and consistent with the cards on the desk; avoid gradients, heavy textures, or ornamental paper effects.
- Prefer existing color tokens and color model; do **not** manufacture a separate set of edit-only swatches. If saturation makes a large surface uncomfortable, a **very slight** uniform tint adjustment is acceptable, but it should unmistakably be the same card color.
- The editor should be pleasantly large on iPad in landscape *and* portrait, with safe margins and readable controls. Don't hard-code the screenshot's dimensions. Drawing gets the majority of the front's available space.
- Keep **one** primary dismiss action: `Done` in a consistent top corner. Do not introduce both `X` and `Done` for the same action. Existing implicit autosave should continue to work.

### 4.2 Front side: title + sketch

Suggested hierarchy (illustrative, not pixel-perfect):

```text
  ┌────────────────────────────────────────────────┐
  │                                         Done   │
  │                                                │
  │ Spikes Orka cluster issue                      │  ← borderless, editable title
  │                                                │
  │ On desk:    [ Title  |  Drawing ]               │  ← small, secondary control
  │                                                │
  │                                                │
  │      (PencilKit sketch / handwriting)          │
  │                                                │
  │                                                │
  │  [existing Pencil tools when editing]          │
  │                             [ Flip to Notes ]  │
  └────────────────────────────────────────────────┘
```

Specifics:

- **Title:** Remove the rounded rectangle / bordered `TextField` appearance. Render an editable title directly on the colored surface, with sufficient visual hierarchy, padding, and good contrast. Use normal platform typography (not a simulated handwriting font). Tapping title focuses the keyboard; tapping the sketch does not.
- **Sketch:** Large, seamless PencilKit area in the remaining space. **No separate white or framed rectangle**, no redundant `Drawing` heading, and no textual instructional clutter. Reuse the current pen/highlighter/eraser/undo integration. Preserve touch policy (Pencil draws; finger does not unintentionally draw) unless the existing code requires a documented exception.
- **Background:** Render ink on a matching colored background with the existing strokes in their original colors. Carefully handle a `PKCanvasView` transparent/opaque background; see technical risks below.
- **Desk preview setting:** Keep the user’s existing persisted choice, but label the UI unambiguously, e.g. `On desk: [Title | Drawing]` or `Show on card:`. It controls **what the small board card displays**, *not* which section is active or available in the editor. Editing the title and ink remains possible regardless of selection. This control can be visually quiet; it's not a headline feature.
- **Flip affordance:** A clearly labeled `Flip to Notes` action is **visible without scrolling**, near the bottom/trailing edge. Use a lightweight icon if helpful, but text is essential for discoverability. The action should never compete with Pencil tools or cover drawn content.

### 4.3 Back side: notes

```text
  ┌────────────────────────────────────────────────┐
  │                                         Done   │
  │                                                │
  │ Spikes Orka cluster issue                      │  ← context/title; needn't edit here
  │                                                │
  │ Notes                                          │
  │                                                │
  │  Started after last deploy                     │
  │  Only on Orka cluster                          │
  │  Check logs for timeouts                       │
  │  ...                                           │
  │                                                │
  │                             [ Flip to Front ]  │
  └────────────────────────────────────────────────┘
```

Specifics:

- The back shares the same card color and overall geometry as the front. An *extremely* subtle shade difference is permissible if it helps imply front/back, but avoid a jarring second color.
- A **real multiline editable notes field** occupies the principal writing area. Use the existing persisted notes/body field and its autosave behavior. No need to invent bullet formatting or other text editor tools.
- When notes exist, show them immediately. When empty, offer a subtle `Add notes…` placeholder and a large tappable/editable area. **Don't leave notes hidden below the fold**.
- Keep enough title/context to remind users which card they are editing. The back-side title can be quieter or read-only; editing the title on the front is sufficient for this pass.
- Put `Flip to Front` in the same place as `Flip to Notes`, and keep `Done` in the same location. Switching sides should not reflow/resize the whole sheet.
- **Long notes:** The notes text area itself may scroll when necessary. The goal is **no mysterious default sheet scrolling** to find the notes, *not* forbidding scrolling through long text.
- No timestamps, paper decoration, labels, or extra metadata unless they already exist and are genuinely useful. The mockup's `Last edited` footer is optional inspiration, **not requested scope**—prefer omitting it.

### 4.4 Transition between sides

- Tapping Flip swaps front/back **inside the same editor** without dismissing the sheet, moving the desk, or replacing the underlying card.
- Use a short, subdued transition (crossfade or slight card-turn suggestion) **only if** it does not break PencilKit, keyboard state, focus, or save behavior. A reliable instant transition is better than a flashy but fragile 3D flip.
- Respect Reduce Motion. A meaningful button label (`Flip to Notes` ↔ `Flip to Front`) matters more than the animation.
- Default to **front** whenever opening the editor, regardless of the desk preview preference, unless existing state UX makes resuming the current side materially better. Front/back is an ephemeral **editor navigation state**, not a property needing database persistence.

## 5. Interaction rules

| Input | Front | Back |
|---|---|---|
| Tap title | Enter title editing | Title is contextual; Flip to Front to edit |
| Apple Pencil on content | Draw editable ink | Interact with notes according to iPadOS text editing conventions |
| Tap `On desk` selector | Update compact board preview preference | Not present; does not change on flip |
| Tap flip button | Show back/notes | Show front/title + drawing |
| Tap Done | Dismiss editor, retain all changes | Same |
| Open editor from any card | Front is initially visible | Not initially shown |
| Keyboard appears | Ensure title remains visible, drawing can shrink responsibly | Notes field remains visible, editable, and scrolled to caret |

**Important:** Flipping or changing the compact card preview preference must **never erase, convert, reorder, or overwrite** title, ink, or notes data. No card-face preference should depend on current editor side.

## 6. Engineering guidance and hazards

The repository is authoritative: first locate existing `Edit Card` view, card color representation, title/body storage, `PKCanvasView` wrapper, desk preview preference, persistence code, and sheet presentation. Reuse them.

### 6.1 Prefer a small view-state refactor

- An editor-local enum such as `EditorSide.front` / `.notes` is fine. Treat it as view state, not a SwiftData migration.
- Consider a shared colored `CardEditorSurface`/container with two conditional child views, but don't abstract prematurely.
- Keep `cardFace` or equivalent **persisted as it already is** (typed-title vs drawing on desk). Keep **editorSide** ephemeral.
- Use the existing data model field for notes. Don't create a duplicate notes value that can drift out of sync.

### 6.2 PencilKit: the main regression risk

- Keep strokes as an editable `PKDrawing` source of truth. Never replace it with a bitmap or discard raw `drawingData`.
- A seamless canvas requires appropriate background/opacity behavior. Verify there is no opaque white underlay on `PKCanvasView`, its scroll view content, or a wrapper.
- **Do not reset `canvasView.drawing` on every SwiftUI state update** or each flip. Repeated rehydration can overwrite in-progress edits. Use the existing coordination/debounced save pattern.
- Preserve drawing coordinates and scale as the editor changes size in portrait/landscape or when the keyboard appears. The drawing must not jump, stretch, or be cropped to an unrecoverable region.
- When leaving the front, ensure latest ink is captured before disposing or hiding the live canvas; when returning, rehydrate it once safely without losing strokes or undo behavior where supported.
- Retain existing PencilKit tool picker integration and undo/erase support. Avoid recreating multiple tool pickers on side switches.
- If a transparent canvas creates rendering/palm-rejection issues on hardware, choose the simplest reliable implementation that still looks like one continuous card-colored surface. Document any necessary compromise.

### 6.3 Layout, focus, and persistence

- Reserve stable space for Done and Flip controls. Controls should not float directly over editable ink or notes text.
- The modal should use available iPad size responsively rather than assuming a single screen orientation; avoid nested invisible scrolling. If content can't fit at an accessibility text size or with a keyboard up, use **explicit, discoverable** scrolling only where necessary.
- Autosave title, ink, notes, and compact face preference as before; flush pending changes on Done/background. Do not introduce a mandatory Save step.
- Prevent `Done`/sheet dismissal from dropping edits while keyboard or Pencil is active.
- Keep current deletion, child-link, color editing, and board interactions untouched.

### 6.4 Accessibility

- 44pt-ish minimum effective hit areas for Flip and Done.
- VoiceOver names: `Flip to Notes`, `Flip to Front`, `Done editing card`, and a clear `Show on desk: Title/Drawing` segmented control.
- Maintain contrast for text and placeholders on every supported pastel color; don't rely on color alone to denote current side.
- Respect Dynamic Type and Reduce Motion.

## 7. Implementation sequence (Codex should code each phase, not stop at planning)

**Phase 1 — Inspect & safeguard.** Review current editor code and model; note real file paths. Run existing build/tests or state why impossible. Confirm where title/notes/PKDrawing/compact face/color live. Preserve unrelated changes.

**Phase 2 — Colored front.** Make the editor a card-color surface; remove gray form framing and white drawing block; make title borderless; retain and clarify the compact `On desk` selector. Keep drawing tools functioning.

**Phase 3 — Flip + notes back.** Add editor-local front/back state and persistent Notes editing on the reverse. Add visible, paired Flip actions and keep sheet dimensions stable. Make default editor open on front.

**Phase 4 — Polish & verify.** Adjust layout/keyboard behavior, subtle transitions only if safe, accessibility, save and drawing lifecycle. Test with pastel colors, large notes, and real Pencil if available. Keep diff small.

## 8. Acceptance criteria

**Must pass**

1. The pink `Spikes Orka cluster issue` card opens into a **pink** editor surface, not a gray form with an inner white canvas. The same applies to blue, green, white, and other existing card colors.
2. The title is editable on the front without the generic rectangular text field; its displayed value persists after Done and relaunch.
3. Pencil ink can be added/erased on the front and survives `Flip to Notes` → `Flip to Front` → Done → relaunch, still editable as strokes.
4. Drawing stays in the same meaningful position/scale on flip, keyboard show/hide, and iPad orientation changes. No spontaneous blanking, clipping, or stroke teleportation.
5. A clearly visible `Flip to Notes` is on the initial editor front **without scrolling**. Notes on the back are immediately visible/editable; empty notes present an obvious area to start typing.
6. `Flip to Front` returns to the same title and drawing, without duplicate tool pickers or lost content. Flip navigation itself does not change stored card preview selection.
7. Changing `On desk` from Title to Drawing or back changes only the *board card preview*, not the editor side; ink, notes, and typed title remain intact.
8. The edit sheet is one reasonably stable size during flips and doesn't need vertical scrolling to find its main controls; long notes can scroll inside their own area.
9. Done dismisses safely from either side and updates the board display; reopening starts on the front.
10. Existing board behavior at **26% zoom** (card drag/select, pan/zoom, connectors, child card creation, colors, compact title/ink appearance) works exactly as before.
11. Keyboard works on both title and notes, with the active input visible and no interference with Done/Flip.
12. Reduced Motion, basic VoiceOver labels, portrait/landscape layouts, and accessibility text sizes are reasonable; no misleading dead controls.

**Verification requirements**

- Run an actual build and relevant tests when tooling is available. Add focused tests for editor-side state vs persisted compact face preference and notes persistence if the existing architecture supports them.
- Include a small **manual physical-iPad checklist** for Pencil/keyboard/flip/save flows. Simulator-only verification does **not** establish Pencil latency, palm rejection, or live tool picker correctness.
- Provide before/after screen captures of the **front and back**, preferably using an existing pink card. If captures cannot be made, say so; don't imply they were verified.
- Report changed files, what was built/tested, and any known remaining issues. Preserve user data and avoid unrelated refactoring.

## 9. What not to accidentally implement

- A *two-sided board card*: this is a front/back metaphor **inside the focused editor only**. The small card on the desk still shows Title or Drawing, as chosen.
- A notes drawer **below** the drawing area: notes are intentionally on the **back**, one tap away, not below the fold.
- A 3D card flip animation requiring a new animation architecture.
- An `X` and a `Done` control performing the same action.
- A fake handwritten font, synthetic paper texture, date stamp, or prominent decorative widgets.
- A new storage object for editor side, or a migration of existing drawing/notes content.

## 10. Codex ready-to-paste prompt

```text
Implement MICA_DESK_CARD_EDITOR_FRONT_BACK.md in the existing Mica Desk app.

This is an implementation request, not a design brainstorm. Inspect the actual app source and the existing previous card UX redesign first. Treat the current working board and data model as authoritative, and preserve all existing functionality and data.

Refine the Edit Card sheet into an enlarged, card-colored writing surface. The front has a borderless editable title, a seamless large PencilKit drawing area, and a small clearly labeled On desk: Title/Drawing preview preference. The back is a discoverable multiline Notes editor reached via Flip to Notes, with Flip to Front in the same location. Keep one Done button. Keep front/back view state separate from the persisted desk preview preference.

Do not introduce hidden below-the-fold notes, redundant controls, a white drawing rectangle, an elaborate animation, or a new data model. Follow the spec's phased implementation and acceptance criteria, build/test what you can, and identify anything requiring physical iPad verification.

Reference images are in references/. Implement and report, don't stop at planning.
```

## 11. Recommended Codex usage

**Terra — Medium effort** for the whole pass. It handled the previous, riskier selection/drag redesign successfully and the user's reported cost (~11% of a five-hour window) was acceptable. This pass is primarily view composition and presentation state with one delicate subsystem (PencilKit).

Stay in the **same repository and, ideally, one Codex task/session** so the agent can reuse context. Ask it to implement Phases 1–4 and validate; review front/back screenshots and hardware Pencil behavior before requesting polish. Use **Terra Low/Medium** for subsequent spacing/copy/color adjustments; raise effort or switch to a stronger reasoning setting **only** if drawing persistence or view lifecycle becomes stubborn. No multi-agent orchestration needed.
