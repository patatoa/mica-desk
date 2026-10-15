# InkStack

InkStack is a native, local-first iPad table for typed notes and editable Apple Pencil handwriting. Cards can be placed freely, nested to any depth, collapsed, and completed. All content is stored on-device with SwiftData; there is no account, network service, or CloudKit dependency.

## Requirements

- Xcode 16 or newer
- iPadOS 18 or newer
- An iPad and Apple Pencil for validating Pencil input, palm rejection, and the finger-scroll/Pencil-write split

## Build and run

1. Open `InkStack.xcodeproj` in Xcode.
2. Select the shared **InkStack** scheme.
3. For the simulator, select any available iPad simulator and press **Run**.
4. For a physical iPad, connect and trust the device, select it as the run destination, choose your Apple Developer team under **InkStack target > Signing & Capabilities**, and press **Run**.

The bundle identifier is `com.patatoa.InkStack`. Change it under **Signing & Capabilities** if your developer account requires a unique identifier. No capabilities or entitlements are needed.

Command-line build and test examples:

```sh
xcodebuild -project InkStack.xcodeproj \
  -scheme InkStack \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' \
  build test
```

Use the exact simulator name shown by `xcrun simctl list devices available`.

## Using the app

- Tap **New Card** to put a blank card on the table. Write directly in its paper area or add optional typed text.
- Tap a handwriting area to make the shared PencilKit palette visible. PencilKit provides pen, marker/highlighter, eraser, color, and undo/redo controls.
- Use **Add Child** to create a nested card. The parent expands automatically.
- Drag anywhere across a card's top/title strip to place it freely on the table. Tap the displayed title to enter editing mode; press Done or tap away to make the strip draggable again. Moving a parent carries its complete subtree with it while preserving the children's relative arrangement.
- Dashed connectors show parent/child relationships. Use the chevron/count control to hide or reveal descendants.
- Use the card's color dot to choose paper, blue, green, yellow, pink, or gray. The PencilKit drawing surface matches the card color.
- Pan the table with one finger starting on empty table space; dragging on a card never pans the board. Use the toolbar magnifiers or a live two-finger pinch to zoom between 62.5% and 150%.
- Drag a card's top strip onto the fixed bottom trash target to delete it. A parent requires confirmation before its entire subtree is removed.

Edits autosave. Drawing changes use a short debounce and flush when the app resigns active or enters the background. Handwriting is persisted as `PKDrawing` data, not a flattened image.

## Tests

The `InkStackTests` target covers hierarchy ordering, subtree movement and deletion, legacy position migration, cycle prevention, color persistence, completion isolation, valid PencilKit drawing round-trip, and malformed drawing recovery.

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

InkStack deliberately has one local table and no accounts, sync, CloudKit, multiple boards, tags, due dates, notifications, OCR, handwriting recognition, collaboration, or drag-to-reparent behavior. Those are possible future enhancements rather than hidden requirements of this build.

