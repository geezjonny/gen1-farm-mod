-- Pokemon Farm
--
-- The opposite of a catch-everything mod: a place for Pokemon you let go.
--
-- Rebuilt around the engine's own ListMenu/TextBox widgets after the first
-- version's hand-rolled screen (custom self:update()/self:draw(), polling
-- game.input:wasPressed(...)) failed to respond to input in testing. That
-- approach was modeled on gen3_box's fully custom grid screen, which is
-- real and does work there -- but this mod doesn't need a custom grid, and
-- MULTI_SAVE_SLOTS v1.0.0's actual source shows a simpler, confirmed path
-- for exactly this shape of feature (pick one thing from a list, act on
-- it): push a ListMenu, let the engine handle all input, react in
-- onChoose. No polling loop of our own to get wrong.
--
-- Confirmed directly from MULTI_SAVE_SLOTS-1.0.0/main.lua:
--   * require("src.ui.ListMenu"), require("src.render.TextBox")
--   * game.stack:push(ListMenu.new(game, title, rows, { onChoose = function(item, menu) ... end }))
--   * game.stack:push(TextBox.new(game, message))  -- message-only, no callback needed
--   * a menu can be rebuilt in place after an action: menu.items = newRows(),
--     clamp menu.index, reset menu.scroll = 0, and menu:close() if now empty
--   * mod.hooks:wrap("ui.start_menu.items", ...) items can also be reached by
--     walking `items` and wrapping/inserting directly, not only via
--     mod.ui.insertBefore -- both are real, insertBefore is used here since
--     it was confirmed in gen3_box too and is less code.
--
-- Still confirmed from gen3_box, unchanged:
--   * save.boxes[save.currentBox] / save.party are the real storage arrays
--   * mod.hooks:wrap("ui.pc.items", ...) with the BILL'S PC / SOMEONE'S PC anchors
--   * mod.options:define / mod.options:get

-- Confirmed from the wiki's Tutorial 07 (New Map), pasted in directly:
--   * mod.content.maps:register(id, { id, label, index, tileset, width,
--     height, blocks, borderBlock, connections }) -- a map is a block grid
--     over a tileset; blocks must be exactly width*height entries.
--   * mod.content.maps:patch(existingId, { connections = { side = {...} } })
--     merges into the connections dict -- doesn't disturb existing sides.
--   * connections = { side = { map = id, offset = n } } is seamless
--     edge-to-edge scrolling between two outdoor maps, not a warp tile --
--     both maps need the reciprocal side registered or one direction won't
--     work (a flagged pitfall in the tutorial itself).
--   * Pallet Town's vanilla connections are only north (Route 1) and south
--     (Route 21) -- east/west are free, so adding one doesn't touch the
--     town's existing exits or story flow at all.
--   * mod.content.encounters:register(mapId, { grass = {...} }) adds wild
--     encounters -- deliberately NOT used for the farm map: no grass
--     blocks, no encounter table, so it's a safe zone by construction, not
--     by convention.
--   * disabling the mod on a save whose location was the mod's map falls
--     back to the last heal point automatically -- confirmed safe, not
--     just assumed.

-- Confirmed from the actual engine source (world/WorldAPI.lua, world/Map.lua,
-- world/OverworldController.lua, world/Warp.lua -- read directly, not from
-- docs) while chasing down why the map connection was walled off:
--   * mod.world is the sanctioned mod-facing bridge to the live overworld
--     ("Reaching into OverworldState internals stays unsupported; anything
--     a mod legitimately needs belongs here" -- WorldAPI's own header).
--   * mod.world:current() -> { mapId, x, y, facing } for the live player,
--     or nil, "no overworld" when not in one (e.g. from a menu/battle).
--   * mod.world:replaceBlock(bx, by, block) mutates one block on the LIVE
--     map and rebuilds the renderer -- same primitive vanilla uses for
--     Victory Road boulders and Cut trees. Its own comment: this only
--     mutates the runtime Map, NOT saved/reloadable data -- "a layout
--     change that must survive a reload belongs in a maps patch." So
--     placed fences need to be recorded in save data ourselves and
--     re-applied (not just placed once and forgotten).
--   * Map:isWalkableCell checks the tileset's `walkable` list per cell --
--     this is what actually blocked the very first walk-out attempt: the
--     `connections` patch alone doesn't make a vanilla border tile
--     walkable, and there's no confirmed way to un-walkable a *placed*
--     fence block from our own farm's ground -- so this feature is
--     "place a known-solid block," which needs no walkable-list edits at
--     all, only a real solid block id already used somewhere in Pallet
--     Town's own vanilla border, read directly from its data rather than
--     guessed.

return function(mod)
  local Boxes = require("src.pokemon.Boxes")
  local Party = require("src.pokemon.Party")
  local Strings = require("src.core.Strings")
  local TextBox = require("src.render.TextBox")
  local ListMenu = require("src.ui.ListMenu")
  local Logger = require("src.core.Logger")
  -- Set on enter, not at require time, per OverworldController.lua's own
  -- comment ("avoids circular require at load time") -- confirmed real,
  -- used the same way there.
  local Game = require("src.core.Game")

  mod.options:define({
    { key = "access", label = "OPEN FROM", type = "choice", default = "both",
      choices = {
        { "START+PC", "both" },
        { "START", "start" },
        { "PC", "pc" },
      } },
  })

  local function access() return mod.options:get("access") or "both" end
  local function onStart() local a = access() return a == "both" or a == "start" end
  local function onPC() local a = access() return a == "both" or a == "pc" end

  ------------------------------------------------------------------
  -- the physical place -- now authored properly in Tiled instead of a
  -- hand-built flat field. Confirmed via world/Map.lua reading, the
  -- earlier version needed a manual border-opening hack because
  -- `connections` alone is a pure data link -- Map:isWalkableCell still
  -- blocks ordinary movement on whatever the border tiles really are.
  -- Painting the layout directly in Tiled (with View > Show Tile
  -- Collision Shapes as live feedback) replaces that whole hack: the
  -- exported PALLET_TOWN.lua already carries a real, visually-confirmed
  -- walkable opening in its own `blocks` data, so there's nothing left
  -- to patch here beyond loading the two exported files.
  --
  -- mod:read + load is the same shape gen1-mod-export's own generated
  -- main.lua uses for bundled extra files.
  ------------------------------------------------------------------

  do
    local MAP_FILES = { "maps/PALLET_TOWN.lua", "maps/POKEMON_FARM.lua" }
    for _, relative in ipairs(MAP_FILES) do
      local source = mod:read(relative)
      if not source then
        Logger.error("pokemon_farm: %s missing -- reinstall the mod", relative)
      else
        local chunk, compileErr = load(source, "@" .. mod.path .. "/" .. relative)
        if not chunk then
          Logger.error("pokemon_farm: %s did not compile: %s", relative, tostring(compileErr))
        else
          local ok, apply = pcall(chunk)
          if not ok or type(apply) ~= "function" then
            Logger.error("pokemon_farm: %s must return function(mod): %s", relative, tostring(apply))
          else
            apply(mod)
          end
        end
      end
    end
  end

  ------------------------------------------------------------------
  -- static props -- custom-art stationary NPCs, replacing the whole
  -- replaceBlock-based system above (block-ID guessing, 2x2-block
  -- granularity, parity/gap math). NPCs position at CELL granularity
  -- (confirmed from world/NPC.lua: self.cellX, self.cellY = objDef.x,
  -- objDef.y), giving real single-cell placement precision instead.
  -- Reuses the SAME confirmed sprite-registration + spawnNpc/removeNpc
  -- infrastructure already proven working for roaming Pokemon -- just
  -- custom art and movement left unset. self.wanders = objDef.movement
  -- == "WALK" (confirmed from NPC.lua) means anything else never moves.
  -- NPCs also block movement (Collision.lua's verdict() checks
  -- Collision.occupied), so a placed prop is a genuine obstacle, same
  -- goal as the old block system, just with real precision this time.
  ------------------------------------------------------------------

  local PROP_TYPES = { "seed", "grass", "tree", "fence", "house" }

  local PROP_SPRITE_KEYS = {}
  for _, propName in ipairs(PROP_TYPES) do
    local file = "prop_sprites/prop_" .. propName .. ".png"
    local fullPath = mod.path .. "/" .. file
    local exists = love.filesystem and love.filesystem.getInfo
      and love.filesystem.getInfo(fullPath) ~= nil
    if exists then
      local key = "pokemon_farm_prop_" .. propName
      local ok = pcall(function()
        mod.content.sprites:register(key, {
          image = fullPath,
          frames = 1,
          trueColor = true,
        })
      end)
      if ok then
        PROP_SPRITE_KEYS[propName] = key
      else
        Logger.warn("pokemon_farm: could not register prop art for %s", propName)
      end
    else
      Logger.warn("pokemon_farm: %s not found -- draw prop_sprites/prop_%s.png (16x16) to enable it", file, propName)
    end
  end

  local FACING_DELTA = {
    up = { dx = 0, dy = -1 }, down = { dx = 0, dy = 1 },
    left = { dx = -1, dy = 0 }, right = { dx = 1, dy = 0 },
  }

  local propIndex = 1
  local placedProps = {}  -- "mapId:x,y" -> npcId, in-memory only (same
                           -- "in-chunk is fine" scope as everything else)
  local nextPropObjIndex = 0

  local function propCellKey(mapId, x, y) return mapId .. ":" .. x .. "," .. y end

  local function currentPropName()
    return PROP_TYPES[propIndex]
  end

  local function placePropHere()
    local pos = mod.world and mod.world:current()
    if not pos then return false, "Not in the overworld." end
    local propName = currentPropName()
    local sprite = PROP_SPRITE_KEYS[propName]
    if not sprite then return false, propName .. " has no art yet." end
    local d = FACING_DELTA[pos.facing]
    if not d then return false, "Unknown facing." end
    local tx, ty = pos.x + d.dx, pos.y + d.dy
    local key = propCellKey(pos.mapId, tx, ty)
    if placedProps[key] then return false, "Already something there." end
    nextPropObjIndex = nextPropObjIndex + 1
    local objDef = {
      index = 5000 + nextPropObjIndex,  -- clear of roamers' 1000+ range and vanilla objects
      sprite = sprite,
      x = tx, y = ty,
      range = "DOWN",
      -- movement intentionally omitted -- stationary, not a wanderer
    }
    local npcId = mod.world:spawnNpc(pos.mapId, objDef)
    if not npcId then return false, "Could not place." end
    placedProps[key] = npcId
    return true, propName .. " placed."
  end

  local function removePropHere()
    local pos = mod.world and mod.world:current()
    if not pos then return false, "Not in the overworld." end
    local d = FACING_DELTA[pos.facing]
    if not d then return false, "Unknown facing." end
    local tx, ty = pos.x + d.dx, pos.y + d.dy
    local key = propCellKey(pos.mapId, tx, ty)
    local npcId = placedProps[key]
    if not npcId then return false, "Nothing there." end
    mod.world:removeNpc(npcId)
    placedProps[key] = nil
    return true, "Removed."
  end

  ------------------------------------------------------------------
  -- direct key triggers -- raw keyboard keys, not the 8 GB buttons, so
  -- they only ever mean "prop action" and never collide with
  -- movement/menu input. Wired the confirmed way real mods do this when
  -- there's no named hook for a thing: capture the existing
  -- Game:keypressed, wrap it, always call through.
  --
  -- love.keypressed fires repeatedly while a key is held (OS key repeat,
  -- confirmed by testing on the old system) -- debounced with a plain
  -- time cooldown rather than relying on an unconfirmed isrepeat flag.
  --
  -- T/Y/U are a guess at genuinely unused desktop keys, not confirmed
  -- against an actual keybinding list -- easy lines to change if any of
  -- them collide with something.
  ------------------------------------------------------------------

  local PLACE_KEY, BREAK_KEY, CYCLE_KEY = "t", "y", "u"
  local ACTION_COOLDOWN = 0.3  -- seconds; comfortably longer than typical OS key-repeat delay
  local lastActionAt = 0

  local innerKeypressed = Game.keypressed
  function Game:keypressed(key, ...)
    if key == CYCLE_KEY or key == PLACE_KEY or key == BREAK_KEY then
      local now = love.timer and love.timer.getTime() or 0
      if now - lastActionAt < ACTION_COOLDOWN then return end
      lastActionAt = now
    end
    if key == CYCLE_KEY then
      propIndex = (propIndex % #PROP_TYPES) + 1
      local game = mod.world and mod.world.game
      if game and game.stack then
        game.stack:push(TextBox.new(game, "Prop: " .. currentPropName()))
      end
      return
    end
    if key == PLACE_KEY or key == BREAK_KEY then
      local game = mod.world and mod.world.game
      local ok, err = (key == PLACE_KEY) and placePropHere() or removePropHere()
      if not ok and game and game.stack then
        game.stack:push(TextBox.new(game, err))
      end
      return
    end
    return innerKeypressed(self, key, ...)
  end

  ------------------------------------------------------------------
  -- data helpers -- unchanged from the previous version: everything
  -- reads/writes save.party, save.boxes, save.farm directly.
  ------------------------------------------------------------------

  local function ensureFarm(save)
    save.farm = save.farm or {}
    return save.farm
  end

  ------------------------------------------------------------------
  -- roaming -- one wandering NPC per farmed Pokemon, in the farm itself
  -- (moved here from Pallet Town, which was only ever a stopgap before
  -- this map existed). Confirmed from world/NPC.lua directly:
  -- objDef.movement == "WALK" gives an object the engine's own built-in
  -- random-wander AI (no per-frame ticking of our own needed),
  -- constrained by objDef.range ("ANY_DIR" = all 4 directions). Spawned
  -- via mod.world:spawnNpc, which WorldAPI confirms persist across
  -- seamless connection crossings (Pallet Town <-> the farm) via the
  -- engine's own npcPool -- but NOT across a reload, matching the same
  -- "in-chunk is fine" scope as the fence/palette work, so no save-data
  -- tracking here either.
  --
  -- Known rough edge: the +/-3 cell random offset around the player was
  -- fine in Pallet Town's larger space, but POKEMON_FARM is a compact
  -- 10x9-block map -- if the player is near an edge when this syncs, a
  -- roamer could spawn on or past the border. Not yet bounds-checked
  -- against the farm's actual walkable area.
  ------------------------------------------------------------------

  -- A real, guaranteed-valid sprite key, read from an existing Pallet
  -- Town NPC rather than guessed -- data.sprites almost certainly has no
  -- generic per-species Pokemon entries (Yellow's Pikachu-follows-you is
  -- its own dedicated hand-built module, PikachuFollower.lua, which
  -- wouldn't need to exist if arbitrary species already had usable
  -- overworld sprites). Known limitation: every roamer looks like some
  -- existing NPC's sprite regardless of species until/unless integrated
  -- with a real Follower-style sprite system.
  --
  -- objects[1] turned out to be Professor Oak (confirmed by testing --
  -- "Prof Oak was standing in the grass"), which is a confusing choice
  -- for a placeholder even though it worked mechanically. Prefer a sprite
  -- key that doesn't look like a named character, and search from the
  -- end of the list rather than assume index 1 is generic.
  local ROAMER_SPRITE = (function()
    local pallet = mod.content.maps:get("PALLET_TOWN")
    local objects = pallet and pallet.objects
    if not objects or #objects == 0 then return nil end

    local NAMED_CHARACTER_PATTERNS = { "OAK", "RIVAL", "BLUE", "GARY", "RED" }
    local function looksGeneric(spriteKey)
      if not spriteKey then return false end
      local upper = tostring(spriteKey):upper()
      for _, pattern in ipairs(NAMED_CHARACTER_PATTERNS) do
        if upper:find(pattern, 1, true) then return false end
      end
      return true
    end

    for i = #objects, 1, -1 do
      local sprite = objects[i] and objects[i].sprite
      if looksGeneric(sprite) then return sprite end
    end
    return objects[#objects] and objects[#objects].sprite  -- fallback: last, not first
  end)()

  -- Custom art, organized by the game's own real icon GROUPS (not
  -- types) -- reuses the confirmed-working species-to-group resolution
  -- (icons.bySpecies / def.icon / icons.byDex, the same fields the real
  -- party menu itself uses) purely to figure out WHICH group a species
  -- belongs to. The actual image drawn is always our own art, never a
  -- ROM file -- this sidesteps both problems hit earlier: no more
  -- guessing real filenames (BALL/BIRD/etc. vs their true internal
  -- names like "plant" for GRASS), and no blur from downscaling ROM
  -- battle art. "plant" is the confirmed real internal name for GRASS,
  -- direct from a listing of assets/generated/icons/; the others are a
  -- best guess at the same lowercase convention.
  -- Group names are the canonical uppercase ones (BALL, BIRD, BUG,
  -- FAIRY, GRASS, HELIX, MON, QUADRUPED, SNAKE, WATER) -- confirmed real
  -- directly from PartyMenu.lua's own iconFrames table (BUG/GRASS/SNAKE/
  -- QUADRUPED keys). "plant" was the underlying decoded FILE's name, a
  -- different thing from this logical name -- not needed anymore since
  -- we use our own art, not the real files.
  local GROUP_ART_NAMES = {
    "BALL", "BIRD", "BUG", "FAIRY", "GRASS",
    "HELIX", "MON", "QUADRUPED", "SNAKE", "WATER",
  }

  -- Both lowercase and UPPERCASE filenames tried per group, since the
  -- type_* files use uppercase while earlier group_* testing showed a
  -- case-sensitivity trap -- trying both removes the need to get it
  -- exactly right.
  local GROUP_ART_KEYS = {}
  for _, groupName in ipairs(GROUP_ART_NAMES) do
    local candidates = {
      "roam_sprites/group_" .. groupName:lower() .. ".png",
      "roam_sprites/group_" .. groupName .. ".png",
    }
    for _, file in ipairs(candidates) do
      local fullPath = mod.path .. "/" .. file
      local exists = love.filesystem and love.filesystem.getInfo
        and love.filesystem.getInfo(fullPath) ~= nil
      if exists then
        local key = "pokemon_farm_group_" .. groupName:lower()
        local ok = pcall(function()
          mod.content.sprites:register(key, {
            image = fullPath,
            frames = 1,
            trueColor = true,
          })
        end)
        if ok then
          GROUP_ART_KEYS[groupName] = key
        else
          Logger.warn("pokemon_farm: could not register group art for %s", groupName)
        end
        break  -- found one for this group, stop trying the other case
      end
    end
  end

  -- Resolve which group a species belongs to, confirmed directly from
  -- PartyMenu.lua's own drawIcon function (read from real source, not
  -- guessed): icons live at game.data.icons -- NOT game.data.pokemon
  -- .icons, a wrong nesting that was the actual root cause of every
  -- previous "none found" result. The name itself (e.g. "QUADRUPED")
  -- comes directly from icons.bySpecies[species] / def.icon / (via dex)
  -- icons.byDex[dex] -- no path-parsing needed, since PartyMenu.lua's
  -- own code confirms these three fields already yield the NAME, with
  -- icons.icons[name] only needed to go from name to file path (which we
  -- don't need, since we use our own art keyed by name directly).
  local function resolveIconGroupFilename(mon)
    local game = mod.world and mod.world.game
    local data = game and game.data
    local icons = data and data.icons
    local def = data and data.pokemon and data.pokemon[mon.species]
    if not icons or not def then return nil end
    local entry = (icons.bySpecies and icons.bySpecies[mon.species]) or def.icon
    if not entry and def.dex and icons.byDex then
      entry = icons.byDex[def.dex]
    end
    return type(entry) == "string" and entry or nil
  end

  local function groupArtKeyFor(mon)
    local name = resolveIconGroupFilename(mon)
    return name and GROUP_ART_KEYS[name:upper()] or nil
  end

  -- Custom type-icon sprites -- one small 16x16 PNG per Gen 1 type,
  -- shipped in the mod's own roam_sprites/ folder. Kept as a fallback
  -- tier under group art -- still useful for any species whose group
  -- resolution fails, or before you've drawn all 10 group icons.
  -- trueColor = true skips the DMG/GBC palette remap meant for
  -- ROM-derived art, since this is original art with its own colors.
  --
  -- mod.content.sprites:register(...) IS a confirmed real registry --
  -- proven by the NORMAL type icon actually rendering correctly earlier.
  local TYPE_SPRITE_FILES = {
    NORMAL = "roam_sprites/type_NORMAL.png",
    WATER = "roam_sprites/type_WATER.png",
    -- FIRE, ELECTRIC, GRASS, ICE, FIGHTING, POISON, GROUND,
    -- FLYING, PSYCHIC, BUG, ROCK, GHOST, DRAGON -- add here as art
    -- becomes available, same { key, file } shape.
  }

  local TYPE_SPRITE_KEYS = {}
  for typeName, file in pairs(TYPE_SPRITE_FILES) do
    -- The registration pcall below only protects the registration call
    -- itself, which just stores a path string. The actual image load is
    -- lazy -- it happens later, at NPC-spawn time, deep in engine code we
    -- don't control and can't wrap. A missing file there is a hard crash,
    -- not a graceful failure (confirmed by testing). Check the file is
    -- genuinely present FIRST, using love.filesystem.getInfo (a normal,
    -- always-available LOVE call, not an engine-internal one) -- only
    -- register/use a key when the art actually exists on disk.
    local fullPath = mod.path .. "/" .. file
    local exists = love.filesystem and love.filesystem.getInfo
      and love.filesystem.getInfo(fullPath) ~= nil
    if not exists then
      Logger.warn("pokemon_farm: %s not found, %s type will use the placeholder sprite", file, typeName)
    else
      local key = "pokemon_farm_type_" .. typeName:lower()
      local ok = pcall(function()
        mod.content.sprites:register(key, {
          image = fullPath,
          frames = 1,
          trueColor = true,
        })
      end)
      if ok then
        TYPE_SPRITE_KEYS[typeName] = key
      else
        Logger.warn("pokemon_farm: could not register sprite for type %s (mod.content.sprites may not be a real registry name)", typeName)
      end
    end
  end

  local nextRoamId = 1
  local roamers = {}  -- roamId -> npcId, in-memory only (see scope note above)

  -- The species-def type field name is unconfirmed -- try the shapes
  -- that seem most plausible given how nameOf() reads game.data.pokemon
  -- elsewhere in this file. Whichever one is real, this needs live
  -- testing to confirm; the others are dead branches until then.
  local function typeOfMon(mon)
    local game = mod.world and mod.world.game
    local def = game and game.data and game.data.pokemon and game.data.pokemon[mon.species]
    if not def then return nil end
    if type(def.type1) == "string" then return def.type1 end
    if type(def.types) == "table" and def.types[1] then return def.types[1] end
    if type(def.type) == "string" then return def.type end
    return nil
  end

  local function spriteForMon(mon)
    -- Group art first (matches the real menu's own species-to-icon
    -- resolution, custom-drawn so it's always crisp), then the type
    -- icon as a fallback, then the borrowed-NPC placeholder last.
    local group = groupArtKeyFor(mon)
    if group then return group end
    local t = typeOfMon(mon)
    local key = t and TYPE_SPRITE_KEYS[t:upper()]
    return key or ROAMER_SPRITE
  end

  local function objectIndexFor(mapId)
    -- objDef.index must be unique per map; base it off our own counter,
    -- offset well clear of the map's real object count to avoid clashing
    -- with existing vanilla NPCs/items.
    local mapDef = mod.content.maps:get(mapId)
    local base = (mapDef and mapDef.objects and #mapDef.objects or 0) + 1000
    return base + nextRoamId
  end

  -- Roaming itself is already safe -- confirmed by reading Collision.lua
  -- directly: verdict() checks map:inBounds() against the CURRENT map's
  -- own dimensions, and its own comment says out-of-bounds is blocked
  -- there, with "the OverworldController handles map connections and
  -- edge warps before asking" -- meaning only the PLAYER's own movement
  -- code ever crosses a connection; the generic NPC wander logic never
  -- does. Roamers can't walk out of POKEMON_FARM no matter how they
  -- wander. The only real gap is the SPAWN position itself, which had no
  -- bounds check at all -- clamp it to the farm's real interior here,
  -- read from the actual registered map rather than hardcoded, with a
  -- margin to stay clear of the border ring.
  local FARM_SPAWN_BOUNDS = (function()
    local def = mod.content.maps:get("POKEMON_FARM")
    if not def or not def.width or not def.height then return nil end
    local margin = 2
    return {
      minX = margin, maxX = (def.width * 2) - 1 - margin,
      minY = margin, maxY = (def.height * 2) - 1 - margin,
    }
  end)()

  local function clampToFarmBounds(x, y)
    if not FARM_SPAWN_BOUNDS then return x, y end
    local b = FARM_SPAWN_BOUNDS
    return math.max(b.minX, math.min(b.maxX, x)),
           math.max(b.minY, math.min(b.maxY, y))
  end

  local function spawnRoamer(mon)
    if roamers[mon.roamId] then return end
    local sprite = spriteForMon(mon)
    if not sprite then return end
    local pos = mod.world and mod.world:current()
    -- Now that POKEMON_FARM is a real, walkable place (built in Tiled),
    -- roamers belong there instead of Pallet Town, which was only ever a
    -- stopgap before this map existed.
    if not pos or pos.mapId ~= "POKEMON_FARM" then return end
    local ox = love.math and love.math.random(-3, 3) or 0
    local oy = love.math and love.math.random(-3, 3) or 0
    local spawnX, spawnY = clampToFarmBounds(pos.x + ox, pos.y + oy)
    local objDef = {
      index = objectIndexFor("POKEMON_FARM"),
      sprite = sprite,
      x = spawnX, y = spawnY,
      range = "ANY_DIR",
      movement = "WALK",
      -- Not a field the engine reads (talkTo only checks d.text/d.item/
      -- d.pokemon), so this is a safe place to tag which mon a roamer
      -- represents -- read back in the talkTo intercept below. roamId
      -- lets talkTo find THIS mon's own save.farm record (for a
      -- per-mon closeness counter), not just its species.
      pokemonFarmSpecies = mon.species,
      pokemonFarmRoamId = mon.roamId,
    }
    local npcId = mod.world:spawnNpc("POKEMON_FARM", objDef)
    if npcId then roamers[mon.roamId] = npcId end
  end

  local function despawnRoamer(mon)
    local npcId = mon.roamId and roamers[mon.roamId]
    if npcId then
      mod.world:removeNpc(npcId)
      roamers[mon.roamId] = nil
    end
  end

  ------------------------------------------------------------------
  -- talking to a roamer -- confirmed via real source (PikachuFollower.lua,
  -- OverworldController.lua, both read directly, not guessed):
  --   * OverworldState:talkTo(npc) reads npc.def (our own objDef) and
  --     checks d.text / d.item / d.pokemon in sequence -- since our
  --     objDef has none of those, it currently falls through to nothing.
  --     pokemonFarmSpecies (tagged above) isn't one of those fields, so
  --     it's a safe place to mark our own NPCs without disturbing that
  --     resolution chain for anyone else's.
  --   * Sound.playCry(data, species) is the real, generic cry player --
  --     confirmed at PikachuFollower.lua:723 (Sound.playCry(game.data,
  --     "PIKACHU")), not Pikachu-specific despite living in that file.
  --   * TextBox.new(game, text, callback) accepts a third callback arg,
  --     confirmed from talkTo's own wild-encounter branch.
  --
  -- require("src.world.OverworldController") is INFERRED, not directly
  -- observed -- every other file in this same folder (Map, NPC,
  -- Collision, MapLoader, WorldAPI...) has followed the exact
  -- src.world.<Filename> pattern with zero exceptions all session, but
  -- this one specific path was never seen requiring itself. pcall
  -- wrapped so a wrong guess fails quietly instead of crashing the mod.
  ------------------------------------------------------------------

  do
    local ok, OverworldState = pcall(require, "src.world.OverworldController")
    if ok and OverworldState and OverworldState.talkTo then
      local innerTalkTo = OverworldState.talkTo
      -- Gen 1 has no real happiness/friendship stat to reflect -- confirmed
      -- from Pokemon.lua's own Pokemon.new() constructor, which only ever
      -- sets species/level/exp/dvs/statExp/stats/hp/catchRate/status/moves.
      -- (Gen 2's Happiness.lua is real in this engine, but it's part of
      -- the Gen 2 data model specifically -- a Gen 1 Blue mon genuinely
      -- has nothing to hook into.) This is our own simple analog instead:
      -- a plain per-mon talk counter, stored right on the mon's own
      -- save.farm record since that's already a real, persisted table.
      local CLOSENESS_MESSAGES = {
        { threshold = 1, text = " looks up at you." },
        { threshold = 2, text = " seems curious about you." },
        { threshold = 4, text = " seems to like you." },
        { threshold = 7, text = " seems very happy to see you!" },
      }
      local function closenessMessage(count)
        local msg = CLOSENESS_MESSAGES[1].text
        for _, entry in ipairs(CLOSENESS_MESSAGES) do
          if count >= entry.threshold then msg = entry.text end
        end
        return msg
      end

      function OverworldState:talkTo(npc, ...)
        local d = npc and npc.def
        local species = d and d.pokemonFarmSpecies
        if species then
          local game = mod.world and mod.world.game
          if game then
            local Sound = require("src.core.Sound")
            pcall(Sound.playCry, game.data, species)
            local sdef = game.data.pokemon and game.data.pokemon[species]
            local name = sdef and sdef.name or species

            local mon
            for _, m in ipairs(ensureFarm(game.save)) do
              if m.roamId == d.pokemonFarmRoamId then mon = m break end
            end
            if mon then
              mon.farmTalkCount = (mon.farmTalkCount or 0) + 1
            end

            npc.frozen = true
            game.stack:push(TextBox.new(game,
              name .. closenessMessage(mon and mon.farmTalkCount or 1),
              function() npc.frozen = false end))
          end
          return
        end
        return innerTalkTo(self, npc, ...)
      end
    else
      Logger.warn("pokemon_farm: could not hook OverworldState.talkTo -- roamer interaction will be silent")
    end
  end

  -- Spawn a roamer for every farmed Pokemon that doesn't already have one
  -- (a fresh boot, or the player having just arrived in Pallet Town).
  -- Cheap and idempotent -- safe to call from any natural touchpoint.
  local function syncRoamers(game)
    for _, mon in ipairs(ensureFarm(game.save)) do
      if not mon.roamId then
        mon.roamId = nextRoamId
        nextRoamId = nextRoamId + 1
      end
      if not roamers[mon.roamId] then spawnRoamer(mon) end
    end
  end

  local function currentBox(game)
    Boxes.ensure(game.save)
    return game.save.boxes[game.save.currentBox]
  end

  local function nameOf(game, mon)
    local def = game.data.pokemon[mon.species]
    return mon.nickname or (def and def.name) or mon.species or "?"
  end

  local function sendList(game)
    local out = {}
    for i, mon in ipairs(game.save.party) do
      out[#out + 1] = { mon = mon, source = game.save.party, index = i, from = "party" }
    end
    local box = currentBox(game)
    for i, mon in ipairs(box) do
      out[#out + 1] = { mon = mon, source = box, index = i, from = "box" }
    end
    return out
  end

  local function farmList(game)
    local farm = ensureFarm(game.save)
    local out = {}
    for i, mon in ipairs(farm) do
      out[#out + 1] = { mon = mon, source = farm, index = i, from = "farm" }
    end
    return out
  end

  local function sendToFarm(game, entry)
    -- Same rule gen3_box enforces on its own grab(): the party may not be
    -- emptied. Check before removing anything, not after.
    if entry.from == "party" and #game.save.party <= 1 then
      return false, "That's your last one!"
    end
    local mon = table.remove(entry.source, entry.index)
    if not mon then return false, "Nothing there." end
    table.insert(ensureFarm(game.save), mon)
    mon.roamId = nextRoamId
    nextRoamId = nextRoamId + 1
    spawnRoamer(mon)
    local groupName = resolveIconGroupFilename(mon)
    local msg = nameOf(game, mon) .. " went to the farm. (icon group: "
      .. tostring(groupName or "none found") .. ")"
    return true, msg
  end

  local function reclaimFromFarm(game, entry)
    local mon = table.remove(entry.source, entry.index)
    if not mon then return false, "Nothing there." end
    despawnRoamer(mon)

    if #game.save.party < Party.MAX then
      table.insert(game.save.party, mon)
      return true, nameOf(game, mon) .. " came back to your party."
    end

    local box = currentBox(game)
    if #box < Boxes.CAPACITY then
      table.insert(box, mon)
      return true, nameOf(game, mon) .. " came back to the box."
    end

    table.insert(ensureFarm(game.save), mon)
    spawnRoamer(mon)  -- didn't fit anywhere -- back on the farm, roaming again
    return false, "No room in Party or Box."
  end

  ------------------------------------------------------------------
  -- menus -- confirmed ListMenu/TextBox pattern from MULTI_SAVE_SLOTS
  ------------------------------------------------------------------

  local function say(game, msg)
    game.stack:push(TextBox.new(game, msg))
  end

  local function sendRows(game)
    local out = {}
    for _, entry in ipairs(sendList(game)) do
      out[#out + 1] = {
        label = Strings("%s :L%d (%s)", nameOf(game, entry.mon), entry.mon.level or 0, entry.from),
        value = entry,
      }
    end
    return out
  end

  local function farmRows(game)
    local out = {}
    for _, entry in ipairs(farmList(game)) do
      out[#out + 1] = {
        label = Strings("%s :L%d", nameOf(game, entry.mon), entry.mon.level or 0),
        value = entry,
      }
    end
    return out
  end

  -- Shared shape: build rows, bail with a message if empty, otherwise push
  -- a ListMenu and rebuild it in place after each action rather than
  -- closing and reopening -- same pattern MULTI_SAVE_SLOTS uses for its
  -- delete-slot list.
  local function openListAction(game, title, rowsFn, actionFn, emptyMsg)
    local rows = rowsFn(game)
    if #rows == 0 then
      say(game, Strings(emptyMsg))
      return
    end

    local function rebuild(menu)
      menu.items = rowsFn(game)
      menu.index = math.max(1, math.min(menu.index or 1, #menu.items))
      menu.scroll = 0
      if #menu.items == 0 and menu.close then menu:close() end
    end

    game.stack:push(ListMenu.new(game, Strings(title), rows, {
      onChoose = function(item, menu)
        local ok, msg = actionFn(game, item.value)
        say(game, msg)
        rebuild(menu)
      end,
    }))
  end

  local function openSendMenu(game)
    openListAction(game, "SEND TO FARM", sendRows, sendToFarm, "Nothing to send.")
  end

  local function openFarmMenu(game)
    openListAction(game, "FARM", farmRows, reclaimFromFarm, "Farm is empty.")
  end

  local function openFarmHub(game)
    syncRoamers(game)
    local count = #ensureFarm(game.save)
    local rows = {
      { label = Strings("SEND TO FARM"), value = "send" },
      { label = Strings("VIEW FARM (%d)", count), value = "view" },
    }
    game.stack:push(ListMenu.new(game, Strings("FARM"), rows, {
      onChoose = function(item)
        if item.value == "send" then
          openSendMenu(game)
        else
          openFarmMenu(game)
        end
      end,
    }))
  end

  ------------------------------------------------------------------
  -- reaching it
  ------------------------------------------------------------------

  mod.hooks:wrap("ui.start_menu.items", function(next, game, items)
    local out = next(game, items)
    if type(out) ~= "table" or not onStart() then return out end
    return mod.ui.insertBefore(out, "SAVE", {
      label = Strings("FARM"),
      onSelect = function() openFarmHub(game) end,
    })
  end)

  local BOX_ROWS = { "BILL'S PC", "SOMEONE'S PC" }

  mod.hooks:wrap("ui.pc.items", function(next, game, items)
    local out = next(game, items)
    if type(out) ~= "table" or not onPC() then return out end
    local row = {
      label = Strings("FARM"),
      onSelect = function() openFarmHub(game) end,
    }
    for _, anchor in ipairs(BOX_ROWS) do
      for _, entry in ipairs(out) do
        if entry.label == anchor then
          return mod.ui.insertAfter(out, anchor, row)
        end
      end
    end
    table.insert(out, 1, row)
    return out
  end)
end
