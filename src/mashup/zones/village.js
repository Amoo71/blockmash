// Minecraft-style village (core 64x64): paths, well, bell, houses, farms, lamp posts
'use strict'
const { gableRoof, hash2 } = require('./common')

const base = [
  { kind: 'house', u0: 20, v0: 21, w: 7, d: 7, door: 'S' },
  { kind: 'house', u0: 7, v0: 21, w: 9, d: 7, door: 'S' },
  { kind: 'farm', u0: 5, v0: 5, w: 12, d: 11 },
  { kind: 'house', u0: 21, v0: 7, w: 7, d: 9, door: 'E' }
]
// mirror into the 4 quadrants (center path at 31..33)
const flipDoor = { S: 'N', N: 'S', E: 'W', W: 'E' }
const SLOTS = []
for (const s of base) {
  for (const [mu, mv] of [[0, 0], [1, 0], [0, 1], [1, 1]]) {
    SLOTS.push({
      ...s,
      u0: mu ? 64 - s.u0 - s.w : s.u0,
      v0: mv ? 64 - s.v0 - s.d : s.v0,
      door: s.door && ((s.door === 'E' || s.door === 'W') ? (mu ? flipDoor[s.door] : s.door) : (mv ? flipDoor[s.door] : s.door))
    })
  }
}

function doorPos (s) {
  if (s.door === 'S') return { u: s.u0 + (s.w >> 1), v: s.v0 + s.d - 1, du: 0, dv: 1 }
  if (s.door === 'N') return { u: s.u0 + (s.w >> 1), v: s.v0, du: 0, dv: -1 }
  if (s.door === 'E') return { u: s.u0 + s.w - 1, v: s.v0 + (s.d >> 1), du: 1, dv: 0 }
  return { u: s.u0, v: s.v0 + (s.d >> 1), du: -1, dv: 0 }
}
const facing = { S: 'south', N: 'north', E: 'east', W: 'west' }

function house (s, bu, bv, put, G, seed, rx, rz) {
  const { w, d } = s
  const inside = bu >= 0 && bu < w && bv >= 0 && bv < d
  if (inside) {
    put(G, 'cobblestone')
    const wall = bu === 0 || bu === w - 1 || bv === 0 || bv === d - 1
    const corner = (bu === 0 || bu === w - 1) && (bv === 0 || bv === d - 1)
    const dp = doorPos(s)
    const isDoor = (s.u0 + bu) === dp.u && (s.v0 + bv) === dp.v
    for (let r = 0; r < 4; r++) {
      const y = G + 1 + r
      if (!wall) { if (r === 3) put(y, 'oak_planks'); continue }
      if (corner) { put(y, 'oak_log'); continue }
      if (isDoor && r < 2) { put(y, `oak_door[facing=${facing[s.door]},half=${r === 0 ? 'lower' : 'upper'}]`); continue }
      const along = (bu === 0 || bu === w - 1) ? bv : bu
      if ((r === 1 || r === 2) && along % 2 === 1 && !isDoor) { put(y, 'glass'); continue }
      put(y, r === 0 ? 'cobblestone' : 'oak_planks')
    }
    if (!wall) {
      const h = hash2(s.u0 + bu, s.v0 + bv, seed ^ rx * 31 ^ rz)
      if (bu === 1 && bv === 1) put(G + 1, 'crafting_table')
      else if (bu === w - 2 && bv === d - 2) put(G + 1, 'lantern')
      else if (bu === w - 2 && bv === 1 && h % 2) put(G + 1, 'barrel')
    }
  }
  gableRoof(bu, bv, w, d, 4, 'spruce_stairs', 'spruce_planks', put, G)
}

function farm (s, bu, bv, put, G) {
  const { w, d } = s
  if (bu < 0 || bu >= w || bv < 0 || bv >= d) return
  if (bu === 0 || bu === w - 1 || bv === 0 || bv === d - 1) { put(G, 'oak_log'); return }
  if (bu % 4 === 0) { put(G, 'water'); return }
  put(G, 'farmland[moisture=7]')
  const crop = (s.u0 + s.v0 + bv) % 3
  put(G + 1, crop === 0 ? 'wheat[age=7]' : crop === 1 ? 'carrots[age=7]' : 'potatoes[age=7]')
}

function column (u, v, G, put, ctx) {
  // central cross paths
  const onPath = (Math.abs(u - 32) <= 1 && v >= 2 && v < 62) || (Math.abs(v - 32) <= 1 && u >= 2 && u < 62)
  if (onPath) put(G, 'grass_path')
  // well 30..34
  if (u >= 29 && u <= 35 && v >= 29 && v <= 35) {
    const ring = u === 29 || u === 35 || v === 29 || v === 35
    if (ring) {
      put(G, 'cobblestone'); put(G + 1, 'cobblestone')
      if ((u === 29 || u === 35) && (v === 29 || v === 35)) { put(G + 2, 'oak_fence'); put(G + 3, 'oak_fence') }
      put(G + 4, 'cobblestone_slab')
    } else {
      put(G - 2, 'water'); put(G - 1, 'water'); put(G, 'water'); put(G + 4, 'cobblestone_slab')
    }
    return
  }
  if (u === 37 && v === 37) { put(G, 'cobblestone'); put(G + 1, 'bell[attachment=floor]') }
  // lamp posts along paths
  if ((Math.abs(u - 32) === 2 && v % 10 === 5) || (Math.abs(v - 32) === 2 && u % 10 === 5)) {
    put(G + 1, 'oak_fence'); put(G + 2, 'oak_fence'); put(G + 3, 'lantern')
  }
  for (const s of SLOTS) {
    const bu = u - s.u0; const bv = v - s.v0
    if (bu < -1 || bu > s.w || bv < -1 || bv > s.d) continue
    if (s.kind === 'farm') farm(s, bu, bv, put, G)
    else house(s, bu, bv, put, G, ctx.seed, ctx.rx, ctx.rz)
  }
  // small paths from doors to the main path
  for (const s of SLOTS) {
    if (s.kind !== 'house') continue
    const dp = doorPos(s)
    for (let i = 1; i < 12; i++) {
      const pu = dp.u + dp.du * i; const pv = dp.v + dp.dv * i
      if (Math.abs(pu - 32) <= 1 || Math.abs(pv - 32) <= 1) break
      if (pu === u && pv === v) put(G, 'grass_path')
    }
  }
  if (u === 33 && v === 22) put(G + 1, 'composter')
}
module.exports = { column, SLOTS }
