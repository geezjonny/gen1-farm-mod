-- PALLET_TOWN (patch): exported from Tiled by gen1-mod-export.
-- Applied by main.lua; see the mod README.
return function(mod)
  mod.content.maps:patch("PALLET_TOWN", {
    width = 10,
    height = 9,
    blocks = {
       82,  79,  82,  82,  79,  11,  80,  82,  82,  80,
       78,   1,  56,  57,   1,   1,  56,  57,   1,  77,
       78,   8,  60,  61,   1,   8,  60,  61,   1,   1,
       78,   1,   1,   1,   1,   1,   1,   1,   1,   1,
       78,   1, 119,  86,   1,  12,  13,  14,   1,   1,
       78,   1, 116, 116,   1,  16,  58,   0,   1,  77,
       78,   1,   1,   1,   1, 119,  86, 119,  49,  77,
       78,  10,  29,  30,  49, 116, 116,  10,  49,  77,
       80,  10, 101, 100,  97,  97,  97,  97,  97,  79,
    },
    connections = {
      east = { map = "POKEMON_FARM", offset = 0 },
    },
  })
end
