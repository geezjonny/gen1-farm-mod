-- POKEMON_FARM (register): exported from Tiled by gen1-mod-export.
-- Applied by main.lua; see the mod README.
return function(mod)
  mod.content.maps:register("POKEMON_FARM", {
    id = "POKEMON_FARM",
    label = "FARM",
    index = 1000,
    tileset = "OVERWORLD",
    width = 10,
    height = 9,
    borderBlock = 0,
    blocks = {
       15,  62,  63,  59, 108, 108, 108, 108,  54,  15,
       15,  36,   6,  37,  10,  10,   2,   3,  10,  15,
       15,  52,  10,  10,  10,  10,  10,  10,  10,  15,
       85,  85,  85,  85,  85,  85,  85,  85,  85,  15,
       15, 108,  10,  10,  10,  11,  11,  11,  11,  15,
       15,  76,  10,  11,  11,  11,  11,  29,  30,  15,
       15,  10,  11,  11,  11,  11,  11, 101, 100,  15,
       15,  10,  11,  11,  11,  29,  31,  46, 100,  15,
       15,  15,  15,  15,  15,  15,  15,  15,  15,  15,
    },
    connections = {
      west = { map = "PALLET_TOWN", offset = 0 },
    },
    warps = {},
    signs = {},
    objects = {},
  })
end
