// Dark Mod quarter (core 128x128): winding cobbled MC lanes with lanterns and a fountain plaza; every lot carries a
// real The Dark Mod building prefab (rendered as polygons by client/dmprefabs.ts, collision = barrier voxels of
// its brushes). Without the converted prefabs the lots stay empty (no invented buildings).
'use strict'
const { hash2, rnd2, pick } = require('./common')
const { getPrefabs } = require('../surface/darkmodworld')

const C = 18; const OFF = 10
const roadA = (u, v) => Math.abs(v - 64 - 5 * Math.sin(u / 13))
const roadB = (u, v) => Math.abs(u - 64 - 5 * Math.sin(v / 11))
const isRoad = (u, v) => roadA(u, v) <= 2.5 || roadB(u, v) <= 2.5
const GROUND = ['cobblestone', 'stone_bricks', 'andesite']

const cellCache = new Map()
function cellInfo (ci, cj, ctx) {
  const k = `${ctx.rx},${ctx.rz},${ci},${cj}`
  let c = cellCache.get(k)
  if (c && c.P === !!getPrefabs()) return c
  const h = hash2(ci + ctx.rx * 13, cj + ctx.rz * 13, ctx.seed ^ 0xda4c)
  const P = getPrefabs()
  const manor = ci === 1 && cj === 1
  const type = manor ? 'manor' : (h >>> 7) % 5 === 0 ? 'tower' : 'house'
  const pf = P ? (manor ? P.manor() : type === 'tower' ? P.tower(h >>> 13) : P.house(h >>> 13)) : null
  const rot = manor ? 0 : (h >>> 5) & 3
  const [w, d] = pf ? P.foot(pf, rot) : [0, 0]
  const u0 = OFF + ci * C + 1; const v0 = OFF + cj * C + 1
  let ok = !!pf && ci >= 0 && cj >= 0 && ci < 6 && cj < 6
  // reject lots that touch the lanes or the plaza
  for (const [a, b] of [[0, 0], [w, 0], [0, d], [w, d], [w >> 1, d >> 1], [w >> 1, 0], [w >> 1, d], [0, d >> 1], [w, d >> 1]]) {
    if (roadA(u0 + a, v0 + b) <= 4 || roadB(u0 + a, v0 + b) <= 4 || Math.hypot(u0 + a - 64, v0 + b - 64) < 10) ok = false
  }
  c = { ok, h, w, d, u0, v0, type, prefab: pf?.name ?? null, rot, ground: pick(GROUND, h >>> 11), P: !!P }
  cellCache.set(k, c)
  return c
}

function building (c, bu, bv, put, G) {
  if (bu < 0 || bu >= c.w || bv < 0 || bv >= c.d) return
  const P = getPrefabs(); const pf = P.byName.get(c.prefab)
  put(G, 'stone_bricks')
  for (const [y0, y1] of P.solid(pf, c.rot, bu, bv) ?? []) for (let y = y0; y < y1; y++) put(G + 1 + y, 'barrier')
}

function column (u, v, G, put, ctx) {
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
  put(G, rnd2(u, v, ctx.seed ^ 0x99) < 0.25 ? 'coarse_dirt' : 'grass_block')
  const ci = Math.floor((u - OFF) / C); const cj = Math.floor((v - OFF) / C)
  // houses can overhang one block into the neighbour cell; check own cell only (cells have margin)
  if (u < OFF || v < OFF) return
  const c = cellInfo(ci, cj, ctx)
  if (!c.ok) return
  const bu = u - c.u0; const bv = v - c.v0
  building(c, bu, bv, put, G)
}
module.exports = { column, cellInfo }
