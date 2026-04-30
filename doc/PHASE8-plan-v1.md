# Phase 8 - Plan v1

Date: 2026-04-29

## Purpose of this document

Define the implementation of Phase 8 after stabilizing the navigable selection.
The focus now is to exit the state "editing to be defined" and choose a concrete, small, and validatable flow for editing, saving, canceling, and deleting entries from journal_custom without reopening the pagination issues from Phase 7.

---

## Main decision

### UX chosen

Phase 8 should use a dedicated modal editor, separate from `MenuBook`.

Instead of trying to edit text directly inside the book, the flow becomes:

1. player selects an entry in `MenuBook`
2. player activates edit
3. mod opens a modal with multi-line text field
4. save or cancel closes the modal
5. book is rebuilt near the same context

### Technical reason

This decision follows directly from the current state of the code:

1. `book.lua` already knows how to preserve `selectedEntryId` and `restoreSpreadStart` on rebuild.
2. `data.lua` already has `updateEditedText()` and `markDeleted()`.
3. `input.lua` already separates navigation from selection and has clear stubs for `beginEdit()`, `commitEdit()` and `cancelEdit()`.
4. `render.lua` already uses `editedText` and ignores entries with `deleted = true`.

In other words: the smallest safe expansion is to add a modal flow around capabilities that already exist.

### What we are deliberately avoiding

Not editing inside `MenuBook` avoids reopening these risks:

- keyboard capture competing with arrow navigation
- HTML reflow of the book on each keystroke
- mapping invalidity in the middle of typing
- need for highlight or cursor inside paginated text
- regression of current spread while the player is writing

`MenuBook` continues to be a surface for reading, selection, and context.
The modal becomes the writing surface.

---

## Scope of Phase 8

### Within scope

1. Open the editor for the currently selected entry.
2. Populate the field with the entry's current `editedText`.
3. Save changes explicitly.
4. Cancel without persisting draft.
5. Delete the entry from the mod's journal with `deleted = true`.
6. Create a new player note via dedicated modal and insert below the selected entry, or at the end if there is no selection.
7. Reopen the book near the same spread after saving or deleting.
8. Revalidate selection after the operation.

### Out of scope

1. Inline editing inside `MenuBook`.
2. Search, tags, filters, or custom order.
3. Sync the edit back to the vanilla journal.
4. Live preview inside the book while the player types.

---

## Current state of code that Phase 8 inherits

### `journal/input.lua`

- `moveSelection()` already navigates only through `activeVisibleBlocks`.
- `onKeyDown()` is already the natural entry point to hook the command to open editor and create note.

### `journal/book.lua`

- `applySelection()` already persists `selectedEntryId`.
- `resolveContext()` and `rebuild()` already know about context preservation.
- `renderCurrentBook()` already knows how to restore spread after rebuild.

### `journal/data.lua`

- `updateEditedText(id, text)` already changes `editedText`.
- `markDeleted(id, deleted)` already does soft delete.
- `createPlayerEntry(params)` already offers the natural entry point to persist new player note.
- persisted state still has no concept of draft, which is good: draft should remain only in UI memory.

### `journal/render.lua`

- rendering already favors `editedText`.
- deleting an entry from the mod already removes it visually from the book on rebuild.

---

## Recommended architecture

## Phase 8A - In-memory editing state

Create a transitory editing state, in memory, without persisting to JSON:

```lua
local editSession = {
    active = false,
    entryId = nil,
    originalText = nil,
    draftText = nil,
    restoreSpreadStart = nil,
}
```

### Rules

1. `draftText` never goes to `data.lua` before saving.
2. `originalText` serves for local rollback on cancel.
3. `restoreSpreadStart` is captured before opening the modal.
4. If modal closes by cancellation, the book returns without side effects.
5. Even after hitting `Save` in the modal, JSON disk write only happens when the player saves the game.

### Ideal location

The cleanest approach is to extract this behavior to a new `journal/editor.lua` module, leaving:

- `input.lua` to decide when to start or end editing
- `editor.lua` to handle the modal and draft
- `book.lua` to handle rebuild and context restoration
- `data.lua` to remain only as persistence

If necessary to reduce the first delivery, the state can start in `book.lua`, but this should be treated as a provisional stage.

---

## Phase 8B - Open the editor for the selected entry

### Functional rule

Editing is only allowed for the currently selected entry.
Without valid selection, editor does not open.

### Flow

1. get `selectedEntryId`
2. fetch entry from `data.getEntry()`
3. capture `currentSpreadStart`
4. open modal with multi-line field populated with `entry.editedText`
5. acquire text focus explicitly

### UX decision

The modal needs to be simple:

- title with entry identification
- text area
- `Save` button
- `Cancel` button
- `Delete` button

No live preview in the book this first round.

### Safety rule

While the modal is active:

- book selection input should ignore arrows
- book rebuild should be blocked, except when closing the editing flow
- there cannot be more than one active editing modal

---

## Phase 8C - Save

### Expected flow

1. validate that `editSession.active` exists
2. read `draftText` from text field
3. normalize text minimally only if necessary
4. call `data.updateEditedText(entryId, draftText)`
5. ensure `data.markDeleted(entryId, false)` in case restoring previously deleted entry
6. mark journal state as modified, without saving to disk immediately
7. close modal
8. reapply `selectedEntryId`
9. `book.rebuild(true, restoreSpreadStart, "editSave")`

### Important rule

Saving is the only operation that applies `editedText` to the mod state.
JSON disk persistence only happens when the player saves the game.
Closing modal by any other path persists nothing.

### Edge cases

1. Empty text can be allowed, but `render.lua` will continue showing `(no text)`.
2. If the entry no longer exists, abort with log and close editing session safely.
3. If `data.save()` fails, don't close silently without logging feedback.

---

## Phase 8D - Cancel

### Expected flow

1. discard `draftText`
2. close modal
3. clear `editSession`
4. reopen or focus the book on the same spread
5. maintain selection of the same entry

### Important rule

Cancel does not call `data.updateEditedText()` nor `data.save()`.

### Simple mental validation

If the player opens the editor, deletes all text and cancels, JSON should remain byte for byte as it was before.

---

## Phase 8E - Delete

### Deletion model

Phase 8 should do soft delete in the mod's journal.
Don't delete anything from the engine journal.

### Expected flow

1. confirm that `entryId` exists
2. call `data.markDeleted(entryId, true)`
3. mark journal state as modified, without saving to disk immediately
4. close modal
5. rebuild the book with `restoreSpreadStart`
6. choose valid new selection on the same spread, if one exists
7. if the spread becomes empty, clear selection

### Selection fallback rule

When deleting the selected entry:

1. prefer the next visible entry on current spread
2. if none, prefer the previous one
3. if the spread becomes empty, clear selection

This rule prevents rebuild with `selectedEntryId` pointing to invisible or deleted item.

---

## Phase 8F - Keys and input contracts

### Minimum recommended commands

1. `Enter` or dedicated key opens the editor for the selected entry.
2. `N` inside journal opens a new player note.
3. `Esc` cancels when modal is open.
4. `Ctrl+Enter` or `Save` button confirms.
5. `J` must not close the journal while the modal is active.
6. `Delete` is optional; the `Delete` button in the modal already covers the flow.

### Contract between modules

`input.lua` must not manipulate text directly.
It only decides:

1. if valid context exists to start editing
2. if a save/cancel command needs to be forwarded
3. if the book should ignore input because modal is active

---

## Recommended implementation sequence

1. Create the editing state and modal without persisting anything yet.
2. Make `beginEdit()` open the modal with current text of selected entry.
3. Implement `cancelEdit()` with full rollback and return to book.
4. Implement `commitEdit()` saving `editedText` and rebuilding on same spread.
5. Implement `delete` as soft delete with selection fallback.
6. Implement creation of player note reusing the same modal and inserting below current selection or at end.
7. Defer JSON disk write to the game save event.
8. Lock book input while modal is open, including journal key.
9. Add short logs for `editOpen`, `editSave`, `editCancel`, `editDelete`, and `noteCreate`.

---

## Definition of done for Phase 8

Phase 8 should only be considered ready when all points below are true:

1. Editor only opens when there is a selected entry.
2. Initial text in modal matches entry's current `editedText`.
3. `N` opens a new player note independent of selected entry.
4. Cancel never persists draft.
5. Save updates mod state and appears in book after rebuild.
6. JSON only goes to disk when player saves the game.
7. Delete removes entry from mod's journal without affecting engine journal.
8. New note enters below selected entry or at end if no selection.
9. Book returns to same spread or coherent region after saving, deleting, or creating note.
10. Modal does not let arrow navigation or journal key interfere during typing.
11. No crash or unintended game closure when switching between book and modal.

---

## In-game validation

### Case 1 - Save simple change

1. open journal_custom
2. select a visible entry
3. open editor
4. change an easy-to-recognize word
5. save
6. confirm in book and JSON that new text persisted

### Case 2 - Cancel without persisting

1. open editor on same entry
2. change several lines
3. cancel
4. confirm that book shows old text
5. confirm that JSON didn't change

### Case 3 - Delete

1. open editor
2. delete the entry
3. confirm it disappears from mod's book
4. confirm engine quest progress was not removed
5. confirm selection falls on valid neighbor or is cleared

### Case 4 - Create new note

1. open journal_custom
2. press `N`
3. type an easy-to-recognize note
4. save
5. confirm new note appears in book right below selected entry, or at end if no selection
6. confirm it stays in JSON as `source = "player"` only after player saves the game
7. confirm pressing `J` during this modal doesn't close the journal
8. confirm canceling this same flow doesn't create anything

### Case 5 - Context after rebuild

1. repeat save and delete on more advanced spreads
2. confirm book returns near same region
3. confirm spread restoration doesn't break selection

---

## Anti-goals of Phase 8

1. Don't edit text directly in `MenuBook`.
2. Don't persist draft on every keystroke.
3. Don't mix temporary UI state with saved JSON.
4. Don't use physical entry deletion when `deleted = true` solves the case.
5. Don't open Phase 9 before save, cancel, and delete are stable.

---

## Short summary for opening next chat

Phase 8 should proceed with dedicated modal editor.
`MenuBook` continues only for reading, selection, and context.
Save, cancel, and delete must operate on the selected entry, and `N` should open a new player note in the same modal, always with draft only in memory and rebuild preserving spread at the end.
