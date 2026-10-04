// Renders the locally extracted Duke Nukem 3D map (Build engine sectors/walls/sprites) as real polygons on the
// BlockMash surface. Tiles are packed into one atlas -> 2 draw calls (opaque + masked). Shareware data is never shipped.
import * as THREE from 'three'
import { GeoBuilder, surfaceMaterial } from './surfmat'

const SKIP_SPRITE = (p: number) => p <= 10 || (p >= 21 && p <= 60) || p === 100 || (p >= 1680 && p < 1760) || (p >= 1820 && p <= 1830) || (p >= 2000 && p <= 2050) || (p >= 2630 && p <= 2700) || p === 1405 || p === 2271
export type VoxSource = { pos: number[], idx: number[], tc: number[] }

export type DukeLight = { x: number, y: number, z: number, r: number, c: [number, number, number] }

export async function buildDukeMap (dm: any, base: string, tiles: Record<string, { w: number, h: number, avg?: number[], glow?: number }>) {
  const { m, ox, oz, G, zref } = dm
  const W = m.walls; const S = m.sectors
  const X = (bx: number) => ox + bx / 512; const Z = (by: number) => oz + by / 512; const Y = (bz: number) => G + (zref - bz) / 8192 // original Build scale
  const shadeC = (s: number) => Math.max(0.4, Math.min(1.7, 1.55 - s / 48))
  // ---- atlas
  const used = new Set<number>()
  for (const s of S) { used.add(s.fpic); if (!(s.cstat & 1)) used.add(s.cpic) }
  for (const w of W) { used.add(w.pic); if (w.cstat & 16) used.add(w.opic) }
  for (const sp of m.sprites) if (!SKIP_SPRITE(sp.pic) && !(sp.cstat & 32768)) used.add(sp.pic)
  const list = [...used].filter(p => tiles[p]).sort((a, b) => tiles[b].h - tiles[a].h)
  let AW = 2048; let place = new Map<number, [number, number]>(); let AH = 0
  for (const tryW of [2048, 4096]) {
    AW = tryW; place = new Map(); let x = 0; let y = 0; let rowH = 0
    for (const p of list) {
      const t = tiles[p]
      if (x + t.w > AW) { x = 0; y += rowH; rowH = 0 }
      place.set(p, [x, y]); x += t.w; rowH = Math.max(rowH, t.h)
    }
    AH = y + rowH
    if (AH <= tryW) break
  }
  AH = 1 << Math.ceil(Math.log2(Math.max(AH, 16)))
  const canvas = document.createElement('canvas'); canvas.width = AW; canvas.height = AH
  const ctx = canvas.getContext('2d')!
  await Promise.all(list.map(async p => {
    const img = new Image(); img.src = `${base}/tiles/${p}.png`
    try { await img.decode(); const [x, y] = place.get(p)!; ctx.drawImage(img, x, y) } catch {}
  }))
  const atlas = new THREE.CanvasTexture(canvas)
  atlas.flipY = false; atlas.magFilter = THREE.NearestFilter; atlas.minFilter = THREE.NearestFilter; atlas.generateMipmaps = false
  atlas.colorSpace = THREE.SRGBColorSpace
  const tinfo = (p: number) => { const pl = place.get(p); const t = tiles[p]; return pl ? [pl[0], pl[1], t.w, t.h] : null }
  const avg = (p: number): [number, number, number] => (tiles[p]?.avg as any) ?? [120, 120, 120]

  const solid = new GeoBuilder(true); const masked = new GeoBuilder(true)
  const fz = (si: number, bx: number, by: number) => dm.floorZ(si, bx, by)
  const cz = (si: number, bx: number, by: number) => dm.ceilZ(si, bx, by)
  // ---- walls
  let curSect = -1
  const facesIn = (w: any, w2: any) => {
    const dx = w2.x - w.x; const dy = w2.y - w.y; const l = Math.hypot(dx, dy) || 1
    const mx = (w.x + w2.x) / 2 - dy / l * 24; const my = (w.y + w2.y) / 2 + dx / l * 24
    return dm.sectorAt(mx, my) === curSect
  }
  const wallQuad = (g: GeoBuilder, w: any, w2: any, z1a: number, z1b: number, z0a: number, z0b: number, pic: number, ref: number, sh: number) => {
    // z1 = top (smaller build z), z0 = bottom at both ends
    const t = tinfo(pic); if (!t) return
    if (z0a <= z1a && z0b <= z1b) return
    const tw = t[2]; const th = t[3]
    const uL = w.xr * 8; const pan = w.xp
    const vs = (bz: number) => (bz - ref) * w.yr / 2048 + w.yp * th / 256
    const c = shadeC(sh); g.cur = avg(pic)
    const a = g.v(X(w.x), Y(z0a), Z(w.y), pan, vs(z0a), c, t); const b = g.v(X(w2.x), Y(z0b), Z(w2.y), pan + uL, vs(z0b), c, t)
    const d = g.v(X(w2.x), Y(z1b), Z(w2.y), pan + uL, vs(z1b), c, t); const e = g.v(X(w.x), Y(z1a), Z(w.y), pan, vs(z1a), c, t)
    if (g !== solid || facesIn(w, w2)) g.quad(a, b, d, e); else g.quad(b, a, e, d)
    void tw
  }
  // real light sources of the level: walls/sprites drawn with negative (bright) Build shade, tiles with fullbright colours
  const lights: DukeLight[] = []
  const lightOf = (pic: number, shade: number, x: number, y: number, z: number) => {
    const g = tiles[pic]?.glow ?? 0
    if (shade > -6 && g < 0.01) return
    const a = avg(pic); const mx = Math.max(a[0], a[1], a[2], 1)
    const k = Math.min(1.6, 0.5 + Math.max(-shade, 0) / 24 + g * 4)
    lights.push({ x, y, z, r: 5 + Math.min(7, Math.max(-shade, 0) / 4), c: [a[0] / mx * k, a[1] / mx * k, a[2] / mx * k] })
  }
  const setEnv = (g: GeoBuilder, s: any) => { g.outdoor = s.cstat & 1 ? 1 : 0; g.vis = (s.vis ?? 0) / 255 }
  S.forEach((s: any, si: number) => {
    curSect = si
    setEnv(solid, s); setEnv(masked, s)
    for (let i = s.wallptr; i < s.wallptr + s.wallnum; i++) {
      const w = W[i]; const w2 = W[w.p2]
      const fa = fz(si, w.x, w.y); const fb = fz(si, w2.x, w2.y); const ca = cz(si, w.x, w.y); const cb = cz(si, w2.x, w2.y)
      if (w.ns < 0 || w.cstat & 16) {
        const zm = Math.max((fa + fb) / 2 - 6 * 8192, (fa + ca) / 2)
        const nx = -(w2.y - w.y); const ny = w2.x - w.x; const l = Math.hypot(nx, ny) || 1
        lightOf(w.cstat & 16 ? w.opic : w.pic, w.shade, X((w.x + w2.x) / 2 + nx / l * 300), Y(zm), Z((w.y + w2.y) / 2 + ny / l * 300))
      }
      if (w.ns < 0) {
        // walls under a parallax sky: Build draws them up to the (very high) sky ceiling; cap them at ~12 blocks
        const cap = s.cstat & 1 ? Math.min(fa, fb) - 12 * 8192 : -Infinity
        wallQuad(solid, w, w2, Math.max(ca, cap), Math.max(cb, cap), fa, fb, w.pic, w.cstat & 4 ? s.fz : s.cz, w.shade)
        // map boundary: also give the wall a real Duke exterior face down into the ground (hides the block fill)
        const dx = w2.x - w.x; const dy = w2.y - w.y; const l = Math.hypot(dx, dy) || 1
        const ox2 = (w.x + w2.x) / 2 + dy / l * 24; const oy2 = (w.y + w2.y) / 2 - dx / l * 24
        if (dm.sectorAt(ox2, oy2) < 0) {
          const deep = zref + (G - 40) * 8192
          const save = curSect; curSect = -2 // facesIn() false -> reversed winding = outward face
          wallQuad(solid, w, w2, Math.max(ca, cap), Math.max(cb, cap), deep, deep, w.pic, s.cz, w.shade + 4)
          curSect = save
        }
        continue
      }
      const n = S[w.ns]; const ni = w.ns
      const nfa = fz(ni, w.x, w.y); const nfb = fz(ni, w2.x, w2.y); const nca = cz(ni, w.x, w.y); const ncb = cz(ni, w2.x, w2.y)
      // lower step (neighbour floor higher = smaller z)
      if (nfa < fa || nfb < fb) {
        const bw = w.cstat & 2 ? W[w.nw] ?? w : w
        wallQuad(solid, w, w2, nfa, nfb, fa, fb, bw.pic, w.cstat & 4 ? s.cz : n.fz, w.shade)
      }
      // upper part (neighbour ceiling lower), skipped between two sky ceilings
      if ((nca > ca || ncb > cb) && !((s.cstat & 1) && (n.cstat & 1))) wallQuad(solid, w, w2, ca, cb, nca, ncb, w.pic, w.cstat & 4 ? s.cz : n.cz, w.shade)
      if (w.cstat & 16) wallQuad(masked, w, w2, Math.max(ca, nca), Math.max(cb, ncb), Math.min(fa, nfa), Math.min(fb, nfb), w.opic, w.cstat & 4 ? Math.min(s.fz, n.fz) : Math.max(s.cz, n.cz), w.shade)
    }
  })
  // ---- floors / ceilings
  S.forEach((s: any, si: number) => {
    setEnv(solid, s)
    const loops: number[][] = dm.loops[si]
    if (!loops.length) return
    const area = (l: number[]) => { let a = 0; for (let k = 0; k < l.length; k++) { const p = W[l[k]]; const q = W[l[(k + 1) % l.length]]; a += p.x * q.y - q.x * p.y } return Math.abs(a) }
    const order = [...loops].sort((a, b) => area(b) - area(a))
    const outer = order[0].map(i => new THREE.Vector2(W[i].x, W[i].y))
    const holes = order.slice(1).map(l => l.map(i => new THREE.Vector2(W[i].x, W[i].y)))
    let tris: number[][]
    try { tris = THREE.ShapeUtils.triangulateShape(outer, holes) } catch { return }
    const pts = [...outer, ...holes.flat()]
    const plane = (pic: number, sh: number, zf: (bx: number, by: number) => number, flip: boolean) => {
      const t = tinfo(pic); if (!t) return
      const c = shadeC(sh); solid.cur = avg(pic)
      const base = solid.n
      for (const p of pts) solid.v(X(p.x), Y(zf(p.x, p.y)), Z(p.y), p.x / 16, p.y / 16, c, t)
      for (const [a, b, d] of tris) {
        // floors face up, ceilings face down (FrontSide: from outside/below the level you look into it, no dark box)
        const A = pts[a]; const B = pts[b]; const D = pts[d]
        const ny = (B.y - A.y) * (D.x - A.x) - (B.x - A.x) * (D.y - A.y)
        const up = ny > 0
        if (up !== flip) solid.tri(base + a, base + b, base + d); else solid.tri(base + a, base + d, base + b)
      }
    }
    plane(s.fpic, s.fshade, (x, y) => fz(si, x, y), false)
    if (!(s.cstat & 1)) plane(s.cpic, s.cshade, (x, y) => cz(si, x, y), true)
  })
  // ---- sprites (decoration only; actors and pickups are live entities)
  for (const sp of m.sprites) {
    if (SKIP_SPRITE(sp.pic) || (sp.cstat & 32768)) continue
    const t = tinfo(sp.pic); if (!t) continue
    const wB = t[2] * sp.xr / 4 / 512; const hB = t[3] * sp.yr * 4 / 8192
    if (wB <= 0 || hB <= 0) continue
    const cx = X(sp.x); const czz = Z(sp.y); let yb = Y(sp.z); if (sp.cstat & 128) yb -= hB / 2
    const c = shadeC(sp.shade); masked.cur = avg(sp.pic)
    if (S[sp.sect]) setEnv(masked, S[sp.sect])
    lightOf(sp.pic, sp.shade, cx, yb + hB / 2, czz)
    const a = sp.ang / 2048 * Math.PI * 2
    const kind = sp.cstat & 48
    const quad = (dx: number, dz: number) => {
      const p = masked.v(cx - dx * wB / 2, yb, czz - dz * wB / 2, 0, t[3] - 0.01, c, t); const q = masked.v(cx + dx * wB / 2, yb, czz + dz * wB / 2, t[2] - 0.01, t[3] - 0.01, c, t)
      const r = masked.v(cx + dx * wB / 2, yb + hB, czz + dz * wB / 2, t[2] - 0.01, 0, c, t); const s = masked.v(cx - dx * wB / 2, yb + hB, czz - dz * wB / 2, 0, 0, c, t)
      masked.quad(p, q, r, s)
    }
    if (kind === 16) quad(Math.sin(a), -Math.cos(a))
    else if (kind === 32) {
      const ux = Math.cos(a); const uz = Math.sin(a); const vx = -uz; const vz = ux; const hh = t[3] * sp.yr / 4 / 512
      const y = Y(sp.z) + 0.01
      const p = masked.v(cx - ux * wB / 2 - vx * hh / 2, y, czz - uz * wB / 2 - vz * hh / 2, 0, 0, c, t); const q = masked.v(cx + ux * wB / 2 - vx * hh / 2, y, czz + uz * wB / 2 - vz * hh / 2, t[2] - 0.01, 0, c, t)
      const r = masked.v(cx + ux * wB / 2 + vx * hh / 2, y, czz + uz * wB / 2 + vz * hh / 2, t[2] - 0.01, t[3] - 0.01, c, t); const s = masked.v(cx - ux * wB / 2 + vx * hh / 2, y, czz - uz * wB / 2 + vz * hh / 2, 0, t[3] - 0.01, c, t)
      masked.quad(p, q, r, s)
    } else { quad(1, 0); quad(0, 1) } // face sprite -> static cross billboard (cheap, merged)
  }
  const mk = (g: GeoBuilder, alpha: boolean) => {
    const mat = surfaceMaterial({ map: atlas, atlas: true, side: alpha ? THREE.DoubleSide : THREE.FrontSide, alphaTest: alpha ? 0.5 : undefined })
    mat.uniforms.uAtlas.value.set(AW, AH)
    const mesh = new THREE.Mesh(g.build(), mat)
    mesh.name = alpha ? 'duke-masked' : 'duke-level'
    mesh.frustumCulled = false
    mesh.castShadow = !alpha
    return mesh
  }
  const group = new THREE.Group(); group.name = 'blockmash-duke-map'
  group.add(mk(solid, false), mk(masked, true))
  const sources: VoxSource[] = [{ pos: solid.pos, idx: solid.idx, tc: solid.tc }]
  // parallax sky of this level (most used parallaxed ceiling tile, e.g. the LA skyline)
  const skyCount = new Map<number, number>()
  for (const s of S) if (s.cstat & 1) skyCount.set(s.cpic, (skyCount.get(s.cpic) ?? 0) + 1)
  const sky = [...skyCount].sort((a, b) => b[1] - a[1])[0]?.[0]
  return { group, sources, lights, sky }
}
