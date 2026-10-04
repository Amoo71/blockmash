// Shared shader materials for the polygon surface (terrain, Duke3D map, Dark Mod buildings, Yorg track).
// All of them clip against the same crater list (uHoles) so explosions/mining cut real holes into every mesh,
// with a scorch ring around the cut. Lighting: baked vertex colours * day/night factor (cheap on mobile).
import * as THREE from 'three'

export const MAX_HOLES = 64
export const holeUniform = { value: Array.from({ length: MAX_HOLES }, () => new THREE.Vector4(0, -1000, 0, 0)) }
export const holeCount = { value: 0 }
export const dayUniform = { value: 1 }
/** xz of the player + radius of loaded block terrain: meshes are clipped there so nothing floats beyond loaded chunks */
export const farUniform = { value: new THREE.Vector3(0, 0, 1e6) }
export const holes: Array<{ x: number, y: number, z: number, r: number }> = []

export function addHoleUniform (h: { x: number, y: number, z: number, r: number }) {
  holes.push(h)
  if (holes.length > MAX_HOLES) holes.shift()
  holes.forEach((o, i) => holeUniform.value[i].set(o.x, o.y, o.z, o.r))
  holeCount.value = holes.length
}
export const inHole = (x: number, y: number, z: number, pad = 0) => holes.some(h => (h.x - x) ** 2 + (h.y - y) ** 2 + (h.z - z) ** 2 < (h.r + pad) ** 2)

const HOLE_GLSL = /* glsl */`
uniform vec4 uHoles[${MAX_HOLES}];
uniform vec3 uFar;
uniform int uHoleN;
float holeShade (vec3 p) {
  float s = 1.0;
  if (distance(p.xz, uFar.xy) > uFar.z) discard;
  for (int i = 0; i < ${MAX_HOLES}; i++) {
    if (i >= uHoleN) break;
    vec4 h = uHoles[i];
    float d = distance(p, h.xyz);
    #ifndef NOHOLE
    if (d < h.w) discard;
    #endif
    s = min(s, mix(0.72, 1.0, clamp((d - h.w * 0.85) / (0.45 * h.w + 0.3), 0.0, 1.0)));
  }
  return s;
}`

let whiteTex: THREE.Texture | null = null
const white = () => { if (!whiteTex) { whiteTex = new THREE.DataTexture(new Uint8Array([255, 255, 255, 255]), 1, 1); whiteTex.needsUpdate = true } return whiteTex }

type Opts = { map?: THREE.Texture | null, atlas?: boolean, alphaTest?: number, side?: THREE.Side, terrain?: boolean, textures?: THREE.Texture[] }

export function surfaceMaterial (o: Opts = {}) {
  const uniforms: Record<string, any> = { uFar: farUniform, uHoles: holeUniform, uHoleN: holeCount, uDay: dayUniform, map: { value: o.map ?? white() }, uAtlas: { value: new THREE.Vector2(1, 1) } }
  const defs: Record<string, any> = {}
  if (o.atlas) defs.ATLAS = 1
  if (o.terrain) {
    defs.TERRAIN = 1
    defs.NOHOLE = 1 // terrain is cut per removed block (cells vanish), not by a sphere
    if ((o as any).texNorm) defs.TEXNORM = 1
    o.textures!.forEach((t, i) => { uniforms['t' + i] = { value: t } })
  }
  if (o.alphaTest) defs.ALPHATEST = o.alphaTest
  const m = new THREE.ShaderMaterial({
    uniforms,
    defines: defs,
    side: o.side ?? THREE.FrontSide,
    vertexShader: /* glsl */`
      #include <common>
      #include <logdepthbuf_pars_vertex>
      attribute vec3 color;
      varying vec3 vCol; varying vec3 vW; varying vec2 vUv;
      #ifdef ATLAS
      attribute vec4 aTile; varying vec4 vTile;
      #endif
      #ifdef TERRAIN
      attribute vec4 aMix; varying vec4 vMix; varying vec3 vN;
      #endif
      void main () {
        vCol = color; vUv = uv;
        vec4 w = modelMatrix * vec4(position, 1.0); vW = w.xyz;
        #ifdef ATLAS
        vTile = aTile;
        #endif
        #ifdef TERRAIN
        vMix = aMix; vN = normal;
        #endif
        gl_Position = projectionMatrix * viewMatrix * w;
        #include <logdepthbuf_vertex>
      }`,
    fragmentShader: /* glsl */`
      #include <logdepthbuf_pars_fragment>
      uniform sampler2D map; uniform vec2 uAtlas; uniform float uDay;
      varying vec3 vCol; varying vec3 vW; varying vec2 vUv;
      #ifdef ATLAS
      varying vec4 vTile;
      #endif
      #ifdef TERRAIN
      uniform sampler2D t0; uniform sampler2D t1; uniform sampler2D t2; uniform sampler2D t3; uniform sampler2D t4;
      varying vec4 vMix; varying vec3 vN;
      #endif
      ${HOLE_GLSL}
      vec3 tn (vec4 c, float avgL, vec3 target, float sat) {
        #ifdef TEXNORM
        float l = dot(c.rgb, vec3(0.2126, 0.7152, 0.0722));
        return mix(vec3(l), c.rgb, sat) / avgL * target;
        #else
        return c.rgb;
        #endif
      }
      void main () {
        #include <logdepthbuf_fragment>
        float sh = holeShade(vW);
        vec4 c;
        #ifdef TERRAIN
        vec2 uv = vW.xz * 0.25;
        vec2 uvs = (abs(vN.x) > abs(vN.z) ? vW.zy : vW.xy) * 0.25;
        vec4 g = texture2D(t0, uv); vec4 r = texture2D(t1, mix(uv, uvs, 0.6)); vec4 s = texture2D(t2, uv); vec4 n = texture2D(t3, uv); vec4 d = texture2D(t4, uvs);
        float wd = max(0.0, 1.0 - vMix.x - vMix.y - vMix.z - vMix.w);
        vec3 cc = tn(g, 0.1255, vec3(0.10, 0.25, 0.035), 0.45) * vMix.x + tn(r, 0.0742, vec3(0.2, 0.19, 0.165), 0.15) * vMix.y + tn(s, 0.2438, vec3(0.58, 0.54, 0.4), 0.12) * vMix.z + tn(n, 0.3794, vec3(0.8, 0.84, 0.9), 0.0) * vMix.w + tn(d, 0.1004, vec3(0.15, 0.085, 0.04), 0.4) * wd;
        c = vec4(cc, 1.0);
        #elif defined(ATLAS)
        vec2 p = vTile.xy + mod(vUv, vTile.zw);
        c = texture2D(map, p / uAtlas);
        #else
        c = texture2D(map, vUv);
        #endif
        #ifdef ALPHATEST
        if (c.a < float(ALPHATEST)) discard;
        #endif
        gl_FragColor = vec4(c.rgb * vCol * uDay * sh, 1.0);
        #include <colorspace_fragment>
      }`
  })
  return m
}

export const loadTex = (() => {
  const loader = new THREE.TextureLoader()
  const cache = new Map<string, THREE.Texture>()
  return (url: string, nearest = false) => {
    let t = cache.get(url)
    if (!t) {
      t = loader.load(url)
      t.wrapS = t.wrapT = THREE.RepeatWrapping
      t.colorSpace = THREE.SRGBColorSpace
      if (nearest) { t.magFilter = THREE.NearestFilter; t.minFilter = THREE.NearestFilter } else t.anisotropy = 4
      cache.set(url, t)
    }
    return t
  }
})()

/** Small geometry builder: quads/triangles with uv + baked colour, merged into one BufferGeometry */
export class GeoBuilder {
  pos: number[] = []; uv: number[] = []; col: number[] = []; idx: number[] = []; tile: number[] | null = null
  /** per-triangle rgb (0..255) used by the mesh-to-voxel rim generator */
  tc: number[] = []; cur: [number, number, number] = [128, 128, 128]; tint: [number, number, number] | null = null
  constructor (atlas = false) { if (atlas) this.tile = [] }
  get n () { return this.pos.length / 3 }
  v (x: number, y: number, z: number, u: number, v: number, c: number, t?: number[]) {
    this.pos.push(x, y, z); this.uv.push(u, v)
    if (this.tint) this.col.push(c * this.tint[0] / 255, c * this.tint[1] / 255, c * this.tint[2] / 255); else this.col.push(c, c, c)
    if (this.tile) this.tile.push(...(t ?? [0, 0, 1, 1]))
    return this.n - 1
  }
  tri (a: number, b: number, c: number) { this.idx.push(a, b, c); this.tc.push(...this.cur) }
  quad (a: number, b: number, c: number, d: number) { this.idx.push(a, b, c, a, c, d); this.tc.push(...this.cur, ...this.cur) }
  /** vertical wall from (x0,z0) to (x1,z1), y from yb to yt; u along length, v up */
  wall (x0: number, z0: number, x1: number, z1: number, yb: number, yt: number, c: number, us = 1, vs = 1, t?: number[]) {
    const L = Math.hypot(x1 - x0, z1 - z0)
    const a = this.v(x0, yb, z0, 0, yb * vs, c, t); const b = this.v(x1, yb, z1, L * us, yb * vs, c, t)
    const d = this.v(x1, yt, z1, L * us, yt * vs, c, t); const e = this.v(x0, yt, z0, 0, yt * vs, c, t)
    this.quad(a, b, d, e)
  }
  build () {
    const g = new THREE.BufferGeometry()
    g.setAttribute('position', new THREE.Float32BufferAttribute(this.pos, 3))
    g.setAttribute('uv', new THREE.Float32BufferAttribute(this.uv, 2))
    g.setAttribute('color', new THREE.Float32BufferAttribute(this.col, 3))
    if (this.tile) g.setAttribute('aTile', new THREE.Float32BufferAttribute(this.tile, 4))
    g.setIndex(this.n > 65535 ? new THREE.Uint32BufferAttribute(this.idx, 1) : new THREE.Uint16BufferAttribute(this.idx, 1))
    g.computeBoundingSphere()
    return g
  }
}
