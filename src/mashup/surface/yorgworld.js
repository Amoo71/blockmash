// BlockMash: placement of the real Yorg race track (converted by tools/yorg/fetch_track.py) in the world,
// shared by the world generator (block layer under the track), the server (race/teleport) and the client renderer.
// Data: globalThis.blockmashYorgTrack = { meta (mesh.json), ground: ArrayBuffer (ground.bin) } preloaded by index.ts.
'use strict'
const OX = 0; const OZ = 640 // track-local origin in world blocks (south of spawn, clear of the Duke strip)
const YG = 67 // world y of track-local y = 0 (Yorg roads sit at about -1.4 -> y 65.6)
const MARGIN = 40 // terrain blends from the track level back to natural terrain over this distance
let cache = null

function getYorg () {
  const raw = globalThis.blockmashYorgTrack
  if (!raw) return null
  if (cache && cache.raw === raw) return cache
  const { meta, ground } = raw
  const g = meta.grid; const N = g.nx * g.nz
  const H = new Float32Array(ground, 0, N); const K = new Uint8Array(ground, N * 4, N)
  // world bbox of the drivable area (Y-up local: x, z = -panda_y)
  const bbox = { x0: OX + g.x0, x1: OX + g.x0 + g.nx, z0: OZ - (g.y0 + g.nz), z1: OZ - g.y0 }
  const cell = (x, z) => { // world block column containing (x, z) -> heightfield cell (panda y = -local z)
    const i = Math.floor(Math.floor(x) + 0.5 - OX) - g.x0; const j = Math.floor(-(Math.floor(z) + 0.5 - OZ)) - g.y0
    if (i < 0 || j < 0 || i >= g.nx || j >= g.nz) return -1
    return i * g.nz + j
  }
  /** surface at world (x, z): { y (world), kind 1 road / 2 offroad / 3 wall } or null */
  const surf = (x, z) => {
    const c = cell(x, z)
    if (c < 0 || H[c] < -900) return null
    return { y: YG + H[c], kind: K[c] }
  }
  const dist = (x, z) => Math.hypot(Math.max(bbox.x0 - x, 0, x - bbox.x1), Math.max(bbox.z0 - z, 0, z - bbox.z1))
  const toWorld = (p) => ({ x: OX + p[0], y: YG + p[1], z: OZ + p[2] })
  // racing line (closed polyline) in world coordinates, rotated so that s = 0 is at the start line
  let path = meta.path.map(toWorld)
  const starts = meta.starts.map(toWorld)
  if (path.length > 2 && starts.length) {
    const s0 = starts[0]; let bi = 0; let bd = 1e9
    path.forEach((p, i) => { const d = (p.x - s0.x) ** 2 + (p.z - s0.z) ** 2; if (d < bd) { bd = d; bi = i } })
    path = [...path.slice(bi), ...path.slice(0, bi)]
    // direction: the grid (start 1 in front of start 2) must point along +s
    if (starts.length > 1) {
      const fx = starts[0].x - starts[1].x; const fz = starts[0].z - starts[1].z
      const nx = path[1].x - path[0].x; const nz = path[1].z - path[0].z
      const px = path[path.length - 1].x - path[0].x; const pz = path[path.length - 1].z - path[0].z
      if (fx * nx + fz * nz < fx * px + fz * pz) path = [path[0], ...path.slice(1).reverse()]
    }
  }
  const cum = [0]
  for (let i = 1; i <= path.length; i++) { const a = path[i - 1]; const b = path[i % path.length]; cum.push(cum[i - 1] + Math.hypot(b.x - a.x, b.z - a.z)) }
  const L = cum[path.length]
  cache = { raw, meta, OX, OZ, YG, MARGIN, bbox, surf, dist, path, cum, L, starts, center: { x: (bbox.x0 + bbox.x1) / 2, z: (bbox.z0 + bbox.z1) / 2 } }
  globalThis.blockmashYorg3d = cache
  return cache
}
module.exports = { getYorg, OX, OZ, YG }
