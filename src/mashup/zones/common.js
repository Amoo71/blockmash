'use strict'
const { hash2, rnd2 } = require('../noise')
// gable roof, ridge parallel to the u axis. footprint [0,w)x[0,d), overhang 1
function gableRoof (bu, bv, w, d, base, mat, planks, put, G) {
  if (bu < -1 || bu > w || bv < -1 || bv > d) return
  const a = bv + 1; const b = d - bv
  const e = Math.min(a, b)
  let spec
  if (a < b) spec = `${mat}[facing=south,half=bottom]`
  else if (a > b) spec = `${mat}[facing=north,half=bottom]`
  else spec = planks
  put(G + 1 + base + e - 1, spec)
  if ((bu === 0 || bu === w - 1) && bv >= 0 && bv < d) {
    for (let r = 0; r < e - 1; r++) put(G + 1 + base + r, planks)
  }
}
const pick = (arr, h) => arr[h % arr.length]
module.exports = { gableRoof, pick, hash2, rnd2 }
