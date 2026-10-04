// BlockMash polygon surface (client): the real Duke Nukem 3D shareware levels (E1L1..E1L6, local extraction only)
// rendered as Build-engine polygons side by side on top of the normal Minecraft world. Blocks stay authoritative
// (mining, physics, mobs): the server puts a block layer 1 below every Duke floor; mining/explosions remove those
// blocks, the floor polygons get a hole there (shared hole list) and the cut edge of the level geometry is
// voxelised into colour-matched blocks (mesh-to-voxel, see /workspace/vcmc DESIGN.md).
import * as THREE from 'three'
import { Vec3 } from 'vec3'
import { addHoleUniform, dayUniform, farUniform, inHole } from './surfmat'
import { buildDukeMap, VoxSource } from './dukemap'
import { triBoxOverlap } from '../surface/voxelize'
// eslint-disable-next-line @typescript-eslint/no-require-imports
const { getDuke } = require('../surface/dukeworld')

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
  const dm = getDuke()
  if (!dm) { console.log('[blockmash] no Duke3D maps extracted - plain Minecraft surface'); return }
  const scene: THREE.Scene = viewer.scene
  const mobile = matchMedia('(pointer: coarse)').matches || innerWidth < 1000
  const root = new THREE.Group(); root.name = 'blockmash-surface'; scene.add(root)
  const blockName = (x: number, y: number, z: number): string | null | undefined => bot.world.getBlock(new Vec3(x, y, z))?.name
  let man: any = null
  try { man = await (await fetch('./duke/manifest.json')).json() } catch {}
  if (!man) return

  // ---------------- Duke levels, built lazily when near, dropped when far (GPU memory on mobile)
  type Lvl = { sub: any, group?: THREE.Group, sources?: VoxSource[], building?: boolean }
  const levels: Lvl[] = dm.maps.map((sub: any) => ({ sub }))
  const NEAR = mobile ? 140 : 220
  const distTo = (b: any, p: any) => Math.hypot(Math.max(b.x0 - p.x, 0, p.x - b.x1), Math.max(b.z0 - p.z, 0, p.z - b.z1))
  const updateLevels = (p: any) => {
    for (const L of levels) {
      const d = distTo(L.sub.bbox, p)
      if (d < NEAR && !L.group && !L.building) {
        L.building = true
        void buildDukeMap(L.sub, './duke', man.tiles).then(r => { r.group.name = 'duke-' + L.sub.name; L.group = r.group; L.sources = r.sources; root.add(r.group); L.building = false }).catch(e => { console.warn('[blockmash] Duke level failed', L.sub.name, e); L.building = false })
      } else if (d > NEAR + 80 && L.group) {
        root.remove(L.group)
        L.group.traverse((o: any) => { o.geometry?.dispose(); o.material?.uniforms?.map?.value?.dispose?.(); o.material?.dispose?.() })
        L.group = undefined; L.sources = undefined
      }
    }
  }

  bot.on('blockUpdate', (o: any, n: any) => {
    if (!o?.position) return
    const p = o.position
    // mining the block under a Duke floor punches a hole into the floor polygons
    if (n?.name === 'air' && o.name !== 'air' && o.name !== 'barrier') {
      const c = dm.col(p.x, p.z)
      if (c && c.kind === 1 && p.y === c.top - 2 && !inHole(p.x + 0.5, c.top, p.z + 0.5)) server.blockmash.addHole(p.x + 0.5, c.top + 0.3, p.z + 0.5, 0.95)
    }
  })

  // ---------------- craters: clip meshes + mesh-to-voxel rim
  const onHole = (h: { x: number, y: number, z: number, r: number }) => {
    addHoleUniform(h)
    const R0 = h.r - 0.5; const R1 = h.r + 0.9
    const cells = new Map<string, [number, number, number, string]>()
    for (const L of levels) {
      if (!L.sources || distTo(L.sub.bbox, h) > R1) continue
      for (const s of L.sources) {
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
    }
    if (cells.size) void server.blockmash.surfaceVoxels([...cells.values()].slice(0, 600))
  }
  server.on('blockmashHole', onHole)
  for (const h of server.blockmash.surfaceHoles ?? []) addHoleUniform(h)

  // ---------------- walk on the Duke floors (the block layer is 1 below them)
  const groundY = (x: number, z: number): number | null => {
    const c = dm.col(x, z)
    if (!c || c.kind !== 1) return null
    const f = dm.floorAt(x, z)
    if (!f || inHole(x, f.y, z, 0.25)) return null
    if (blockName(Math.floor(x), c.top - 2, Math.floor(z)) === 'air') return null
    return f.y
  }
  ;(globalThis as any).blockmashGroundY = groundY
  bot.on('physicsTick', () => {
    const e = bot.entity; if (!e || bot.game?.gameMode === 'spectator' || (globalThis as any).blockmashYorg?.drive) return
    const g = groundY(e.position.x, e.position.z)
    if (g == null) return
    if (e.position.y < g && e.position.y > g - 1.2 && e.velocity.y <= 0.05) { e.position.y = g; e.velocity.y = 0; e.onGround = true }
  })
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
  let lastFar = 0; let lastLv = 0
  const updateFar = (p: any) => {
    let r = 16
    for (let d = 16; d <= 256; d += 16) {
      let ok = true
      for (let a = 0; a < 8 && ok; a++) { const x = p.x + Math.cos(a * Math.PI / 4) * d; const z = p.z + Math.sin(a * Math.PI / 4) * d; if (bot.world.getColumnAt?.(new Vec3(Math.floor(x), 0, Math.floor(z))) == null) ok = false }
      if (!ok) break
      r = d
    }
    farUniform.value.set(p.x, p.z, Math.max(24, r - 6)) // no level geometry floating over unloaded chunks
  }
  const tick = () => {
    requestAnimationFrame(tick)
    const p = bot.entity?.position; if (!p) return
    const t = bot.time?.timeOfDay ?? 6000
    const s = Math.cos(((t - 6000) / 24000) * Math.PI * 2)
    dayUniform.value = Math.max(0.18, Math.min(1, 0.55 + s * 0.9))
    const now = performance.now()
    if (now - lastFar > 500) { lastFar = now; updateFar(p) } else { farUniform.value.x = p.x; farUniform.value.y = p.z }
    if (now - lastLv > 1500) { lastLv = now; updateLevels(p) }
    liftMobs()
  }
  tick()
  console.log('[blockmash] Duke surface ready', dm.maps.map((m: any) => m.name))
}
