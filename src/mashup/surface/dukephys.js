// Build-engine style movement on a placed Duke3D level (shared by the client player controller and the server
// mobs): circle-vs-wall clipping against one-sided walls and two-sided walls whose neighbour sector is too high
// (step) or too low under its ceiling, then floor/ceiling heights from the (possibly sloped, possibly moving)
// sectors. Works in world blocks; sector heights are read live from the map JSON, so doors/lifts just mutate it.
'use strict'
// Build sector lotags: 16-19 platforms/elevators, 20-23/25/26 doors, 27 stretch bridge
const DOOR_LT = new Set([20, 21, 22, 23, 25, 26, 27]); const LIFT_LT = new Set([16, 17, 18, 19])
const SLIDE_LT = new Set([23, 25, 26])
const STEP = 0.8 // Duke climbs steps up to about 3/4 of a block without jumping

function makePhys (d) {
  if (d.phys) return d.phys
  const W = d.m.walls; const S = d.m.sectors
  const CELL = 4
  const segs = []
  const grid = new Map()
  W.forEach((w, i) => {
    const w2 = W[w.p2]; if (!w2) return
    const a = d.toWorld(w.x, w.y); const b = d.toWorld(w2.x, w2.y)
    let owner = -1
    for (let s = 0; s < S.length; s++) if (i >= S[s].wallptr && i < S[s].wallptr + S[s].wallnum) { owner = s; break }
    const seg = { i, ax: a.x, az: a.z, bx: b.x, bz: b.z, ns: w.ns, own: owner, block: !!(w.cstat & 1), thin: owner >= 0 && DOOR_LT.has(S[owner].lotag) }
    segs.push(seg)
    const x0 = Math.floor(Math.min(a.x, b.x) / CELL); const x1 = Math.floor(Math.max(a.x, b.x) / CELL)
    const z0 = Math.floor(Math.min(a.z, b.z) / CELL); const z1 = Math.floor(Math.max(a.z, b.z) / CELL)
    for (let gx = x0; gx <= x1; gx++) for (let gz = z0; gz <= z1; gz++) { const k = gx * 65536 + gz; let l = grid.get(k); if (!l) grid.set(k, l = []); l.push(seg) }
  })
  // blocking sprites (cstat & 1): wall sprites = short vertical walls, floor sprites = walkable planks/platforms
  const tiles = globalThis.blockmashDukeTiles || {}
  const plats = []
  for (const sp of d.m.sprites) {
    if (!(sp.cstat & 1) || (sp.cstat & 32768)) continue
    const t = tiles[sp.pic]; if (!t) continue
    const kind = sp.cstat & 48
    const w = t.w * sp.xr / 4 / 512; const hh = kind === 32 ? t.h * sp.yr / 4 / 512 : t.h * sp.yr * 4 / 8192
    const c = d.toWorld(sp.x, sp.y); const y0 = d.zToY(sp.z) - (sp.cstat & 128 ? hh / 2 : 0)
    const a = sp.ang / 2048 * Math.PI * 2
    if (kind === 32) {
      plats.push({ x: c.x, z: c.z, ux: Math.cos(a), uz: Math.sin(a), hw: w / 2, hd: hh / 2, y: d.zToY(sp.z) })
    } else if (kind === 16) {
      const dx = Math.sin(a) * w / 2; const dz = -Math.cos(a) * w / 2
      const seg = { i: -1, ax: c.x - dx, az: c.z - dz, bx: c.x + dx, bz: c.z + dz, ns: -1, own: -1, block: true, y0, y1: y0 + hh }
      segs.push(seg)
      const x0 = Math.floor(Math.min(seg.ax, seg.bx) / CELL); const x1 = Math.floor(Math.max(seg.ax, seg.bx) / CELL)
      const z0 = Math.floor(Math.min(seg.az, seg.bz) / CELL); const z1 = Math.floor(Math.max(seg.az, seg.bz) / CELL)
      for (let gx = x0; gx <= x1; gx++) for (let gz = z0; gz <= z1; gz++) { const k = gx * 65536 + gz; let l = grid.get(k); if (!l) grid.set(k, l = []); l.push(seg) }
    }
  }
  const platAt = (x, z, y, step) => {
    let best = -Infinity
    for (const p of plats) {
      const rx = x - p.x; const rz = z - p.z
      if (Math.abs(rx * p.ux + rz * p.uz) > p.hw || Math.abs(-rx * p.uz + rz * p.ux) > p.hd) continue
      if (p.y <= y + step && p.y > best) best = p.y
    }
    return best
  }
  const near = (x, z) => {
    const out = new Set()
    const gx = Math.floor(x / CELL); const gz = Math.floor(z / CELL)
    for (let dx = -1; dx <= 1; dx++) for (let dz = -1; dz <= 1; dz++) for (const s of grid.get((gx + dx) * 65536 + gz + dz) ?? []) out.add(s)
    return out
  }
  const doorBoxes = []
  S.forEach((s, si) => {
    if (!SLIDE_LT.has(s.lotag)) return
    let x0 = Infinity; let z0 = Infinity; let x1 = -Infinity; let z1 = -Infinity
    for (let i = s.wallptr; i < s.wallptr + s.wallnum; i++) { const p = d.toWorld(W[i].x, W[i].y); x0 = Math.min(x0, p.x); x1 = Math.max(x1, p.x); z0 = Math.min(z0, p.z); z1 = Math.max(z1, p.z) }
    doorBoxes.push({ si, x0: x0 - 0.02, z0: z0 - 0.02, x1: x1 + 0.02, z1: z1 + 0.02 })
  })
  const fl = (si, x, z) => { const b = d.toBuild(x, z); return d.zToY(d.floorZ(si, b.bx, b.by)) }
  const ce = (si, x, z) => { const b = d.toBuild(x, z); return d.zToY(d.ceilZ(si, b.bx, b.by)) }
  // all sectors containing a point (rooms over rooms) -> the one whose floor fits the feet best
  // sectors at a point (Build allows overlapping sectors for rooms above rooms) -> the one the feet are in
  const sgrid = new Map()
  const sbb = S.map((s, si) => {
    let x0 = Infinity; let z0 = Infinity; let x1 = -Infinity; let z1 = -Infinity
    for (let i = s.wallptr; i < s.wallptr + s.wallnum; i++) { const p = d.toWorld(W[i].x, W[i].y); x0 = Math.min(x0, p.x); x1 = Math.max(x1, p.x); z0 = Math.min(z0, p.z); z1 = Math.max(z1, p.z) }
    for (let gx = Math.floor(x0 / CELL); gx <= Math.floor(x1 / CELL); gx++) for (let gz = Math.floor(z0 / CELL); gz <= Math.floor(z1 / CELL); gz++) { const k = gx * 65536 + gz; let l = sgrid.get(k); if (!l) sgrid.set(k, l = []); l.push(si) }
    return [x0, z0, x1, z1]
  })
  const inSect = (si, bx, by) => {
    let inside = false; const s = S[si]
    for (let i = s.wallptr; i < s.wallptr + s.wallnum; i++) {
      const a = W[i]; const b = W[a.p2]
      if ((a.y > by) !== (b.y > by) && bx < (b.x - a.x) * (by - a.y) / (b.y - a.y) + a.x) inside = !inside
    }
    return inside
  }
  const sectorsAt = (x, z) => {
    const out = []; const b = d.toBuild(x, z)
    for (const si of sgrid.get(Math.floor(x / CELL) * 65536 + Math.floor(z / CELL)) ?? []) {
      const bb = sbb[si]; if (x < bb[0] || x > bb[2] || z < bb[1] || z > bb[3]) continue
      if (inSect(si, b.bx, b.by)) out.push(si)
    }
    return out
  }
  const sectorFor = (x, z, y, step = STEP) => {
    const list = sectorsAt(x, z)
    let s0 = -1
    if (list.length === 1) s0 = list[0]
    else if (list.length > 1) {
      // highest floor not above the feet (+step); else the lowest one
      let bf = -Infinity; let lo = Infinity; let lowest = -1
      for (const si of list) { const f = fl(si, x, z); if (f <= y + step && f > bf) { bf = f; s0 = si } if (f < lo) { lo = f; lowest = si } }
      if (s0 < 0) s0 = lowest
    }
    if (s0 >= 0) return s0
    // open sliding/swinging doors: their (degenerate, collapsed) sector stands for the whole door frame
    for (const o of doorBoxes) if (S[o.si].__open && x >= o.x0 && x <= o.x1 && z >= o.z0 && z <= o.z1) return o.si
    return -1
  }
  // does wall `s` stop a body at feet y with height h, coming from the `own` side?
  const blocks = (s, x, z, y, h, step) => {
    if (s.y0 != null) return y + h > s.y0 && y + step < s.y1 // sprite wall: only where the body overlaps it
    // walls of a sector entirely above or below the body (overlapping rooms) do not matter
    if (s.own >= 0) {
      const lo = Math.min(fl(s.own, x, z), s.ns >= 0 ? fl(s.ns, x, z) : Infinity); const hi = Math.max(ce(s.own, x, z), s.ns >= 0 ? ce(s.ns, x, z) : -Infinity)
      if (y + h <= lo + 0.01 || y >= hi - 0.01) return false
    }
    if (s.ns < 0) return !(S[s.own] && S[s.own].__open && s.thin) // open door slab: its side walls swing away too
    if (s.block && !(S[s.own].__open || S[s.ns].__open)) return true
    const f = Math.max(fl(s.ns, x, z), fl(s.own, x, z)); const c = Math.min(ce(s.ns, x, z), ce(s.own, x, z))
    const fN = fl(s.ns, x, z); const fO = fl(s.own, x, z)
    // which side is higher matters: we only block if the far side is too high / too low a gap
    const farF = Math.max(fN, fO)
    if (farF > y + step) return true
    if (c - Math.max(f, y) < h) return true
    return false
  }
  // horizontal move from (x,z) by (dx,dz); returns the clipped position
  const slide = (x, z, y, dx, dz, r = 0.3, h = 1.5, step = STEP) => {
    const len = Math.hypot(dx, dz)
    const n = Math.max(1, Math.ceil(len / (r * 0.5)))
    let px = x; let pz = z
    for (let k = 0; k < n; k++) {
      const ox = px; const oz = pz
      px += dx / n; pz += dz / n
      for (let it = 0; it < 3; it++) {
        let moved = false
        for (const s of near(px, pz)) {
          const ex = s.bx - s.ax; const ez = s.bz - s.az; const L2 = ex * ex + ez * ez; if (!L2) continue
          let t = ((px - s.ax) * ex + (pz - s.az) * ez) / L2; t = Math.max(0, Math.min(1, t))
          const cx = s.ax + ex * t; const cz = s.az + ez * t
          let ddx = px - cx; let ddz = pz - cz; let dist = Math.hypot(ddx, ddz)
          if (dist >= r) continue
          if (!blocks(s, cx, cz, y, h, step)) continue
          // push towards the side we came from (no tunnelling: sub-steps are < r/2)
          const side = Math.sign((ox - s.ax) * ez - (oz - s.az) * ex) || 1
          const nx = ez / Math.sqrt(L2) * side; const nz = -ex / Math.sqrt(L2) * side
          if (dist < 1e-4 || (ddx * nx + ddz * nz) < 0) { ddx = nx; ddz = nz; dist = 0 } else { ddx /= dist; ddz /= dist }
          const push = r - dist + 1e-3
          px += ddx * push; pz += ddz * push; moved = true
        }
        if (!moved) break
      }
      if (sectorFor(px, pz, y) < 0) { px = ox; pz = oz; break } // never leave the level
    }
    return { x: px, z: pz }
  }
  // floor (highest reachable under the body) and ceiling (lowest) around a point
  const ground = (x, z, y, r = 0.3, step = STEP) => {
    let floor = -Infinity; let ceil = Infinity; let sect = -1
    for (const [ax, az] of [[0, 0], [r * 0.7, 0], [-r * 0.7, 0], [0, r * 0.7], [0, -r * 0.7]]) {
      const si = sectorFor(x + ax, z + az, y)
      if (si < 0) continue
      const f = fl(si, x + ax, z + az)
      if (ax === 0 && az === 0) sect = si
      if (f <= y + step && f > floor) floor = f
      ceil = Math.min(ceil, ce(si, x + ax, z + az))
    }
    if (sect < 0) return null
    if (floor === -Infinity) floor = fl(sect, x, z) // sunk below the floor (fast fall, lift moving up): back on top
    const pf = platAt(x, z, y, step); if (pf > floor) floor = pf
    return { floor, ceil, sect, lotag: S[sect].lotag }
  }
  d.phys = { slide, ground, sectorFor, fl, ce, segs }
  return d.phys
}

// open state of a door sector: a plain passage at the height of the rooms around it
// (ceiling doors rise, swinging/sliding door slabs drop away), or null if it is no closed door
function doorOpen (m, si, any = false) {
  const S = m.sectors; const W = m.walls; const s = S[si]
  if (!any && !DOOR_LT.has(s.lotag)) return null
  const nb = new Set(); for (let i = s.wallptr; i < s.wallptr + s.wallnum; i++) { const n = W[i].ns; if (n >= 0 && !DOOR_LT.has(S[n].lotag)) nb.add(n) }
  if (!nb.size) return null
  const fl = [...nb].map(n => S[n].fz)
  // floor: the highest neighbour floor that is not above the door floor, else the lowest neighbour floor
  const below = fl.filter(z => z >= s.fz - 64).sort((a, b) => a - b)
  const f1 = below.length ? below[0] : Math.max(...fl)
  const cs = [...nb].map(n => S[n].cz).filter(z => f1 - z >= 1.7 * 8192).sort((a, b) => b - a)
  const c1 = cs[0] ?? f1 - 2 * 8192
  if (s.fz - s.cz >= 1.7 * 8192 && Math.abs(s.fz - f1) < 1024) {
    // already full height: swinging/sliding doors (SE11/SE15) whose panels are the sector's own one-sided walls
    return SLIDE_LT.has(s.lotag) ? { f1: s.fz, c1: s.cz, slide: true } : null
  }
  return { f1, c1 }
}
function liftTarget (m, si) {
  const S = m.sectors; const W = m.walls; const s = S[si]
  if (!LIFT_LT.has(s.lotag)) return null
  const fs = []; for (let i = s.wallptr; i < s.wallptr + s.wallnum; i++) { const n = W[i].ns; if (n >= 0 && Math.abs(S[n].fz - s.fz) > 1024) fs.push(S[n].fz) }
  const up = s.lotag === 17 || s.lotag === 19
  const above = fs.filter(z => z < s.fz).sort((a, b) => b - a)[0]; const below = fs.filter(z => z > s.fz).sort((a, b) => a - b)[0]
  const f1 = up ? above ?? below : below ?? above
  return f1 == null ? null : { f1, moveC: s.lotag === 18 || s.lotag === 19 }
}
// SE7 transports (Duke's room-over-room drops): pairs of sector effector sprites sharing a hitag
function transports (d) {
  if (d.tele) return d.tele
  const by = new Map()
  for (const sp of d.m.sprites) if (sp.pic === 1 && sp.lotag === 7) { let l = by.get(sp.hitag); if (!l) by.set(sp.hitag, l = []); l.push(sp) }
  const out = []
  for (const l of by.values()) {
    if (l.length !== 2) continue
    for (const [a, b] of [[l[0], l[1]], [l[1], l[0]]]) {
      const S = d.m.sectors; const W = d.m.walls; const A = S[a.sect]
      // a -> b when a is a drop shaft (its floor well below every neighbour floor): falling into it lands in b,
      // offset by the two effector sprites (x, z and height)
      let minN = Infinity; for (let i = A.wallptr; i < A.wallptr + A.wallnum; i++) { const n = W[i].ns; if (n >= 0) minN = Math.min(minN, A.fz - S[n].fz) }
      if (minN >= 2 * 8192) out.push({ from: a.sect, to: b.sect, dx: (b.x - a.x) / d.XY, dz: (b.y - a.y) / d.XY, dy: d.zToY(b.z) - d.zToY(a.z) })
    }
  }
  d.tele = out
  return out
}

// SE13 (C-9 explosive): sectors that open (cracked wall / blocked passage) when something explodes next to them
function explosives (d) {
  if (d.boom) return d.boom
  const out = []; const seen = new Set()
  for (const sp of d.m.sprites) {
    if (sp.pic !== 1 || sp.lotag !== 13 || seen.has(sp.sect)) continue
    seen.add(sp.sect)
    const o = doorOpen(d.m, sp.sect, true); if (!o) continue
    const w = d.toWorld(sp.x, sp.y)
    out.push({ si: sp.sect, x: w.x, z: w.z, y: d.zToY(sp.z), ...o, hitag: sp.hitag })
  }
  d.boom = out
  return out
}

module.exports = { explosives, STEP, makePhys, doorOpen, liftTarget, transports, DOOR_LT, LIFT_LT }
