Static prop art, cycled with U, placed with T, removed with Y:
  prop_seed.png, prop_grass.png, prop_tree.png, prop_fence.png, prop_house.png
Each 16x16, transparent background. Same spec as roam_sprites/.

Unlike the old block-placement system, these are stationary custom-art
NPCs -- exact single-cell placement, no block-ID guessing, no parity
math. Anything without art yet just can't be placed (T will show
"<name> has no art yet.") until you draw it.
