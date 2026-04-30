# Custom Journal — Technical Implementation Plan

> This document replaces the previous broad design version with an incremental implementation technical plan. The focus now is to build the mod in small stages, each one self-validatable, while maintaining quest progress in the engine and using the native book renderer as the primary interface for the journal.

---

## 1. Name, scope and base decisions

### 1.1 First mod name

- Visible package name: `Mod 1 - Custom Journal`
- Initial technical namespace: `journal_custom`
- Initial Lua folder: `MWSE/mods/journal_custom/`

**Decision:** the first mod now uses the technical identifier `journal_custom`, with self-contained folder and metadata. The visible package name remains `Mod 1 - Custom Journal`.

### 1.2 System scope

The mod will have two different layers:

- **Engine journal**: continues to be the source of truth for quest progress, `tes3.getJournalIndex`, script compatibility and save state.
- **Mod journal**: becomes the source of truth for reading, editing, searching, tagging, filtering, visual order and player notes, with persistent state embedded in the current save.

### 1.3 Architectural decisions that must not change

1. The player will not use the vanilla `MenuJournal` as the primary UI.
2. The main visual will be the native book renderer via `tes3ui.showBookMenu`.
3. The mod journal does not depend on duplicating entries in the vanilla journal by default.
4. The persistent state of the mod journal, embedded in the current save, is the only source of truth for what will be displayed, edited, deleted or reorganized.
5. The final editing UX remains open until Phase 7 stabilizes; current options are editing in the journal itself or in a dedicated modal editor.
6. Development will be incremental, with feature flags and validation per phase.

---

## 2. Final system flow

```text
[Quest progresses in engine]
        ↓
[tes3.event.journal]
        ↓
[journal.capture registers/updates entry in the in-memory state of the journal in the save]
        ↓
[Player presses journal key]
        ↓
[journal.compat blocks vanilla MenuJournal]
        ↓
[journal.book opens MenuBook with HTML generated from the current state of the journal]
        ↓
[journal.mapping collects visible blocks from the page]
        ↓
[journal.input controls navigable selection in the open spread]
        ↓
[future editing phase chooses between journal or modal]
        ↓
[journal.data updates the in-memory state of the current save]
        ↓
[journal.book rebuilds the book preserving context]
        ↓
[tes3.event.save synchronizes the confirmed changes in the savegame]
```

---

## 3. Incremental development method

### 3.1 General principle

Each phase must fulfill four requirements:

1. **Small delivery**: a new capability, not a large package of features.
2. **Observability**: clear logging, persistent state and visible behavior.
3. **Simple rollback**: if the phase goes wrong, a flag disables the new behavior.
4. **Local validation**: there must be a cheap way to prove if the phase works before continuing.

### 3.2 Mandatory feature flags

The `config.lua` must be born with rollout flags. They reduce risk and make each phase testable.

```lua
return {
    debugLogging = true,
    enableVanillaJournalBlock = false,
    enableBookMode = false,
    enableMigration = false,
    enableSelection = false,
    enableEditMode = false,
    enableSearch = false,
    enableCustomOrder = false,
    syncPlayerNotesToVanilla = false,
}
```

### 3.3 Phase validation strategy

Each phase should have:

- **Editor validation**: no new errors in touched files, correct names, updated references.
- **In-game validation**: observable behavior with short manual steps.
- **Failure signal**: objective criterion that prevents advancing to the next phase.

---

## 4. Module structure

```text
MWSE/mods/journal_custom/
├── main.lua
├── config.lua
├── mcm.lua
├── journal/
│   ├── capture.lua
│   ├── migrate.lua
│   ├── data.lua
│   ├── render.lua
│   ├── mapping.lua
│   ├── book.lua
│   ├── input.lua
│   ├── search.lua
│   ├── order.lua
│   └── compat.lua
└── util/
    ├── logger.lua
    ├── text.lua
    └── date.lua
```

---

## 5. Technical plan per file

## 5.1 `main.lua`

### Responsibilities

- load configuration
- initialize logger
- register global events
- connect modules without putting business logic here

### Expected API

```lua
local config = require("journal_custom.config")
local logger = require("journal_custom.util.logger")
local capture = require("journal_custom.journal.capture")
local compat = require("journal_custom.journal.compat")
local book = require("journal_custom.journal.book")

local function initialized()
    capture.register()
    compat.register(book.open)
end
```

### Rules

- `main.lua` does not serialize the journal directly; it only coordinates the commit before saving
- `main.lua` does not mount HTML
- `main.lua` does not manipulate the book page directly

### Local validation

- the MWSE log should show a single `Initialized.`
- no circular dependency should appear when loading the mod

---

## 5.2 `config.lua`

### Responsibilities

- declare defaults
- load and save persistent configuration
- expose feature flags and keybinds

### Public API

```lua
local M = {}

function M.getDefaults() end
function M.load() end
function M.save(state) end

return M
```

### Recommended structure

- `settings` for UI and keybinds
- `featureFlags` for incremental rollout
- `schemaVersion` for future config migrations

### Local validation

- change a flag and confirm it persists in JSON
- open and close the game without losing configuration

---

## 5.3 `mcm.lua`

### Responsibilities

- expose keybinds
- expose debug and rollout feature flags
- expose search, ordering and optional sync options with vanilla

### Public API

```lua
local M = {}

function M.register(configModule) end

return M
```

### Initial scope

In the first version, MCM does not need to expose everything. The minimum necessary:

- journal keybind
- `enableVanillaJournalBlock`
- `enableBookMode`
- `enableEditMode`
- `debugLogging`

### Local validation

- change keybind and verify that the mod respects the new binding
- disable flag and confirm behavior disappears without editing code

---

## 5.4 `util/logger.lua`

### Responsibilities

- centralize log prefix
- provide `debug`, `info`, `warn`, `error` functions
- respect the `debugLogging` flag

### Public API

```lua
local M = {}

function M.get() end
function M.debug(...) end
function M.info(...) end
function M.warn(...) end
function M.error(...) end

return M
```

### Local validation

- with `debugLogging = true`, detailed logs appear
- with `debugLogging = false`, only important logs remain

---

## 5.5 `util/text.lua`

### Responsibilities

- sanitize text for book HTML
- remove proprietary journal markup when necessary
- generate anchor keys for visible block mapping

### Public API

```lua
local M = {}

function M.sanitizeBookText(text) end
function M.stripJournalMarkup(text) end
function M.buildAnchorKey(text) end
function M.normalizeWhitespace(text) end

return M
```

### Rules

- `sanitizeBookText` must never return `nil`
- all text rendered in the book must ultimately be compatible with `showBookMenu`
- `buildAnchorKey` must be deterministic

### Local validation

- pass text with `<`, `>`, `&`, `@Topic#` and line breaks
- confirm that the output renders and does not break the book

---

## 5.6 `util/date.lua`

### Responsibilities

- build display date for new entries
- generate fallback strings for migrated entries

### Public API

```lua
local M = {}

function M.buildCurrentDisplayDate() end
function M.buildUnknownDisplayDate() end

return M
```

### Local validation

- call on different days/months
- confirm that the format is stable and readable

---

## 5.7 `journal/data.lua`

### Responsibilities

- load the journal persisted within the current save
- maintain a session in-memory state for selection, cache and ephemeral context
- prepare the journal persistent snapshot when the game saves
- create, update, logically delete and order entries
- expose high-level queries for render, search and input

### Source of truth

This module is the core of the system. No other module should modify `state.entries` directly. The persisted journal lives in the current save; the module can maintain ephemeral fields in memory during the session, but only the persistent subset enters the savegame.

### Public API

```lua
local M = {}

function M.load() end
function M.save() end
function M.getState() end
function M.getEntry(id) end
function M.getEntries() end
function M.upsertEngineEntry(entry) end
function M.createPlayerEntry(params) end
function M.updateEditedText(id, text) end
function M.markDeleted(id, deleted) end
function M.setCustomOrder(id, order) end
function M.setLastKnownPage(id, page) end
function M.setSelectedEntry(id) end

return M
```

### Invariants

- every `entry.id` is unique
- `editedText` exists for every visible entry
- `source` can only be `engine` or `player`
- `deleted = true` never physically removes the entry from the save persistent state

### Local validation

- create a player entry, save the game and reload
- edit entry, save the game and confirm persistence
- mark deleted and confirm that the entry remains in the persistent state

---

## 5.8 `journal/capture.lua`

### Responsibilities

- listen to `tes3.event.journal`
- transform engine event into entry in the in-memory state of the save journal
- avoid duplicates when the same quest updates several times

### Public API

```lua
local M = {}

function M.register() end
function M.buildEntryFromJournalEvent(e) end

return M
```

### Rules

- this phase does not write to the vanilla journal
- this phase does not open the book
- this phase does not depend on UI

### Local validation

- complete a quest stage in the game
- check capture log
- verify that the persistent state of the save received `questId`, `questIndex`, `originalText`, `editedText`, `daysPassed`

---

## 5.9 `journal/migrate.lua`

### Responsibilities

- import old entries when the mod is installed in an existing save
- register `migrationDone`
- never re-import the same set twice

### Public API

```lua
local M = {}

function M.needsMigration(state) end
function M.run() end
function M.importDialogue(dialogue) end

return M
```

### Rules

- access `info.text` only once per entry during migration
- save progress in batches if the migration is long
- never assume the real date of the migrated entry

### Local validation

- use save with old quests
- run migration
- confirm that `migrationDone` was marked
- confirm that opening the book shows old entries

---

## 5.10 `journal/render.lua`

### Responsibilities

- convert persisted entries from the save into valid HTML for `showBookMenu`
- apply view mode: diary, quests, search, filtered
- build headers, separators and coherent blocks

### Public API

```lua
local M = {}

function M.renderBook(entries, context) end
function M.renderEntry(entry, context) end
function M.renderHeader(entry, context) end

return M
```

### Rules

- always end HTML with `<br>`
- never insert player text without sanitization
- keep rendering deterministic for the same set of entries

### Local validation

- open book with 1 entry, 10 entries and 100 entries
- confirm that the book opens without breaking the renderer
- confirm that text with special characters does not disappear

---

## 5.11 `journal/mapping.lua`

### Responsibilities

- collect visible blocks from `MenuBook_page_1` and `MenuBook_page_2`
- map visible elements to `entryId` and `field`
- maintain `lastKnownPage` and minimal page visit cache

### Public API

```lua
local M = {}

function M.collectVisibleBlocks(menu, state) end
function M.findBlockByEntryId(blocks, entryId) end
function M.updatePageCache(state, pageNumber, blocks) end

return M
```

### Rules

- mapping never alters persistent text
- mapping depends on the open book and must be recalculated on each page turn
- key heuristics must be simple and predictable

### Local validation

- open book, turn pages and verify that the module records `entryId -> page`
- confirm that selection returns to a known entry after rebuild

---

## 5.12 `journal/book.lua`

### Responsibilities

- open the book via `tes3ui.showBookMenu`
- close via `tes3ui.closeBookMenu`
- rebuild the book preserving context
- trigger mapping collection after opening and page turn

### Public API

```lua
local M = {}

function M.open() end
function M.close() end
function M.rebuild(preserveContext) end
function M.restoreContext() end
function M.goToEntry(entryId) end

return M
```

### Rules

- `open()` must never depend on `MenuJournal`
- `rebuild()` must be idempotent
- `preserveContext` must try to restore selected entry, known page and current mode

### Local validation

- open the book by keybind
- turn a few pages and confirm that the rebuild preserves relevant context
- force rebuild after selection, page change or context change
- close and reopen without losing relevant state

---

## 5.13 `journal/input.lua`

### Responsibilities

- capture keyboard for navigable selection within visible spread
- move selection between visible entries in the open spread
- resolve selection transitions when changing page or spread
- expose hooks for future editing without deciding yet between journal or modal
- prevent selection from leaking to blocks outside the current spread

### Public API

```lua
local M = {}

function M.ensure(menu) end
function M.resolveSelection(blocks, selectedEntryId, selectedSpreadStart) end
function M.moveSelection(blocks, selectedEntryId, direction) end
function M.beginEdit(entryId, block) end
function M.commitEdit() end
function M.cancelEdit() end
function M.onKeyDown(e, blocks, selectedEntryId) end
function M.onKeyPress(e, blocks, selectedEntryId) end

return M
```

### Rules

- navigable selection only works within blocks explicitly visible in the open spread
- when changing page or spread, selection must be cleared or revalidated
- the decision between editing in the journal itself and a modal editor remains open until the end of Phase 7
- visual highlight must point to the correct entry text, not repeated technical labels

### Local validation

- select the first visible entry
- navigate to a middle entry and the last visible entry
- change page and confirm selection clearing or revalidation
- confirm that selection does not leak outside the open spread

---

## 5.14 `journal/search.lua`

### Responsibilities

- search in the persistent state of the save, not in the visible page text
- maintain results in memory
- navigate to the next or previous result

### Public API

```lua
local M = {}

function M.setQuery(query) end
function M.getResults() end
function M.nextResult() end
function M.prevResult() end
function M.clear() end

return M
```

### Rules

- search must use `editedText`
- filters and visual modes must be respected
- navigating to a result must reuse `journal.book.goToEntry`

### Local validation

- search for text present in a distant entry
- confirm that the book navigates to it
- confirm wrap-around for next/previous result

---

## 5.15 `journal/order.lua`

### Responsibilities

- order entries for display
- support chronological order, by quest and custom order
- prepare foundation for tag and type filters

### Public API

```lua
local M = {}

function M.getRenderableEntries(state, mode) end
function M.moveEntryBefore(entryId, otherEntryId) end
function M.moveEntryAfter(entryId, otherEntryId) end
function M.rebuildCustomOrder(entries) end

return M
```

### Rules

- reordering only affects the display of the mod journal
- internal engine order is not altered

### Local validation

- move a player note up and down
- reopen book and confirm persistence of order

---

## 5.16 `journal/compat.lua`

### Responsibilities

- intercept journal keybind
- suppress vanilla `MenuJournal` when enabled
- be the only module that knows this compatibility layer

### Public API

```lua
local M = {}

function M.register(openBookCallback) end
function M.registerKeybindRedirect(openBookCallback) end
function M.registerVanillaJournalSuppression() end

return M
```

### Rules

- suppress `MenuJournal` only when `enableVanillaJournalBlock = true`
- during development, this layer must be quickly disableable

### Local validation

- with flag disabled, vanilla opens normally
- with flag enabled, journal key opens the mod book
- if some system tries to open `MenuJournal`, it is destroyed without crashing the game

---

## 6. Persisted data model in the save

```json
{
  "schemaVersion": 1,
  "migrationDone": false,
  "viewMode": "diary",
  "entries": {
    "entry_001": {
      "id": "entry_001",
      "questId": "ms_caius",
      "questIndex": 10,
      "originalText": "Caius Cosades gave me...",
      "editedText": "The old man gave me strange orders.",
      "displayDate": "16 Hearthfire",
      "daysPassed": 23,
      "source": "engine",
      "deleted": false,
      "customOrder": 120,
      "tags": ["mainquest"],
      "lastKnownPage": 8
    }
  }
}
```

### Non-persisted session state

- `selectedEntryId`
- `lastSearch`
- `pageCache`
- visible blocks, temporary selection and modal drafts

### Mandatory invariants

1. `id` always unique.
2. `editedText` never empty by accident; if the user deletes everything, that must be deliberate.
3. `source` only accepts `engine` or `player`.
4. `deleted` never physically removes from the persistent save state.
5. `customOrder` can be `nil`, but when it exists must be numeric.
6. `lastKnownPage` is only cached persistence for convenience; never a source of truth.

---

## 7. Incremental roadmap with validation per step

### Objective list of steps

1. Phase 0 — Foundation and package name. Status: completed.
2. Phase 1 — Persistence per save without UI. Status: completed and validated in-game.
3. Phase 2 — Engine journal capture. Status: completed and validated in-game.
4. Phase 3 — Redirect keybind without permanently blocking vanilla. Status: completed and validated in-game.
5. Phase 4 — Static book generated from the persistent save state. Status: completed and validated in-game.
6. Phase 5 — Migration of existing saves. Status: pending.
7. Phase 6 — Visible block mapping on page. Status: pending.
8. Phase 7 — Navigable selection. Status: pending.
9. Phase 8 — Real editing, contextual creation and persistence in dedicated modal. Status: implemented in code; in-game validation pending.
10. Phase 9 — Persisted dates and vanilla-style date entries. Status: implemented in code; in-game validation pending.
11. Phase 10 — Final shortcuts and contextual help in journal. Status: implemented in code; in-game validation pending.
12. Phase 11 — MCM and final hardening. Status: implemented in code; in-game validation pending.
13. Phase 12 — Final pagination compatibility with arrows. Status: implemented in code; in-game validation pending.
14. Phase 13 — Writing sound feedback. Status: implemented in code; in-game validation pending.

### Recent scope decisions

- **Immediate focus**: stabilize Phases 6 and 7 and harden the keybind to not open the journal in text context, save/load or dialog.
- **Scope for version 1.0**: close Phases 8 to 13 with dedicated modal, editable dates, discoverable shortcuts, basic MCM, arrow pagination and writing sound feedback.
- **Editing UX maintained**: Phase 8 continues with dedicated modal editor; `MenuBook` remains as a reading surface, selection and context.
- **External references**: Scribo continues as reference for modal and audio; MWSE 2.1 Journal becomes reference for help button and future image features; neither solves block selection or `MenuBook` pagination alone.

### Post-1.0 backlog

- Search over the persistent save state.
- Custom order, tags and filters.
- MCM option for first entry of a new date to always start on next page.
- Insertion of found in-game images, inspired by MWSE 2.1 Journal.
- Insertion of custom images. Proposal: the modal saves an ASCII alias of the asset within the mod itself, plus optional caption, scale and alignment; the renderer resolves that alias by a local whitelist and injects the validated markup in the book.
- MCM to customize as much formatting as possible.
- Optional integration with ink and notebook consumption.
- MCM option to hide default entries.
- Options within the journal itself to hide default entries and/or player entries.
- Expansion of the editing and creation flow for entries beyond the base 1.0 modal.
- Import bring custom entries, if any.

### Additional post-1.0 suggestions

- Favorites and entries pinned to the top of the journal.
- Export and import the journal in plain text for backup or manual migration.
- Snapshots before deleting or rewriting entries, to allow safe undo.
- Quick templates for notes on travel, loot, clues and alchemy.

## Phase 0 — Foundation and package name

### Objective

Make the package visible with the correct name and prepare the module base.

### Files

- `journal_custom/journal_custom-metadata.toml`
- `main.lua`
- `config.lua`
- `util/logger.lua`

### Delivery

- correct visible name
- centralized logger
- config with feature flags

### How to validate in editor

- metadata with correct name
- `main.lua` using the new name in logger

### How to validate in-game

- log shows `Mod 1 - Custom Journal`

### Readiness criterion

- the mod initializes and does nothing else beyond logging

---

## Phase 1 — Persistence per save without UI

### Objective

Create `journal.data` and prove that the mod can read and maintain its own state per save, with commit only when the game saves.

### Files

- `journal/data.lua`
- `config.lua`

### Delivery

- journal state loaded from current save
- load/save API working with commit on save event

### How to validate in editor

- no new errors in touched Lua files

### How to validate in-game

- start game loads the mod
- debug action creates a fictional note in the in-memory state of the journal
- save game, close and open the same save preserves the note

### Readiness criterion

- the journal is persisted with integrity within the save

### Failure signal

- changes disappear even after saving the game
- structure changes unexpectedly between saves

---

## Phase 2 — Engine journal capture

### Objective

Persist each new engine entry in the persistent state of the save journal without touching UI.

### Files

- `journal/capture.lua`
- `journal/data.lua`

### Delivery

- quest progression generates entries in the persistent state of the save

### How to validate in-game

1. start test save
2. trigger a known quest stage
3. check capture log
4. save game and confirm recorded entry in the save loaded afterwards

### Readiness criterion

- each new quest progress generates or updates a coherent entry

### Failure signal

- duplicate entries in excess
- `questId` or `editedText` inconsistencies

---

## Phase 3 — Redirect keybind without permanently blocking vanilla

### Objective

Open an entry point of the mod by journal keybind, but with a disableable compatibility flag.

### Files

- `journal/compat.lua`
- `main.lua`

### Delivery

- journal key calls mod callback
- suppression controlled by flag

### How to validate in-game

- flag disabled: vanilla journal opens
- flag enabled: mod callback executes and vanilla does not open

### Readiness criterion

- behavior toggles correctly by flag

---

## Phase 4 — Static book generated from the persistent save state

### Objective

Prove that the mod journal can be read as a native book.

### Files

- `journal/render.lua`
- `journal/book.lua`
- `util/text.lua`

### Delivery

- `showBookMenu` opens with HTML from the save journal

### How to validate in-game

- press journal with `enableBookMode = true`
- book opens with 1, 10 and 50 entries
- next and previous page work

### Readiness criterion

- the book opens without breaking and text is readable

### Failure signal

- blank book
- rendering broken by invalid HTML

---

## Phase 5 — Migration of existing saves

### Objective

Import journal prior to the mod.

### Files

- `journal/migrate.lua`
- `journal/data.lua`

### Delivery

- old entries appear in the mod book

### How to validate in-game

- use save with advanced quests
- run migration once
- confirm `migrationDone`

### Readiness criterion

- book now reflects the historical record of the old save

### Failure signal

- migration runs every time
- imported text breaks the book

---

## Phase 6 — Mapping of visible blocks

### Objective

Know which entry is visible on each page and begin selecting blocks.

### Files

- `journal/mapping.lua`
- `journal/book.lua`

### Delivery

- `visibleBlocks` list
- `lastKnownPage` updated

### How to validate in-game

- open book
- turn several pages
- confirm in log which `entryId`s are visible

### Readiness criterion

- the mod knows how to locate an entry on the open page with reasonable confidence

---

## Phase 7 — Navigable selection

### Objective

Allow keyboard selection among entries explicitly visible in the open spread, with reliable visual highlight and clear transitions between pages.

### Files

- `journal/input.lua`
- `journal/mapping.lua`
- `journal/book.lua`

### Delivery

- keyboard selection limited to entries explicitly visible in the open spread
- deselection when changing spread or page
- visual highlight applied to the correct entry text, not repeated technical labels
- support for cases where the first visible line of entry does not start with technical identifier

### How to validate in-game

1. select the first visible entry of the open spread
2. navigate to next, to a middle entry and to the last visible entry
3. turn page and confirm deselection
4. go back to previous spread and confirm no residual selection on wrong block
5. confirm that visual highlight follows the correct entry text, not a repeated technical line

### Readiness criterion

- navigable selection works without corrupting the visual state of the book
- deselection when changing page is correct
- visual highlight is reliable even when first visible line does not show complete technical identifier

### Failure signal

- selection leaks to hidden blocks or to another spread
- changing page leaves residual selection
- visual highlight points to the first repeated label on the page, not the entry text

---

## Phase 8 — Real editing, contextual creation and persistence

### Objective

Implement the real editing flow, creation, deletion and rebuild of book preserving context, using a dedicated modal editor and relative insertion from the selected entry.

### Files

- `journal/input.lua`
- `journal/data.lua`
- `journal/book.lua`
- `journal/editor.lua`

### Delivery

- modal opens from the selected entry
- initial text of modal reflects `editedText`
- `Shift+N` opens a new player note in the same modal flow
- default insertion creates the note after the selected entry
- modal offers an explicit action to insert the new note before the selected entry
- save editing
- cancel editing with visual rollback
- delete via soft delete in the mod journal
- reopen book near the same region

### How to validate in-game

- start editing a selected entry
- press `Shift+N` and create a new player note
- save a new note and confirm it entered after the selected entry
- use the insert-before action and confirm the note enters in the previous position
- confirm that modal draft does not persist too early
- save the edit, save the game and confirm persistence in the save loaded afterwards
- cancel and confirm visual rollback
- delete entry and confirm it disappears from the mod journal, not from engine
- confirm book reopens near the edited or deleted entry

### Readiness criterion

- full flow of selection -> creation/editing -> persistence or rollback is reliable

---

## Phase 9 — Persisted dates and vanilla-style date entries

### Objective

Transform the date into a first-class content type in the mod journal, persisting the game date for engine and player entries and allowing creation, editing and deletion of date entries.

### Files

- `journal/data.lua`
- `journal/capture.lua`
- `journal/render.lua`
- `journal/book.lua`
- `journal/editor.lua`

### Delivery

- entries from engine and created by player save the game date when inserted
- first note inserted on a new day creates or ensures a date entry like in vanilla journal
- date entry is one line from first note and two lines from previous entry
- `Shift+D` opens the flow to insert a date entry with chosen date
- date entry can be selected, edited and deleted
- date entry uses the same visual formatting as original journal

### Recommended organization for the agent

- separate **captured real timestamp** from **visual label**: `calendarDay`, `calendarMonth`, `calendarYear`, `daysPassed` and `dateKey` define the real date; visible date text is derived from this or in explicit override when player edits the date entry
- treat date entries in two groups: `auto` for headers generated from first real note of a day, and `manual` for entries created by `Shift+D`
- old entries inherited from saves without real timestamp should not gain retroactive date; only entries captured after this phase enter the automatic date flow
- default visual format for dates must follow vanilla journal: `28 Last Seed (Day 13)`; time and day of week from rest menu do not enter journal in this phase
- `Shift+J` must be compatibility exception, opening vanilla `MenuJournal` without dismantling normal keybind `J` interception

### How to validate in-game

- insert first note of a new day and confirm date appears only once
- insert another note same day and confirm date does not duplicate
- create date entry with `Shift+D`, edit, delete and confirm flow works
- save game, reload and confirm engine and player entries preserve the game date when inserted

### Readiness criterion

- date layer behaves as first-class persisted content and stays visually coherent with vanilla journal

---

## Phase 10 — Final shortcuts and contextual help in journal

### Objective

Close the 1.0 shortcuts and make them discoverable within the journal itself, reducing conflict with normal typing and making flow self-explanatory.

### Files

- `journal/input.lua`
- `journal/book.lua`
- `journal/editor.lua`
- `journal/render.lua`

### Delivery

- `Shift+N` replaces `N` as official shortcut for new note
- `Shift+D` opens date chosen flow
- journal now displays a help button with available shortcuts
- help button takes MWSE 2.1 Journal visual pattern as reference, adapted to `journal_custom`
- help text covers creation, insert before/after, editing, delete, save and cancel

### How to validate in-game

- confirm `N` alone no longer creates new note
- confirm `Shift+N` and `Shift+D` trigger correct flows
- open help and verify listed shortcuts match actual behavior
- confirm help is accessible without breaking book reading

### Readiness criterion

- shortcuts become discoverable, coherent with 1.0 UX and without conflicting with normal typing

---

## Phase 11 — MCM and final hardening

### Objective

Expose final 1.0 configuration and harden compatibility so the mod is safe in concurrent UI contexts.

### Files

- `mcm.lua`
- `journal/compat.lua`
- `journal/book.lua`
- `journal/input.lua`

### Delivery

- useable MCM
- reduced logging
- mature flags
- journal keybind safely ignored during typing, save/load, dialog and equivalent menus
- internal `MenuBook` rebuilds with no side effects of sound or unexpected reopening

### How to validate in-game

- change keybinds
- disable features by MCM
- confirm each part can be disabled without breaking the mod
- open save screen and confirm `J` goes back to normal typing
- open NPC dialog and confirm journal does not open over conversation
- move selection in book and confirm no sound of opening journal on each rebuild

### Readiness criterion

- mod useable without editing code

---

## Phase 12 — Final pagination compatibility with arrows

### Objective

Ensure that the journal_custom book responds reliably to left and right arrows for page turning.

### Files

- `journal/book.lua`
- `journal/compat.lua`
- `journal/mapping.lua`

### Delivery

- left arrow turns back page
- right arrow advances page
- mapping stays coherent after keyboard page turn
- selection and date entries stay coherent after page turn

### How to validate in-game

- open journal_custom book
- use right arrow to advance several pages
- use left arrow to go back
- confirm in log that mapping keeps changing with open page
- confirm selection does not get stuck on invisible entry after pagination

### Readiness criterion

- arrow navigation works without breaking book, without corrupting text and without losing current context

---

## Phase 13 — Writing sound feedback

### Objective

Add a pen-writing sound while player is in the writing flow, reinforcing immersive feedback.

### Files

- `journal/input.lua`
- `journal/book.lua`
- `journal_custom` sound assets, if necessary

### Delivery

- short writing sound when typing
- start and stop coherent with writing flow
- no aggressive repetition or broken audio overlap
- silent rebuilds of book, with feedback focused on writing and not journal reopening

### How to validate in-game

- open entry in writing flow
- type continuously for a few seconds
- stop typing
- confirm sound accompanies writing and stops without getting stuck looping
- confirm save, cancel or cursor movement do not replay journal open sound in loop

### Readiness criterion

- sound feedback reinforces writing without annoying, without leaking after leaving writing flow and without degrading responsiveness

---

## 8. Continuous validation matrix

This matrix should be run whenever a phase touches the corresponding behavior.

| Area | Minimum validation |
|---|---|
| Persistence | save records, reloads and preserves journal invariants |
| Capture | new quest update appears in persistent journal of save |
| Keybind | journal binding triggers mod correctly and does not fire in unsafe context |
| Book | opens, pages and responds to arrows without blank screen |
| Mapping | `selectedEntryId` points to coherent visible block |
| Editing | preview, insert before/after, save and cancel work |
| Dates | first note of day generates correct date entry without duplication |
| Shortcuts and help | `Shift+N`, `Shift+D` and help reflect actual behavior |
| Audio | writing sound accompanies typing, stops correctly and does not reopen journal by audio |
| Deletion | entry disappears from mod journal and continues existing in engine |
| Compatibility | disabling flags returns to safe behavior |

---

## 9. What not to do

1. Do not use `MenuJournal` as the base of the main experience; the book renderer is the correct visual target.
2. Do not treat the book as source of truth; the source of truth is the persistent state of the journal in the current save.
3. Do not duplicate everything in vanilla journal by default; that complicates more than helps.
4. Do not implement multiple new features in the same phase; each step needs short and cheap validation.
5. Do not save player text without HTML sanitization.
6. Do not proceed to the next phase if the current still requires frequent manual debugging.

---

## 10. Expected result in version 1.0

By the end of version 1.0, the player will have:

- a journal with native book visual
- game entries captured automatically
- own notes
- editing and creation by dedicated modal, with contextual insertion before or after selection
- persisted dates and editable date entries, in vanilla journal style
- discoverable shortcuts via help within the journal itself
- basic MCM for operation without editing code
- reliable arrow pagination
- writing sound feedback without spurious journal reopening sounds
- safe visual deletion

And the project will have:

- small isolated modules
- clear APIs per file
- implementable phases one at a time
- objective validation path to not lose control during development
- explicit post-1.0 backlog for search, organization, images, advanced formatting and optional integrations
