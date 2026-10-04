// BlockMash: renders the real Yorg race track (track.egg + all its instanced props, converted by
// tools/yorg/fetch_track.py, CC BY-SA) as polygons on the surface. Blocks under it stay authoritative:
// mining/explosions cut holes into the track polygons (shared crater list), the karts and the player
// ride on the track's own collision surface (heightfield from collision.egg).
import * as THREE from 'three'
import { Vec3 } from 'vec3'
import { inHole, surfaceMaterial, loadTex } from './surfmat'
// eslint-disable-next-line @typescript-eslint/no-require-imports
const { getYorg } = require('../surface/yorgworld')

export async function initYorgTrack () {
  const viewer = (globalThis as any).viewer; const bot = (globalThis as any).bot; const server = (globalThis as any).localServer
  const yt = getYorg()
  if (!viewer?.scene || !yt) return
  const name = (globalThis as any).blockmashYorgTrack.name
  const base = `./yorg/tracks/${name}`
  const mobile = matchMedia('(pointer: coarse)').matches || innerWidth < 1000
  const root = new THREE.Group(); root.name = 'blockmash-yorg-track'; root.position.set(yt.OX, yt.YG, yt.OZ); root.visible = false
  viewer.scene.add(root)
  let built = false; let building = false
  const meshes: Array<{ mesh: THREE.InstancedMesh, mats: number[][] }> = []
  const matCache = new Map<string, THREE.ShaderMaterial>()
  const mat = (tex: string | null, rep?: string, rs?: [number, number]) => {
    const k = `${tex ?? ''}|${rep ?? ''}|${rs ?? ''}`
    let m = matCache.get(k)
    if (!m) { m = surfaceMaterial({ map: tex ? loadTex(`${base}/tex/${tex}`) : null, detail: rep ? loadTex(`${base}/tex/${rep}`) : undefined, detailScale: rs }); matCache.set(k, m) }
    return m
  }
  const build = async () => {
    building = true
    const buf = await (await fetch(`${base}/mesh.bin`)).arrayBuffer()
    const meta = yt.meta
    const V = new Float32Array(buf, 0, meta.verts * 5); const I = new Uint32Array(buf, meta.verts * 20, meta.indices)
    for (const md of meta.models) {
      const g = new THREE.BufferGeometry()
      const vs = V.subarray(md.v0 * 5, (md.v0 + md.nv) * 5)
      const ib = new THREE.InterleavedBuffer(vs, 5)
      g.setAttribute('position', new THREE.InterleavedBufferAttribute(ib, 3, 0))
      g.setAttribute('uv', new THREE.InterleavedBufferAttribute(ib, 2, 3))
      g.setAttribute('color', new THREE.Float32BufferAttribute(new Float32Array(md.nv * 3).fill(1.15), 3))
      const env = new Float32Array(md.nv * 2); for (let i = 0; i < md.nv; i++) env[i * 2] = 1
      g.setAttribute('aEnv', new THREE.Float32BufferAttribute(env, 2))
      const first = md.groups[0].start; const last = md.groups[md.groups.length - 1]
      g.setIndex(new THREE.BufferAttribute(I.slice(first, last.start + last.count), 1))
      const mats: THREE.Material[] = []
      md.groups.forEach((gr: any, i: number) => { g.addGroup(gr.start - first, gr.count, i); mats.push(mat(gr.tex, gr.rep, gr.rs)) })
      g.computeBoundingSphere()
      const im = new THREE.InstancedMesh(g, mats, md.inst.length)
      const m4 = new THREE.Matrix4()
      md.inst.forEach((e: number[], i: number) => { m4.fromArray(e); im.setMatrixAt(i, m4) })
      im.instanceMatrix.needsUpdate = true
      im.frustumCulled = false; im.castShadow = md.name === 'track' || md.inst.length < 20; im.name = 'yorg-' + md.name
      root.add(im)
      meshes.push({ mesh: im, mats: md.inst, tris: md.groups.reduce((a: number, g: any) => a + g.count, 0) / 3 } as any)
    }
    built = true; building = false
    console.log('[blockmash] Yorg track', name, meta.tris, 'tris')
  }

  // instance LOD: only the nearest props are drawn (cheap distance sort per model, once per second)
  const lod = (p: any) => {
    const q = (globalThis as any).blockmashQuality?.() ?? (mobile ? 'low' : 'medium')
    const R = q === 'low' ? 90 : q === 'medium' ? 170 : 400
    const m4 = new THREE.Matrix4()
    for (const { mesh, mats, tris } of meshes as any) {
      if (mats.length === 1) continue
      // Low (mobile default): per-prop draw distance by its triangle cost, decimating ~474k -> well under 100k tris
      const Rm = q !== 'low' ? R : tris > 1000 ? 110 : tris > 300 ? 55 : 38
      const lx = p.x - yt.OX; const lz = p.z - yt.OZ
      const near = mats.map((e, i) => [i, (e[12] - lx) ** 2 + (e[14] - lz) ** 2] as [number, number]).filter(a => a[1] < Rm * Rm).sort((a, b) => a[1] - b[1])
      near.forEach(([i], k) => { m4.fromArray(mats[i]); mesh.setMatrixAt(k, m4) })
      mesh.count = near.length; mesh.instanceMatrix.needsUpdate = true
    }
  }

  // mining the block layer under the track punches a hole into the track polygons
  bot.on('blockUpdate', (o: any, n: any) => {
    if (!o?.position || n?.name !== 'air' || o.name === 'air' || o.name === 'barrier') return
    const p = o.position; const s = yt.surf(p.x, p.z)
    if (s && s.kind !== 3 && p.y === Math.floor(s.y - 0.35) - 1 && !inHole(p.x + 0.5, s.y, p.z + 0.5)) server.blockmash.addHole(p.x + 0.5, s.y + 0.3, p.z + 0.5, 0.95)
  })
  // walk on the track surface (the block layer is up to ~1.3 below it)
  bot.on('physicsTick', () => {
    const e = bot.entity; if (!e || !built || bot.game?.gameMode === 'spectator' || (globalThis as any).blockmashYorg?.drive) return
    const s = yt.surf(e.position.x, e.position.z)
    if (!s || s.kind === 3 || inHole(e.position.x, s.y, e.position.z, 0.25)) return
    const b = bot.world.getBlock(new Vec3(Math.floor(e.position.x), Math.floor(s.y - 0.35) - 1, Math.floor(e.position.z)))
    if (!b || b.name === 'air') return
    if (e.position.y < s.y && e.position.y > s.y - 1.6 && e.velocity.y <= 0.05) { e.position.y = s.y; e.velocity.y = 0; e.onGround = true }
  })
  let lastT = 0
  const tick = () => {
    requestAnimationFrame(tick)
    const p = bot.entity?.position; if (!p) return
    const now = performance.now(); if (now - lastT < 1000) return; lastT = now
    const d = yt.dist(p.x, p.z)
    if (d < 260 && !built && !building) void build().catch(e => { console.warn('[blockmash] Yorg track failed', e); building = false })
    root.visible = built && d < 320
    if (root.visible) lod(p)
  }
  tick()
}
