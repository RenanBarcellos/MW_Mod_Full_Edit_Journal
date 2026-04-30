# Morrowind Journal — In-Depth Analysis and Mod Proposal

---

## 1. Available Reference Mods

### 1.1 Journal Enhanced (v1.1 — Aerelorn, ~2004)
**Type:** ESP + External DLL (Morrowind Enhanced / MWE)

The oldest mod in the collection. It worked before the MWSE-Lua era: the player had to install the "Morrowind Enhanced" executable (a pre-MWSE DLL injector), then equip a physical object (quill + inkwell) to open a messagebox for typing. Upon confirmation, the entry was injected into the journal via MWScript.

**Technical Limitations:**
- Limit of ~650 characters per entry (one page of journal).
- Dependency on an external tool (MWE) that no longer exists actively.
- The UI was a messagebox — no real text field, no editing, no formatting.
- Noticeable lag when typing quickly (framerate dropped with the messagebox active).

**Historical Value:** First to prove that it's possible to inject player text into the journal. Conceptually correct, implementation limited by technology available at the time.

---

### 1.2 D-I-Y Journal Keeping (2xStrange, ~2004)
**Type:** Pure ESP

Deletes the text from *all* journal entries in the base game (Morrowind + Tribunal + Bloodmoon), leaving them empty. When an entry is activated, the game finds empty text and doesn't add even the date — the player's journal remains blank for them to write manually, using Journal Enhanced.

**Intention:** Hardcore roleplay — the player's character writes the diary with their own hand.

**Problems:**
- Depends entirely on Journal Enhanced for any functionality.
- Incompatible with most mods that add journal entries.
- No Lua component; pure ESP.

**Value:** Demonstrates an interesting concept of immersive journaling — the player as narrator. Can inspire a feature of "diary mode" where automatic game entries are hidden and the focus is on the player's own text.

---

### 1.3 Update My Journal (KRX — Modern MWSE-Lua)
**Type:** Pure MWSE-Lua, single file (`main.lua`, ~80 lines)

The simplest mod in the collection. When the journal is open, it registers `keyDown`. Pressing `Alt+Enter` creates a fixed menu with `tes3ui.createMenu` containing a `createParagraphInput`. The player types, confirms with `Alt+Enter` again, and the text is saved via `tes3.addJournalEntry({ text = inputText })`. The journal is closed and reopened programmatically to show the new entry.

**Relevant Code:**
```lua
inputCapture = inputBlock:createParagraphInput{}
inputCapture.widget.lengthLimit = 450

-- when saving:
tes3.addJournalEntry({ text = inputText })
```

**Strengths:**
- Clean code, didactic, good foundation for learning the mechanic.
- Works without ESP, without dependencies.
- Uses the modern API correctly.

**Limitations:**
- Hardcoded limit of 450 characters.
- Not persistent — enters as permanent journal entry (cannot be edited afterwards).
- No title, no category, no customizable date.
- Closes and opens the journal after saving, which is visually abrupt.
- No MCM, no configurable keybind.

---

### 1.4 MWSE 2.1 Journal Search and Edit (Svengineer99 — SVE)
**Type:** Advanced MWSE-Lua (`main.lua` ~1600 lines + `config.lua` + `mcm.lua`)

The most complete mod in the collection. The author even warns in the header that the code "is not well optimized, organized or commented". Despite this, the *functionality* implemented is impressive and reveals the real limits of working with the journal via MWSE.

**Implemented Features:**
1. **Real-time Search** — text field integrated into MenuJournal, searches entry text on the visible page, auto-advances pages by holding the key.
2. **In-place Editing** — selects editable entries on the current page, opens the input field with original text, saves modifications.
3. **Inserted Pages** — divides the current page into two halves (left/right) and injects a custom page on the opposite side.
4. **Image Insertion** — images collected from read books (`BookArt/`) can be inserted into custom pages with adjustable scaling.
5. **Headers with Date** — inserted pages receive auto header with in-game day/month.
6. **Space Compression** — reduces excess spacing between entries from different topics.
7. **Redundant Header Hiding** — hides duplicate date headers on the same page.
8. **Complete MCM** — all shortcuts are reconfigurable, with option to restore defaults.
9. **JSON Persistence** — edits are saved via `mwse.saveConfig`/`loadConfig` and reapplied each time the journal is opened.

**How Persistence Works:**
```lua
-- Structure saved in JSON:
journalEdits = {
    insertedPage = {          -- main journal
        ["1"] = "text...",   -- content of page 1
        ["1H"] = "header...", -- header of page 1
        ["1I"] = { contentPath = "...", width = ..., height = ... }
    },
    insertedPagequests = { ... }, -- quests tab
    hyperText = { ["topic"] = true }, -- known hyperlinks
    bookArtImages = { ... },
    customImageScaling = { ["path"] = 1.0 }
}
```

---

## 2. Inherent Difficulties with Morrowind's Journal

This is the most important part for defining the scope of what is viable.

### 2.1 The Journal is Read-Only at Engine Level
`tes3.addJournalEntry()` **adds** entries permanently. There is no API to edit or delete an entry once it has been added. Any "editing" that a mod does is a **UI illusion**: the true text of the entry remains in the savegame, and the visible modification is reapplied every time the journal is opened.

The approach adopted by this mod is the **shadow copy**: every entry added by the engine is intercepted via `tes3.event.journal`, copied as a player entry (`source = "engine_copy"`), and the original engine entry is permanently hidden in the UI. The player sees and edits only the copies. The original text is saved in `originalText` in the JSON as an immutable lookup key for the hide.

Consequence: exporting the complete journal exports only the copies (already with player edits), cleaned of HTML notation and hyperlinks.

### 2.2 Page-by-Page Rendering, No Access to Complete Array
The journal renders its entries on book pages. There is no API to "give me all entries as an array". To search the entire journal, you must paginate programmatically — turning page by page via `triggerEvent("mouseClick")` on navigation buttons, which is slow and visually intrusive (SVE does exactly this during search).

### 2.3 Entry Text Uses Partial HTML with Proprietary Hyperlinks
Journal entries use a subset of HTML and the proprietary notation `@TopicName#` to create topic hyperlinks. Any string manipulation must preserve or reconstruct this notation, or hyperlinks break. SVE implemented `restoreHyperLinks()` to deal with this.

Characters `<` and `>` in free text can corrupt rendering (they are interpreted as HTML tags).

### 2.4 The Journal UI Was Not Designed for Editing
`MenuJournal` is essentially a read-only book. To make text editable, SVE resorts to a "field overlay" approach: places an invisible `ParagraphInput` over the page text and synchronizes content, which results in complex and fragile code. There is no API of "enter edit mode for this element".

### 2.5 Length Limit per Entry
`tes3.addJournalEntry` accepts long text, but the *rendering* of an entry is limited by the book page size. Long text overflows to the next page automatically, which fragments long player entries unpredictably.

### 2.6 No Index of Player Entries
Entries added via `tes3.addJournalEntry` enter in chronological order along with all other game entries. There is no separate "tab" for personal notes by the player outside the main journal tab.

### 2.7 Closing/Reopening the Journal = Loss of UI State
Any UI element created within `MenuJournal` is destroyed when the journal closes. Everything must be recreated on the next opening. This makes any feature that needs UI state (like "was editing entry X") complicated to preserve.

---

## 3. What is Possible, What is Difficult, and What is Impossible

| Feature | Viability | Notes |
|---|---|---|
| Add new entries | ✅ Simple | `tes3.addJournalEntry` |
| Text search | ✅ Possible | Requires paginating UI or limiting to current page |
| Visual in-place editing | ✅ Possible | Complex; SVE proves it works |
| Duplicate entry | ✅ Possible | Copy text and call `addJournalEntry` |
| Export journal to file | ✅ Possible | `io.open` from LuaJIT or MWSE `lfs` |
| Import entries from file | ✅ Possible | Read JSON/text and call `addJournalEntry` |
| Tags/categories in entries | ✅ Possible | Metadata saved in separate JSON |
| Filter by type (player vs game) | ✅ Possible | Mark player entries in JSON |
| Shortcut to add entry quickly | ✅ Simple | `keyDown` outside of menu |
| Delete player entry / engine copy | ✅ Simple | Flag `deleted = true` in JSON + hide on opening |
| Move entry to end of timeline | ✅ Possible | Delete + re-insert as new entry |
| Delete original engine entry | ❌ Impossible | No API; hidden by shadow copy, not deleted |
| Reordering to arbitrary historical position | ❌ Impossible | Engine does not allow retroactive insertion in timeline |
| Separate native journal tab | ❌ Impossible | UI hardcoded in engine |
| Rich text (bold, italic, sizes) | ❌ Impossible | Journal renderer does not support |
| Search without paginating the journal | ❌ Impossible | No access to entries array |
| Robust Undo/Redo | ⚠️ Difficult | Would require state stack; possible but costly |
| Auto-save draft | ✅ Possible | Timer + periodic JSON |
| Multiple "notebooks" | ⚠️ Difficult | Can simulate with custom UI tabs, but outside native journal |

---

## 4. Proposal: Immersive Journal — Features and Architecture

Based on the analysis above, here is a proposal for a mod that would be the most complete and cohesive possible within engine limitations.

### 4.1 Design Principle
The goal is not to replace the game's journal, but to **make it a real diary** that the player wants to open and write in. The central idea is: **everything the player sees is editable**. Engine entries are copied as shadow copies and hidden at source; entries created by the player enter directly as copies. From the user's perspective there is no distinction — there is just "the journal", and they can edit, delete, and reorganize anything in it.

### 4.2 Proposed Features (from Simplest to Most Complex)

---

#### Feature 1 — Quick Add Entry (Inside or Outside Journal)
**How it Works:** Configurable key (default: `Alt+J` outside menus, or `N` inside journal) opens a compact overlay with `ParagraphInput`. The player types and confirms. The entry is saved with `tes3.addJournalEntry` and internally marked (JSON) as "player entry" with in-game timestamp.

**Improvement over Update My Journal:**
- Does not close/reopen the journal.
- Auto-configurable prefix (e.g.: "[Note —]" or character name).
- Length limit configurable in MCM (default: 800 chars).
- In-game date added automatically as optional prefix.

---

#### Feature 2 — Intelligent Search
**How it Works:** Search field always visible at top or bottom of journal. Searches entries on current page with immediate highlight. Keys `[` and `]` advance to previous/next occurrence. If not found on page, auto-paginate (like SVE, but smoother: uses timer with visual feedback).

**Improvement over SVE:**
- Indicator of "X occurrences found" total (calculated while paginating).
- Wrap-around: reaches end, loops to beginning with warning.
- "Search only my notes" mode (filters by player entry marker).

---

#### Feature 3 — Edit Any Entry
**How it Works:** All entries visible in the journal are player shadow copies — there is no UI distinction between "game entry" and "personal entry". Configurable key (default: `E`) puts the entry under cursor in edit mode (ParagraphInput overlay with current `editedText`). On save, `editedText` is persisted in JSON and reapplied on next journal opening. The `originalText` is never altered and serves as lookup key for hiding the original engine entry.

Interception flow in `journal` event:
```lua
event.register(tes3.event.journal, function(e)
    -- 1. Save copy in JSON with originalText = e.text
    -- 2. Schedule addJournalEntry for next frame (cannot call during event)
    -- 3. On journal opening, hide elements whose text == originalText
end)
```

---

#### Feature 4 — Duplicate Player Entry
**How it Works:** With player entry selected (edit mode active), configurable key duplicates the text as new entry `tes3.addJournalEntry`, also marked as "player entry". Useful for creating entry variations or making reference copies.

---

#### Feature 5 — Export / Import (Clean Text Format)
**How it Works:**

- **Export:** In MCM or by key, generates a `.txt` or `.json` file in `Data Files\MWSE\config\renan\journal\export\` with all entries marked as "player entry" (clean text, no HTML). Can include or exclude game entries (option).
- **Import:** Reads a `.txt` file from same directory. Each line (or block separated by blank line) is treated as an entry. Mod asks for confirmation before inserting.

**Implementation:** `io.open` from LuaJIT, which MWSE exposes directly.

```lua
-- Simplified export
local file = io.open("Data Files\\MWSE\\config\\renan\\journal\\export.txt", "w")
for _, entry in ipairs(playerEntries) do
    file:write("[" .. entry.date .. "]\n" .. entry.text .. "\n\n")
end
file:close()
```

---

#### Feature 6 — Tags and Filtering
**How it Works:** When creating/editing an entry, player can associate a tag (e.g.: "quest", "map", "clue", "personal"). Tags stay in metadata JSON. A filter UI in journal (simple side button) allows showing only entries with specific tag. Entries without tag show normally.

**Interface:** Filter buttons horizontally below journal tab buttons (Quests, Topics, Main) — added as UI elements via `uiActivated`.

---

#### Feature 7 — Automatic Backup
**How it Works:** On save game (event `save`), mod saves a copy of player entries JSON in `...journal\backup\save_SaveName.json`. Keeps last N backups (configurable in MCM). Protects against accidental corruption.

---

#### Feature 8 — Delete and Reorganize Entries
**Delete:**
Configurable key (default: `Delete`) with confirmation (`Yes/No`) marks selected entry with `deleted = true` in JSON. On next journal opening, hide processes both original engine entry and player copy — the pair disappears completely. Operation is reversible: data exists in JSON and MCM option ("Show deleted entries") can reveal everything.

**Reorganize by Deletion:**
Deleting intermediate entries is the natural way to reorganize. Hiding an entry between A and C makes those two appear adjacent in the journal. The narrative flow closes without visible gaps.

**Move to End (Cut and Paste):**
With entry selected, key `M` (configurable) executes:
1. Mark entry as `deleted = true` (disappears from current location)
2. Create new entry `addJournalEntry` with same `editedText`, marked with `movedFrom = "uuid-original"`
3. New entry appears at end of timeline with current date

**Reorganization Limitation:**
Cannot insert an entry at arbitrary historical position (between day 5 and day 10 when today is day 50). Engine timeline is strictly chronological. "Moving" always means moving to the end.

---

### 4.3 Proposed Architecture

```text
MWSE/mods/journal_custom/
├── main.lua          — bootstrap, event registration
├── config.lua        — defaults + mwse.loadConfig
├── mcm.lua           — complete MCM
├── journal/
│   ├── core.lua      — central logic (add, edit, tags, persistence)
│   ├── ui.lua        — journal UI building/manipulation
│   ├── search.lua    — search feature
│   └── io.lua        — file export/import
└── util/
    └── logger.lua    — logging wrapper
```

**JSON Data Structure:**
```json
{
  "entries": {
    "uuid-1234": {
      "originalText": "Caius Cosades gave me...",
      "editedText": "The old man gave me a strange mission...",
      "date": "16 Hearthfire",
      "daysPassed": 23,
      "source": "engine_copy",
      "tags": ["quest", "mainquest"],
      "deleted": false,
      "movedFrom": null
    },
    "uuid-5678": {
      "originalText": "I arrived at Balmora.",
      "editedText": "I arrived at Balmora. Need to rest.",
      "date": "17 Hearthfire",
      "daysPassed": 24,
      "source": "player_original",
      "tags": [],
      "deleted": false,
      "movedFrom": null
    }
  },
  "migrationDone": false
}
```

- `originalText` — immutable; engine text at moment of interception. Lookup key for the hide.
- `editedText` — current visible version in journal. Starts equal to `originalText`.
- `source` — `"engine_copy"` for entries intercepted from `journal` event; `"player_original"` for entries created directly by player.
- `deleted` — if `true`, both original engine entry and copy are hidden.
- `movedFrom` — UUID of original entry when this is a copy created by "move to end".
- `migrationDone` — flag for one-time process of migrating existing playthrough (paginate journal and create copies of all existing entries).

---

## 5. What NOT to Do (Lessons Learned from Existing Mods)

1. **Masking engine entries is the central mechanism — do it robustly** — hide must use `originalText` as immutable key, never `editedText`. If lookup fails, original engine entry appears duplicated next to player copy. Hide must be reapplied on each page opening, not just on journal opening.

2. **Don't use messagebox for text input** — lag, severe limit, bad experience. Always use `createParagraphInput`.

3. **Don't close/reopen journal to update UI** — visually abrupt and causes state inconsistencies. Use `updateLayout()` on existing menu.

4. **Don't attempt full-journal real-time search** — programmatic pagination is slow and freezes UI. Search should be lazy (page by page on user demand).

5. **Don't put everything in a single file** — SVE's main.lua with 1600 lines is a real maintenance problem. Modularize from the start.

6. **Don't hardcode keybinds** — make everything configurable via MCM from first version.

---

## 6. Implementation References by Feature

| Feature | Primary Reference | Secondary Reference |
|---|---|---|
| Add entry | `Update My Journal/main.lua` | SVE `newEdit(3)` |
| Search | SVE `searchOpenPages()` + `searchJournal()` | — |
| In-place editing | SVE `saveEdit()` + `newEdit()` | — |
| ParagraphInput / UI | `Update My Journal/main.lua` | Clocks/mcm.lua (MCM patterns) |
| Export/Import file | `lfs` (`C:\dev\Morrowind-ref\MWSE-ref`) + LuaJIT `io` | — |
| MCM keybinds | SVE `mcm.lua` | Clocks/mcm.lua |
| JSON Persistence | SVE `config.lua` (`mwse.loadConfig`) | — |
| UI injection in journal | SVE `onMenuJournalActivated()` | — |
