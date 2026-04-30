# Phase 7 - Plan v2

Date: 2026-04-28

## Purpose of this document

This document replaces the accumulated and noisy reasoning from the latest Phase 7 attempts.
The idea is to serve as a clean starting point for a new chat.

The focus here is:
- stabilize navigable selection in the journal within MenuBook
- remove the regressions introduced by the latest attempts
- define a robust strategy for highlighting and mapping
- remove control of widows and orphans from the critical path until selection is stable

---

## Current observed state

### Confirmed symptoms

1. Text became corrupted at several points with strange characters like `A`, coming from attempts to fiddle with HTML / non-breaking spacing.
2. On pages 1 and 2 highlighting works most of the time, but sometimes picks up a line from the following entry.
3. When crossing from page 1 to page 2, the highlight can also reach a line from another entry in the middle of page 2.
4. On pages 3 and 4, pressing the up arrow can close the game.
5. From pages 5 and 6 onwards, selection stops working or becomes very inconsistent.
6. The runtime save shows `selectedEntryId` being updated, so navigation is not completely dead; the main problem is between visual highlighting and mapping on later spreads.
7. The runtime save still showed `pageCache["3"]` with old signature based on `header`, while the first pages were already being written with `body`.

### What this means

- Input is not the biggest problem at this moment.
- The biggest problem is the visual strategy and the matching between rendered text and entries.
- Controlling widows and orphans through HTML / entities / special spaces is introducing more regression than benefit.
- Later pages are not being mapped reliably.

---

## Technical conclusions

### 1. Current highlighting is at the wrong level

The latest attempts alternated between:
- changing the color of text nodes
- injecting `rect` / overlays
- detecting text fragments to discover what to highlight

All of this remains fragile because it depends on the final result of MenuBook pagination.
When an entry breaks differently, the system highlights the wrong fragment, highlights too many fragments, or interferes with the layout.

### 2. Matching by visible fragment is necessary for mapping, but insufficient for highlighting

Matching by snippets of text is acceptable for answering:
- which entries appear to be visible in this spread?
- on which page of the current opening will those entries fall?

But that same matching is not sufficient to safely answer:
- which exact lines should receive highlighting?
- where does an entry visually begin and end after pagination?

In other words:
- `mapping` can remain approximate
- `highlight` should not depend on that same approximate line-by-line matching

### 3. `&nbsp;`, NBSP and typographic hacks are not safe here

Attempts to avoid widows and orphans using HTML entities or non-breaking spaces generated corrupted text.
In the current state, this should be considered forbidden for Phase 7.

### 4. The crash on 3/4 is the most important signal

Closing the game when pressing the up arrow on 3/4 indicates that we are still doing some operation that is too unsafe in the UI pipeline.
While this exists, it makes no sense to continue visually refining the current highlighting approach.

---

## Recommended decision

### Main decision

Stop trying to solve Phase 7 with post-render highlighting based on text fragments from MenuBook.

### New direction

The most promising strategy now is:

1. Use `mapping.lua` only to discover which entries are visible in the current spread.
2. Keep navigation restricted to the current spread.
3. Remove highlighting from the post-render DOM and move the highlight to the HTML generated in `render.lua`.
4. Rebuild the book when selection changes, preserving the current spread.

In other words:
- MenuBook should paginate the text that is already highlighted
- the code should not stay painting fragments after the text has already been broken into lines and pages

This changes the question from:
- "which node do I need to paint now?"

To:
- "which entry is selected before rendering?"

That second question is much more stable.

---

## Proposed solution

## Phase 7A - Safety reset

Before attempting the new approach, perform a controlled reset:

1. Remove all NBSP / `&nbsp;` / typographic protection logic in `render.lua` and `util/text.lua`.
2. Remove `rect` overlays and any highlighting by element injection in `book.lua`.
3. Remove highlighting by color in individual nodes, if it continues to depend on fragment matching.
4. Keep only:
   - `selectedEntryId`
   - `selectedSpreadStart`
   - `mapping.collectVisibleBlocks`
   - selection cleanup when switching spreads
   - navigation through `activeVisibleBlocks`

The goal of Phase 7A is to leave the journal without crashes and without corrupting the layout, even if temporarily without highlighting.

---

## Phase 7B - HTML highlighting, not UI tree highlighting

### Idea

Each entry should be rendered in `render.lua` with its own wrapper.
If the entry is selected, that wrapper receives a visually highlighted version.

Conceptual example:

- normal entry: normal black text
- selected entry: text with subtle highlighting or discreet frame, generated in the HTML itself

Since the page is broken by MenuBook after that, the highlight naturally follows the break between pages.
There is no need to discover afterwards where each line is.

### Important requirement

For this to work without being annoying, the rebuild must preserve the current spread.

So the correct chain becomes:

1. player presses arrow
2. `input.lua` chooses new `selectedEntryId` within `activeVisibleBlocks`
3. `book.lua` saves the selection
4. `book.lua` rebuilds the book
5. the rebuild reopens the book on the same spread
6. `render.lua` generates the selected entry with highlighting in the HTML

---

## How to preserve the spread during rebuild

This is the most important point for the next round.

Today the system already knows which spread is open via:
- `MenuBook_page_number_1`
- `blocks.spreadStart`
- `selectedSpreadStart`
- `pageCache`

The new work of Phase 7 should prioritize an explicit mechanism for restoring page/spread after rebuild.

### Recommended approach

1. Before rebuild, capture `currentSpreadStart` from the open book.
2. After reopening the book, navigate programmatically to that spread.
3. Only then confirm `scheduleVisibleBlockCollection`.

If this cannot be done stably with MenuBook, then the acceptable alternative for Phase 7 is:
- keep highlighting only when the book is open
- or even leave it without highlighting
- but never go back to overlays that might break layout or crash the game

Better without highlighting than with a crash.

---

## What to do with `mapping.lua`

`mapping.lua` does not need to identify the exact geometry of the highlight.
It needs to do only three things:

1. discover the set of entries visible in the current spread
2. correctly assign `spreadStart`
3. keep `pageCache` coherent with what was observed

### Current problem in `mapping.lua`

The runtime showed a later spread still being persisted with `header`, while the initial spreads were already being written with `body`.
This suggests one of these hypotheses:

- spread 3 was never rewritten after the code change
- the `body` matching failed on that spread and fell back to an old path
- the persisted state became outdated in part of the cache

### Recommended correction

1. Add stronger logging for later spreads:
   - `spreadStart`
   - summarized `pageText`
   - matched `entryId`
   - `field`
   - `confidence`
2. In case of `#blocks == 0`, never silently reuse old signature.
3. When visiting a spread, always overwrite the cache of that spread with the new signature observed on that opening.
4. Continue with windows by characters and by words, but use this only to decide visibility, not highlighting.

---

## What to do with `input.lua`

`input.lua` should go back to being simple.

### Desired rules

1. Navigation only between entries explicitly visible in the current spread.
2. Up / down arrow cannot try to select anything outside `activeVisibleBlocks`.
3. If the spread changes, selection is cleared.
4. `input.lua` should not know about highlighting, overlay, HTML or pageCache.

### Safety rule

If there is any doubt between:
- navigating further
- or maintaining the coherence of the current spread

Choose coherence of the current spread.

---

## Widows and orphans

### Recommended decision

Take this subject off the critical path of Phase 7.

### Reason

In the current MenuBook context:
- we have no real control over final line breaking
- hacks with entities / unicode already corrupted text
- each attempt to fix typography worsened stability

### Rule for the next round

During Phase 7:
- do not use `&nbsp;`
- do not use NBSP unicode
- do not use special invisible characters
- do not touch visible text with typographic replacements

If you want to resume widows and orphans later, that should become its own phase, based on line measurement and predictable layout, not HTML entities.

---

## Recommended implementation sequence in the next chat

1. Revert typographic hacks and any remaining special HTML.
2. Remove unsafe post-render overlays and highlighting.
3. Ensure that pages 3/4 stop crashing when pressing the up arrow.
4. Instrument `mapping.lua` with short logs for spreads 3/4 and 5/6.
5. Confirm that `activeVisibleBlocks` works on those spreads.
6. Only then implement HTML highlighting with rebuild preserving spread.
7. If spread preservation does not become stable, freeze Phase 7 without visual highlighting and proceed with functional navigation.

---

## Definition of done for Phase 7

Phase 7 should only be considered done when all of the following points are true:

1. Up and down arrows never close the game.
2. Selection works on pages 1/2, 3/4, 5/6 and subsequent spreads.
3. When switching spreads, selection is cleared or revalidated correctly.
4. No strange characters appear in the rendered text.
5. The highlight does not alter layout, does not erase text and does not pick up lines from neighboring entries.
6. Entry broken between two pages remains highlighted in a coherent way.
7. `pageCache` reflected the visited spreads with coherent and current signature.

---

## Anti-goals: what not to do again

1. Do not use `&nbsp;` or special unicode to control typography.
2. Do not highlight line by line trying to guess loose fragments.
3. Do not inject elements within the local text flow to highlight the entry.
4. Do not accept a crash in exchange for prettier highlighting.
5. Do not continue refining the visual before stabilizing 3/4 and 5/6.

---

## Files that will likely need to be touched in the next chat

- `MWSE/mods/journal_custom/journal/book.lua`
- `MWSE/mods/journal_custom/journal/mapping.lua`
- `MWSE/mods/journal_custom/journal/render.lua`
- `MWSE/mods/journal_custom/util/text.lua`
- possibly `MWSE/mods/journal_custom/journal/input.lua`

---

## Short summary for opening the next chat

Phase 7 entered a state in which:
- input still exists
- visual highlighting is fragile
- typography hacks broke text
- later spreads still fail

The recommendation is to restart Phase 7 in this order:
- reset unsafe visual hacks
- stabilize mapping on 3/4 and 5/6
- then migrate highlighting to HTML + rebuild preserving spread
- leave widows and orphans for later
