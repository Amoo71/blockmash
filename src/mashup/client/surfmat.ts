// Shared shader materials for the polygon surface (terrain, Duke3D map, Dark Mod buildings, Yorg track).
// All of them clip against the same crater list (uHoles) so explosions/mining cut real holes into every mesh,
// with a scorch ring around the cut. Lighting: Build sector shade (vertex colour) x sun/moon for outdoor sectors,
// dynamic point lights, optional sun shadow map lookup, Build fullbright glow, distance/height fog, tone mapping.
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

// ---------------- shared lighting/atmosphere uniforms (driven by atmosphere.ts)
export const MAX_LIGHTS = 8
export const lightPos = { value: Array.from({ length: MAX_LIGHTS }, () => new THREE.Vector4(0, -1000, 0, 1)) } // xyz + radius
export const lightCol = { value: Array.from({ length: MAX_LIGHTS }, () => new THREE.Vector3()) }
export const lightN = { value: 0 }
export const fogColor = { value: new THREE.Color(0.68, 0.85, 0.9) }
/** x near, y far, z height-fog top (world y), w height-fog strength */
export const fogParams = { value: new THREE.Vector4(80, 260, 60, 0) }
/** colour of the outdoor (sky) ambient: bright neutral by day, blue-grey at night */
export const skyTint = { value: new THREE.Color(1, 1, 1) }
/** interior ambient (sector shade does the rest) */
export const indoor = { value: 1 }
export const glowBoost = { value: 2.2 }
export const shadowOn = { value: 0 }
export const shadowMap: { value: THREE.Texture | null } = { value: null }
export const shadowMat = { value: new THREE.Matrix4() }
export const shadowSize = { value: new THREE.Vector2(1024, 1024) }
export const sunDir = { value: new THREE.Vector3(0.5, 1, 0.3).normalize() }

type Opts = { map?: THREE.Texture | null, atlas?: boolean, alphaTest?: number, side?: THREE.Side }

export function surfaceMaterial (o: Opts = {}) {
  const uniforms: Record<string, any> = {
    uFar: farUniform, uHoles: holeUniform, uHoleN: holeCount, uDay: dayUniform, map: { value: o.map ?? white() }, uAtlas: { value: new THREE.Vector2(1, 1) },
    uLP: lightPos, uLC: lightCol, uLN: lightN, uFogC: fogColor, uFogP: fogParams, uSky: skyTint, uIndoor: indoor, uGlow: glowBoost,
    uShOn: shadowOn, uShMap: { get value () { return shadowMap.value ?? white() } }, uShMat: shadowMat, uShSize: shadowSize
  }
  const defs: Record<string, any> = {}
  if (o.atlas) defs.ATLAS = 1
  if (o.alphaTest) defs.ALPHATEST = o.alphaTest
  const m = new THREE.ShaderMaterial({
    uniforms,
    defines: defs,
    side: o.side ?? THREE.FrontSide,
    vertexShader: /* glsl */`
      #include <common>
      #include <logdepthbuf_pars_vertex>
      attribute vec3 color; attribute vec2 aEnv;
      varying vec3 vCol; varying vec3 vW; varying vec2 vUv; varying vec2 vEnv; varying float vDist;
      #ifdef ATLAS
      attribute vec4 aTile; varying vec4 vTile;
      #endif
      void main () {
        vCol = color; vUv = uv; vEnv = aEnv;
        vec4 w = modelMatrix * vec4(position, 1.0); vW = w.xyz;
        #ifdef ATLAS
        vTile = aTile;
        #endif
        vec4 mv = viewMatrix * w; vDist = length(mv.xyz);
        gl_Position = projectionMatrix * mv;
        #include <logdepthbuf_vertex>
      }`,
    fragmentShader: /* glsl */`
      #include <common>
      #include <packing>
      #include <logdepthbuf_pars_fragment>
      uniform sampler2D map; uniform vec2 uAtlas; uniform float uDay;
      uniform vec4 uLP[${MAX_LIGHTS}]; uniform vec3 uLC[${MAX_LIGHTS}]; uniform int uLN;
      uniform vec3 uFogC; uniform vec4 uFogP; uniform vec3 uSky; uniform float uIndoor; uniform float uGlow;
      uniform float uShOn; uniform sampler2D uShMap; uniform mat4 uShMat; uniform vec2 uShSize;
      varying vec3 vCol; varying vec3 vW; varying vec2 vUv; varying vec2 vEnv; varying float vDist;
      #ifdef ATLAS
      varying vec4 vTile;
      #endif
      ${HOLE_GLSL}
      float sunVis () {
        vec4 sc = uShMat * vec4(vW, 1.0); sc.xyz /= sc.w;
        if (sc.x < 0.0 || sc.x > 1.0 || sc.y < 0.0 || sc.y > 1.0 || sc.z > 1.0) return 1.0;
        float z = sc.z - 0.0015; vec2 t = 1.0 / uShSize; float v = 0.0;
        v += step(z, unpackRGBAToDepth(texture2D(uShMap, sc.xy + vec2(-0.5, -0.5) * t)));
        v += step(z, unpackRGBAToDepth(texture2D(uShMap, sc.xy + vec2(0.5, -0.5) * t)));
        v += step(z, unpackRGBAToDepth(texture2D(uShMap, sc.xy + vec2(-0.5, 0.5) * t)));
        v += step(z, unpackRGBAToDepth(texture2D(uShMap, sc.xy + vec2(0.5, 0.5) * t)));
        return v * 0.25;
      }
      void main () {
        #include <logdepthbuf_fragment>
        float sh = holeShade(vW);
        vec4 c;
        #ifdef ATLAS
        vec2 p = vTile.xy + mod(vUv, vTile.zw);
        c = texture2D(map, p / uAtlas);
        #else
        c = texture2D(map, vUv);
        #endif
        #ifdef ALPHATEST
        if (c.a < float(ALPHATEST)) discard;
        #endif
        // Build fullbright palette entries (alpha 250 in the extracted tiles) and negative sector/wall shade glow
        float glow = (c.a > 0.95 && c.a < 0.99) ? 1.0 : 0.0;
        float shadeGlow = clamp((vCol.r - 1.58) * 8.0, 0.0, 1.0);
        // outdoor sectors follow the sun/moon, interiors keep their Build sector shade
        vec3 amb = mix(vec3(uIndoor), uSky * uDay, vEnv.x);
        if (uShOn > 0.5 && vEnv.x > 0.5) amb *= mix(0.55, 1.0, sunVis()) * 1.0;
        vec3 pl = vec3(0.0);
        for (int i = 0; i < ${MAX_LIGHTS}; i++) {
          if (i >= uLN) break;
          float d = distance(vW, uLP[i].xyz); float f = max(0.0, 1.0 - d / uLP[i].w);
          pl += uLC[i] * f * f;
        }
        vec3 col = c.rgb * vCol * sh * (max(amb, vec3(shadeGlow * 0.9)) + pl);
        col = mix(col, c.rgb * uGlow, glow);
        // distance fog (denser in sectors with a high Build visibility value) + height fog in low ground
        float fd = clamp((vDist * (0.8 + vEnv.y * 1.6) - uFogP.x) / max(1.0, uFogP.y - uFogP.x), 0.0, 1.0);
        float fh = clamp((uFogP.z - vW.y) / 12.0, 0.0, 1.0) * uFogP.w * smoothstep(4.0, 48.0, vDist);
        col = mix(col, uFogC, max(fd, fh));
        gl_FragColor = vec4(col, 1.0);
        #include <tonemapping_fragment>
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
  /** per-vertex environment: x = outdoor (under a parallax sky), y = Build sector visibility (0..1) */
  env: number[] = []; outdoor = 1; vis = 0
  constructor (atlas = false) { if (atlas) this.tile = [] }
  get n () { return this.pos.length / 3 }
  v (x: number, y: number, z: number, u: number, v: number, c: number, t?: number[]) {
    this.pos.push(x, y, z); this.uv.push(u, v)
    if (this.tint) this.col.push(c * this.tint[0] / 255, c * this.tint[1] / 255, c * this.tint[2] / 255); else this.col.push(c, c, c)
    if (this.tile) this.tile.push(...(t ?? [0, 0, 1, 1]))
    this.env.push(this.outdoor, this.vis)
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
    g.setAttribute('aEnv', new THREE.Float32BufferAttribute(this.env, 2))
    if (this.tile) g.setAttribute('aTile', new THREE.Float32BufferAttribute(this.tile, 4))
    g.setIndex(this.n > 65535 ? new THREE.Uint32BufferAttribute(this.idx, 1) : new THREE.Uint16BufferAttribute(this.idx, 1))
    g.computeBoundingSphere()
    return g
  }
}
