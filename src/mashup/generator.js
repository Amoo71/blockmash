// BlockMash world generation for flying-squid.
// Underground: vanilla-style (stone variants, caves, ores, lava, bedrock).
// Surface: vanilla biomes + villages, mixed with mashup zones (Duke city, Dark Mod quarter, Yorg track).
'use strict'
const { Vec3 } = require('vec3')
const { rnd2, rnd3, hash2, hash3, value3 } = require('./noise')
const layout = require('./layout')
const { getDuke } = require('./surface/dukeworld')
const makeResolver = require('./blocks')
const ZONES = {
  village: require('./zones/village'),
  duke: require('./zones/duke'),
  darkmod: require('./zones/darkmod'),
  yorg: require('./zones/yorg')
}
const BIOME_ID = { ocean: 0, plains: 1, desert: 2, forest: 4, snowy: 12, beach: 16 }

function generation ({ version, seed = 1 } = {}) {
  const Chunk = require('prismarine-chunk')(version)
  const mcData = require('minecraft-data')(version)
  const S = makeResolver(mcData)
  seed |= 0
  const B = new Proxy({}, { get: (_, n) => S(n) })
  const ORES = [
    { b: 'coal_ore', max: 128, p: 0.012, k: 11 },
    { b: 'iron_ore', max: 64, p: 0.009, k: 12 },
    { b: 'gold_ore', max: 32, p: 0.0025, k: 13 },
    { b: 'redstone_ore', max: 16, p: 0.008, k: 14 },
    { b: 'lapis_ore', max: 31, p: 0.002, k: 15 },
    { b: 'diamond_ore', max: 15, p: 0.0018, k: 16 }
  ]
  const STONES = ['granite', 'diorite', 'andesite', 'dirt', 'gravel']
  const AIR = 0
  const col = new Int32Array(256)

  function isCave (x, y, z) {
    const a = value3(x / 28, y / 18, z / 28, seed + 1)
    const b = value3(x / 28, y / 18, z / 28, seed + 2)
    if (a * a + b * b < 0.012) return true
    return y > 14 && y < 48 && value3(x / 50, y / 30, z / 50, seed + 3) > 0.58
  }

  function trees (x, z, info, put) {
    // surface mode: only a 3-block log trunk (hidden inside the client's low-poly tree) so wood stays obtainable
    if (((x % 6) + 6) % 6 === 0 || true) {
      const t = layout.treeInCell(Math.floor((x - 1) / 6), Math.floor((z - 1) / 6), seed)
      if (!t || t.x !== x || t.z !== z) return
      for (let y = info.h + 1; y < info.h + 4; y++) put(y, t.kind + '_log', true)
    }
  }

  // surface mode: the visible surface is polygon geometry rendered by the client (src/mashup/client/surface*.ts);
  // structures of the Dark Mod quarter / Yorg track become invisible collision (barrier) + kept interactive blocks
  const KEEP_DM = /^(lantern|campfire|chest|bookshelf|lectern|furnace|blast_furnace|smoker|anvil|grindstone|hopper|cauldron|crafting_table|water|iron_block|gold_block|iron_bars|dark_oak_door.*)$/
  const surfacePut = (type, G, put) => (y, spec, force = true) => {
    const name = spec.split('[')[0]
    if (y <= G) {
      if (name === 'coarse_dirt') return put(y, 'grass_block', force)
      return put(y, spec, force)
    }
    if (type === 'darkmod') {
      if (KEEP_DM.test(spec) || name === 'water') return put(y, spec, force)
      if (/stairs|slab|planks|ladder|_wall$/.test(name)) return
      return put(y, 'barrier', force)
    }
    if (type === 'yorg') { if (name === 'barrel' || name === 'air') return; return put(y, 'barrier', force) }
    return put(y, spec, force)
  }
  const HS = new Float32Array(17 * 17)

  return function generateChunk (chunkX, chunkZ) {
    const chunk = new Chunk()
    const pos = new Vec3(0, 0, 0)
    for (let a = 0; a <= 16; a++) for (let b = 0; b <= 16; b++) HS[a * 17 + b] = layout.surfaceHeight(chunkX * 16 + a, chunkZ * 16 + b, seed)
    const dm = getDuke(seed)
    for (let i = 0; i < 16; i++) {
      for (let k = 0; k < 16; k++) {
        const x = chunkX * 16 + i; const z = chunkZ * 16 + k
        const info = layout.columnInfo(x, z, seed)
        // block top must stay below all 4 corners of the smooth surface cell above it
        info.h = Math.floor(Math.min(HS[i * 17 + k], HS[(i + 1) * 17 + k], HS[i * 17 + k + 1], HS[(i + 1) * 17 + k + 1]) - 0.01) - 1
        const dcol = dm && dm.col(x, z)
        const inDuke = dcol && dcol.kind !== 0
        if (inDuke) { info.h = dcol.top - 1; info.biome = 'plains'; info.w = 1; info.G = dcol.top - 1 }
        const { h, biome } = info
        col.fill(AIR)
        const put = (y, spec, force = true) => {
          if (y < 1 || y > 255) return
          if (!force && col[y] !== AIR) return
          col[y] = S(spec)
        }
        // --- underground (vanilla style)
        const soil = biome === 'desert' ? 4 : 3 + (hash2(x, z, seed) & 1)
        const caveTop = info.w > 0 ? Math.min(h - 7, info.G - 10) : h - 6
        col[0] = B.bedrock
        for (let y = 1; y <= h; y++) {
          let b
          if (y <= 4 && rnd3(x, y, z, seed) < (5 - y) / 5) b = B.bedrock
          else if (y > h - soil) {
            if (biome === 'desert' || biome === 'beach') b = y > h - 3 ? B.sand : B.sandstone
            else if (biome === 'ocean') b = y === h ? (rnd2(x, z, seed) < 0.3 ? B.gravel : B.sand) : B.dirt
            else b = y === h ? (biome === 'snowy' ? S('grass_block[snowy=true]') : B.grass_block) : B.dirt
          } else {
            b = B.stone
            const bl = value3(x / 12, y / 10, z / 12, seed + 40)
            if (bl > 0.62) b = S(STONES[hash3(x >> 4, y >> 4, z >> 4, seed) % STONES.length])
            for (const o of ORES) {
              if (y <= o.max && hash3(x >> 1, y >> 1, z >> 1, seed ^ o.k) / 4294967296 < o.p * 2.5 && rnd3(x, y, z, seed ^ o.k) < 0.55) { b = S(o.b); break }
            }
            if (y > 4 && y < caveTop && isCave(x, y, z)) b = y <= 9 ? B.lava : AIR
          }
          col[y] = b
        }
        // water
        if (h < layout.WATER) for (let y = h + 1; y <= layout.WATER; y++) col[y] = B.water
        if (h < layout.WATER && biome === 'ocean' && info.w === 0) {
          const t = layout.biomeAt(x, z, seed, 70)
          if (t === 'snowy') col[layout.WATER] = B.ice
        }
        // --- surface: zones or vanilla decoration
        const Z = !inDuke && info.inCore && !(info.type === 'duke' && dm) && ZONES[info.type]
        if (inDuke) {
          col[h] = S('smooth_stone') // not "natural" -> no terrain mesh; the Duke floor polygons sit on top
          if (dcol.bar1 > dcol.bar0) for (let y = dcol.bar0; y < dcol.bar1; y++) put(y, 'barrier')
        } else if (Z) {
          Z.column(info.u, info.v, info.G, info.type === 'village' ? put : surfacePut(info.type, info.G, put), { seed, rx: info.rx, rz: info.rz })
        } else if (h >= layout.WATER) {
          // natural surface: no block plants/snow; trees = hidden log trunk inside the client's low-poly tree mesh
          if (info.w < 0.5) trees(x, z, info, put)
        } else if (false) {
          const r = rnd2(x, z, seed ^ 0xdec)
          if (biome === 'plains' || biome === 'forest') {
            if (r < 0.1) put(h + 1, 'grass')
            else if (r < 0.115 && biome === 'plains') put(h + 1, ['dandelion', 'poppy', 'cornflower', 'oxeye_daisy', 'azure_bluet'][hash2(x, z, seed) % 5])
            else if (r < 0.125 && biome === 'forest') put(h + 1, r < 0.12 ? 'fern' : 'brown_mushroom')
          } else if (biome === 'desert') {
            if (r < 0.006) put(h + 1, 'dead_bush')
            else if (r < 0.01 && info.w === 0) { const ch = 1 + hash2(x, z, seed) % 3; for (let y = 1; y <= ch; y++) put(h + y, 'cactus') }
          } else if (biome === 'beach' && h === layout.WATER && r < 0.03) {
            for (let y = 1; y <= 2; y++) put(h + y, 'sugar_cane')
          }
          if (info.w < 0.5) trees(x, z, info, put)
          if (biome === 'snowy') { let top = 255; while (top > 0 && col[top] === AIR) top--; if (col[top] !== B.water && top < 255) col[top + 1] = B.snow }
        }
        // --- write column
        pos.x = i; pos.z = k
        for (let y = 0; y < 256; y++) {
          pos.y = y
          if (col[y] !== AIR) chunk.setBlockStateId(pos, col[y])
          chunk.setSkyLight(pos, 15)
        }
        pos.y = 0
        if (chunk.setBiome) chunk.setBiome(pos, BIOME_ID[biome] ?? 1)
      }
    }
    return chunk
  }
}

module.exports = generation
module.exports.layout = layout
