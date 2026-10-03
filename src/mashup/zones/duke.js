// Duke3D-style city blocks (core 128x128): streets, sidewalks, towers, shops, parking plazas, neon, TNT barrels
'use strict'
const { hash2, rnd2, pick } = require('./common')

const P = 32
const WALLS = ['bricks', 'stone_bricks', 'light_gray_concrete', 'white_concrete', 'cyan_terracotta', 'polished_andesite', 'red_terracotta']
const NEON = ['red_concrete', 'magenta_concrete', 'lime_concrete', 'light_blue_concrete', 'yellow_concrete']

function lotInfo (li, lj, ctx) {
  const h = hash2(li + ctx.rx * 7, lj + ctx.rz * 7, ctx.seed ^ 0xd0e)
  const r = h % 10
  return {
    h,
    type: r < 6 ? 'tower' : r < 8 ? 'shop' : 'plaza',
    floors: 3 + (h >>> 4) % 7,
    wall: pick(WALLS, h >>> 8),
    neon: pick(NEON, h >>> 12),
    sign: ((h >>> 16) & 3) !== 0
  }
}

function street (u, v, cu, cv, put, G, ctx) {
  let m = 'gray_concrete'
  const inter = cu < 8 && cv < 8
  if (!inter && cu < 8 && (cu === 3 || cu === 4) && v % 6 < 3) m = 'yellow_concrete'
  else if (!inter && cv < 8 && (cv === 3 || cv === 4) && u % 6 < 3) m = 'yellow_concrete'
  else if (inter && (cu === 0 || cu === 7 || cv === 0 || cv === 7) && (u + v) % 2 === 0) m = 'white_concrete' // crosswalk
  else if (rnd2(u, v, ctx.seed ^ 0x51) < 0.05) m = 'black_concrete'
  put(G, m)
  // manhole -> sewer shaft (Duke-style)
  if (cu === 4 && cv === 20 && (ctx.rx + ctx.rz) % 2 === 0) { put(G, 'iron_trapdoor'); for (let y = G - 6; y < G; y++) put(y, 'air') }
}

function building (L, bu, bv, put, G) {
  const isTower = L.type === 'tower'
  const H = isTower ? L.floors * 4 : 5
  const wall = bu === 0 || bu === 19 || bv === 0 || bv === 19
  const corner = (bu === 0 || bu === 19) && (bv === 0 || bv === 19)
  const ladder = bu === 1 && bv === 18
  put(G, 'smooth_stone')
  for (let rel = 0; rel < H; rel++) {
    const y = G + 1 + rel
    const fl = rel % 4
    if (wall) {
      const along = (bu === 0 || bu === 19) ? bv : bu
      if (corner) { put(y, 'polished_andesite'); continue }
      if (bv === 0 && (bu === 9 || bu === 10) && rel < 3) { put(y, 'air'); continue } // entrance
      if (!isTower) {
        if (bv === 0 && rel < 3) { put(y, 'glass'); continue }
        if (bv === 0 && rel === 3) { put(y, along % 2 ? 'glowstone' : L.neon); continue }
        put(y, L.wall); continue
      }
      if ((fl === 1 || fl === 2) && along % 3 !== 0) { put(y, 'black_stained_glass'); continue }
      put(y, L.wall)
    } else {
      if (ladder) { put(y, 'ladder[facing=north]'); continue }
      if (fl === 3 || rel === H - 1) put(y, 'smooth_stone')
    }
  }
  // parapet
  if (wall) put(G + 1 + H, L.wall)
  if (ladder) put(G + H, 'ladder[facing=north]')
  // interior props on ground floor
  if (!wall && !ladder) {
    if (!isTower && bv === 4 && bu > 3 && bu < 16) put(G + 1, 'quartz_block') // shop counter
    if (isTower && (bu === 17 && bv === 2)) put(G + 1, 'barrel')
  }
  // roof billboard
  if (L.sign && bv === 2 && bu >= 3 && bu <= 16) {
    for (let r = 1; r <= 5; r++) {
      const y = G + H + r
      const border = r === 1 || r === 5 || bu === 3 || bu === 16
      if (r === 1 && (bu === 4 || bu === 15)) { put(y, 'iron_bars'); continue }
      if (r === 1) continue
      const bit = ((L.h >>> ((bu * 3 + r) % 29)) & 1)
      put(y, border ? 'black_concrete' : bit ? L.neon : 'glowstone')
    }
  }
}

function plaza (L, bu, bv, put, G, u, v, ctx) {
  put(G, 'gray_concrete')
  if (bv >= 2 && bv < 8 && bu % 4 === 0) put(G, 'white_concrete')
  if (bv >= 12 && bv < 18 && bu % 4 === 0) put(G, 'white_concrete')
  // fountain
  const du = bu - 10; const dv = bv - 10
  const r = Math.hypot(du + 0.5, dv + 0.5)
  if (r < 2.5) { put(G, 'water') } else if (r < 3.5) { put(G, 'smooth_stone'); put(G + 1, 'smooth_stone_slab') }
  // crates + explosive barrels
  const h = hash2(u, v, ctx.seed ^ 0xc8a7e)
  if ((bu === 1 || bu === 18) && bv > 1 && bv < 18 && h % 5 === 0) {
    put(G + 1, 'oak_planks'); if (h % 3 === 0) put(G + 2, 'barrel')
  }
  if ((bu === 2 && bv === 9) || (bu === 2 && bv === 10) || (bu === 17 && bv === 9)) { put(G + 1, 'tnt'); if (bv === 9) put(G + 2, 'tnt') }
}

function column (u, v, G, put, ctx) {
  const cu = u % P; const cv = v % P
  if (cu < 8 || cv < 8) { street(u, v, cu, cv, put, G, ctx); return }
  const L = lotInfo(Math.floor(u / P), Math.floor(v / P), ctx)
  // sidewalk ring
  if (cu < 10 || cu >= 30 || cv < 10 || cv >= 30) {
    put(G, 'smooth_stone')
    put(G + 1, 'smooth_stone_slab')
    if (cu === 9 && cv % 10 === 5) { for (let r = 2; r <= 5; r++) put(G + r, 'iron_bars'); put(G + 6, 'sea_lantern') }
    if (cv === 9 && cu === 20 && L.h % 3 === 0) { put(G + 2, 'red_concrete'); put(G + 3, 'red_concrete') } // hydrant-ish
    return
  }
  const bu = cu - 10; const bv = cv - 10
  if (L.type === 'plaza') plaza(L, bu, bv, put, G, u, v, ctx)
  else building(L, bu, bv, put, G)
}
module.exports = { column, lotInfo, P }
