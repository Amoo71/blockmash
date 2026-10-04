// BlockMash: renders the real The Dark Mod building prefabs (tdm_prefabs01.pk4, CC BY-NC-SA 3.0, converted by
// tools/darkmod/fetch_prefabs.py) on the lots of every Dark Mod quarter near the player. One InstancedMesh per
// prefab; the world generator puts barrier voxels of the same brushes underneath for collision.
import * as THREE from 'three'
import { surfaceMaterial, loadTex } from './surfmat'
// eslint-disable-next-line @typescript-eslint/no-require-imports
const { getPrefabs } = require('../surface/darkmodworld')
// eslint-disable-next-line @typescript-eslint/no-require-imports
const layout = require('../layout')
// eslint-disable-next-line @typescript-eslint/no-require-imports
const { cellInfo } = require('../zones/darkmod')

const BASE = './darkmod/prefabs'
export async function initDarkmodPrefabs () {
  const viewer = (globalThis as any).viewer; const server = (globalThis as any).localServer
  const P = getPrefabs()
  if (!viewer?.scene || !P) return
  const buf = await (await fetch(`${BASE}/mesh.bin`)).arrayBuffer()
  const meta = P.meta
  const V = new Float32Array(buf, 0, meta.verts * 5); const I = new Uint32Array(buf, meta.verts * 20, meta.indices)
  const root = new THREE.Group(); root.name = 'blockmash-darkmod-prefabs'; viewer.scene.add(root)
  const mats = new Map<string, THREE.ShaderMaterial>()
  const mat = (tex: string) => { let m = mats.get(tex); if (!m) { m = surfaceMaterial({ map: loadTex(`${BASE}/tex/${tex}`) }); mats.set(tex, m) } return m }
  const geos = new Map<string, { g: THREE.BufferGeometry, m: THREE.Material[] }>()
  const geo = (pf: any) => {
    let e = geos.get(pf.name)
    if (e) return e
    const g = new THREE.BufferGeometry()
    const vs = V.slice(pf.v0 * 5, (pf.v0 + pf.nv) * 5)
    const pos = new Float32Array(pf.nv * 3); const uv = new Float32Array(pf.nv * 2)
    for (let i = 0; i < pf.nv; i++) { pos.set(vs.subarray(i * 5, i * 5 + 3), i * 3); uv.set(vs.subarray(i * 5 + 3, i * 5 + 5), i * 2) }
    g.setAttribute('position', new THREE.BufferAttribute(pos, 3)); g.setAttribute('uv', new THREE.BufferAttribute(uv, 2))
    const first = pf.groups[0].start; const last = pf.groups[pf.groups.length - 1]
    const idx = new Uint32Array(last.start + last.count - first)
    for (let i = 0; i < idx.length; i++) idx[i] = I[first + i] - pf.v0
    g.setIndex(new THREE.BufferAttribute(idx, 1))
    // baked face shading (the surface shader has no normals): tops bright, undersides dark, walls in between;
    // self-lit TDM window materials glow (shade > 1.58 is the shader's glow threshold)
    const col = new Float32Array(pf.nv * 3).fill(0.85)
    const ms: THREE.Material[] = []
    const a = new THREE.Vector3(); const b = new THREE.Vector3(); const c = new THREE.Vector3()
    pf.groups.forEach((gr: any, gi: number) => {
      g.addGroup(gr.start - first, gr.count, gi); ms.push(mat(gr.tex))
      for (let t = gr.start - first; t < gr.start - first + gr.count; t += 3) {
        const i0 = idx[t]; const i1 = idx[t + 1]; const i2 = idx[t + 2]
        a.fromArray(pos, i0 * 3); b.fromArray(pos, i1 * 3); c.fromArray(pos, i2 * 3)
        const n = b.sub(a).cross(c.sub(a)).normalize()
        const s = gr.glow ? 1.75 : n.y > 0.6 ? 1.0 : n.y < -0.6 ? 0.5 : 0.7 + 0.12 * Math.abs(n.x) + 0.18 * n.y
        for (const i of [i0, i1, i2]) col.fill(s, i * 3, i * 3 + 3)
      }
    })
    g.setAttribute('color', new THREE.BufferAttribute(col, 3))
    const env = new Float32Array(pf.nv * 2); for (let i = 0; i < pf.nv; i++) env[i * 2] = 1
    g.setAttribute('aEnv', new THREE.BufferAttribute(env, 2))
    g.computeBoundingSphere()
    e = { g, m: ms }; geos.set(pf.name, e)
    return e
  }
  const placed = new Map<string, THREE.InstancedMesh>()
  let key = ''
  const rebuild = (rx0: number, rz0: number) => {
    const seed = (server?.overworld?.seed ?? 0) | 0
    const inst = new Map<string, THREE.Matrix4[]>()
    for (let rx = rx0 - 1; rx <= rx0 + 1; rx++) {
      for (let rz = rz0 - 1; rz <= rz0 + 1; rz++) {
        if (layout.zoneType(rx, rz, seed) !== 'darkmod') continue
        const ox = rx * layout.REGION + 32; const oz = rz * layout.REGION + 32; const G = layout.ZONE_G
        for (let ci = 0; ci < 6; ci++) {
          for (let cj = 0; cj < 6; cj++) {
            const c = cellInfo(ci, cj, { seed, rx, rz })
            if (!c.ok) continue
            const pf = P.byName.get(c.prefab); const sx = Math.ceil(pf.size[0]); const sz = Math.ceil(pf.size[2])
            const [ma, mb, tu, mc, md, tv] = [[1, 0, 0, 0, 1, 0], [0, -1, sz, 1, 0, 0], [-1, 0, sx, 0, -1, sz], [0, 1, 0, -1, 0, sx]][c.rot]
            const m4 = new THREE.Matrix4().set(ma, 0, mb, ox + c.u0 + tu, 0, 1, 0, G + 1, mc, 0, md, oz + c.v0 + tv, 0, 0, 0, 1)
            if (!inst.has(pf.name)) inst.set(pf.name, [])
            inst.get(pf.name)!.push(m4)
          }
        }
      }
    }
    for (const m of placed.values()) { root.remove(m); m.dispose() }
    placed.clear()
    let tris = 0
    for (const [name, list] of inst) {
      const pf = P.byName.get(name); const { g, m } = geo(pf)
      const im = new THREE.InstancedMesh(g, m, list.length)
      list.forEach((m4, i) => im.setMatrixAt(i, m4))
      im.instanceMatrix.needsUpdate = true; im.frustumCulled = false; im.castShadow = true; im.name = 'tdm-' + name
      root.add(im); placed.set(name, im); tris += pf.tris * list.length
    }
    if (inst.size) console.log('[blockmash] Dark Mod prefabs', [...inst.values()].reduce((a, l) => a + l.length, 0), 'buildings', tris, 'tris')
  }
  const tick = () => {
    const p = (globalThis as any).bot?.entity?.position
    if (p) {
      const rx = Math.floor(p.x / layout.REGION); const rz = Math.floor(p.z / layout.REGION)
      const k = `${rx},${rz}`
      if (k !== key) { key = k; rebuild(rx, rz) }
    }
  }
  tick(); setInterval(tick, 1000)
  ;(globalThis as any).blockmashDarkmodPrefabsRoot = root
}
