// BlockMash polygon surface (client). Only the underground is Minecraft blocks: on top of the block world the
// player sees smooth CC0-textured heightmap terrain, the locally extracted Duke3D level, Dark Mod buildings and
// the Yorg track. Blocks stay authoritative (mining, physics, mobs): terrain cells are drawn only where their
// natural top block still exists, so mining/explosions open real holes onto the block world. Craters also clip
// all meshes via a shared hole list and get a mesh-to-voxel rim (cut triangles voxelised into colour-matched blocks).
import * as THREE from 'three'
import { Vec3 } from 'vec3'
import { surfaceMaterial, loadTex, GeoBuilder, addHoleUniform, dayUniform, inHole } from './surfmat'
import { buildDukeMap, VoxSource } from './dukemap'
import { buildZoneMeshes } from './zonemesh'
import { triBoxOverlap } from '../surface/voxelize'
// eslint-disable-next-line @typescript-eslint/no-require-imports
const layout = require('../layout')
// eslint-disable-next-line @typescript-eslint/no-require-imports
const { getDuke } = require('../surface/dukeworld')

const NATURAL = new Set(['grass_block', 'dirt', 'coarse_dirt', 'sand', 'red_sand', 'sandstone', 'stone', 'gravel', 'clay', 'granite', 'diorite', 'andesite', 'podzol', 'snow_block'])
const OPEN_ABOVE = (n: string | null | undefined) => !n || n === 'air' || n === 'cave_air' || n === 'water' || n.endsWith('_log')
const CS = 32
const PALETTE: Array<[string, number, number, number]> = [
  ['white_concrete', 207, 213, 214], ['light_gray_concrete', 125, 125, 115], ['gray_concrete', 54, 57, 61], ['black_concrete', 8, 10, 15],
  ['brown_concrete', 96, 59, 31], ['red_concrete', 142, 32, 32], ['orange_concrete', 224, 97, 0], ['yellow_concrete', 240, 175, 21],
  ['lime_concrete', 94, 168, 24], ['green_concrete', 73, 91, 36], ['cyan_concrete', 21, 119, 136], ['light_blue_concrete', 35, 137, 198],
  ['blue_concrete', 44, 46, 143], ['purple_concrete', 100, 31, 156], ['pink_concrete', 213, 101, 142], ['terracotta', 152, 94, 67],
  ['white_terracotta', 209, 178, 161], ['light_gray_terracotta', 135, 107, 98], ['brown_terracotta', 77, 51, 35], ['stone', 125, 125, 125],
  ['bricks', 150, 97, 83], ['sandstone', 216, 203, 155], ['dirt', 134, 96, 67], ['stone_bricks', 122, 121, 122], ['dark_oak_planks', 66, 43, 20]
]
const nearestBlock = (r: number, g: number, b: number) => { let best = PALETTE[0]; let bd = 1e9; for (const p of PALETTE) { const d = (p[1] - r) ** 2 + (p[2] - g) ** 2 + (p[3] - b) ** 2; if (d < bd) { bd = d; best = p } } return best[0] }

export async function initSurface () {
  const viewer = (globalThis as any).viewer; const bot = (globalThis as any).bot; const server = (globalThis as any).localServer
  if (!viewer?.scene || !server?.blockmash) return
  const seed = server.overworld?.seed | 0
  const scene: THREE.Scene = viewer.scene
  const mobile = matchMedia('(pointer: coarse)').matches || innerWidth < 1000
  const RADIUS = mobile ? 3 : 5
  const root = new THREE.Group(); root.name = 'blockmash-surface'; scene.add(root)
  const sources: VoxSource[] = []
  const blockName = (x: number, y: number, z: number): string | null | undefined => bot.world.getBlock(new Vec3(x, y, z))?.name

  // ---------------- textures (Poly Haven CC0, fetched at install); flat colours as fallback
  let haveTex = false
  try { haveTex = (await fetch('./surface/manifest.json')).ok } catch {}
  const flat = (r: number, g: number, b: number) => { const t = new THREE.DataTexture(new Uint8Array([r, g, b, 255]), 1, 1); t.needsUpdate = true; t.colorSpace = THREE.SRGBColorSpace; return t }
  const texs = haveTex ? ['grass', 'rock', 'sand', 'snow', 'dirt'].map(n => loadTex(`./surface/${n}.jpg`)) : [flat(96, 140, 60), flat(120, 118, 112), flat(214, 200, 150), flat(240, 244, 250), flat(110, 80, 55)]
  const terrainMat = surfaceMaterial({ terrain: true, textures: texs, texNorm: haveTex } as any)

  // ---------------- heightmap terrain chunks
  type TChunk = { mesh?: THREE.Mesh, trees?: THREE.Mesh, drawn: Uint8Array, h: Int16Array, hs: Float32Array, dirty: boolean, complete: boolean }
  const chunks = new Map<string, TChunk>()
  const SUN = new THREE.Vector3(0.45, 1, 0.3).normalize()
  const treeMat = surfaceMaterial({})
  const buildChunk = (cx: number, cz: number, ch: TChunk) => {
    const x0 = cx * CS; const z0 = cz * CS; const N = CS + 1; const M = CS + 3 // vertex grid with 1-ring margin for normals
    const hs = new Float32Array(M * M)
    for (let i = 0; i < M; i++) for (let k = 0; k < M; k++) hs[i * M + k] = layout.surfaceHeight(x0 + i - 1, z0 + k - 1, seed)
    const H = (i: number, k: number) => hs[(i + 1) * M + (k + 1)]
    ch.hs = hs
    const g = new GeoBuilder(); const mix: number[] = []; const nrm: number[] = []
    const vid = new Int32Array(N * N).fill(-1)
    // smooth biome weights: coarse 4-block grid, 3x3 blurred, bilinear per vertex
    const CG = CS / 4 + 5; const bw = new Float32Array(CG * CG * 3); const bw2 = new Float32Array(CG * CG * 3)
    for (let a = 0; a < CG; a++) {
      for (let c = 0; c < CG; c++) {
        const b = layout.columnInfo(x0 + (a - 2) * 4, z0 + (c - 2) * 4, seed).biome
        const j = (a * CG + c) * 3
        bw[j] = b === 'snowy' ? 1 : 0; bw[j + 1] = b === 'desert' || b === 'beach' ? 1 : 0; bw[j + 2] = 1 - bw[j] - bw[j + 1]
      }
    }
    for (let a = 0; a < CG; a++) {
      for (let c = 0; c < CG; c++) {
        for (let q = 0; q < 3; q++) {
          let sum = 0; let n = 0
          for (let da = -1; da <= 1; da++) for (let dc = -1; dc <= 1; dc++) { const aa = a + da; const cc = c + dc; if (aa < 0 || cc < 0 || aa >= CG || cc >= CG) continue; sum += bw[(aa * CG + cc) * 3 + q]; n++ }
          bw2[(a * CG + c) * 3 + q] = sum / n
        }
      }
    }
    const biomeW = (i: number, k: number) => {
      const fa = i / 4 + 2; const fc = k / 4 + 2; const a = Math.min(CG - 2, Math.floor(fa)); const c = Math.min(CG - 2, Math.floor(fc)); const ta = fa - a; const tc = fc - c
      const out = [0, 0, 0]
      for (let q = 0; q < 3; q++) {
        const v00 = bw2[(a * CG + c) * 3 + q]; const v10 = bw2[((a + 1) * CG + c) * 3 + q]; const v01 = bw2[(a * CG + c + 1) * 3 + q]; const v11 = bw2[((a + 1) * CG + c + 1) * 3 + q]
        out[q] = (v00 * (1 - ta) + v10 * ta) * (1 - tc) + (v01 * (1 - ta) + v11 * ta) * tc
      }
      return out
    }
    const vert = (i: number, k: number) => {
      const j = i * N + k
      if (vid[j] >= 0) return vid[j]
      const y = H(i, k)
      const n = new THREE.Vector3(H(i - 1, k) - H(i + 1, k), 2, H(i, k - 1) - H(i, k + 1)).normalize()
      const [bs, bd, bg] = biomeW(i, k)
      const slope = 1 - n.y
      const rock = Math.min(1, Math.max(0, (slope - 0.1) / 0.18) + Math.max(0, (y - 104) / 10))
      const snow = Math.min(1, bs + Math.max(0, (y - 116) / 6))
      const sand = Math.max(bd, Math.min(1, Math.max(0, (layout.WATER + 3.2 - y) / 2)))
      const grass = Math.max(0, bg - sand * bg)
      let w = [grass * (1 - snow), rock, sand * (1 - snow), snow]
      const s = w[0] + w[1] + w[2] + w[3]; w = w.map(v => v / Math.max(1e-3, s))
      const light = 0.5 + 0.55 * Math.max(0, n.dot(SUN))
      vid[j] = g.v(x0 + i, y, z0 + k, 0, 0, light)
      mix.push(...w); nrm.push(n.x, n.y, n.z)
      return vid[j]
    }
    const drawn = new Uint8Array(CS * CS); const hh = new Int16Array(CS * CS)
    let complete = true
    for (let i = 0; i < CS; i++) {
      for (let k = 0; k < CS; k++) {
        const h = Math.floor(Math.min(H(i, k), H(i + 1, k), H(i, k + 1), H(i + 1, k + 1)) - 0.01) - 1
        hh[i * CS + k] = h
        const top = blockName(x0 + i, h, z0 + k)
        if (top === undefined || top === null) { if (bot.world.getColumnAt?.(new Vec3(x0 + i, 0, z0 + k)) == null) complete = false; continue }
        if (!NATURAL.has(top) || !OPEN_ABOVE(blockName(x0 + i, h + 1, z0 + k))) continue
        drawn[i * CS + k] = 1
      }
    }
    for (let i = 0; i < CS; i++) {
      for (let k = 0; k < CS; k++) {
        if (!drawn[i * CS + k]) continue
        const a = vert(i, k); const b = vert(i + 1, k); const c = vert(i + 1, k + 1); const d = vert(i, k + 1)
        g.idx.push(a, c, b, a, d, c)
      }
    }
    // skirts down to the block top where the neighbour cell is not drawn (hole, structure, zone)
    const skirt = new GeoBuilder()
    const sk = (xa: number, za: number, ya: number, xb: number, zb: number, yb: number, bot0: number, shade: number) => {
      const p = skirt.v(xa, ya, za, 0, 0, shade); const q = skirt.v(xb, yb, zb, 0, 0, shade); const r = skirt.v(xb, bot0, zb, 0, 0, shade); const s2 = skirt.v(xa, bot0, za, 0, 0, shade)
      skirt.quad(p, q, r, s2)
    }
    const isDrawn = (i: number, k: number) => i >= 0 && k >= 0 && i < CS && k < CS ? drawn[i * CS + k] === 1 : true
    for (let i = 0; i < CS; i++) {
      for (let k = 0; k < CS; k++) {
        if (!drawn[i * CS + k]) continue
        const yb = hh[i * CS + k] + 1; const X = x0 + i; const Z = z0 + k
        if (!isDrawn(i - 1, k)) sk(X, Z + 1, H(i, k + 1), X, Z, H(i, k), yb, 0.55)
        if (!isDrawn(i + 1, k)) sk(X + 1, Z, H(i + 1, k), X + 1, Z + 1, H(i + 1, k + 1), yb, 0.55)
        if (!isDrawn(i, k - 1)) sk(X, Z, H(i, k), X + 1, Z, H(i + 1, k), yb, 0.7)
        if (!isDrawn(i, k + 1)) sk(X + 1, Z + 1, H(i + 1, k + 1), X, Z + 1, H(i, k + 1), yb, 0.7)
      }
    }
    // append skirts (dirt: aMix all zero)
    const base = g.n
    for (let v = 0; v < skirt.n; v++) { g.v(skirt.pos[v * 3], skirt.pos[v * 3 + 1], skirt.pos[v * 3 + 2], 0, 0, skirt.col[v * 3]); mix.push(0, 0, 0, 0); nrm.push(1, 0, 0) }
    for (const j of skirt.idx) g.idx.push(base + j)
    if (ch.mesh) { root.remove(ch.mesh); ch.mesh.geometry.dispose(); ch.mesh = undefined }
    if (g.idx.length) {
      const geo = g.build()
      geo.setAttribute('aMix', new THREE.Float32BufferAttribute(mix, 4))
      geo.setAttribute('normal', new THREE.Float32BufferAttribute(nrm, 3))
      ch.mesh = new THREE.Mesh(geo, terrainMat); ch.mesh.name = `terrain ${cx},${cz}`
      root.add(ch.mesh)
    }
    // low-poly trees over the hidden log trunks
    if (ch.trees) { root.remove(ch.trees); ch.trees.geometry.dispose(); ch.trees = undefined }
    const tg = new GeoBuilder()
    const addGeo = (geo: THREE.BufferGeometry, m: THREE.Matrix4, rgb: [number, number, number], jitter: number) => {
      const p = geo.toNonIndexed(); p.applyMatrix4(m); p.computeVertexNormals()
      const P = p.getAttribute('position'); const Nn = p.getAttribute('normal')
      tg.tint = rgb
      for (let v = 0; v < P.count; v += 3) {
        const n = new THREE.Vector3(Nn.getX(v), Nn.getY(v), Nn.getZ(v))
        const l = (0.5 + 0.55 * Math.max(0, n.dot(SUN))) * (1 - jitter / 2 + Math.random() * jitter)
        const a = tg.v(P.getX(v), P.getY(v), P.getZ(v), 0, 0, l); const b = tg.v(P.getX(v + 1), P.getY(v + 1), P.getZ(v + 1), 0, 0, l); const c = tg.v(P.getX(v + 2), P.getY(v + 2), P.getZ(v + 2), 0, 0, l)
        tg.tri(a, b, c)
      }
    }
    const trunk = new THREE.CylinderGeometry(0.62, 0.78, 1, 6); const crown = new THREE.IcosahedronGeometry(1, 0); const cone = new THREE.ConeGeometry(1, 1, 7)
    for (let a = Math.floor(x0 / 6) - 1; a <= Math.floor((x0 + CS) / 6); a++) {
      for (let b = Math.floor(z0 / 6) - 1; b <= Math.floor((z0 + CS) / 6); b++) {
        const t = layout.treeInCell(a, b, seed)
        if (!t || t.x < x0 || t.x >= x0 + CS || t.z < z0 || t.z >= z0 + CS) continue
        const i = t.x - x0; const k = t.z - z0
        if (!drawn[i * CS + k]) continue
        const by = hh[i * CS + k] + 1
        if (!(blockName(t.x, by, t.z) ?? '').endsWith('_log')) continue
        const gy = H(i, k) - 0.3; const cxp = t.x + 0.5; const czp = t.z + 0.5; const s = t.size
        const M4 = (sx: number, sy: number, sz: number, y: number) => new THREE.Matrix4().compose(new THREE.Vector3(cxp, y, czp), new THREE.Quaternion().setFromEuler(new THREE.Euler(0, (t.x * 7 + t.z) % 6, 0)), new THREE.Vector3(sx, sy, sz))
        const top = by + 3
        addGeo(trunk, M4(1, top + 0.6 - gy, 1, (gy + top + 0.6) / 2), t.kind === 'birch' ? [225, 222, 210] : [110, 80, 50], 0)
        if (t.kind === 'spruce') { addGeo(cone, M4(2.6 * s, 3.4 * s, 2.6 * s, top + 1.2 * s), [40, 85, 50], 0.2); addGeo(cone, M4(1.9 * s, 3 * s, 1.9 * s, top + 3.2 * s), [45, 95, 55], 0.2) } else addGeo(crown, M4(2.5 * s, 2.2 * s, 2.5 * s, top + 1.2 * s), t.kind === 'birch' ? [120, 170, 70] : [70, 130, 45], 0.25)
      }
    }
    if (tg.n) { ch.trees = new THREE.Mesh(tg.build(), treeMat); root.add(ch.trees) }
    ch.drawn = drawn; ch.h = hh; ch.dirty = false; ch.complete = complete
  }
  const key = (cx: number, cz: number) => cx + ',' + cz
  const dirtyAt = (x: number, z: number) => { const c = chunks.get(key(Math.floor(x / CS), Math.floor(z / CS))); if (c) c.dirty = true }
  bot.on('blockUpdate', (o: any, n: any) => {
    if (!o?.position) return
    const p = o.position
    dirtyAt(p.x, p.z)
    // mining the floor of the Duke level: punch a small round hole into the polygon floor too
    const dm = (globalThis as any).blockmashDuke
    if (dm && n?.name === 'air' && o.name !== 'air' && o.name !== 'barrier') {
      const c = dm.col(p.x, p.z)
      if (c && c.kind === 1 && p.y === c.top - 1) server.blockmash.addHole(p.x + 0.5, c.top + 0.3, p.z + 0.5, 0.95)
    }
  })
  bot.on('chunkColumnLoad', (p: any) => { for (const [dx, dz] of [[0, 0], [16, 0], [0, 16], [16, 16]]) dirtyAt(p.x + dx - 8, p.z + dz - 8); dirtyAt(p.x, p.z); dirtyAt(p.x + 15, p.z + 15) })

  // ---------------- Duke3D level
  const dm = getDuke(seed)
  if (dm) {
    try {
      const man = await (await fetch('./duke/manifest.json')).json()
      const d = await buildDukeMap(dm, './duke', man.tiles)
      root.add(d.group); sources.push(...d.sources)
    } catch (e) { console.warn('[blockmash] Duke map mesh failed', e) }
  }
  // ---------------- zones (Dark Mod, Yorg)
  const builtZones = new Set<string>()
  const zoneGroups: Array<{ group: THREE.Object3D, x0: number, z0: number, x1: number, z1: number }> = []
  if (dm) { const g = root.getObjectByName('blockmash-duke-map'); if (g) zoneGroups.push({ group: g, x0: dm.bbox.x0, z0: dm.bbox.z0, x1: dm.bbox.x1, z1: dm.bbox.z1 }) }
  const VIS = mobile ? 112 : 176
  const updateZones = () => {
    const p = bot.entity?.position; if (!p) return
    for (const z of buildZoneMeshes(p.x, p.z, seed, builtZones)) {
      root.add(z.group); sources.push(...z.sources)
      const [rx, rz] = z.key.split(',').map(Number)
      zoneGroups.push({ group: z.group, x0: rx * layout.REGION + 32, z0: rz * layout.REGION + 32, x1: rx * layout.REGION + 160, z1: rz * layout.REGION + 160 })
    }
  }

  // ---------------- craters: clip meshes + mesh-to-voxel rim
  const onHole = (h: { x: number, y: number, z: number, r: number }) => {
    addHoleUniform(h)
    const R0 = h.r - 0.5; const R1 = h.r + 0.9
    const cells = new Map<string, [number, number, number, string]>()
    for (const s of sources) {
      const P = s.pos; const I = s.idx
      for (let t = 0; t < I.length; t += 3) {
        const a = I[t] * 3; const b = I[t + 1] * 3; const c = I[t + 2] * 3
        const mnx = Math.min(P[a], P[b], P[c]); const mxx = Math.max(P[a], P[b], P[c])
        if (mnx > h.x + R1 || mxx < h.x - R1) continue
        const mnz = Math.min(P[a + 2], P[b + 2], P[c + 2]); const mxz = Math.max(P[a + 2], P[b + 2], P[c + 2])
        if (mnz > h.z + R1 || mxz < h.z - R1) continue
        const mny = Math.min(P[a + 1], P[b + 1], P[c + 1]); const mxy = Math.max(P[a + 1], P[b + 1], P[c + 1])
        if (mny > h.y + R1 || mxy < h.y - R1) continue
        const A = [P[a], P[a + 1], P[a + 2]]; const B = [P[b], P[b + 1], P[b + 2]]; const C = [P[c], P[c + 1], P[c + 2]]
        for (let x = Math.floor(Math.max(mnx, h.x - R1)); x <= Math.floor(Math.min(mxx, h.x + R1)); x++) {
          for (let y = Math.floor(Math.max(mny, h.y - R1)); y <= Math.floor(Math.min(mxy, h.y + R1)); y++) {
            for (let z = Math.floor(Math.max(mnz, h.z - R1)); z <= Math.floor(Math.min(mxz, h.z + R1)); z++) {
              const d = Math.hypot(x + 0.5 - h.x, y + 0.5 - h.y, z + 0.5 - h.z)
              if (d < R0 || d > R1) continue
              const k = x + ',' + y + ',' + z
              if (cells.has(k)) continue
              if (triBoxOverlap([x + 0.5, y + 0.5, z + 0.5], 0.5, A, B, C)) cells.set(k, [x, y, z, nearestBlock(s.tc[t], s.tc[t + 1], s.tc[t + 2])])
            }
          }
        }
      }
    }
    if (cells.size) void server.blockmash.surfaceVoxels([...cells.values()].slice(0, 600))
    crater(h)
  }
  // scorch decal on the ground around the crater (soft dark disc, drawn on top of terrain)
  const decalTex = (() => {
    const c = document.createElement('canvas'); c.width = c.height = 128
    const g = c.getContext('2d')!; const gr = g.createRadialGradient(64, 64, 10, 64, 64, 64)
    gr.addColorStop(0, 'rgba(20,14,10,0.9)'); gr.addColorStop(0.6, 'rgba(30,22,16,0.6)'); gr.addColorStop(1, 'rgba(30,22,16,0)')
    g.fillStyle = gr; g.fillRect(0, 0, 128, 128)
    const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; return t
  })()
  const decals: THREE.Mesh[] = []
  const crater = (h: { x: number, y: number, z: number, r: number }) => {
    const m = new THREE.Mesh(new THREE.PlaneGeometry(h.r * 3.6, h.r * 3.6), new THREE.MeshBasicMaterial({ map: decalTex, transparent: true, depthWrite: false, polygonOffset: true, polygonOffsetFactor: -4 }))
    m.rotation.x = -Math.PI / 2
    m.position.set(h.x, groundY(h.x + h.r * 1.3, h.z) ?? h.y, h.z)
    m.renderOrder = 3
    root.add(m); decals.push(m)
    if (decals.length > 24) { const o = decals.shift()!; root.remove(o); o.geometry.dispose() }
  }
  server.on('blockmashHole', onHole)
  for (const h of server.blockmash.surfaceHoles ?? []) addHoleUniform(h)

  // ---------------- ground (walk/drive on the polygons)
  const terrainY = (x: number, z: number) => {
    const cx = Math.floor(x / CS); const cz = Math.floor(z / CS); const ch = chunks.get(key(cx, cz))
    if (!ch?.hs || ch.dirty && !ch.drawn) return null
    const i = Math.floor(x) - cx * CS; const k = Math.floor(z) - cz * CS
    if (!ch.drawn[i * CS + k]) return null
    const M = CS + 3; const H = (a: number, b: number) => ch.hs[(a + 1) * M + (b + 1)]
    const fx = x - Math.floor(x); const fz = z - Math.floor(z)
    const h00 = H(i, k); const h10 = H(i + 1, k); const h01 = H(i, k + 1); const h11 = H(i + 1, k + 1)
    const y = fx > fz ? h00 + fx * (h10 - h00) + fz * (h11 - h10) : h00 + fz * (h01 - h00) + fx * (h11 - h01)
    return { y, by: ch.h[i * CS + k] }
  }
  const groundY = (x: number, z: number): number | null => {
    const dmm = (globalThis as any).blockmashDuke
    if (dmm) {
      const c = dmm.col(x, z)
      if (c && c.kind !== 0) {
        if (c.kind !== 1) return null
        const f = dmm.floorAt(x, z)
        if (!f || inHole(x, f.y, z, 0.25)) return null
        if (blockName(Math.floor(x), c.top - 1, Math.floor(z)) === 'air') return null
        return f.y
      }
    }
    const t = terrainY(x, z)
    if (!t || inHole(x, t.y, z, 0.2)) return null
    return t.y
  }
  ;(globalThis as any).blockmashGroundY = groundY
  bot.on('physicsTick', () => {
    const e = bot.entity; if (!e || bot.game?.gameMode === 'spectator' || (globalThis as any).blockmashDriving) return
    const g = groundY(e.position.x, e.position.z)
    if (g == null) return
    if (e.position.y < g && e.position.y > g - 1.2 && e.velocity.y <= 0.05) { e.position.y = g; e.velocity.y = 0; e.onGround = true }
  })
  // mobs: lift their meshes onto the polygons (the server simulates them on the block grid)
  const liftMobs = () => {
    const ents = viewer.entities?.entities; if (!ents) return
    for (const id of Object.keys(ents)) {
      const o = ents[id]; const en = bot.entities[id]
      if (!o || !en || en === bot.entity) continue
      const g = groundY(en.position.x, en.position.z)
      if (g != null && en.position.y < g && en.position.y > g - 1.2) o.position.y = Math.max(o.position.y, g)
    }
  }

  // ---------------- per-frame driver
  let lastZones = 0
  const tick = () => {
    requestAnimationFrame(tick)
    const p = bot.entity?.position; if (!p) return
    const t = bot.time?.timeOfDay ?? 6000
    const s = Math.cos(((t - 6000) / 24000) * Math.PI * 2)
    dayUniform.value = Math.max(0.18, Math.min(1, 0.55 + s * 0.9))
    const pcx = Math.floor(p.x / CS); const pcz = Math.floor(p.z / CS)
    const t0 = performance.now(); const budgetMs = mobile ? 6 : 12; let built = 0
    const want = new Set<string>()
    const order: Array<[number, number, number]> = []
    for (let dx = -RADIUS; dx <= RADIUS; dx++) for (let dz = -RADIUS; dz <= RADIUS; dz++) if (dx * dx + dz * dz <= RADIUS * RADIUS + 1) order.push([dx * dx + dz * dz, pcx + dx, pcz + dz])
    order.sort((a, b) => a[0] - b[0])
    for (const [, cx, cz] of order) {
      const k = key(cx, cz); want.add(k)
      let ch = chunks.get(k)
      if (!ch) { ch = { drawn: new Uint8Array(CS * CS), h: new Int16Array(CS * CS), hs: null as any, dirty: true, complete: false }; chunks.set(k, ch) }
      if ((ch.dirty || !ch.complete) && (built === 0 || performance.now() - t0 < budgetMs)) { built++; buildChunk(cx, cz, ch) }
    }
    for (const [k, ch] of chunks) {
      if (want.has(k)) continue
      if (ch.mesh) { root.remove(ch.mesh); ch.mesh.geometry.dispose() }
      if (ch.trees) { root.remove(ch.trees); ch.trees.geometry.dispose() }
      chunks.delete(k)
    }
    if (performance.now() - lastZones > 2000) { lastZones = performance.now(); updateZones() }
    liftMobs()
    for (const zg of zoneGroups) {
      // only show zone meshes whose nearest part stands on loaded block terrain (no floating meshes at the horizon)
      const nx = Math.min(zg.x1 - 1, Math.max(zg.x0, p.x)); const nz = Math.min(zg.z1 - 1, Math.max(zg.z0, p.z))
      const near = Math.hypot(nx - p.x, nz - p.z) < VIS
      zg.group.visible = near && bot.world.getColumnAt?.(new Vec3(Math.floor(nx), 0, Math.floor(nz))) != null
    }
  }
  tick()
  console.log('[blockmash] polygon surface ready', { duke: !!dm, mobile, radius: RADIUS })
}
