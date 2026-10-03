// Billboard sprite helpers (BUILD-engine style 5-rotation actors) for mashup content
import * as THREE from 'three'

const loader = new THREE.TextureLoader()
const cache = new Map<string, THREE.Texture>()
export const tex = (url: string) => {
  let t = cache.get(url)
  if (!t) {
    t = loader.load(url)
    t.magFilter = THREE.NearestFilter
    t.minFilter = THREE.NearestFilter
    t.colorSpace = THREE.SRGBColorSpace
    cache.set(url, t)
  }
  return t
}

export type Manifest = { tiles: Record<string, { w: number, h: number, off: [number, number] }>, sounds: string[] }

export function makeSprite (m: Manifest, base: string, tile: number, pxPerBlock = 40) {
  const mat = new THREE.SpriteMaterial({ map: tex(`${base}/tiles/${tile}.png`), transparent: true, alphaTest: 0.4, depthWrite: true })
  const s = new THREE.Sprite(mat)
  s.center.set(0.5, 0)
  setTile(s, m, base, tile, false, pxPerBlock)
  s.renderOrder = 2
  return s
}

export function setTile (s: THREE.Sprite, m: Manifest, base: string, tile: number, mirror: boolean, pxPerBlock = 40) {
  const meta = m.tiles[tile]
  if (!meta) return
  const mat = s.material
  const key = `${tile}${mirror ? 'm' : ''}`
  if ((s as any).__tile !== key) {
    ;(s as any).__tile = key
    mat.map = tex(`${base}/tiles/${tile}.png`)
    mat.needsUpdate = true
  }
  s.scale.set((mirror ? -1 : 1) * meta.w / pxPerBlock, meta.h / pxPerBlock, 1)
}

/** 5-rotation BUILD actor: returns [rotationIndex 0..4, mirrored] for camera vs. facing */
export function rotation (facingYaw: number, from: THREE.Vector3, cam: THREE.Vector3): [number, boolean] {
  const fx = -Math.sin(facingYaw); const fz = -Math.cos(facingYaw)
  const a = Math.atan2(cam.x - from.x, cam.z - from.z) - Math.atan2(fx, fz)
  let k = Math.round(a / (Math.PI / 4)) % 8
  if (k < 0) k += 8
  return k <= 4 ? [k, false] : [8 - k, true]
}
