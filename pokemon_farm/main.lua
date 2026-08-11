-- Pokemon Farm
--
-- The opposite of a catch-everything mod: a place for Pokemon you let go.
-- Adds a FARM screen alongside Party and Box storage. Sending a Pokemon to
-- the farm moves it out of save.party / save.boxes and into save.farm --
-- the same in-place splice gen3_box uses to move a Pokemon between box and
-- party -- rather than deleting it the way vanilla release does. Reclaiming
-- does the same thing in reverse, back into an open Party or Box slot.
--
-- Vanilla release is left completely alone. This is an additive option
-- living next to it, not a replacement -- turning the mod off just makes
-- save.farm inert data the rest of the game never looks at again.
--
-- ------- what's confirmed vs assumed
--
-- Confirmed against gen1recomp-gen3-boxes v1.5.2's actual main.lua:
--   * mods can require() engine source directly (src.pokemon.Boxes, etc.)
--   * save.boxes[save.currentBox] and save.party are the real storage
--     arrays, and Boxes.ensure(save) safely backfills them on an old save
--   * mod.content.screens:register(name, { new = fn }) registers a custom
--     full-screen UI state
--   * mod.hooks:wrap("ui.start_menu.items", function(next, game, items) ... end)
--     and the same for "ui.pc.items" -- call next() first, decorate, return
--   * mod.ui.insertBefore / insertAfter splice a menu row in by anchor label
--   * mod.options:define({...}) / mod.options:get(key)
--
-- Still ASSUMPTION (not visible in the portion of gen3_box read so far):
--   * the exact input-handling method name on a screen object -- written
--     here as self:keypressed(key), matching the love2d/VoxelMod
--     convention seen elsewhere, but gen3_box's own input handler wasn't
--     in view when this was written. Grep the full file for how it reads
--     A/B/SELECT and rename if it differs.
--   * mod.ui.pop(game) for exiting a pushed screen -- gen3_box pushes via
--     mod.ui.push(game, SCREEN) but its pop call wasn't in view either.
--   * Party.MAX and Boxes.CAPACITY are confirmed to exist (used in
--     gen3_box's header text) and are used here as the reclaim capacity
--     checks.

return function(mod)
  local Boxes = require("src.pokemon.Boxes")
  local Party = require("src.pokemon.Party")
  local Font = require("src.render.Font")
  local Strings = require("src.core.Strings")

  local SCREEN = "PokemonFarm"

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
  -- data helpers -- everything reads/writes save.party, save.boxes and
  -- save.farm directly, same posture as gen3_box's box/party helpers.
  ------------------------------------------------------------------

  local function ensureFarm(save)
    save.farm = save.farm or {}
    return save.farm
  end

  local function currentBox(game)
    Boxes.ensure(game.save)
    return game.save.boxes[game.save.currentBox]
  end

  local function nameOf(game, mon)
    local def = game.data.pokemon[mon.species]
    return mon.nickname or (def and def.name) or mon.species or "?"
  end

  -- The "send" pane: party first, then the current box, each entry tagged
  -- with where it came from so the reclaim/send action knows which live
  -- array to splice.
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

  -- Moves whatever is at entry.source[entry.index] into the farm array.
  local function sendToFarm(game, entry)
    local mon = table.remove(entry.source, entry.index)
    if not mon then return false, "Nothing there." end
    table.insert(ensureFarm(game.save), mon)
    return true, nameOf(game, mon) .. " went to the farm."
  end

  -- Moves a farm entry back out. Prefers Party if it has room, else the
  -- current Box if it has room, else refuses -- same "no room" boundary
  -- vanilla deposit/withdraw already enforces, just checked here instead
  -- of assumed.
  local function reclaimFromFarm(game, entry)
    local mon = table.remove(entry.source, entry.index)
    if not mon then return false, "Nothing there." end

    if #game.save.party < Party.MAX then
      table.insert(game.save.party, mon)
      return true, nameOf(game, mon) .. " came back to your party."
    end

    local box = currentBox(game)
    if #box < Boxes.CAPACITY then
      table.insert(box, mon)
      return true, nameOf(game, mon) .. " came back to the box."
    end

    -- put it back where it was rather than lose it
    table.insert(ensureFarm(game.save), mon)
    return false, "No room in Party or Box."
  end

  ------------------------------------------------------------------
  -- the screen
  ------------------------------------------------------------------

  local function newScreen(game)
    ensureFarm(game.save)

    local self = {
      game = game,
      isOpaque = true,
      mode = "send",   -- "send" (party+box, pick one to farm) | "farm" (reclaim)
      index = 1,
      notice = nil,
      noticeAt = 0,
    }

    function self:uiSize()
      return 160, 144
    end

    local function list()
      return self.mode == "send" and sendList(self.game) or farmList(self.game)
    end

    local function clampIndex()
      local n = #list()
      if n == 0 then self.index = 1
      elseif self.index > n then self.index = n
      elseif self.index < 1 then self.index = 1 end
    end

    local function say(msg)
      self.notice = msg
      self.noticeAt = love.timer and love.timer.getTime() or 0
    end

    -- ASSUMPTION: input arrives here as self:keypressed(key) -- see header
    -- note. Rename to match the confirmed input method once checked
    -- against the rest of gen3_box or another screen mod.
    function self:keypressed(key)
      local set = list()

      if key == "up" or key == "down" then
        if #set > 0 then
          local delta = (key == "down") and 1 or -1
          self.index = ((self.index - 1 + delta) % #set) + 1
        end
        return
      end

      if key == "select" or key == "tab" then
        self.mode = (self.mode == "send") and "farm" or "send"
        self.index = 1
        return
      end

      if key == "a" or key == "return" then
        clampIndex()
        local entry = set[self.index]
        if not entry then say("Nothing selected.") return end

        local ok, msg
        if self.mode == "send" then
          ok, msg = sendToFarm(self.game, entry)
        else
          ok, msg = reclaimFromFarm(self.game, entry)
        end
        say(msg)
        clampIndex()
        return
      end

      if key == "b" or key == "escape" then
        if mod.ui.pop then mod.ui.pop(self.game) end
        return
      end
    end

    function self:draw()
      love.graphics.clear(1, 1, 1, 1)
      love.graphics.setColor(0, 0, 0, 1)

      local set = list()
      clampIndex()

      local title = self.mode == "send"
        and Strings("SEND TO FARM  %d", #set)
        or  Strings("FARM  %d", #set)
      Font.draw(title, 4, 2)

      local rowY = 16
      local visibleRows = 8
      local top = math.max(1, self.index - math.floor(visibleRows / 2))
      for row = 0, visibleRows - 1 do
        local i = top + row
        local entry = set[i]
        if not entry then break end
        local prefix = (i == self.index) and "> " or "  "
        local label = nameOf(self.game, entry.mon) .. " :L" .. tostring(entry.mon.level or 0)
        if self.mode == "send" and entry.from then
          label = label .. " (" .. entry.from .. ")"
        end
        Font.draw(prefix .. label, 4, rowY + row * 14)
      end

      if #set == 0 then
        Font.draw(self.mode == "send" and "Nothing to send." or "Farm is empty.", 4, rowY)
      end

      local footer
      if self.notice then
        local now = love.timer and love.timer.getTime() or 0
        if now - self.noticeAt < 1.5 then footer = self.notice else self.notice = nil end
      end
      footer = footer or "A:CONFIRM  SELECT:SWITCH  B:EXIT"
      Font.draw(footer, 4, 132)
    end

    return self
  end

  mod.content.screens:register(SCREEN, { new = newScreen })

  ------------------------------------------------------------------
  -- reaching it -- same call-next-first pattern as gen3_box, so another
  -- mod's row on the same menu survives instead of being overwritten.
  ------------------------------------------------------------------

  mod.hooks:wrap("ui.start_menu.items", function(next, game, items)
    local out = next(game, items)
    if type(out) ~= "table" or not onStart() then return out end
    return mod.ui.insertBefore(out, "SAVE", {
      label = Strings("FARM"),
      onSelect = function() mod.ui.push(game, SCREEN) end,
    })
  end)

  local BOX_ROWS = { "BILL'S PC", "SOMEONE'S PC" }

  mod.hooks:wrap("ui.pc.items", function(next, game, items)
    local out = next(game, items)
    if type(out) ~= "table" or not onPC() then return out end
    local row = {
      label = Strings("FARM"),
      onSelect = function() mod.ui.push(game, SCREEN) end,
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
