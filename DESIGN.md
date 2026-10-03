# BlockMash – Design Notes

BlockMash is a non-commercial browser block game built on zardoy/minecraft-web-client (MIT) with a local
flying-squid server (singleplayer, protocol 1.14.4). PureBDcraft 128x is the only texture source.

## World layers
- **Underground: vanilla-style.** Stone/deepslate-like layers, caves (3D noise worms), ores at vanilla-like
  depths (coal, iron, gold, redstone, lapis, diamond, emerald), bedrock floor, water/lava pockets.
- **Surface: Minecraft + mashup mixed.** Normal biomes (grass, forest, desert, snow, beaches, oceans) and
  Minecraft elements stay: villages (houses, farms, paths, well), iron golems, villagers, animals, hostile mobs at
  night, inventory, player, GUI, chat. The mashup zones are *added* among them and replace nothing:
  - **Duke3D zones** – city blocks: asphalt streets, concrete/brick high-rises, neon signs, "XXX"-style bars
    (kept tame), crates with ammo and pipebombs, alien troopers/pig cops (phase 3).
  - **Dark Mod zones** – medieval/steampunk quarters: cobbled alleys, timbered houses, manor with vault,
    gas lamps, guards; loot items (coins, goblets, keys), blackjack, broadhead/water arrows (phase 4).
  - **Yorg zones** – race tracks: banked asphalt circuit with kerbs, start grid, checkpoints and drivable karts (phase 5).
- **Everything is blocks.** Every structure is made of normal minable blocks. TNT and Duke pipebombs blow holes
  in buildings and terrain alike; the vanilla underground shows through.

## Zone placement
The world is split into 256×256 regions; a seeded hash picks *vanilla only* (~55 %), Duke city, Dark Mod
quarter or Yorg track for each region. Zones flatten/blend into the surrounding terrain at the region border and only
touch Y ≥ surface-6, so caves and ores below are untouched. The spawn region always contains a village and a
signpost pointing to the nearest zone of each type.

## Implementation
- `src/mashup/generator.js` – flying-squid generation (`generation.name: 'blockmash'`), deterministic per seed.
- `src/mashup/*` – zone builders, entity/weapon logic as flying-squid plugins + client HUD.
- Content from GPL games is reimplemented/adapted; data files are only used where their license allows
  redistribution (see ASSETS_AUDIT.md and credits.html).
