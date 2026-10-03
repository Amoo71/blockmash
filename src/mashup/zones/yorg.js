// Yorg-style kart race track (core 128x128): stadium circuit with kerbs, start/finish, grid, gantry, grandstand,
// tyre walls and pit garage
'use strict'
const { rnd2 } = require('./common')
const A = 22; const R = 34; const HW = 6

function trackCoords (u, v) {
  const x = u - 63.5; const z = v - 63.5
  const px = Math.max(-A, Math.min(A, x))
  const d = Math.hypot(x - px, z)
  // along-track parameter (blocks), used for kerb stripes
  let s
  if (Math.abs(x) <= A) s = z > 0 ? x : -x
  else s = Math.atan2(z, x - px) * R
  return { x, z, d, s }
}

function column (u, v, G, put, ctx) {
  const { x, z, d, s } = trackCoords(u, v)
  const off = d - R
  if (Math.abs(off) <= HW) {
    let m = 'gray_concrete'
    if (Math.abs(off) > HW - 1) m = Math.floor(s / 2) % 2 === 0 ? 'red_concrete' : 'white_concrete'
    else if (Math.abs(x) <= 1 && z > 0) m = ((u + v) % 2) ? 'black_wool' : 'white_wool'
    else if (z > 0 && x < -3 && x > -20 && u % 5 === 0 && Math.abs(off) < HW - 2) m = 'white_concrete' // grid slots
    else if (Math.abs(x) > A && rnd2(u, v, ctx.seed ^ 0x9a) < 0.06) m = 'black_concrete'
    put(G, m)
    // start/finish gantry beam
    if (Math.abs(x) <= 0.5 && z > 0) { put(G + 7, 'black_concrete'); if (Math.floor(off) % 2 === 0) put(G + 6, 'sea_lantern') }
    return
  }
  // gantry posts
  if (Math.abs(x) <= 0.5 && z > 0 && Math.abs(Math.abs(off) - (HW + 1)) < 0.75) { for (let r = 1; r <= 7; r++) put(G + r, 'black_concrete'); return }
  // tyre wall outside
  if (off > HW + 0.5 && off <= HW + 1.5 && !(Math.abs(x) < 3 && z < 0)) { put(G + 1, 'black_wool'); if (Math.abs(x) > A) put(G + 2, 'black_wool'); put(G, 'gray_concrete'); return }
  // grandstand outside the main straight
  if (z > 0 && Math.abs(x) <= 18 && off > HW + 2 && off <= HW + 12) {
    const step = Math.floor((off - HW - 2) / 1.5) + 1
    for (let r = 1; r < step; r++) put(G + r, 'light_gray_concrete')
    put(G + step, step % 2 ? 'red_concrete' : 'blue_concrete')
    if (Math.abs(x) === 17.5) for (let r = step + 1; r <= 9; r++) put(G + r, 'white_concrete')
    return
  }
  // infield: pit garage + grass, tyre stacks
  if (off < -HW) {
    if (Math.abs(x) <= 12 && Math.abs(z) <= 6) {
      const wall = Math.abs(x) >= 11.5 || Math.abs(z) >= 5.5
      put(G, 'smooth_stone')
      if (wall) {
        const open = z <= -5.5 && Math.abs(x) < 10
        for (let r = 1; r <= 4; r++) put(G + r, open && r < 4 ? 'air' : (r === 4 ? 'light_blue_concrete' : 'white_concrete'))
      }
      put(G + 5, 'smooth_stone_slab')
      if (!wall && z > 3 && Math.round(x) % 4 === 0) put(G + 1, 'barrel')
      return
    }
    if (rnd2(u, v, ctx.seed ^ 0xa1) < 0.004) { put(G + 1, 'black_wool'); put(G + 2, 'black_wool') }
  }
  put(G, 'grass_block')
}
module.exports = { column, trackCoords, A, R, HW }
