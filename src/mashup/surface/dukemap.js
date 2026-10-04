// Build-engine map (Duke Nukem 3D) placed into the BlockMash world. Pure JS, shared by the world generator
// (column heights + invisible collision for the block layer) and the client mesh renderer.
// Map data comes from the user's local shareware extraction (assets/duke/maps/*.json) and is never shipped.
'use strict'
const XY = 512 // build units per block (horizontal)
const ZS = XY * 16 // build z units per block (vertical, z grows downward)

function prepare (m, { ox, oz, G, zref = 8192 }) {
  const W = m.walls; const S = m.sectors
  const toWorld = (bx, by) => ({ x: ox + bx / XY, z: oz + by / XY })
  const toBuild = (x, z) => ({ bx: (x - ox) * XY, by: (z - oz) * XY })
  const zToY = (bz) => G + (zref - bz) / ZS
  // loops per sector (first = outer)
  const loops = S.map(s => {
    const out = []; const seen = new Set()
    for (let i = s.wallptr; i < s.wallptr + s.wallnum; i++) {
      if (seen.has(i)) continue
      const loop = []; let j = i
      while (!seen.has(j) && j >= s.wallptr && j < s.wallptr + s.wallnum) { seen.add(j); loop.push(j); j = W[j].p2 }
      out.push(loop)
    }
    return out
  })
  let x0 = Infinity; let y0 = Infinity; let x1 = -Infinity; let y1 = -Infinity
  for (const w of W) { x0 = Math.min(x0, w.x); x1 = Math.max(x1, w.x); y0 = Math.min(y0, w.y); y1 = Math.max(y1, w.y) }
  // sector bounding boxes + coarse grid index
  const CELL = 2048
  const grid = new Map()
  const sbb = S.map((s, si) => {
    let a = Infinity; let b = Infinity; let c = -Infinity; let d = -Infinity
    for (let i = s.wallptr; i < s.wallptr + s.wallnum; i++) { a = Math.min(a, W[i].x); c = Math.max(c, W[i].x); b = Math.min(b, W[i].y); d = Math.max(d, W[i].y) }
    for (let gx = Math.floor(a / CELL); gx <= Math.floor(c / CELL); gx++) {
      for (let gy = Math.floor(b / CELL); gy <= Math.floor(d / CELL); gy++) { const k = gx + ',' + gy; if (!grid.has(k)) grid.set(k, []); grid.get(k).push(si) }
    }
    return [a, b, c, d]
  })
  const inSector = (si, bx, by) => {
    const bb = sbb[si]; if (bx < bb[0] || bx > bb[2] || by < bb[1] || by > bb[3]) return false
    let inside = false; const s = S[si]
    for (let i = s.wallptr; i < s.wallptr + s.wallnum; i++) {
      const a = W[i]; const b = W[a.p2]
      if ((a.y > by) !== (b.y > by) && bx < (b.x - a.x) * (by - a.y) / (b.y - a.y) + a.x) inside = !inside
    }
    return inside
  }
  const sectorAt = (bx, by, low = false) => {
    const c = grid.get(Math.floor(bx / CELL) + ',' + Math.floor(by / CELL))
    if (!c) return -1
    let best = -1
    for (const si of c) if (inSector(si, bx, by)) { if (best < 0 || (low ? S[si].fz > S[best].fz : S[si].fz < S[best].fz)) best = si } // overlapping rooms: the higher floor (or the lowest, for the block fill under every room)
    return best
  }
  const slopeZ = (si, base, heinum, bx, by) => {
    if (!heinum) return base
    const w = W[S[si].wallptr]; const w2 = W[w.p2]
    const dx = w2.x - w.x; const dy = w2.y - w.y; const len = Math.hypot(dx, dy)
    if (!len) return base
    // Build getzofslope(): z + heinum * dmulscale3(dx, y - wy, -dy, x - wx) / (len << 5)
    const j = (dx * (by - w.y) - dy * (bx - w.x)) / 8
    return base + heinum * j / (len * 32)
  }
  const floorZ = (si, bx, by) => slopeZ(si, S[si].fz, S[si].fstat & 2 ? S[si].fheinum : 0, bx, by)
  const ceilZ = (si, bx, by) => slopeZ(si, S[si].cz, S[si].cstat & 2 ? S[si].cheinum : 0, bx, by)
  const wb0 = toWorld(x0, y0); const wb1 = toWorld(x1, y1)
  const bbox = { x0: Math.floor(wb0.x) - 2, z0: Math.floor(wb0.z) - 2, x1: Math.ceil(wb1.x) + 2, z1: Math.ceil(wb1.z) + 2 }
  const NX = bbox.x1 - bbox.x0; const NZ = bbox.z1 - bbox.z0
  // per column: top face of the block fill, barrier range, kind (0 outside map, 1 walkable sector, 2 wall/void)
  const top = new Int16Array(NX * NZ); const bar0 = new Int16Array(NX * NZ); const bar1 = new Int16Array(NX * NZ); const kind = new Uint8Array(NX * NZ)
  const sectOfCol = new Int16Array(NX * NZ).fill(-1)
  for (let i = 0; i < NX; i++) {
    for (let k = 0; k < NZ; k++) {
      const idx = i * NZ + k; const x = bbox.x0 + i; const z = bbox.z0 + k
      const c = toBuild(x + 0.5, z + 0.5); const sc = sectorAt(c.bx, c.by, true)
      if (sc < 0) {
        // outside every sector: map exterior (no walls around) or solid wall/pillar mass
        let near = false; let lo = G
        for (const [dx, dz] of [[-1, 0], [1, 0], [0, -1], [0, 1], [-1, -1], [1, 1], [-1, 1], [1, -1]]) { const p = toBuild(x + 0.5 + dx * 1.5, z + 0.5 + dz * 1.5); const s2 = sectorAt(p.bx, p.by, true); if (s2 >= 0) { near = true; lo = Math.min(lo, Math.floor(zToY(floorZ(s2, p.bx, p.by)))) } }
        // wall mass: blocks never stick out above the lowest floor next to it (they would show as MC walls)
        kind[idx] = near ? 2 : 0; top[idx] = near ? Math.min(G, lo) : G; if (near) { bar0[idx] = top[idx]; bar1[idx] = top[idx] + 10 }
        continue
      }
      sectOfCol[idx] = sc
      let fy = zToY(floorZ(sc, c.bx, c.by)); let wall = false
      for (const [dx, dz] of [[0, 0], [1, 0], [0, 1], [1, 1]]) {
        const p = toBuild(x + dx, z + dz); let s2 = sectorAt(p.bx, p.by, true)
        if (s2 < 0) { wall = true; s2 = sc }
        fy = Math.min(fy, zToY(floorZ(s2, p.bx, p.by)))
      }
      const cy = zToY(ceilZ(sc, c.bx, c.by))
      top[idx] = Math.floor(fy + 1e-3)
      // columns on the map boundary: keep the block fill low so it never pokes out through the exterior walls
      if (wall) { let outside = false; for (const [dx, dz] of [[0, 0], [1, 0], [0, 1], [1, 1]]) { const p = toBuild(x + dx, z + dz); if (sectorAt(p.bx, p.by) < 0) outside = true } if (outside) top[idx] = Math.min(top[idx], G - 3) }
      kind[idx] = 1
      if (cy - zToY(floorZ(sc, c.bx, c.by)) < 1.2) { bar0[idx] = top[idx]; bar1[idx] = top[idx] + 4 } // closed door / crawl space
      else if (wall) { // column touches a solid wall: block it only if most of the cell is outside
        let out = 0
        for (const [dx, dz] of [[0.2, 0.2], [0.8, 0.2], [0.2, 0.8], [0.8, 0.8]]) { const p = toBuild(x + dx, z + dz); if (sectorAt(p.bx, p.by) < 0) out++ }
        if (out >= 3) { bar0[idx] = top[idx]; bar1[idx] = top[idx] + 10 }
      }
    }
  }
  const col = (x, z) => {
    const i = Math.floor(x) - bbox.x0; const k = Math.floor(z) - bbox.z0
    if (i < 0 || k < 0 || i >= NX || k >= NZ) return null
    const idx = i * NZ + k
    return { top: top[idx], bar0: bar0[idx], bar1: bar1[idx], kind: kind[idx], sect: sectOfCol[idx] }
  }
  // exact walkable floor (world y) at a world point, or null outside sectors
  const floorAt = (x, z) => { const b = toBuild(x, z); const s = sectorAt(b.bx, b.by); return s < 0 ? null : { y: zToY(floorZ(s, b.bx, b.by)), ceil: zToY(ceilZ(s, b.bx, b.by)), sect: s } }
  const start = { ...toWorld(m.start.x, m.start.y), y: zToY(floorZ(m.start.sect, m.start.x, m.start.y)), yaw: Math.atan2(-Math.cos(m.start.ang / 2048 * Math.PI * 2), -Math.sin(m.start.ang / 2048 * Math.PI * 2)) }
  return { m, XY, ZS, ox, oz, G, zref, loops, toWorld, toBuild, zToY, sectorAt, floorZ, ceilZ, floorAt, col, bbox, start }
}

module.exports = { prepare, XY, ZS }
