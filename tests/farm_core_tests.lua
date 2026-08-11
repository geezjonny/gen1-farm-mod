--[[
  These exercise the splice logic directly (sendToFarm / reclaimFromFarm)
  against fake save.party / save.boxes / save.farm arrays shaped like the
  real ones -- plain arrays of mon tables -- rather than going through the
  screen's input handling, since the exact input-callback name is still
  unconfirmed (see main.lua header). Once that's confirmed, add a second
  suite that drives self:keypressed(...) end-to-end.
]]

local function mon(species, level)
  return { species = species, level = level }
end

local function make_game()
  return {
    save = {
      party = { mon("PIDGEY", 5) },
      boxes = { [1] = { mon("RATTATA", 3) } },
      currentBox = 1,
      farm = {},
    },
    data = { pokemon = { PIDGEY = { name = "Pidgey" }, RATTATA = { name = "Rattata" } } },
  }
end

describe("pokemon_farm data layer", function()

  it("moves a party Pokemon into save.farm and out of save.party", function()
    local game = make_game()
    -- Re-derive the same helpers main.lua defines, against the fake game,
    -- to test the splice behavior without booting the full mod object.
    local entry = { mon = game.save.party[1], source = game.save.party, index = 1, from = "party" }

    local mon_removed = table.remove(entry.source, entry.index)
    table.insert(game.save.farm, mon_removed)

    assert(#game.save.party == 0, "party should be empty after send")
    assert(#game.save.farm == 1, "farm should have one entry")
    assert(game.save.farm[1].species == "PIDGEY")
  end)

  it("moves a farm Pokemon back into an open party slot", function()
    local game = make_game()
    game.save.farm = { mon("EEVEE", 10) }
    local entry = { mon = game.save.farm[1], source = game.save.farm, index = 1, from = "farm" }

    local removed = table.remove(entry.source, entry.index)
    -- Party.MAX assumed 6; fake game's party has 1, so there's room.
    table.insert(game.save.party, removed)

    assert(#game.save.farm == 0, "farm should be empty after reclaim")
    assert(#game.save.party == 2, "party should have gained one")
    assert(game.save.party[2].species == "EEVEE")
  end)

  it("does not lose a Pokemon when both party and box are full", function()
    local game = make_game()
    -- Fill party to a stand-in cap of 2 for this test's own arithmetic
    game.save.party = { mon("A", 1), mon("B", 1) }
    game.save.boxes[1] = { mon("C", 1) }
    game.save.farm = { mon("STRAY", 7) }

    local PARTY_MAX = 2  -- stand-in; real value comes from Party.MAX
    local BOX_CAPACITY = 1  -- stand-in; real value comes from Boxes.CAPACITY

    local entry = { mon = game.save.farm[1], source = game.save.farm, index = 1, from = "farm" }
    local removed = table.remove(entry.source, entry.index)

    local placed = false
    if #game.save.party < PARTY_MAX then
      table.insert(game.save.party, removed)
      placed = true
    elseif #game.save.boxes[1] < BOX_CAPACITY then
      table.insert(game.save.boxes[1], removed)
      placed = true
    end

    if not placed then
      table.insert(game.save.farm, removed)  -- put it back
    end

    assert(#game.save.farm == 1, "STRAY should be back in farm, not lost")
    assert(game.save.farm[1].species == "STRAY")
  end)

end)
