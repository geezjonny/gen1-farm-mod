
## 0.2.0
- Rebuilt around ListMenu/TextBox (confirmed from MULTI_SAVE_SLOTS) after
  the custom screen's input handling didn't respond in testing
- Same save.party/save.boxes/save.farm splice logic, unchanged

## 0.2.1
- Fixed: sending party Pokemon to the farm could empty the party entirely.
  Now blocked with "That's your last one!", matching gen3_box's own rule.

## 0.3.0
- The farm is now a real, walkable place: a 10x8 open field registered on
  Pallet Town's east edge (previously unused -- doesn't touch the town's
  north/south exits to Route 1 / Route 21)
- No grass or encounters registered on the farm map -- a safe zone
- Menu-based send/reclaim (FARM from Start/PC) still works exactly as
  before; walking there is now an additional way to think about it, not a
  replacement for it -- the farm's Pokemon don't have visible sprites yet

## 0.3.1
- Fixed: farm map height was 8, Pallet Town is actually 9 blocks tall.
  The mismatch left part of the shared edge unaligned at offset=0,
  producing an impassable wall of border blocks along part of the
  boundary -- exactly the pitfall the New Map tutorial warns about.

## 0.4.0
- Found the real root cause via the engine's own source (Map.lua,
  OverworldController.lua, Warp.lua): connections are a pure data link,
  consumed only once the player already stands on the map's true edge
  cell. Pallet Town's own vanilla border tiles were never walkable in
  that direction, so ordinary wall collision stopped the player before
  the connection code ever ran -- no error, no version issue, nothing
  wrong with the connections patch itself.
- Fix: read Pallet Town's real block array via mod.content.maps:get and
  patch its entire east column to walkable ground (id 10), instead of
  assuming the vanilla border there was already open.

## 0.5.0
- Added PLACE FENCE / REMOVE FENCE to the FARM menu, using mod.world
  (WorldAPI) -- the engine's own sanctioned mod-facing bridge to the live
  overworld, read directly from world/WorldAPI.lua.
- The fence block is read from Pallet Town's own real border data
  (blocks[1], its top-left corner) rather than a guessed tileset number.
- Placements persist via save.fences, re-applied at boot (game.ready) and
  whenever the FARM menu opens, since mod.world:replaceBlock() only
  mutates the live map and doesn't survive a reload on its own.
- REMOVE FENCE restores whatever block was originally there, recorded at
  placement time.

## 0.6.0
- Added a direct keyboard trigger: T places a tree at the facing cell, Y
  removes it -- reuses the same placeFenceHere/removeFenceHere logic from
  0.5.0, just a simpler, instant trigger than going through the FARM menu.
- Wired via wrapping Game:keypressed (capture original, always call
  through) -- the same confirmed technique DramaticShapeVoxelMod uses for
  its own unhookable inputs, applied here since there's no named event/hook
  for "any keyboard key, once, in the overworld."
- T/Y are a guess at unused desktop keys, not verified against a real
  keybinding list -- easy to change if either collides with something.

## 0.7.0
- Generalized the single tree/fence key into a real palette + break
  system, per the "in-chunk persistence is fine" scope decision:
  - T places the current palette block at the facing cell
  - Y breaks it back to plain ground
  - U cycles the palette (TREE / GRASS / GROUND)
- Dropped the save.fences bookkeeping and game.ready reapply hook from
  0.5.0/0.6.0 entirely -- not needed now that placements only need to
  hold for the current map instance in memory, which
  mod.world:replaceBlock() already does on its own.
- Removed the now-dead PLACE FENCE/REMOVE FENCE menu entries from the
  FARM hub -- placement is key-driven now, hub is back to SEND/VIEW only.

## 0.7.1
- Fixed: place/break both aimed at the wrong cell -- mod.world:current()
  returns player position in CELL coordinates (p.cellX/p.cellY), but
  replaceBlock/Map:setBlock index in BLOCK coordinates (half the
  resolution -- confirmed via Map.lua's widthCells = def.width * 2 and
  setBlock's own bounds check against def.width/height). Was passing cell
  coordinates straight through; now floor-divides by 2 after applying the
  facing offset. This was the root cause of both "breaking not working"
  and "not placing right in front of the player" -- same bug, one fix.
- Known residual imprecision: since a block is 2x2 cells, a 1-cell facing
  step doesn't always cross into the next block -- depending on which
  half of your current block you're standing in, T/Y can sometimes affect
  the block you're standing in rather than the one ahead. Block-level
  operations only have block-level granularity; not fixed in this pass.

## 0.7.2
- Fixed the residual imprecision flagged in 0.7.1: now converts the
  player's own position to their current block FIRST, then steps one
  full block in the facing direction -- rather than stepping 1 cell and
  converting after, which could land back in the player's own block
  depending on which half of it they stood in. Should now reliably hit
  the block directly ahead every time, at full block granularity.

## 0.8.0
- Place/break footprint is now 2x2 BLOCKS (4 blocks, 8x8 cells) instead
  of a single block -- a single block only covers 2x2 cells, which read
  thin/asymmetric. The footprint is anchored so it always extends away
  from the player along the facing direction (never back over them), with
  a fixed right/down bias on the perpendicular axis.

## 0.8.1
- Fixed: a single T press produced two 2x2 placements (the "two rows of
  4" screenshot) -- OS key-repeat firing love.keypressed more than once
  per physical press, not a footprint math bug. Added a 0.3s cooldown
  across T/Y/U so a held or slightly-repeated key only acts once.

## 0.9.0
- Fixed: placed blocks were walkable through -- the "TREE" block
  (Pallet Town's top-left corner) was never actually confirmed solid,
  just guessed from a screenshot. Replaced with the exact block that
  blocked the original east-edge walk-out attempt, captured right before
  we overwrote it to open that edge -- proven non-walkable by the bug we
  already fixed, not another guess.
- Renamed TREE -> FENCE, since we don't actually know what the graphic
  depicts and "fence" was the original ask anyway.

## 0.10.0
- Fixed: FENCE was still walkable through in 0.9.0. Root cause, confirmed
  by reading Map.lua's tileAt/cellTile/isWalkableCell directly:
  walkability is checked per-cell, at the bottom-left TILE of each cell,
  not the whole visually-solid-looking block. Many tall Gen 1 objects are
  decoration on top with collision only at the base -- "this block
  visibly blocked me once" never actually guaranteed "this block is solid
  on the specific tiles the game checks."
- Replaced the positional guess with a real scan: replicate the engine's
  own block->tile resolution math, check the 4 tile positions that
  actually matter (indices 5/7/13/15 in a block's 16-tile definition)
  against the OVERWORLD tileset's real `walkable` list, and use the first
  Pallet Town block that's solid on all four.

## 0.10.1
- Fixed the "gap between player and placement" report -- confirmed to be
  a real even/odd (parity) artifact: a block is 2x2 cells, the player
  moves 1 cell at a time, and 0.7.2's "player's block + 1 block over"
  approach had a gap that varied depending on which of the 2 cells within
  the player's block they occupied. Switched to stepping 1 cell in the
  facing direction first, then converting to a block -- guarantees zero
  gap always, at the cost of occasionally landing on the player's own
  block (when already on the far cell) instead of always a fresh one
  ahead. A genuine tradeoff between "always adjacent" and "never
  overlaps the player's block" -- picked adjacency per your feedback.

## 0.11.0
- Added roaming: farmed Pokemon now spawn as wandering NPCs in Pallet
  Town instead of only existing as menu entries. Uses the engine's own
  built-in wander AI (objDef.movement == "WALK", confirmed directly from
  world/NPC.lua) -- no per-frame ticking of our own needed.
- Spawns near wherever the player is standing in Pallet Town (only when
  actually there), via mod.world:spawnNpc; despawns via mod.world:removeNpc
  on reclaim. Synced whenever the FARM menu opens, so a fresh boot or
  walking into town re-creates any missing roamers.
- Known limitation: every roamer uses the same placeholder sprite (read
  from an existing Pallet Town NPC, since data.sprites almost certainly
  has no generic per-species Pokemon overworld art -- Yellow's Pikachu
  follower needed its own dedicated module for exactly that reason).
  Species-accurate sprites would need real integration with a
  Follower-style mod.
- In-memory only, same "in-chunk is fine" scope as the palette placement
  work -- roamers don't survive a reload, and are simply respawned by the
  next FARM-menu sync.

## 0.11.1
- Fixed: roamer sprite was Professor Oak -- objects[1] in Pallet Town's
  data turned out to be him, confirmed by testing ("Prof Oak was standing
  in the grass"). Now searches from the end of the object list and skips
  any sprite key matching a named-character pattern (OAK/RIVAL/BLUE/
  GARY/RED), falling back to the last object rather than the first.

## 1.0.0
- The farm map is now real, artist-authored data from Tiled
  (bryanthaboi/tiled_gen1recomp + gen1-mod-export), replacing the
  hand-built flat all-ground field and the manual border-opening hack.
- No more computed "open the east column" patch -- the exported
  PALLET_TOWN.lua already carries a real, visually-confirmed walkable
  opening, painted directly with View > Show Tile Collision Shapes as
  live feedback instead of reverse-engineered tile-index math.
- Both maps are 9 tall, matching (a height mismatch here was exactly
  what caused the original wall-of-border-blocks bug).
- Everything else unchanged: FARM menu (send/reclaim), roaming Pokemon
  in Pallet Town, and the T/Y/U palette placement system all still work
  exactly as before -- this only replaces how the farm's own layout data
  is authored.

## 1.1.0
- Roaming Pokemon now spawn in POKEMON_FARM instead of Pallet Town, now
  that it's a real place -- Pallet Town spawning was only ever a stopgap
  from before this map existed.
- Sprite is still sourced from an existing Pallet Town NPC (POKEMON_FARM
  has no objects of its own to borrow from).
- Known rough edge: the +/-3 cell spawn offset was tuned for Pallet
  Town's larger space; the farm is a more compact 10x9-block map, so a
  roamer could spawn near/on the border if synced while the player is
  close to an edge. Not yet bounds-checked.

## 1.2.0
- Added a custom type-icon sprite mechanism -- roam_sprites/type_NORMAL.png
  tested first, before building out all 15 Gen 1 types. Registered via
  mod.content.sprites:register (NOT yet confirmed to be a real registry
  name -- pcall wrapped, falls back to the borrowed-NPC placeholder if
  registration fails).
- Rattata should pick up the NORMAL icon if: (a) sprites IS a real
  registry, (b) the image path resolves correctly, and (c) the type
  field name guess (def.type1 / def.types[1] / def.type, tried in that
  order) matches this engine's real Pokemon data shape. Any of those
  being wrong falls back to the old placeholder -- worth checking which
  actually happened if it doesn't show up.

## 1.3.0
- Added WATER type icon -- confirmed the whole mechanism works with
  NORMAL, so this is just the same pattern, one more entry.

## 1.4.0
- Pressing A on a roaming farm Pokemon now plays its real cry and shows
  "<Name> seems happy!" -- confirmed via real source: PikachuFollower.lua
  showed Sound.playCry(data, species) is a generic cry player (not
  Pikachu-specific despite living in that file), and OverworldController
  .lua's talkTo(npc) reads npc.def, which we already control as our own
  objDef.
- Implemented by monkeypatching OverworldState.talkTo (capture original,
  check for our own pokemonFarmSpecies tag, call through for every other
  NPC). require("src.world.OverworldController") is an inferred path
  (matches every other file in this folder's naming pattern, but was
  never directly observed requiring itself) -- pcall wrapped, falls back
  to silent interaction (old behavior) if the guess is wrong.

## 1.4.1
- Fixed a hard crash: registering a type sprite pointing at a PNG that
  doesn't actually exist (e.g. reinstalling without re-adding your own
  art to roam_sprites/) crashed at NPC-spawn time, not registration time
  -- the earlier pcall only covered registration, which just stores a
  path string; the actual image load is lazy and happens deep in engine
  code we don't wrap.
- Now checks the file genuinely exists (love.filesystem.getInfo) before
  ever registering or using that type's sprite key. A missing file falls
  back safely to the placeholder instead of crashing.
- Not fully certain getInfo resolves correctly against a mod's own
  installed path (untested against how mods are actually mounted) -- but
  worst case it just always reports "not found," which still fails safe.

## 1.5.0
- Added real ROM party-menu icons as the preferred sprite source, ahead
  of the custom type art: the game's own ~10 shared body-shape icons
  (BALL/BIRD/BUG/FAIRY/GRASS/HELIX/MON/QUADRUPED/SNAKE/WATER -- confirmed
  real group names, NOT type-based, which is why Abra looks like a
  generic quadruped despite being Psychic).
- No per-species hardcoding needed: only the ~10 group files are
  pre-registered at boot (existence-checked, same safety pattern as the
  custom art). Each mon's real icon is resolved LIVE per farmed species
  via def.icon/icons.bySpecies/icons.byDex (the same fields Sprites.lua
  documents the vanilla party menu using), then matched back to a
  registered key by path -- so any of the 151 species just works, not
  only ones we thought to list.
- Priority order: real ROM icon > custom type icon (if supplied) >
  borrowed NPC placeholder.
- The exact filename convention (assets/generated/icons/<GROUP>.png) is
  a guess -- the icons/ folder itself is confirmed real, the per-file
  naming inside it isn't. If wrong, it fails safe (existence check) and
  falls back to type icons automatically -- check the mod manager for
  the "no real icon files found" warning if roamers still show the old
  art.

## 1.5.1
- Fixed the icon filename guess using a real listing of
  assets/generated/icons/: filenames are lowercase, and GRASS is
  actually named "plant" internally, not matching the documented group
  name. Only 4 of ~10 files existed in that listing (bug, plant,
  quadruped, snake) -- likely decoded on demand, not all upfront.
- Now tries a couple of candidate filenames per group (starting with
  "plant" before falling back to "grass") rather than trusting a single
  guess, since one silent rename already turned up -- others might too.

## 1.6.0
- Added full per-species battle art as the top-priority sprite source,
  using assets/generated/battle/front/<SPECIES>.png -- confirmed named
  by exact species string, no guessing needed unlike the shared icons.
- Real image dimensions are probed per file (love.graphics.newImage(path)
  :getDimensions()) before registering, rather than assuming a fixed
  size -- registering with the wrong frameWidth/frameHeight wouldn't
  crash, it would silently crop the art to a useless corner sliver.
- Hardcoded the standard 151 Gen 1 species list (public, stable data --
  no registry enumeration needed, same reasoning as the 15 types). A
  handful of tricky names (Nidoran M/F, Mr. Mime, Farfetch'd) may not
  match this engine's exact internal spelling; those specific misses
  just fail their existence check and fall through to the next tier.
- Final priority order: per-species battle art > shared group icon >
  custom type icon > borrowed NPC placeholder.

## 1.6.1
- Fixed giant Rattata: battle art was registered at native full size (no
  built-in scaling exists anywhere in SpriteRenderer), confirmed by
  testing. Now renders each species' battle art down onto a 16x16 canvas
  first (matching SpriteRenderer's own default frame size, same as every
  other overworld sprite) and writes it out as a real small PNG via
  ImageData:encode's write-to-save-directory form -- standard LOVE 11.x
  calls only (newCanvas, graphics.draw, canvas:newImageData,
  imageData:encode), nothing engine-internal.
- Cached across boots: skips re-rendering a species whose shrunk file
  already exists from a previous run.
- Explicitly creates the target directory first (love.filesystem writes
  typically don't auto-create nested paths).

## 1.6.2
- Fixed blurry shrunk battle art: LOVE's default image filter is linear
  (smooth), which badly blurs pixel art on a downscale. Set nearest-
  neighbor filtering on the source image before drawing it onto the
  small canvas, so hard pixel edges survive instead of the blur getting
  baked into the encoded PNG's actual data.
- Renamed the cache directory (_v2) since the shrink pipeline caches its
  output and skips regenerating an existing file -- without this, the
  old blurry version would've just kept getting reused silently.

## 1.7.0
- Replaced the ROM-based icon/battle-art systems (blurry, guessed
  filenames) with a hybrid: reuses the confirmed-working species-to-group
  resolution (icons.bySpecies/def.icon/icons.byDex, the same fields the
  real party menu itself uses) purely to determine which of the 10 real
  icon groups a species belongs to -- but the actual image drawn is
  always custom art from roam_sprites/, never a ROM file. No more blur,
  no more guessing real internal filenames for anything except the
  lookup itself (and "plant" for GRASS is confirmed real, not guessed).
- Fixed a real bug found while making this change: the previous state
  had spriteForMon calling battleArtKeyFor/realIconKeyFor, neither of
  which existed anymore -- would have errored at runtime. Cleaned up.
- Priority: group art > type icon (fallback) > borrowed NPC placeholder.
- New art needed: group_ball.png, group_bird.png, group_bug.png,
  group_fairy.png, group_plant.png, group_helix.png, group_mon.png,
  group_quadruped.png, group_snake.png, group_water.png (16x16 each,
  same spec as the existing type_*.png files).

## 1.7.1
- Added a diagnostic log naming which real icon group each species
  resolves to, read from the game's own data rather than guessed from
  general knowledge (search results for "icon groups" kept surfacing egg
  groups, a totally different, unrelated system). Check the mod manager
  log after sending a Pokemon to the farm to see exactly which
  group_<name>.png it actually needs.

## 1.7.2
- Fixed: the mod-manager/crash log isn't actually accessible during
  normal play (confirmed by testing) -- the diagnostic added in 1.7.1
  was invisible in practice. Moved it into the SEND TO FARM confirmation
  message itself: "<Name> went to the farm. (icon group: X)" -- visible
  right in-game, no log file needed.
- Group art filenames now try both lowercase and UPPERCASE per group
  (group_water.png AND group_WATER.png), removing the case-sensitivity
  trap that caused one silent miss earlier.
- Fixed a real syntax bug (duplicate "end") introduced while making the
  above change and caught before shipping -- would have broken the
  entire mod's load if it had gone out.

## 1.7.3
- Replaced the talk-to-roamer "seems happy!" message with the same icon
  group diagnostic, temporarily -- this channel is confirmed visible
  (cry+happy text worked before), unlike the send-to-farm message which
  showed nothing at all, suggesting resolution itself might be failing
  entirely, not just missing matching art.
- Both diagnostic messages (send confirmation and talk-to) now ALWAYS
  show something, including "none found" -- the previous version only
  appended group info when resolution succeeded, silently showing
  nothing otherwise, which is indistinguishable from "no diagnostic
  ran at all" and likely why nothing appeared to show up before.

## 1.8.0
- Found and fixed the real bug behind every "none found" result, by
  reading src/ui/PartyMenu.lua's actual drawIcon function directly:
  1. Icons live at game.data.icons, NOT game.data.pokemon.icons -- a
     wrong nesting assumption that made every previous lookup fail
     immediately, every time, for every species.
  2. icons.bySpecies[species] / def.icon / icons.byDex[dex] return a
     NAME (e.g. "QUADRUPED"), not a file path -- icons.icons[name] is a
     separate step needed to get an actual path, which we don't need
     since we use our own art keyed by name directly.
- Group names are now the canonical uppercase ones confirmed directly
  from PartyMenu.lua's own iconFrames table (BALL, BIRD, BUG, FAIRY,
  GRASS, HELIX, MON, QUADRUPED, SNAKE, WATER) -- GRASS, not "plant" (that
  was the underlying decoded file's name, a different thing from this
  logical name, and not relevant anymore since we don't use real files).
- This should be the real fix -- the icon group diagnostic (send message
  and talk-to-roamer text) should finally show a real name instead of
  "none found".

## 1.9.0
- Confirmed via Collision.lua directly: roaming was ALREADY safe.
  verdict() checks map:inBounds() against the current map's own
  dimensions, and its own comment states connections are handled
  separately by OverworldController for player movement only -- the
  generic NPC wander logic never crosses one. Roamers cannot walk out
  of POKEMON_FARM no matter how long they wander.
- Fixed the one real gap: the SPAWN position itself had no bounds check.
  Now clamped to the farm's real interior (read from the actual
  registered map, not hardcoded), with a 2-cell margin to stay clear of
  the border ring -- so a roamer can never spawn on or past the edge
  even if the player was standing right next to it when synced.

## 1.10.0
- Removed the icon-group diagnostic from talk-to-roamer (its job is
  done -- resolution is confirmed working).
- Replaced with a simple closeness system: Gen 1 has no real happiness/
  friendship stat (confirmed from Pokemon.lua's own constructor -- Gen 2's
  Happiness.lua is real in this engine but part of the Gen 2 data model
  only, nothing for a Gen 1 Blue mon to hook into). This is our own
  analog: a plain per-mon talk counter stored on the mon's own
  save.farm record, with the message warming up as the count rises
  ("looks up at you" -> "seems curious" -> "seems to like you" ->
  "seems very happy to see you!").
- roamId is now also tagged on the spawned objDef (alongside species),
  so talkTo can find the exact mon's own record, not just its species.
- Tree/fence placement (T/Y/U) confirmed still fully intact, untouched
  by any of this -- ready to test fresh against the real map.

## 1.10.1
- Added a real TREE palette entry -- FENCE was the first solid block
  found by raw scan order, which turned out to be a building piece, not
  a tree (confirmed by testing). TREE is now targeted specifically at
  Pallet Town's actual border values (78/79/80/82, read directly from
  the real exported maps/PALLET_TOWN.lua data -- 78 repeats down the
  whole west edge, 79/80/82 dominate the top row, exactly where the
  tree canopy renders in every screenshot), using the same confirmed
  solidity check as before, just aimed at these specific candidates
  instead of scanning blind.
- FENCE kept as-is alongside it -- palette is now TREE / FENCE / GRASS /
  GROUND, cycled with U.

## 2.0.0
- Replaced the entire block-manipulation placement system (replaceBlock,
  guessed real tile IDs, 2x2-block granularity, parity/gap math) with
  custom-art stationary NPCs. NPCs position at CELL granularity
  (confirmed from world/NPC.lua), giving real single-cell placement --
  no more block-vs-cell math anywhere.
- New prop types: seed, grass, tree, fence, house -- cycle with U, place
  with T, remove with Y. Draw prop_sprites/prop_<name>.png (16x16,
  transparent) to enable each one; undrawn types just can't be placed
  yet ("<name> has no art yet.").
- Reuses the same confirmed sprite-registration + spawnNpc/removeNpc
  infrastructure already proven working for roaming Pokemon -- movement
  left unset (stationary, confirmed: self.wanders = objDef.movement ==
  "WALK" means anything else never moves).
- NPCs already block movement (Collision.lua's verdict() checks
  Collision.occupied), so a placed prop is a genuine obstacle -- same
  goal the old block system was chasing, just precise this time.
- Placements are in-memory only (same "in-chunk is fine" scope as
  before) -- tracked per cell so REMOVE finds exactly what's there.
- Removed all the real-tile-ID scanning code (CONFIRMED_SOLID_BLOCK /
  CONFIRMED_TREE_BLOCK) -- no longer needed since placement doesn't
  touch map blocks at all anymore.
