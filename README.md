# Mica Desk

Mica Desk is a native, local-first iPad table for typed notes and editable Apple Pencil handwriting. Cards can be placed freely, nested to any depth, collapsed, and completed. All content is stored on-device with SwiftData; there is no account, network service, or CloudKit dependency.

## Requirements

- Xcode 16 or newer
- iPadOS 18 or newer
- An iPad and Apple Pencil for validating Pencil input, palm rejection, and the finger-scroll/Pencil-write split

## Build and run

1. Open `MicaDesk.xcodeproj` in Xcode.
2. Select the shared **MicaDesk** scheme.
3. For the simulator, select any available iPad simulator and press **Run**.
4. For a physical iPad, connect and trust the device, select it as the run destination, choose your Apple Developer team under **MicaDesk target > Signing & Capabilities**, and press **Run**.

The bundle identifier remains `com.patatoa.InkStack` to preserve the app's existing on-device data during the rename. Change it under **Signing & Capabilities** if your developer account requires a unique identifier. No capabilities or entitlements are needed.

Command-line build and test examples:

```sh
xcodebuild -project MicaDesk.xcodeproj \
  -scheme MicaDesk \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' \
  build test
```

Use the exact simulator name shown by `xcrun simctl list devices available`.

## Using the app

- Tap **New Card** to put a compact blank card just above the bottom-left plus button in your current view, without moving the table. Write directly in its paper area or expand it to add optional typed notes. New child cards also start compact.
- Tap a handwriting area to make the shared PencilKit palette visible. PencilKit provides pen, marker/highlighter, eraser, color, and undo/redo controls.
- Double-tap a card title to fold the card into its compact form; double-tap it again to restore the notes section and full **Add Child** label. The choice persists across launches.
- Typed notes sit below the handwriting area. They grow vertically as you type, then scroll internally after reaching their maximum height.
- Use **Add Child** to create a nested card. The parent expands automatically.
- Drag anywhere across a card's top/title strip to place it freely on the table. Tap the displayed title to enter editing mode; press Done or tap away to make the strip draggable again. Moving a parent carries its complete subtree with it while preserving the children's relative arrangement.
- Dashed connectors show parent/child relationships. Use the chevron/count control to hide or reveal descendants.
- Use the card's color dot to choose paper, blue, green, yellow, pink, or gray. The PencilKit drawing surface matches the card color.
- Pan the table with one finger starting on empty table space; dragging on a card never pans the board. Use the toolbar magnifiers or a live two-finger pinch to zoom between 25% and 150%. Cards stop at the top and left table edges so their headers remain reachable; older off-table cards are brought back on launch.
- Drag a card's top strip onto the fixed bottom trash target to delete it. A parent requires confirmation before its entire subtree is removed.

Edits autosave. Drawing changes use a short debounce and flush when the app resigns active or enters the background. Handwriting is persisted as `PKDrawing` data, not a flattened image.

## Tests

The `MicaDeskTests` target covers hierarchy ordering, subtree movement and deletion, legacy position migration, cycle prevention, color and compact-state persistence, completion isolation, valid PencilKit drawing round-trip, and malformed drawing recovery.

The non-UI unit tests can also run on the Mac host without booting a simulator:

```sh
swift test
```

On a physical iPad, manually verify:

1. A completely blank card accepts Pencil writing without a title.
2. Pen, highlighter, and eraser edits remain editable after force-quitting and reopening.
3. A finger scrolls over visible ink canvases without leaving marks, while Apple Pencil still writes.
4. Two separate canvases retain their own drawings when switching between them.
5. Move roots, children, and grandchildren around the table; verify coordinates persist and moving a parent carries all descendants.
6. Nested collapse/expand never loses content, and portrait/landscape plus light/dark appearance remain legible with 20 or more cards.

Simulator or compiler tests cannot validate Apple Pencil latency, palm rejection, physical touch arbitration, or real-device tool-picker behavior.

## MVP boundaries

Mica Desk deliberately has one local table and no accounts, sync, CloudKit, multiple boards, tags, due dates, notifications, OCR, handwriting recognition, collaboration, or drag-to-reparent behavior. Those are possible future enhancements rather than hidden requirements of this build.

## License

Mica Desk is source-available software licensed under the [PolyForm Strict License 1.0.0](LICENSE.md).

The source code is publicly available for personal study and noncommercial use.

Modification, redistribution, commercial use, and creation of derivative works are not permitted without explicit permission from the copyright holder.

Copyright © 2026 patatoa.
