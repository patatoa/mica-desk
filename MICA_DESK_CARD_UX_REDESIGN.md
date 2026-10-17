# Mica Desk — Card UX Redesign

**Version:** 1.0  
**Date:** 2026-10-17  
**Status:** Approved direction; ready to implement in existing app  
**Audience:** Codex, working inside the current Mica Desk Swift/iPad repository

> **Codex assignment:** Implement this redesign in the existing app. This is an implementation brief, not an invitation to redesign the entire app or write another plan. Inspect the actual repository and its current behavior before editing. Use the existing architecture and names where practical. Make incremental, reversible changes, build/test where possible, and report what was actually verified.

## 1. Product intent

**A card should feel like a piece of paper you can pick up and move, not a miniature form.**

Mica Desk is a tactile, spatial, local-first iPad workspace for loosely organized ideas/tasks. At a wide zoom (the reference screenshot shows **26%**) the current cards are visually busy: optional title placeholder, completion checkbox, drawing frame and edit control, notes input, add-child button, and color dot all compete for space. Gesture meanings overlap: a tap, a double-tap, a drag, and a Pencil action can be hard to predict.

Redesign around three distinct activities:

1. **See:** A plain colored card, showing *either* its typed title *or* its handwriting/drawing.
2. **Move/select:** A tap selects it; a finger drag on the card moves it. Selection reveals contextual actions.
3. **Edit:** A deliberate Edit action opens a focused editing surface where title, drawing, and notes are available.

This supersedes the earlier InkStack brief wherever that brief assumed a vertically stacked list, a permanent drag handle, or always-inline PencilKit drawing. **The currently working free-positioned board, zoom/pan behavior, nested cards, and connections are authoritative.** Do not regress or replace those features.

## 2. Reference images

- `references/Micadesktable.png`: actual board at 26% zoom. Observe positions, connected children, existing colors, persistent controls, global add button, zoom UI, and drag-to-trash affordance.
- `references/Sticky.png`: enlarged existing blue card. Observe current checkbox, optional title, drawing frame, Pencil button, add-child button, color dot.

The desired direction combines earlier concepts **1 (Minimal), 4 (text/ink face choice), and 5 (consolidated More menu)**, with a contextual toolbar shown only when selected. The screenshots are **as-built references, not pixel-perfect redesign targets**.

## 3. Scope and boundaries

### In scope

- Unselected card appearance and layout.
- Selected card highlighting and a floating contextual toolbar.
- Consistent gesture semantics and separation of movement from editing.
- Focused card editor; title, editable PencilKit drawing, optional notes.
- Per-card persistent choice of compact face: typed title or ink/drawing.
- Relocation of Add Child, Color, completion, and less frequent actions.
- Preserving board positions, zoom/pan, parent-child hierarchy, connectors, colors, completion state, autosave, and delete behavior.
- Regression tests and physical iPad test checklist.

### Not in scope

- Changing the spatial board to a stack or Kanban columns.
- New card hierarchy or reparenting semantics.
- Rewriting board pan/zoom or spatial placement system unless required to fix a demonstrated conflict.
- Cloud sync, accounts, rich-text formatting, OCR/handwriting recognition, new drawing engine, themes, or broad visual restyling.
- Redesigning global board-level UI unrelated to cards.

## 4. Card anatomy

### A. Idle / unselected: **paper only**

Visible:
- Existing card shape, size behavior, subtle corners/shadow/border, and chosen fill color.
- Exactly one content presentation: **title face** or **ink face**.
- Existing connection lines between related cards should remain visible.
- Preserve a restrained indication for *collapsed children* if the current board would otherwise hide that relationship (prefer a small non-interactive cue; do not add a permanent footer).

**Not visible** on an unselected card:
- “Optional title” placeholder.
- Always-on checkbox or editing pencil button.
- Inner drawing-frame border.
- Notes preview/input or “Typed notes (optional)” placeholder.
- Add Child button, color dot, ellipsis button, toolbar, drag handle.

No text is necessary on an empty card. An empty colored card is valid; ensure it remains selectable/draggable.

**Title face:** show the user's typed title as the card's main content, with good contrast and padding. Do not show the notes body as a fallback title. For long titles, size or line-limit gracefully; never overflow the card. Avoid automatic tiny text on the board just to fit every character.

**Ink face:** display a lightweight, non-interactive preview of the *editable* stored `PKDrawing`. Preserve its aspect ratio and reasonable margins; avoid clipping meaningful strokes. Do not rasterize the stored source of truth. At 26%, the preview is naturally small, but should not be hidden behind controls.

Completion is **data, not permanent chrome**. Retain a quiet completed treatment if one exists (e.g. subtle border/opacity), but keep the actual complete/incomplete toggle in contextual actions.

### B. Selected: **paper + floating actions**

Tap a card once to select it. Show:
- A subtle selection ring/outline or shadow, not a large edit affordance overlay.
- A single small horizontal toolbar **outside** the card, anchored to the card's screen-space bounds. Preferred placement: above card, centered; flip below and constrain inside the viewport as needed.
- Toolbar actions, in this order: **Edit** (pencil), **Add Child** (+), **Color** (palette or color circle), **More** (ellipsis).

**Critical zoom rule:** Toolbar is rendered in **screen/view coordinates**, at a constant readable size, *not transformed by the board zoom*. It must remain tappable at 26% or lower, and should not overlap the card's ink/title face. All toolbar hit targets should be at least ~44×44 pt even if glyphs are smaller.

Selecting a different card transfers the toolbar. Tapping empty board space deselects (unless the tap is the end of a pan/zoom gesture). A selected card is **not automatically editable**.

During a card drag: hide/fade the toolbar to avoid jitter and intercepting the drag. Re-anchor it after the drag ends. The toolbar itself is never a card-drag surface.

### C. Focused editing: **one clear place to work**

The Edit toolbar action opens a comfortably sized, native iPad focused editor, preferably a form sheet/overlay that preserves the desk behind it rather than resizing/reflowing the board. Follow existing app presentation conventions if equivalent.

Editor should include:
- **Title:** editable text field, optional.
- **Drawing:** a generous live `PKCanvasView` with PencilKit tool picker and existing supported pen/highlighter/eraser behavior. Do not shrink the main drawing canvas to the tiny board-card footprint.
- **Notes:** editable optional multiline text using the existing stored note/body field. Visually quiet; can be a disclosure or section after drawing. No need to preview notes on a normal card.
- **Card face selector:** `Show on card: Title | Drawing`. Clearly communicate that it changes **preview content**, not whether the other content is deleted. This toggle may live near the editor title or in a small View/Display section. Use a simple segmented control or equivalent.
- A clear **Done/Close** action, plus predictable outside-tap dismissal only if no draft can be lost.

Keep keyboard, Pencil tool picker, and editing focus from colliding. The editor is the only place where live `PKCanvasView` captures ink; the board uses a passive preview.

**Fast capture:** Existing global Add Card and toolbar Add Child must still create cards quickly. A newly created card should immediately be ready to type or draw with no intermediate mandatory form; ideally open this focused editor automatically, defaulting to drawing if that is the shortest path to handwriting. Preserve sensible creation location and child linkage.

## 5. Gestures and state model

### Interaction matrix

| Context/input | Action | Result |
|---|---|---|
| Board: finger single-tap card | Select | Highlight + floating toolbar; no text focus, no ink |
| Board: finger drag starting on card | Move card | Existing free positioning/drag behavior; *never* begins a stroke |
| Board: finger drag on empty canvas | Pan board | Existing panning behavior |
| Board: two-finger pinch | Zoom | Existing zoom behavior, including if gesture begins over a card |
| Board: double-tap card | Shortcut to Edit (optional) | Only if reliably recognized without interfering with drag; Edit button is canonical |
| Selected toolbar: Edit | Open focused editor | Title, live PencilKit, notes, face selector |
| Selected toolbar: Add Child | Create child | Preserve established parent/child placement and connectors; enter fast editor |
| Selected toolbar: Color | Present swatches | Update fill color without opening full editor |
| Selected toolbar: More | Open menu | Complete/Uncomplete, Delete, and currently supported less-used card actions |
| Editor: Pencil strokes in drawing | Draw | Editable `PKDrawing` with pencil-only policy if supported |
| Editor: finger in drawing | Scroll/navigate per editor behavior | Avoid accidental ink; maintain tool picker and palm rejection |
| Outside card tap | Deselect | Toolbar disappears without affecting canvas placement |
| Board drag to existing trash target | Existing deletion flow | Preserve confirmation/data safeguards; no inadvertent delete |

**Priority order:** An established drag should not turn into a tap, and a double-tap should not steal a drag. Touch-down alone should not immediately open an editor. Do not introduce a long-press requirement for moving cards: **freely draggable remains the product's top interaction priority**. Use a small movement threshold or existing robust movement recognition to distinguish tap from drag. A genuine two-finger pinch/board pan must not move an underlying card accidentally.

**Pencil policy:** On the **board**, card content is *not an editable drawing surface*. A Pencil tap may select a card; a Pencil gesture must never accidentally change ink. In the **focused editor**, Pencil draws. Preserve existing PencilKit editing and persistence, but do not leave active canvases embedded in every board card.

**Selection/editing lifecycle:** One selected card maximum. Editor operates on its card's stable ID. Dismiss menus/toolbars on delete and on leaving the board. After closing editor, retain selection and refresh the correct card preview. Closing an editor must not overwrite newly saved drawing with stale preview state.

## 6. Face mode / data behavior

Add the smallest persistent per-card field necessary, e.g. `compactFace = title | drawing`. Reuse any equivalent existing field. **Do not change existing card IDs, positions, hierarchy, drawing data, note text, or completion values.** Prefer a safe optional/default field or migration that keeps older stored documents readable.

Migration/default for existing cards:
1. If meaningful existing ink is present, default face to **Drawing** (preserves the screenshot's ink-first cards).
2. Otherwise default to **Title**.
3. For new blank cards, default to **Drawing** if fast capture begins with Pencil; otherwise Title is acceptable if consistent with creation flow.
4. After the user explicitly chooses a face, persist it and do not silently flip because they typed or drew somewhere else.

Both title and ink remain stored and editable regardless of face. Notes remain stored, editable, and excluded from compact board render. Do not synthesize a title from notes, auto-OCR ink, or delete the hidden content. If the selected face has no content, a blank card face is allowed; user can switch faces in editor. The editor should make that situation obvious without placing a placeholder on the board.

Use the canonical `PKDrawing` serialization already present, preserve editable strokes, and avoid reassigning live canvas drawing in every SwiftUI render pass. Cache or memoize previews if needed, invalidating when ink actually changes. Avoid a full `PKCanvasView` instance for every idle card.

## 7. Color, child, completion, and More

- **Color:** Tapping the toolbar color icon shows existing palette/swatches in a compact popover anchored to the toolbar. Apply immediately and autosave. Avoid navigating to the editor for this.
- **Add Child:** A single tap creates a child to the selected card. Reuse current hierarchy and spatial-placement rules. Do not duplicate business logic. Keep parent-child connection visuals.
- **Completion:** Move toggle into More, using dynamic `Mark complete` / `Mark incomplete`. Preserve any completion-related descendants behavior and avoid surprising reorder.
- **Delete:** Move to More too, but **keep the existing drag-to-trash board gesture** unless it is currently broken. Preserve the app's existing confirmation/undo safeguards, especially for parents with descendants. Avoid placing a dangerous one-tap destructive icon on the floating toolbar.
- **Other established actions:** Retain any currently working non-obvious actions under More where practical rather than silently removing features.

## 8. Layout, zoom, accessibility, performance

- Preserve the existing card size and aspect/rules initially; only change them if the simplified content demonstrably needs it. This is an interaction/chrome cleanup, not a fresh visual theme.
- Avoid always-visible control affordances at any zoom. At wide zoom, cards should read as calm colored marks on the desk with text/ink rather than tiny forms.
- Use the card's actual transformed screen-space geometry when positioning the selected toolbar. Update position smoothly on pan/zoom/orientation; constrain to safe area. Don't render it inside the zoomed board transform.
- Ensure floating toolbar does not intercept canvas pan outside its own bounds. Tap outside closes toolbars/menus without making incidental moves.
- Maintain readable color/contrast in light/dark appearance, and support Dynamic Type sensibly without destroying compact card geometry.
- Provide accessibility actions for Select, Edit, Add Child, Change Color, Complete/Uncomplete, Delete; card content and state must be described even if visually hidden in the compact face.
- Test landscape and portrait, including cards near edges and deeply nested connected cards.
- Large boards should not instantiate one live PencilKit canvas per card; keep passive previews lightweight and avoid expensive redraw of all ink on every drag frame.

## 9. Implementation order (Codex)

**P0 — Repository audit (do before changes)**
- Identify the current app target, card model, board transform/gesture code, card renderer, hierarchy, persistence, drawing editor, deletion zone, and tests.
- Explicitly note mismatches between this spec and actual code (for example, if a focused editor already exists). Reuse working mechanisms.
- Check repository status. Work in a feature branch if normal for the project; do not clobber uncommitted changes or rewrite unrelated files.

**P1 — Minimal passive card face**
- Extract or simplify compact card presentation to color + chosen title/ink preview.
- Remove existing persistent card-local controls and notes preview from board; keep functionality accessible later.
- Implement the persisted face preference with safe default/migration.
- Test old cards still load with intact ink, title, notes, color, position, and hierarchy.

**P2 — Interaction + toolbar**
- Implement selection state and reliable tap-vs-drag recognition in existing board gesture architecture.
- Add a screen-space floating toolbar anchored to selected card.
- Wire Edit/Add Child/Color/More and preserve delete/trash interaction.
- Confirm pinch, pan, card drag, and toolbar touches do not compete.

**P3 — Focused editor**
- Reuse existing PencilKit implementation where possible; provide Title, Drawing, optional Notes, face selector.
- Enable immediate handwriting on new-card creation; preserve autosave/background flush.
- Keep preview rendering and editor drawing state synchronized safely.

**P4 — Polish + verification**
- Add/update unit/UI tests as feasible; test migration, face persistence, gesture state logic, child creation, notes, completion, deletion, ink round-trip.
- Verify zoom extremes and toolbar hit targets on simulator; provide a physical-iPad/Pencil checklist for tests not reliably simulated.
- Compile and run available tests. Report files changed, commands run, pass/fail, deferred on-device cases, and any deviations from the spec.

Prefer small coherent commits/patches. Don't introduce dependencies or elaborate architecture unless necessary. If there is a genuine architecture blocker, explain it precisely rather than silently changing the product design.

## 10. Acceptance criteria (must satisfy)

### Visual and content

- [ ] An unselected card shows no permanent checkbox, title placeholder, draw-edit icon, notes field, add-child button, color control, or inner drawing frame.
- [ ] An unselected card shows either text title or ink; never both as competing layers. Blank cards are permitted.
- [ ] A card with both title and ink can switch its visible face; both content types are still present in editor afterward.
- [ ] Existing cards load with their original positions, colors, ink, titles, notes, parent-child hierarchy, and completion values intact.
- [ ] Card parent/child connections and collapse behavior remain correct at normal and 26% zoom.

### Interaction

- [ ] A finger drag starting on an unselected card moves the card without drawing, editing text, or waiting for a long press.
- [ ] Single tap selects card and reveals exactly one toolbar; tapping another card transfers selection.
- [ ] Toolbar stays practical to tap at 26% zoom; it tracks selected card and stays within viewport edges.
- [ ] Board pan and pinch zoom work reliably when gestures begin near/over cards; drag gesture does not inadvertently trigger Edit.
- [ ] Tapping Edit opens focused editor. Optional double-tap shortcut, if implemented, never compromises dragging.
- [ ] Toolbar hides while moving a card and returns after move ends.
- [ ] Existing drag-to-trash remains operational with original safeguards.

### Editing/persistence

- [ ] Title editing, live PencilKit drawing, and optional notes all work in focused editor.
- [ ] Apple Pencil draws in editor and never accidentally draws on the passive board preview.
- [ ] Ink remains editable after leaving editor, zooming, switching cards, backgrounding, and relaunching.
- [ ] Notes and title survive even when hidden by the drawing face; drawing survives on text face.
- [ ] Add Child creates a correctly linked, visible, editable child using current board placement rules.
- [ ] Color and completion actions work without needing to open editor.
- [ ] Delete/undo or confirmation works as before, including cards with children.
- [ ] At least a representative 20+ card board remains responsive, including several connected children.

## 11. Physical-device verification checklist

Run on actual iPad with Apple Pencil, not just simulator:

1. Start at ~26% zoom with six or more cards; tap tiny card, invoke floating Edit/+/Color/More.
2. Drag cards quickly, slowly, diagonally, and immediately after selecting; verify no unintended edit/open.
3. Pinch and pan over card and empty grid; verify board movement does not accidentally change card positions.
4. Open editor and write/erase/highlight. Close, switch face, reopen, and write again; confirm stroke round-trip and no ink loss.
5. Simultaneous palm/finger while Pencil writing, typing with onscreen keyboard, orientation changes, app background/force close and relaunch.
6. Move parent cards, add children, collapse/reopen if supported, and drag to trash with safeguards.

## 12. Codex completion report format

Please finish with:

1. **Implemented** — concise description of screens, gestures, persistence/model changes.
2. **Changed files** — paths and what changed.
3. **Verification** — exact build/test commands and result; distinguish simulator from physical device.
4. **Open questions/risks** — only genuine issues, with recommended next test or follow-up.
5. **Before/after screenshots** — if simulator/screenshots can be captured, show board at a wide zoom and focused editor.

---

## Ready-to-paste Codex instruction

> Implement the attached `MICA_DESK_CARD_UX_REDESIGN.md` in this repository. Read the full brief and inspect the existing Mica Desk app before modifying code. This is an existing native SwiftUI/iPad app, not a greenfield project. Preserve the spatial board, free drag, zoom/pan, linked children, persistence, colors, completion, PencilKit data, and drag-to-trash behavior. Follow P0–P4; implement and test, don't respond with only a plan. Avoid unrelated refactors and third-party dependencies. Use the bundled screenshots for the as-built baseline. Flag only true blockers. Finish with the completion report specified in section 12.
