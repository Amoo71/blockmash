// BlockMash atmosphere: Duke3D parallax sky (real shareware sky tiles) blended into the MC day/night cycle,
// sun shadows, dynamic point lights (explosions, muzzle flashes, Duke neon/sign/lamp sources, MC torches),
// distance + height fog, Dark Mod quarter darkness, cave darkness underground, ACES tone mapping and bloom.
// Graphics quality: Low (mobile default) / Medium / Ultra -- F7 cycles, `/mashup gfx <low|medium|ultra>`.
import * as THREE from 'three'
import { EffectComposer } from 'three/examples/jsm/postprocessing/EffectComposer.js'
import { RenderPass } from 'three/examples/jsm/postprocessing/RenderPass.js'
import { UnrealBloomPass } from 'three/examples/jsm/postprocessing/UnrealBloomPass.js'
import { ShaderPass } from 'three/examples/jsm/postprocessing/ShaderPass.js'
import { Vec3 } from 'vec3'
import { MAX_LIGHTS, dayUniform, fogColor, fogParams, glowBoost, indoor, lightCol, lightN, lightPos, shadowMap, shadowMat, shadowOn, shadowSize, skyTint } from './surfmat'
// eslint-disable-next-line @typescript-eslint/no-require-imports
const layout = require('../layout')

export type Quality = 'low' | 'medium' | 'ultra'
const PRESET: Record<Quality, { bloom: number, shadow: number, ext: number, mcLights: number, duLights: number, soft: boolean, fog: number }> = {
  low: { bloom: 0, shadow: 0, ext: 0, mcLights: 0, duLights: 4, soft: false, fog: 0.9 },
  medium: { bloom: 0.5, shadow: 1024, ext: 40, mcLights: 2, duLights: 6, soft: false, fog: 1 },
  ultra: { bloom: 1, shadow: 4096, ext: 96, mcLights: 4, duLights: MAX_LIGHTS, soft: true, fog: 1.15 }
}
const KEY = 'blockmash.gfx'
const mobile = () => matchMedia('(pointer: coarse)').matches || innerWidth < 1000
export const getQuality = (): Quality => { const q = localStorage.getItem(KEY); return q === 'low' || q === 'medium' || q === 'ultra' ? q : mobile() ? 'low' : 'medium' }

type L = { x: number, y: number, z: number, r: number, c: [number, number, number], t0?: number, dur?: number, key?: string, prio: number }
const lerp = (a: number, b: number, t: number) => a + (b - a) * t

export function initAtmosphere () {
  const viewer = (globalThis as any).viewer; const bot = (globalThis as any).bot; const server = (globalThis as any).localServer
  if (!viewer?.scene) return
  const scene: THREE.Scene = viewer.scene
  const renderer: THREE.WebGLRenderer = viewer.renderer
  let q: Quality = getQuality()
  let P = PRESET[q]

  // ---------------- tone mapping + bloom (renderer.render is wrapped so the viewer loop stays untouched)
  renderer.toneMapping = THREE.ACESFilmicToneMapping
  renderer.toneMappingExposure = 1.35
  let composer: EffectComposer | null = null; let renderPass: RenderPass | null = null; let bloom: UnrealBloomPass | null = null
  const rawRender = renderer.render.bind(renderer)
  let inComposer = false
  const size = new THREE.Vector2()
  renderer.render = (sc: THREE.Object3D, cam: THREE.Camera) => {
    if (!composer || inComposer || sc !== scene) { rawRender(sc, cam); return }
    renderer.getSize(size)
    const pr = renderer.getPixelRatio()
    if ((composer as any)._w !== size.x || (composer as any)._h !== size.y || (composer as any)._pr !== pr) {
      composer.setPixelRatio(pr); composer.setSize(size.x, size.y)
      bloom!.resolution.set(size.x * P.bloom, size.y * P.bloom)
      Object.assign(composer, { _w: size.x, _h: size.y, _pr: pr })
    }
    renderPass!.camera = cam
    inComposer = true
    try { composer.render() } finally { inComposer = false }
  }
  const setupComposer = () => {
    composer?.dispose(); composer = null
    if (!P.bloom) return
    composer = new EffectComposer(renderer)
    renderPass = new RenderPass(scene, viewer.camera)
    bloom = new UnrealBloomPass(new THREE.Vector2(256, 256), 0.55, 0.35, 1.02)
    composer.addPass(renderPass); composer.addPass(bloom); composer.addPass(new ShaderPass({ // final pass to the screen: three injects the renderer tone mapping here
      uniforms: { tDiffuse: { value: null } },
      vertexShader: 'varying vec2 vUv; void main(){ vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0); }',
      fragmentShader: 'uniform sampler2D tDiffuse; varying vec2 vUv; void main(){ gl_FragColor = texture2D(tDiffuse, vUv); \n#include <tonemapping_fragment>\n }'
    }))
  }

  // ---------------- sun / moon shadows (one shadow map that follows the player; none on Low)
  const sun: THREE.DirectionalLight = viewer.directionalLight
  scene.add(sun.target)
  const setupShadows = () => {
    renderer.shadowMap.enabled = P.shadow > 0
    renderer.shadowMap.type = P.soft ? THREE.PCFSoftShadowMap : THREE.PCFShadowMap
    sun.castShadow = P.shadow > 0
    if (P.shadow) {
      sun.shadow.map?.dispose(); (sun.shadow as any).map = null
      sun.shadow.mapSize.set(P.shadow, P.shadow)
      const c = sun.shadow.camera; c.left = -P.ext; c.right = P.ext; c.top = P.ext; c.bottom = -P.ext; c.near = 1; c.far = 400; c.updateProjectionMatrix()
      sun.shadow.bias = -0.0006; sun.shadow.normalBias = 0.04
      shadowSize.value.set(P.shadow, P.shadow); shadowMat.value = sun.shadow.matrix
    }
    shadowOn.value = 0
    scene.traverse((o: any) => { if (o.material) { for (const m of [o.material].flat()) m.needsUpdate = true } })
  }
  const markShadowCasters = () => {
    const blockMat = viewer.world?.material
    scene.traverse((o: any) => {
      if (!o.isMesh) return
      if (o.material === blockMat) { o.castShadow = P.shadow > 0; o.receiveShadow = P.shadow > 0 } else if (o.name === 'duke-level') o.castShadow = P.shadow > 0
      else if (o.parent && o.parent !== scene && !o.name.startsWith('duke') && o.material?.isMeshLambertMaterial) { o.castShadow = P.shadow > 0; o.receiveShadow = P.shadow > 0 }
    })
  }

  // ---------------- dynamic light pool (fixed size per quality so materials never recompile mid-game)
  let pool: THREE.PointLight[] = []
  const setupPool = () => {
    for (const l of pool) scene.remove(l)
    pool = Array.from({ length: P.mcLights }, () => { const l = new THREE.PointLight(0xffffff, 0, 10, 2); scene.add(l); return l })
  }
  const dyn: L[] = []
  const addLight = (l: L) => { if (l.key) { const o = dyn.find(d => d.key === l.key); if (o) { Object.assign(o, l); return } } dyn.push(l); if (dyn.length > 48) dyn.shift() }
  const hook = (serv: any) => {
    serv.on('blockmashExplosion', ({ center, radius }: any) => addLight({ x: center.x, y: center.y + 1, z: center.z, r: 10 + radius * 3, c: [3, 1.7, 0.6], t0: performance.now(), dur: 900, prio: 10 }))
    serv.on('blockmashDuke', (ev: any) => {
      const now = performance.now()
      if (ev.type === 'fire' && ev.player === bot.entity?.id) { const p = bot.entity.position; addLight({ x: p.x, y: p.y + 1.5, z: p.z, r: 7, c: [2.2, 1.7, 0.8], t0: now, dur: 110, prio: 9 }) }
      if (ev.type === 'enemyFire') { const e = bot.entities[ev.entity]; if (e) addLight({ x: e.position.x, y: e.position.y + 1.4, z: e.position.z, r: 6, c: [2, 1.5, 0.7], t0: now, dur: 110, prio: 8 }) }
      if (ev.type === 'rocket' && ev.at) addLight({ key: 'r' + ev.id, x: ev.at.x, y: ev.at.y, z: ev.at.z, r: 6, c: [2, 1.1, 0.4], t0: now, dur: 200, prio: 7 })
    })
    serv.on('blockmashGfx', (lvl: Quality) => setQuality(lvl))
  }
  if (server) hook(server)

  // MC light blocks near the player (torches, lanterns, glowstone, fire...)
  const LIGHT_BLOCKS: Record<string, [number, number, number]> = {
    torch: [1.3, 0.85, 0.45], wall_torch: [1.3, 0.85, 0.45], lantern: [1.3, 0.9, 0.5], campfire: [1.4, 0.8, 0.35], fire: [1.5, 0.8, 0.3],
    soul_torch: [0.4, 0.9, 1.3], soul_wall_torch: [0.4, 0.9, 1.3], soul_lantern: [0.4, 0.9, 1.3], glowstone: [1.3, 1.05, 0.6],
    jack_o_lantern: [1.3, 0.8, 0.3], sea_lantern: [0.8, 1.1, 1.2], shroomlight: [1.3, 0.8, 0.4], lava: [1.6, 0.6, 0.15], end_rod: [1.2, 1.1, 1.3]
  }
  let blockLights: L[] = []
  const scanBlocks = () => {
    if (!P.mcLights && P.duLights <= 4) { blockLights = []; return }
    const ids = Object.keys(LIGHT_BLOCKS).map(n => bot.registry.blocksByName[n]?.id).filter((x: any) => x != null)
    try {
      const found: Vec3[] = bot.findBlocks({ matching: ids, maxDistance: 18, count: 10 })
      blockLights = found.map(p => { const n = bot.world.getBlock(p)?.name; return { x: p.x + 0.5, y: p.y + 0.6, z: p.z + 0.5, r: n === 'lava' ? 8 : 9, c: LIGHT_BLOCKS[n] ?? [1, 0.8, 0.5], prio: 2 } })
    } catch { blockLights = [] }
  }

  // ---------------- Duke3D parallax sky (cylinder around the camera, real 8-panel shareware panorama)
  const skyTex = new Map<number, THREE.Texture>()
  const skyMat = new THREE.ShaderMaterial({
    uniforms: { map: { value: null }, uNight: { value: 0 }, uFade: { value: 0 }, uSky: { value: new THREE.Color() } },
    depthWrite: false, depthTest: false, side: THREE.BackSide, fog: false,
    vertexShader: 'varying vec2 vUv; void main(){ vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0); }',
    fragmentShader: `uniform sampler2D map; uniform float uNight; uniform float uFade; uniform vec3 uSky; varying vec2 vUv;
      void main(){
        vec4 t = texture2D(map, vec2(vUv.x * 2.0, vUv.y)); // panorama twice around (Build: 8 panels = 180 deg at this scale)
        float lum = dot(t.rgb, vec3(0.3, 0.59, 0.11));
        vec3 day = mix(uSky, t.rgb * 0.9 + uSky * 0.25, 0.55 + 0.45 * smoothstep(0.02, 0.2, lum));
        vec3 c = mix(day, t.rgb, uNight) + t.rgb * smoothstep(0.35, 0.7, lum) * uNight * 1.4; // lit windows bloom at night
        float a = smoothstep(1.0, 0.72, vUv.y) * uFade * t.a;
        gl_FragColor = vec4(mix(uSky, c, a), 1.0); // opaque, not tone mapped: matches the MC sky colour above the skyline
      }`
  })
  const SKY_R = 360
  const skyMesh = new THREE.Mesh(new THREE.CylinderGeometry(SKY_R, SKY_R, 1, 48, 1, true), skyMat)
  skyMesh.renderOrder = -1000; skyMesh.frustumCulled = false; skyMesh.name = 'blockmash-duke-sky'; skyMesh.visible = false
  scene.add(skyMesh)
  const loadSky = (pic: number, w: number, h: number) => {
    let t = skyTex.get(pic)
    if (!t) {
      t = new THREE.TextureLoader().load(`./duke/tiles/sky_${pic}.png`)
      t.wrapS = THREE.RepeatWrapping; t.magFilter = THREE.NearestFilter; t.minFilter = THREE.LinearFilter; t.generateMipmaps = false
      skyTex.set(pic, t)
    }
    if (skyMat.uniforms.map.value !== t) {
      skyMat.uniforms.map.value = t
      const H = h / w * Math.PI * SKY_R
      skyMesh.scale.set(1, H, 1); (skyMesh as any).H = H
    }
  }
  let man: any = null
  void fetch('./duke/manifest.json').then(r => r.json()).then(m => { man = m }).catch(() => {})

  // ---------------- quality
  const toast = document.createElement('div')
  toast.style.cssText = 'position:fixed;left:50%;top:18%;transform:translateX(-50%);padding:6px 14px;background:rgba(0,0,0,.6);color:#fff;font:14px blockmash,monospace;z-index:40;display:none;pointer-events:none'
  document.body.append(toast)
  let toastT: any
  const setQuality = (nq: Quality) => {
    if (!PRESET[nq]) return
    q = nq; P = PRESET[q]; localStorage.setItem(KEY, q)
    setupComposer(); setupShadows(); setupPool(); markShadowCasters(); scanBlocks()
    toast.textContent = `Graphics: ${q.toUpperCase()}  (F7)`; toast.style.display = 'block'; clearTimeout(toastT); toastT = setTimeout(() => { toast.style.display = 'none' }, 1800)
  }
  ;(globalThis as any).blockmashSetQuality = setQuality
  ;(globalThis as any).blockmashQuality = () => q
  addEventListener('keydown', e => { if (e.code === 'F7') { e.preventDefault(); setQuality(q === 'low' ? 'medium' : q === 'medium' ? 'ultra' : 'low') } })
  setQuality(q)
  toast.style.display = 'none'

  // ---------------- per-frame
  let env = { cave: 0, dark: 0 }; let lastScan = 0; let lastEnv = 0; let lastCast = 0
  let target = { cave: 0, dark: 0 }
  const seed = () => (server?.overworld?.seed ?? 0) | 0
  const covered = (p: any) => {
    for (let y = Math.floor(p.y) + 2; y < Math.floor(p.y) + 40; y++) { const b = bot.world.getBlock(new Vec3(Math.floor(p.x), y, Math.floor(p.z))); if (b && b.boundingBox === 'block' && b.name !== 'barrier') return true }
    return false
  }
  const ownBg = new THREE.Color(); const baseBg = new THREE.Color(0.68, 0.85, 0.9)
  const tick = () => {
    requestAnimationFrame(tick)
    const p = bot.entity?.position; if (!p) return
    const now = performance.now()
    const t = (bot.time?.timeOfDay ?? 6000) % 24000
    const sunA = ((t - 6000) / 24000) * Math.PI * 2
    const sunUp = Math.cos(sunA)
    const day = Math.max(0, Math.min(1, 0.5 + sunUp * 1.6)); const night = 1 - day
    // environment: cave (underground, covered, below sea level-ish) and the Dark Mod quarter
    if (now - lastEnv > 400) {
      lastEnv = now
      const info = layout.columnInfo(Math.floor(p.x), Math.floor(p.z), seed())
      target = { cave: p.y < 60 && covered(p) ? 1 : 0, dark: info.type === 'darkmod' && info.w > 0.5 ? 1 : 0 }
    }
    env = { cave: lerp(env.cave, target.cave, 0.05), dark: lerp(env.dark, target.dark, 0.03) }
    // sky / fog colour: MC day colour -> night, darkened in the Dark Mod quarter and caves
    // the MC sky colour (dayCycle/water.ts assign a new Color object whenever it changes) is our base
    if (scene.background !== ownBg) { if (scene.background instanceof THREE.Color) baseBg.copy(scene.background); scene.background = ownBg }
    const fc = new THREE.Color().copy(baseBg)
    fc.lerp(new THREE.Color(0.03, 0.035, 0.06), env.dark * 0.85)
    fc.lerp(new THREE.Color(0, 0, 0), env.cave)
    ownBg.copy(fc)
    fogColor.value.copy(fc)
    const viewDist = ((viewer.world?.viewDistance ?? 6) * 16) || 96
    const far = lerp(lerp(viewDist * 1.1 * P.fog, viewDist * 0.7, env.dark), 34, env.cave)
    const near = lerp(far * 0.42, 4, env.cave)
    if (!(scene.fog && (scene.fog as THREE.Fog).color?.getHex() === 0x0000ff)) { // keep the underwater fog from water.ts
      if (!scene.fog) scene.fog = new THREE.Fog(fc, near, far)
      const f = scene.fog as THREE.Fog; f.color.copy(fc); f.near = near; f.far = far
    }
    fogParams.value.set(near, far, (globalThis as any).blockmashDuke?.maps?.[0]?.G ?? 62, (0.15 + 0.35 * night) * (1 - env.cave))
    skyTint.value.setRGB(lerp(0.55, 1.05, day), lerp(0.62, 1.0, day), lerp(0.95, 0.98, day)).multiplyScalar(lerp(1, 0.55, env.dark))
    indoor.value = lerp(1, 0.6, night * 0.5 + env.dark * 0.5)
    glowBoost.value = 2.4
    // dayCycle.ts sets the ambient intensity on time changes; caves and the Dark Mod quarter scale it down
    const amb = viewer.ambientLight as any
    if (amb) { if (amb.__set !== amb.intensity) amb.__base = amb.intensity; amb.intensity = amb.__set = amb.__base * lerp(1, 0.4, Math.max(env.cave, env.dark * 0.8)) }
    renderer.toneMappingExposure = lerp(1.35, 1.15, night) * lerp(1, 1.25, env.cave)
    // sun follows the MC clock (moon at night)
    const dir = new THREE.Vector3(Math.sin(sunA), Math.abs(sunUp) < 0.08 ? 0.08 : Math.cos(sunA), 0.35)
    if (sunUp < 0) dir.multiplyScalar(-1)
    dir.normalize()
    const grid = P.ext ? (P.ext * 2) / P.shadow : 1
    const cx = Math.round(p.x / grid) * grid; const cz = Math.round(p.z / grid) * grid
    sun.target.position.set(cx, p.y, cz); sun.target.updateMatrixWorld()
    sun.position.set(cx + dir.x * 150, p.y + dir.y * 150, cz + dir.z * 150); sun.updateMatrixWorld()
    sun.color.setRGB(lerp(0.55, 1, day), lerp(0.62, 0.97, day), lerp(0.9, 0.9, day))
    if (P.shadow && sun.shadow.map) { shadowMap.value = sun.shadow.map.texture; shadowOn.value = env.cave > 0.5 ? 0 : 1 } else shadowOn.value = 0
    if (now - lastCast > 2000) { lastCast = now; markShadowCasters() }
    // lights: dynamic events + Duke level light sources + MC light blocks, nearest/most important first
    for (let i = dyn.length - 1; i >= 0; i--) if (dyn[i].dur && now - dyn[i].t0! > dyn[i].dur!) dyn.splice(i, 1)
    if (now - lastScan > 1500) { lastScan = now; scanBlocks() }
    const cand: L[] = []
    const push = (l: L, k: number) => { const d = Math.hypot(l.x - p.x, l.y - p.y, l.z - p.z); if (d < 48 + l.r) cand.push({ ...l, c: [l.c[0] * k, l.c[1] * k, l.c[2] * k], prio: l.prio - d / 16 }) }
    for (const l of dyn) { const a = l.dur ? 1 - (now - l.t0!) / l.dur : 1; push(l, a * a) }
    const nightGlow = lerp(0.55, 1, night)
    for (const L of ((globalThis as any).blockmashDukeLevels ?? [])) if (L.lights) for (const l of L.lights) push({ ...l, prio: 3 }, nightGlow)
    for (const l of blockLights) push(l, 1)
    cand.sort((a, b) => b.prio - a.prio)
    const nD = Math.min(P.duLights, cand.length)
    for (let i = 0; i < nD; i++) { const l = cand[i]; lightPos.value[i].set(l.x, l.y, l.z, l.r); lightCol.value[i].set(l.c[0], l.c[1], l.c[2]) }
    lightN.value = nD
    const mcC = cand.filter(l => l.prio > 0 || l.dur)
    pool.forEach((pl, i) => {
      const l = mcC[i]
      if (!l) { pl.intensity = 0; return }
      pl.position.set(l.x, l.y, l.z); pl.distance = l.r * 1.2
      const m = Math.max(l.c[0], l.c[1], l.c[2], 0.001); pl.color.setRGB(l.c[0] / m, l.c[1] / m, l.c[2] / m); pl.intensity = m * 1.3
    })
    // Duke sky near the Duke levels
    const dm = (globalThis as any).blockmashDuke
    let fade = 0; let skyPic = 89
    if (dm?.bbox && man?.skies) {
      const b = dm.bbox; const d = Math.hypot(Math.max(b.x0 - p.x, 0, p.x - b.x1), Math.max(b.z0 - p.z, 0, p.z - b.z1))
      fade = Math.max(0, Math.min(1, 1 - (d - 40) / 160)) * (1 - env.cave)
      let best = 1e9
      for (const L of ((globalThis as any).blockmashDukeLevels ?? [])) {
        const bb = L.sub.bbox; const dd = Math.hypot(Math.max(bb.x0 - p.x, 0, p.x - bb.x1), Math.max(bb.z0 - p.z, 0, p.z - bb.z1))
        if (L.sky != null && man.skies[L.sky] && dd < best) { best = dd; skyPic = L.sky }
      }
      if (man.skies[skyPic]) loadSky(skyPic, man.skies[skyPic].w, man.skies[skyPic].h)
    }
    skyMesh.visible = fade > 0.01 && !!skyMat.uniforms.map.value
    const stars = viewer.world?.starField?.points; if (stars) stars.visible = fade < 0.5 // the Duke sky replaces the MC stars
    if (skyMesh.visible) {
      const cam = viewer.camera as THREE.Camera
      const cp = new THREE.Vector3(); cam.getWorldPosition(cp)
      const H = (skyMesh as any).H ?? 200
      skyMesh.position.set(cp.x, cp.y + H * 0.5 - H * 0.2, cp.z); skyMesh.updateMatrixWorld()
      skyMat.uniforms.uFade.value = fade; skyMat.uniforms.uNight.value = Math.min(1, night * 1.1 + env.dark * 0.6); skyMat.uniforms.uSky.value.copy(fc)
    }
    void dayUniform
  }
  tick()
  console.log('[blockmash] atmosphere ready, quality', q)
}
