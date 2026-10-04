// Places the locally extracted Duke Nukem 3D shareware levels (E1L1..E1L6) side by side on the surface, at original
// Build scale (512 units per block). Between and around them the normal Minecraft world stays.
// Raw map JSON is fetched by the client before the integrated server starts (globalThis.blockmashDukeMaps).
'use strict'
const layout = require('../layout')
const { prepare } = require('./dukemap')

const ORDER = ['E1L1', 'E1L2', 'E1L3', 'E1L4', 'E1L5', 'E1L6']
const X0 = 230; const ZC = 96; const GAP = 420 // levels far apart: from inside one level the others are out of sight
let cache = null
const VOIDR = 200

// most common walkable floor height (area-weighted) -> placed at the zone ground level
function mainFloor (m) {
  const hist = new Map()
  for (const s of m.sectors) {
    let a = 0
    for (let i = s.wallptr; i < s.wallptr + s.wallnum; i++) { const p = m.walls[i]; const q = m.walls[p.p2]; a += p.x * q.y - q.x * p.y }
    const k = Math.round(s.fz / 1024) * 1024
    hist.set(k, (hist.get(k) || 0) + Math.abs(a))
  }
  let best = 8192; let bw = -1
  for (const [k, w] of hist) if (w > bw) { bw = w; best = k }
  return best
}

function getDuke () {
  const raw = globalThis.blockmashDukeMaps
  if (!raw) return null
  if (cache) return cache
  const maps = []
  let x = X0
  for (const name of ORDER) {
    const m = raw[name]
    if (!m) continue
    let x0 = Infinity; let x1 = -Infinity; let y0 = Infinity; let y1 = -Infinity
    for (const w of m.walls) { x0 = Math.min(x0, w.x); x1 = Math.max(x1, w.x); y0 = Math.min(y0, w.y); y1 = Math.max(y1, w.y) }
    const ox = x - x0 / 512; const oz = ZC - ((y0 + y1) / 2) / 512
    const dm = prepare(m, { ox, oz, G: layout.ZONE_G, zref: mainFloor(m) })
    dm.name = name
    maps.push(dm)
    x += (x1 - x0) / 512 + GAP
  }
  if (!maps.length) return null
  const bbox = { x0: Math.min(...maps.map(d => d.bbox.x0)), z0: Math.min(...maps.map(d => d.bbox.z0)), x1: Math.max(...maps.map(d => d.bbox.x1)), z1: Math.max(...maps.map(d => d.bbox.z1)) }
  const at = (x, z) => { for (const d of maps) { const b = d.bbox; if (x >= b.x0 && x < b.x1 && z >= b.z0 && z < b.z1) return d } return null }
  cache = {
    maps,
    bbox,
    start: maps[0].start,
    mapAt: at,
    col: (x, z) => { const d = at(x, z); return d ? d.col(x, z) : null },
    floorAt: (x, z) => { const d = at(x, z); return d ? d.floorAt(x, z) : null },
    // Duke mode: everything around the levels is void (Duke sky); Minecraft exists only under the Duke floors
    voidAt: (x, z) => {
      const d = at(x, z)
      if (d) { const c = d.col(x, z); return !c || c.kind === 0 }
      for (const m of maps) { const b = m.bbox; if (x > b.x0 - VOIDR && x < b.x1 + VOIDR && z > b.z0 - VOIDR && z < b.z1 + VOIDR) return true }
      return false
    }
  }
  globalThis.blockmashDuke = cache
  return cache
}
module.exports = { getDuke, ORDER }
