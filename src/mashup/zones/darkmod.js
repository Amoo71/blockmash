// Dark Mod-style medieval / steampunk quarter (core 128x128): city wall, winding cobbled lanes, timber-framed
// houses with gable roofs, steampunk workshops, a manor with a vault, gas lamps, market fountain
'use strict'
const { gableRoof, hash2, rnd2, pick } = require('./common')

const C = 18; const OFF = 10
const roadA = (u, v) => Math.abs(v - 64 - 5 * Math.sin(u / 13))
const roadB = (u, v) => Math.abs(u - 64 - 5 * Math.sin(v / 11))
const isRoad = (u, v) => roadA(u, v) <= 2.5 || roadB(u, v) <= 2.5
const ROOFS = [['dark_oak_stairs', 'dark_oak_planks'], ['spruce_stairs', 'spruce_planks'], ['brick_stairs', 'bricks'], ['stone_brick_stairs', 'stone_bricks']]
const GROUND = ['cobblestone', 'stone_bricks', 'andesite']

const cellCache = new Map()
function cellInfo (ci, cj, ctx) {
  const k = `${ctx.rx},${ctx.rz},${ci},${cj}`
  let c = cellCache.get(k)
  if (c) return c
  const h = hash2(ci + ctx.rx * 13, cj + ctx.rz * 13, ctx.seed ^ 0xda4c)
  const manor = ci === 1 && cj === 1
  const w = manor ? 16 : 8 + h % 5
  const d = manor ? 15 : 7 + (h >>> 3) % 4
  const u0 = OFF + ci * C + 1; const v0 = OFF + cj * C + 1
  let ok = ci >= 0 && cj >= 0 && ci < 6 && cj < 6
  // reject lots that touch the lanes or the plaza
  for (const [a, b] of [[0, 0], [w, 0], [0, d], [w, d], [w >> 1, d >> 1], [w >> 1, 0], [w >> 1, d], [0, d >> 1], [w, d >> 1]]) {
    if (roadA(u0 + a, v0 + b) <= 4 || roadB(u0 + a, v0 + b) <= 4 || Math.hypot(u0 + a - 64, v0 + b - 64) < 10) ok = false
  }
  c = { ok, h, w, d, u0, v0, type: manor ? 'manor' : (h >>> 7) % 5 === 0 ? 'workshop' : 'house', roof: pick(ROOFS, h >>> 9), ground: pick(GROUND, h >>> 11) }
  cellCache.set(k, c)
  return c
}

function house (c, bu, bv, put, G) {
  const { w, d } = c
  const inside = bu >= 0 && bu < w && bv >= 0 && bv < d
  if (inside) {
    put(G, 'spruce_planks')
    const wall = bu === 0 || bu === w - 1 || bv === 0 || bv === d - 1
    const corner = (bu === 0 || bu === w - 1) && (bv === 0 || bv === d - 1)
    const along = (bu === 0 || bu === w - 1) ? bv : bu
    const door = bv === 0 && bu === (w >> 1)
    const ladder = bu === 1 && bv === d - 2
    for (let r = 0; r < 8; r++) {
      const y = G + 1 + r
      if (!wall) {
        if (ladder) put(y, 'ladder[facing=north]')
        else if (r === 3) put(y, 'spruce_planks')
        continue
      }
      if (door && r < 2) { put(y, `dark_oak_door[facing=north,half=${r ? 'upper' : 'lower'}]`); continue }
      if (r < 4) {
        if (corner) { put(y, 'stone_bricks'); continue }
        if ((r === 1 || r === 2) && along % 4 === 2) { put(y, 'brown_stained_glass'); continue }
        put(y, c.ground === 'andesite' ? 'cobblestone' : c.ground); continue
      }
      // timber-framed upper storey
      if (corner || r === 4 || along % 3 === 0) { put(y, 'dark_oak_log'); continue }
      if ((r === 5 || r === 6) && along % 3 === 1) { put(y, 'glass'); continue }
      put(y, 'white_terracotta')
    }
    if (!wall && !ladder) {
      if (bu === w - 2 && bv === d - 2) put(G + 1, 'bookshelf')
      if (bu === w - 2 && bv === 1) put(G + 1, 'lantern')
      if (bu === 2 && bv === 1) put(G + 5, 'chest[facing=south]')
    }
    // chimney with smoke
    if (bu === w - 2 && bv === 1) {
      for (let r = 0; r < 14; r++) put(G + 1 + r, 'bricks')
      put(G + 15, 'campfire[lit=true]')
    }
  }
  if (!(bu === w - 2 && bv === 1)) gableRoof(bu, bv, w, d, 8, c.roof[0], c.roof[1], put, G)
  // gas lamp in front of the door
  if (bu === (w >> 1) + 2 && bv === -1) { put(G + 1, 'dark_oak_fence'); put(G + 2, 'dark_oak_fence'); put(G + 3, 'lantern') }
}

function workshop (c, bu, bv, put, G) {
  const { w, d } = c
  if (bu < 0 || bu >= w || bv < 0 || bv >= d) return
  put(G, 'polished_andesite')
  const wall = bu === 0 || bu === w - 1 || bv === 0 || bv === d - 1
  const corner = (bu === 0 || bu === w - 1) && (bv === 0 || bv === d - 1)
  const along = (bu === 0 || bu === w - 1) ? bv : bu
  const H = 7
  for (let r = 0; r < H; r++) {
    const y = G + 1 + r
    if (!wall) { if (r === H - 1) put(y, 'polished_andesite'); continue }
    if (bv === 0 && Math.abs(bu - (w >> 1)) <= 1 && r < 3) { put(y, 'air'); continue }
    if (corner || r === 0 || r === H - 1) { put(y, r === H - 1 ? 'orange_terracotta' : 'iron_block'); continue }
    if (r >= 2 && r <= 4 && along % 2 === 0) {
      const ns = bv === 0 || bv === d - 1
      put(y, ns ? 'iron_bars[east=true,west=true]' : 'iron_bars[north=true,south=true]'); continue
    }
    put(y, 'bricks')
  }
  if (!wall) {
    const k = (bu + bv * 3) % 7
    if (bv === d - 2 && bu > 1 && bu < w - 2) put(G + 1, ['furnace', 'blast_furnace', 'smoker', 'anvil', 'grindstone', 'hopper', 'cauldron'][k])
    if (bv === 2 && bu === 2) put(G + 1, 'crafting_table')
  }
  // smokestacks and pipes on the roof
  if (bu === 2 && bv === d - 3) { for (let r = H; r < H + 9; r++) put(G + 1 + r, 'bricks'); put(G + 1 + H + 9, 'campfire[lit=true]') }
  if (bv === d >> 1 && bu > 2 && bu < w - 2) put(G + 1 + H, 'polished_andesite_slab')
}

function manor (c, bu, bv, put, G) {
  const { w, d } = c
  if (bu < 0 || bu >= w || bv < 0 || bv >= d) return
  put(G, 'stone_bricks')
  const tower = (bu < 3 || bu >= w - 3) && (bv < 3 || bv >= d - 3)
  const wall = bu === 0 || bu === w - 1 || bv === 0 || bv === d - 1
  const H = tower ? 14 : 10
  const along = (bu === 0 || bu === w - 1) ? bv : bu
  const vault = bu >= 6 && bu <= 9 && bv >= 6 && bv <= 9
  for (let r = 0; r < H; r++) {
    const y = G + 1 + r
    if (wall || (tower && (bu === 2 || bu === w - 3 || bv === 2 || bv === d - 3))) {
      if (bv === 0 && (bu === 7 || bu === 8) && r < 3) { put(y, r < 2 ? `dark_oak_door[facing=north,half=${r ? 'upper' : 'lower'},hinge=${bu === 7 ? 'left' : 'right'}]` : 'stone_bricks'); continue }
      if (!tower && (r % 5 === 1 || r % 5 === 2 || r % 5 === 3) && along % 3 === 1) { put(y, 'glass'); continue }
      put(y, (bu * 7 + r * 3 + bv) % 5 === 0 ? 'mossy_stone_bricks' : 'stone_bricks')
      continue
    }
    if (r === 4 && !vault) put(y, 'dark_oak_planks')
    else if (r === H - 1) put(y, 'stone_bricks')
    else if (vault && r < 4) {
      const vw = bu === 6 || bu === 9 || bv === 6 || bv === 9
      if (vw) put(y, bv === 6 && bu === 7 && r < 2 ? 'iron_bars' : 'iron_block')
      else if (r === 0) put(y, 'gold_block')
      else if (r === 3) put(y, 'iron_block')
    }
  }
  // crenellations
  if (wall || tower) { if ((bu + bv) % 2 === 0) put(G + 1 + H, 'stone_bricks') }
  if (!wall && !tower && !vault) {
    if (bv === 3 && bu === 11) put(G + 1, 'lectern')
    if (bv === d - 2 && bu > 4 && bu < w - 4) put(G + 1, 'bookshelf')
    if (bu === 1 && bv === d - 4) { for (let r = 0; r < H - 1; r++) put(G + 1 + r, 'ladder[facing=east]') }
  }
}

function column (u, v, G, put, ctx) {
  const m = Math.max(Math.abs(u - 63.5), Math.abs(v - 63.5))
  // city wall with gates
  if (m >= 61 && m <= 63) {
    const gate = roadA(u, v) <= 3.5 || roadB(u, v) <= 3.5
    put(G, 'cobblestone')
    if (!gate) {
      for (let r = 1; r <= 7; r++) put(G + r, (u * 5 + v + r) % 7 === 0 ? 'mossy_cobblestone' : 'stone_bricks')
      if (m >= 62.5 && (u + v) % 2 === 0) put(G + 8, 'stone_bricks')
    } else {
      put(G + 6, 'stone_bricks'); put(G + 7, 'stone_bricks')
    }
    return
  }
  const plazaR = Math.hypot(u - 64, v - 64)
  if (isRoad(u, v) || plazaR < 9) {
    const r = rnd2(u, v, ctx.seed ^ 0x77)
    put(G, plazaR < 9 ? (r < 0.5 ? 'polished_andesite' : 'stone_bricks') : r < 0.6 ? 'cobblestone' : r < 0.85 ? 'andesite' : 'gravel')
    if (plazaR < 2.5) put(G, 'water')
    else if (plazaR < 3.5) { put(G + 1, 'stone_brick_wall'); if (Math.abs(u - 64) < 1 && v > 64) {} }
    if (plazaR < 0.8) { put(G + 1, 'stone_bricks'); put(G + 2, 'stone_bricks'); put(G + 3, 'lantern') }
    return
  }
  // gas lamps along lanes
  if ((Math.abs(roadA(u, v) - 3.5) < 0.5 && u % 9 === 0) || (Math.abs(roadB(u, v) - 3.5) < 0.5 && v % 9 === 0)) {
    put(G + 1, 'dark_oak_fence'); put(G + 2, 'dark_oak_fence'); put(G + 3, 'dark_oak_fence'); put(G + 4, 'lantern')
  }
  if (rnd2(u, v, ctx.seed ^ 0x99) < 0.25) put(G, 'coarse_dirt')
  const ci = Math.floor((u - OFF) / C); const cj = Math.floor((v - OFF) / C)
  // houses can overhang one block into the neighbour cell; check own cell only (cells have margin)
  if (u < OFF || v < OFF) return
  const c = cellInfo(ci, cj, ctx)
  if (!c.ok) return
  const bu = u - c.u0; const bv = v - c.v0
  if (c.type === 'manor') manor(c, bu, bv, put, G)
  else if (c.type === 'workshop') workshop(c, bu, bv, put, G)
  else house(c, bu, bv, put, G)
}
module.exports = { column, cellInfo }
