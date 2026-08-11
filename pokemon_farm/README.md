# Pokemon Farm

The opposite of a catch-everything mod: a place for Pokemon you let go.

## What it does

- Adds a **FARM** screen, reachable from the Start menu and/or the PC
  (configurable), following the exact same `mod.content.screens:register`
  + `mod.hooks:wrap("ui.start_menu.items"/"ui.pc.items")` pattern gen3_box
  uses for its own BOXES screen.
- From the **SEND** pane (Party + current Box, merged), select a Pokemon
  and press A to move it into `save.farm`.
- From the **FARM** pane, select a Pokemon and press A to reclaim it —
  goes to Party if there's room, else the current Box, else it's put back
  in the farm rather than lost.
- Vanilla release is untouched. This is a second option living next to it.

## What's confirmed vs. still assumed

This was rewritten after reading gen3_box v1.5.2's actual `main.lua`
(not search snippets), so the following are now **confirmed real**, not
guesses:

- `require("src.pokemon.Boxes")`, `require("src.pokemon.Party")`,
  `require("src.render.Font")`, `require("src.core.Strings")` — mods can
  pull engine source directly with the `engine_internals` permission.
- `game.save.boxes[game.save.currentBox]` and `game.save.party` are the
  real storage arrays; `Boxes.ensure(game.save)` backfills a missing table
  on an old save.
- `mod.content.screens:register(name, { new = fn })` registers a
  full-screen UI state; the object needs `isOpaque` and `uiSize()`.
- `mod.hooks:wrap("ui.start_menu.items", function(next, game, items) ... end)`
  and the identical shape for `"ui.pc.items"` — call `next()` first,
  decorate its result, return it, so other mods' rows survive.
- `mod.ui.insertBefore(list, anchorLabel, row)` / `insertAfter(...)` and
  `mod.ui.push(game, screenName)`.
- `mod.options:define({...})` / `mod.options:get(key)`.

Still **assumed, not yet confirmed** (the portion of gen3_box's file that
would show these wasn't visible when this was written):

1. **The input-handling method name on a screen object.** Written here as
   `self:keypressed(key)` by analogy with the love2d/VoxelMod convention,
   but gen3_box's own cursor-movement code (lines ~195–439 of its
   `main.lua`) wasn't read. Open that range and confirm the real method
   name and key-string values (`"a"` vs `"A"` vs a button-constant, etc.)
   before this will actually respond to input.
2. **`mod.ui.pop(game)`** for exiting a pushed screen — `push` is
   confirmed, `pop` is inferred from symmetry.
3. **`Party.MAX` / `Boxes.CAPACITY`** are confirmed to exist (used in
   gen3_box's header text) but their exact values weren't read — the code
   just compares against them directly rather than hardcoding numbers, so
   this should be safe either way.

## Next step to fully verify

Open `main.lua` lines 195–439 of gen3_box (the range that was truncated
when it was read) — that's where the cursor movement and A/B/SELECT
handling live, and it'll settle assumption #1 and #2 above directly. Once
confirmed, update the two marked spots in this mod's `main.lua` and the
test suite can grow a second file that drives `self:keypressed(...)`
end-to-end instead of only testing the data-splice logic directly.

Run `python3 tools/modkit.py validate pokemon_farm --base imported` once
the input handling is confirmed.
