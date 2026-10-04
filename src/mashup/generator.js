// BlockMash world generation for flying-squid.
// Underground: vanilla-style (stone variants, caves, ores, lava, bedrock).
// Surface: vanilla biomes + villages, mixed with mashup zones (Duke city, Dark Mod quarter, Yorg track).
'use strict'
const { Vec3 } = require('vec3')
const { rnd2, rnd3, hash2, hash3, value3 } = require('./noise')
const layout = require('./layout')
const { getDuke } = require('./surface/dukeworld')
const { getYorg } = require('./surface/yorgworld')
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
    // trees are placed per 6x6 cell; canopies can reach into neighbouring columns/chunks
    const cx0 = Math.floor((x - 3) / 6); const cx1 = Math.floor((x + 3) / 6)
    const cz0 = Math.floor((z - 3) / 6); const cz1 = Math.floor((z + 3) / 6)
    for (let cx = cx0; cx <= cx1; cx++) {
      for (let cz = cz0; cz <= cz1; cz++) {
        const hh = hash2(cx, cz, seed ^ 0x7ee)
        const tx = cx * 6 + 1 + (hh & 3); const tz = cz * 6 + 1 + ((hh >>> 2) & 3)
        const dx = x - tx; const dz = z - tz
        if (Math.abs(dx) > 2 || Math.abs(dz) > 2) continue
        const ti = dx === 0 && dz === 0 ? info : layout.columnInfo(tx, tz, seed)
        if (ti.w > 0.02 || ti.h <= layout.WATER) continue
        const dens = { forest: 0.75, plains: 0.07, snowy: 0.35 }[ti.biome] || 0
        if (((hh >>> 4) & 1023) / 1024 >= dens) continue
        const kind = ti.biome === 'snowy' ? 'spruce' : ti.biome === 'forest' && ((hh >>> 14) & 3) === 0 ? 'birch' : 'oak'
        const th = 4 + ((hh >>> 16) % 3) + (kind === 'spruce' ? 2 : 0)
        const base = ti.h + 1; const top = base + th
        const log = kind + '_log'; const leaves = kind + '_leaves[persistent=true]'
        if (dx === 0 && dz === 0) for (let y = base; y < top; y++) put(y, log, true)
        const ad = Math.max(Math.abs(dx), Math.abs(dz)); const cornerSkip = Math.abs(dx) === 2 && Math.abs(dz) === 2
        if (kind === 'spruce') {
          for (let y = base + 2; y <= top; y++) {
            const r = Math.max(0, Math.min(2, Math.floor((top - y + 1) / 2))) - ((top - y) % 2)
            if (ad <= Math.max(r, y === top ? 0 : 1) && !(cornerSkip)) put(y, leaves, false)
          }
        } else {
          for (let y = top - 3; y <= top; y++) {
            const r = y >= top - 1 ? 1 : 2
            if (ad > r) continue
            if (r === 1 && Math.abs(dx) === 1 && Math.abs(dz) === 1 && y === top) continue
            if (cornerSkip && rnd3(x, y, z, seed) < 0.6) continue
            put(y, leaves, false)
          }
        }
      }
    }
  }

  return function generateChunk (chunkX, chunkZ) {
    const chunk = new Chunk()
    const pos = new Vec3(0, 0, 0)
    const dm = getDuke(seed) // real Duke3D shareware levels on the surface (local extraction only)
    const yt = getYorg() // real Yorg race track (CC BY-SA, fetched at install)
    for (let i = 0; i < 16; i++) {
      for (let k = 0; k < 16; k++) {
        const x = chunkX * 16 + i; const z = chunkZ * 16 + k
        if (dm && dm.voidAt(x, z)) { // Duke mode: pure void around the levels (falling in = Duke death)
          pos.x = i; pos.z = k
          for (let y = 0; y < 256; y++) { pos.y = y; chunk.setSkyLight(pos, 15) }
          continue
        }
        let info = layout.columnInfo(x, z, seed)
        const dcol = dm && dm.col(x, z)
        const inDuke = !!dcol && dcol.kind !== 0
        // block top 1 below the polygon floor (no z-fighting); vanilla underground below
        if (inDuke) info = { ...info, h: dcol.top - 2, biome: 'plains', w: 1, G: dcol.top - 2, inCore: false }
        // Yorg track: block layer just under the track polygons, terrain blends back to natural around it
        let ysurf = null
        if (!inDuke && yt) {
          const dd = yt.dist(x + 0.5, z + 0.5)
          if (dd < yt.MARGIN) {
            ysurf = dd === 0 ? yt.surf(x, z) : null
            const base = yt.YG - 3
            const hh = ysurf ? Math.floor(ysurf.y - 0.35) - 1 : Math.round(base + (info.h - base) * Math.max(0, Math.min(1, dd / yt.MARGIN)))
            info = { ...info, h: hh, biome: 'plains', w: 1, G: hh, inCore: false, type: 'vanilla' }
          }
        }
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
        const Z = info.inCore && info.type !== 'duke' && !(info.type === 'yorg' && yt) && ZONES[info.type]
        if (ysurf) {
          col[h] = B.dirt // soil under the Yorg road polygons (shows in craters)
          if (ysurf.kind === 3) for (let y = h + 1; y < h + 4; y++) put(y, 'barrier') // track walls / fences
        } else if (inDuke) {
          col[h] = B.dirt // plain soil under the Duke floor polygons (shows in craters)
          if (dcol.bar1 > dcol.bar0) for (let y = dcol.bar0; y < dcol.bar1; y++) put(y, 'barrier')
        } else if (Z) {
          Z.column(info.u, info.v, info.G, put, { seed, rx: info.rx, rz: info.rz })
        } else if (h >= layout.WATER) {
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
