// BlockMash phase 5 client: drivable Yorg karts on the race-track zones.
// Car models/textures/sounds come from ./yorg/ (Yorg by Ya2, CC BY-SA, fetched + converted at install time);
// without them a simple box kart is used. Arcade kart physics on the block world (ground following,
// wall bumps, off-road slowdown), chase camera, parked cars in the pit garage, races against AI drivers
// with countdown, lap timing and positions. Own code (MIT).
import * as THREE from 'three'
import { Vec3 } from 'vec3'

const BASE = './yorg'
type Track = { cx: number, cz: number, G: number, A: number, R: number, HW: number, real?: boolean, path?: Array<{ x: number, y: number, z: number }>, cum?: number[], L?: number, starts?: Array<{ x: number, y: number, z: number }> }
// eslint-disable-next-line @typescript-eslint/no-require-imports
const { getYorg } = require('../surface/yorgworld')
type CarInfo = { maxSpeed?: number, acc?: number, steering?: number[], color?: number[] }
const DEFAULT_CARS = ['kronos', 'themis', 'diones', 'iapeto', 'iperion', 'phoibe', 'rea', 'teia']
const DRIVERS = ['Ya2 Bot Alpha', 'Ya2 Bot Bravo', 'Ya2 Bot Charlie']

export async function initYorg () {
  let manifest: { cars: Record<string, CarInfo>, sounds: string[] } = { cars: {}, sounds: [] }
  try { const r = await fetch(`${BASE}/manifest.json`); if (r.ok) manifest = await r.json() } catch {}
  const CARS = Object.keys(manifest.cars).length ? Object.keys(manifest.cars) : DEFAULT_CARS
  const sounds = new Set(manifest.sounds)
  const play = (name: string, vol = 0.8) => { if (!sounds.has(name)) return; const a = new Audio(`${BASE}/sounds/${name}.ogg`); a.volume = vol; void a.play().catch(() => {}) }

  // ---------- models
  const texLoader = new THREE.TextureLoader()
  const meshCache = new Map<string, Promise<any>>()
  const loadMesh = (car: string) => {
    if (!meshCache.has(car)) meshCache.set(car, fetch(`${BASE}/cars/${car}/mesh.json`).then(r => r.ok ? r.json() : null).catch(() => null))
    return meshCache.get(car)!
  }
  const geom = (m: any) => {
    const g = new THREE.BufferGeometry()
    g.setAttribute('position', new THREE.Float32BufferAttribute(m.pos, 3))
    g.setAttribute('uv', new THREE.Float32BufferAttribute(m.uv, 2))
    g.setIndex(m.idx)
    return g
  }
  const geoCache = new Map<string, { body: THREE.BufferGeometry, wheel: THREE.BufferGeometry, wheelRear: THREE.BufferGeometry, slots: number[][], bodyMat: THREE.Material, wheelMat: THREE.Material }>()
  type Kart = { group: THREE.Group, wheels: THREE.Object3D[], front: THREE.Object3D[] }
  const makeKart = async (car: string): Promise<Kart> => {
    const group = new THREE.Group()
    const wheels: THREE.Object3D[] = []; const front: THREE.Object3D[] = []
    let g = geoCache.get(car)
    if (!g) {
      const m = await loadMesh(car)
      if (m) {
        const map = texLoader.load(`${BASE}/cars/${car}/car.jpg`); map.colorSpace = THREE.SRGBColorSpace
        const wmap = texLoader.load(`${BASE}/cars/${car}/wheel.jpg`); wmap.colorSpace = THREE.SRGBColorSpace
        g = { body: geom(m.body), wheel: geom(m.wheel), wheelRear: geom(m.wheelRear), slots: m.slots, bodyMat: new THREE.MeshBasicMaterial({ map, side: THREE.DoubleSide }), wheelMat: new THREE.MeshBasicMaterial({ map: wmap }) }
        geoCache.set(car, g)
      }
    }
    if (g) {
      group.add(new THREE.Mesh(g.body, g.bodyMat))
      for (const s of g.slots) {
        const isFront = s[2] < 0
        const pivot = new THREE.Group(); pivot.position.set(s[0], s[1], s[2])
        const w = new THREE.Mesh(isFront ? g.wheel : g.wheelRear, g.wheelMat)
        if (s[0] < 0) w.rotation.y = Math.PI
        const spin = new THREE.Group(); spin.add(w); pivot.add(spin)
        group.add(pivot); wheels.push(spin); if (isFront) front.push(pivot)
      }
    } else {
      const color = new THREE.Color().setHSL(CARS.indexOf(car) / CARS.length, 0.8, 0.5)
      const body = new THREE.Mesh(new THREE.BoxGeometry(1.4, 0.5, 3), new THREE.MeshBasicMaterial({ color })); body.position.y = 0.2; group.add(body)
      for (const [x, z] of [[0.7, -1], [-0.7, -1], [0.7, 1.1], [-0.7, 1.1]]) {
        const pivot = new THREE.Group(); pivot.position.set(x, 0, z)
        const w = new THREE.Mesh(new THREE.CylinderGeometry(0.29, 0.29, 0.22, 10), new THREE.MeshBasicMaterial({ color: 0x111111 })); w.rotation.z = Math.PI / 2
        const spin = new THREE.Group(); spin.add(w); pivot.add(spin); group.add(pivot); wheels.push(spin); if (z < 0) front.push(pivot)
      }
    }
    return { group, wheels, front }
  }
  const WHEEL_R = 0.29
  const placeKart = (k: Kart, x: number, y: number, z: number, yaw: number, speed: number, steer: number, dt: number) => {
    k.group.position.set(x, y + WHEEL_R + 0.02, z)
    k.group.rotation.set(0, yaw, 0)
    for (const w of k.wheels) w.rotation.x -= speed * dt / WHEEL_R
    for (const f of k.front) f.rotation.y = steer * 0.45
  }
  const shade = () => {
    const t = ((bot as any)?.time?.timeOfDay ?? 6000) % 24000
    const day = t < 12500 || t > 23500 ? 1 : 0.35
    for (const g of geoCache.values()) { (g.bodyMat as any).color.setScalar(day * 0.95); (g.wheelMat as any).color.setScalar(day * 0.95) }
  }

  // ---------- track maths (stadium: two straights of half-length A, semicircles of radius R)
  const trackLen = (t: Track) => t.real ? t.L! : 4 * t.A + 2 * Math.PI * t.R
  // real Yorg track: racing line = closed polyline through the track's own waypoints
  const seg = (t: Track, i: number) => { const P = t.path!; const a = P[i % P.length]; const b = P[(i + 1) % P.length]; return { a, b, len: t.cum![i + 1] - t.cum![i] } }
  const progressReal = (t: Track, wx: number, wz: number) => {
    let best = 1e18; let bs = 0
    for (let i = 0; i < t.path!.length; i++) {
      const { a, b, len } = seg(t, i); const dx = b.x - a.x; const dz = b.z - a.z
      const u = Math.max(0, Math.min(1, ((wx - a.x) * dx + (wz - a.z) * dz) / (len * len || 1)))
      const d = (a.x + dx * u - wx) ** 2 + (a.z + dz * u - wz) ** 2
      if (d < best) { best = d; bs = t.cum![i] + u * len }
    }
    return bs
  }
  const alongReal = (t: Track, p: number, lat: number) => {
    const L = t.L!; p = ((p % L) + L) % L
    let i = 0; while (i < t.path!.length - 1 && t.cum![i + 1] < p) i++
    const { a, b, len } = seg(t, i); const u = len ? (p - t.cum![i]) / len : 0
    const hx = (b.x - a.x) / (len || 1); const hz = (b.z - a.z) / (len || 1)
    // lateral offset: positive = right of the driving direction
    const x = a.x + (b.x - a.x) * u - hz * lat; const z = a.z + (b.z - a.z) * u + hx * lat
    return { x, z, yaw: Math.atan2(-hx, -hz) }
  }
  const surfY = (x: number, z: number, fallback: number) => { const s = getYorg()?.surf(x, z); return s ? s.y : fallback }
  const progress = (t: Track, wx: number, wz: number) => {
    if (t.real) return progressReal(t, wx, wz)
    const x = wx - t.cx; const z = wz - t.cz; const { A, R } = t
    if (Math.abs(x) <= A) return z > 0 ? x : A + Math.PI * R + (A - x)
    if (x > A) return A + (Math.PI / 2 - Math.atan2(z, x - A)) * R
    const th = Math.atan2(z, x + A)
    const tr = (((-Math.PI / 2 - th) % (2 * Math.PI)) + 2 * Math.PI) % (2 * Math.PI)
    return 3 * A + Math.PI * R + tr * R
  }
  // world position + heading for progress p and lateral offset (positive = outside)
  const along = (t: Track, p: number, lat: number) => {
    if (t.real) return alongReal(t, p, lat)
    const { A, R } = t; const L = trackLen(t)
    p = ((p + A) % L + L) % L - A
    let x: number, z: number, hx: number, hz: number
    if (p <= A) { x = p; z = R + lat; hx = 1; hz = 0 } else if (p <= A + Math.PI * R) {
      const th = Math.PI / 2 - (p - A) / R
      x = A + Math.cos(th) * (R + lat); z = Math.sin(th) * (R + lat); hx = Math.sin(th); hz = -Math.cos(th)
    } else if (p <= 3 * A + Math.PI * R) { x = A - (p - A - Math.PI * R); z = -R - lat; hx = -1; hz = 0 } else {
      const th = -Math.PI / 2 - (p - 3 * A - Math.PI * R) / R
      x = -A + Math.cos(th) * (R + lat); z = Math.sin(th) * (R + lat); hx = Math.sin(th); hz = -Math.cos(th)
    }
    // mineflayer yaw: forward = (-sin yaw, -cos yaw)
    return { x: x + t.cx, z: z + t.cz, yaw: Math.atan2(-hx, -hz) }
  }

  // ---------- world queries
  const solidTop = (x: number, y: number, z: number): number | null => {
    const b = bot.blockAt(new Vec3(Math.floor(x), Math.floor(y), Math.floor(z)))
    if (!b || b.boundingBox !== 'block' || !b.shapes?.length) return null
    let top = 0; for (const s of b.shapes) top = Math.max(top, s[4])
    return Math.floor(y) + top
  }
  const groundBelow = (x: number, y: number, z: number) => {
    const ys = getYorg()?.surf(x, z)
    if (ys && ys.kind !== 3 && ys.y <= y + 0.6 && ys.y > y - 4) {
      const b = bot.blockAt(new Vec3(Math.floor(x), Math.floor(ys.y - 0.35) - 1, Math.floor(z)))
      if (b && b.name !== 'air') return ys.y // block layer still there (no crater)
    }
    for (let yy = Math.floor(y + 0.6); yy >= Math.floor(y) - 4; yy--) { const t = solidTop(x, yy, z); if (t !== null && t <= y + 0.6) return t }
    return null
  }
  const OFFROAD = /grass|dirt|sand|gravel|farmland|podzol|snow|mycelium|leaves|water/

  // ---------- HUD
  const hud = document.createElement('div')
  hud.style.cssText = 'position:fixed;top:8px;left:50%;transform:translateX(-50%);display:none;pointer-events:none;z-index:6;font:16px blockmash,sans-serif;color:#fff;text-shadow:2px 2px #000;text-align:center;white-space:pre'
  const big = document.createElement('div')
  big.style.cssText = 'position:fixed;top:30%;left:50%;transform:translateX(-50%);display:none;pointer-events:none;z-index:6;font:bold 64px blockmash,sans-serif;color:#ffd23f;text-shadow:4px 4px #000;text-align:center;white-space:pre'
  const speedo = document.createElement('div')
  speedo.style.cssText = 'position:fixed;right:16px;bottom:80px;display:none;pointer-events:none;z-index:6;font:bold 28px blockmash,monospace;color:#7df;text-shadow:2px 2px #000'
  const exitBtn = document.createElement('div')
  exitBtn.textContent = 'EXIT'
  const btnCss = (right: number, bottom: number, bg: string) => `position:fixed;right:${right}px;bottom:${bottom}px;width:66px;height:66px;border-radius:50%;background:${bg};color:#fff;font:bold 14px blockmash,sans-serif;display:none;align-items:center;justify-content:center;z-index:30;user-select:none;touch-action:none`
  exitBtn.style.cssText = btnCss(110, 235, 'rgba(30,90,200,.55)')
  const brakeBtn = document.createElement('div')
  brakeBtn.textContent = 'DRIFT'
  brakeBtn.style.cssText = btnCss(110, 150, 'rgba(200,120,20,.55)')
  document.body.append(hud, big, speedo, exitBtn, brakeBtn)
  const fmt = (ms: number) => { const s = ms / 1000; return `${Math.floor(s / 60)}:${(s % 60).toFixed(2).padStart(5, '0')}` }
  const say = (text: string, ms = 1200) => { big.textContent = text; big.style.display = 'block'; clearTimeout((say as any).t); (say as any).t = setTimeout(() => { big.style.display = 'none' }, ms) }
  const best = () => Number(localStorage.getItem('blockmash-yorg-best') || 0)

  // ---------- state
  let selected = Number(localStorage.getItem('blockmash-yorg-car') || 0) % CARS.length
  let track: Track | null = null
  const parked: Array<{ car: string, kart: Kart | null, x: number, y: number, z: number, yaw: number }> = []
  let parkedFor = ''
  type Drive = { car: string, kart: Kart | null, pos: Vec3, yaw: number, speed: number, steer: number, vy: number, info: CarInfo, sneakWas: boolean, touchBrake: boolean, engine?: HTMLAudioElement, lastBump: number, parkedIdx: number }
  let drive: Drive | null = null
  type Ai = { name: string, car: string, kart: Kart | null, total: number, speed: number, vmax: number, lat: number, phase: number, done?: number }
  let race: null | { t: Track, laps: number, goAt: number, startAt: number, total: number, prevP: number, lapStart: number, laps_done: number, lapTimes: number[], ai: Ai[], finished?: number, lastCount: number } = null

  const vmaxOf = (info: CarInfo) => 22 * (info.maxSpeed ?? 120) / 120
  const accOf = (info: CarInfo) => 11 * (info.acc ?? 2000) / 2000

  const refreshTrack = () => {
    const serv = (window as any).localServer
    const t = serv?.blockmash?.yorg?.trackNear?.(bot.entity.position)
    track = t && t.dist < 170 ? t : null
    const key = track ? `${track.cx},${track.cz}` : ''
    if (key === parkedFor) return
    for (const p of parked) if (p.kart) viewer.scene.remove(p.kart.group)
    parked.length = 0; parkedFor = key
    if (!track) return
    CARS.forEach((car, i) => {
      const st = track!.real ? track!.starts![i % track!.starts!.length] : null
      const x = st ? st.x : track!.cx - 8.75 + i * 2.5; const z = st ? st.z : track!.cz + 0.5
      const yaw = st ? along(track!, progress(track!, st.x, st.z), 0).yaw : 0
      const spot = { car, kart: null as Kart | null, x, y: st ? surfY(x, z, st.y) : track!.G + 1, z, yaw }
      parked.push(spot)
      void makeKart(car).then(k => { if (parkedFor !== key) return; spot.kart = k; placeKart(k, x, spot.y, z, yaw, 0, 0, 0); viewer.scene.add(k.group) })
    })
  }

  const origCam = viewer.setFirstPersonCamera.bind(viewer)
  ;(viewer as any).setFirstPersonCamera = (pos: any, yaw: number, pitch: number, roll?: number) => {
    if (!drive) return origCam(pos, yaw, pitch, roll)
    const d = drive; const fx = -Math.sin(d.yaw); const fz = -Math.cos(d.yaw)
    const back = 4.2 + Math.min(1.5, Math.abs(d.speed) / 18)
    return origCam(new Vec3(d.pos.x - fx * back, d.pos.y + 0.9, d.pos.z - fz * back), d.yaw, -0.22, roll)
  }

  const startDrive = async (car: string, at?: { x: number, y: number, z: number, yaw: number }, parkedIdx = -1) => {
    if (drive) stopDrive(false)
    const info = manifest.cars[car] ?? {}
    const p = at ?? { x: bot.entity.position.x, y: bot.entity.position.y, z: bot.entity.position.z, yaw: bot.entity.yaw }
    drive = { car, kart: null, pos: new Vec3(p.x, p.y, p.z), yaw: p.yaw, speed: 0, steer: 0, vy: 0, info, sneakWas: true, touchBrake: false, lastBump: 0, parkedIdx }
    if (parkedIdx >= 0 && parked[parkedIdx]?.kart) parked[parkedIdx].kart!.group.visible = false
    bot.physicsEnabled = false
    const k = await makeKart(car)
    if (!drive || drive.car !== car) return
    drive.kart = k; viewer.scene.add(k.group)
    if (sounds.has('engine')) { const a = new Audio(`${BASE}/sounds/engine.ogg`); a.loop = true; a.volume = 0.35; (a as any).preservesPitch = false; void a.play().catch(() => {}); drive.engine = a }
    speedo.style.display = 'block'
  }
  const stopDrive = (park = true) => {
    const d = drive; if (!d) return
    drive = null
    d.engine?.pause()
    if (d.kart) viewer.scene.remove(d.kart.group)
    if (d.parkedIdx >= 0 && parked[d.parkedIdx]?.kart) {
      const sp = parked[d.parkedIdx]
      if (park) { sp.x = d.pos.x; sp.y = d.pos.y; sp.z = d.pos.z; sp.yaw = d.yaw; placeKart(sp.kart!, sp.x, sp.y, sp.z, sp.yaw, 0, 0, 0) }
      sp.kart!.group.visible = true
    }
    // step out to the left of the kart
    const lx = Math.cos(d.yaw) * -1.6; const lz = -Math.sin(d.yaw) * -1.6
    bot.entity.position.set(d.pos.x + lx, d.pos.y + 0.2, d.pos.z + lz)
    bot.entity.velocity.set(0, 0, 0)
    bot.physicsEnabled = true
    speedo.style.display = 'none'
    origCam(bot.entity.position, bot.entity.yaw, bot.entity.pitch)
  }

  const startRace = async (t: Track, laps: number) => {
    if (race) for (const a of race.ai) if (a.kart) viewer.scene.remove(a.kart.group)
    const L = trackLen(t)
    const grid = (i: number) => along(t, -4 - i * 4, i % 2 ? -2.5 : 2.5)
    const me = grid(0)
    if (t.real) for (const p of parked) if (p.kart) p.kart.group.visible = false // the grid is the race now
    await startDrive(CARS[selected], { x: me.x, y: t.real ? surfY(me.x, me.z, t.G + 1) : t.G + 1, z: me.z, yaw: me.yaw })
    const ai: Ai[] = DRIVERS.map((name, i) => ({ name, car: CARS[(selected + 1 + i * 2) % CARS.length], kart: null, total: -4 - (i + 1) * 4, speed: 0, vmax: vmaxOf(manifest.cars[CARS[(selected + 1 + i * 2) % CARS.length]] ?? {}) * (0.9 + i * 0.035 + Math.random() * 0.04), lat: (i + 1) % 2 ? -2.5 : 2.5, phase: Math.random() * 6 }))
    for (const a of ai) void makeKart(a.car).then(k => { a.kart = k; if (race?.ai.includes(a)) viewer.scene.add(k.group) })
    const now = performance.now()
    race = { t, laps, goAt: now + 3600, startAt: now, total: -4, prevP: progress(t, me.x, me.z), lapStart: 0, laps_done: -1, lapTimes: [], ai, lastCount: 4 }
    void L
    hud.style.display = 'block'
  }
  const endRace = () => {
    if (!race) return
    for (const a of race.ai) if (a.kart) viewer.scene.remove(a.kart.group)
    race = null; hud.style.display = 'none'
    for (const p of parked) if (p.kart) p.kart.group.visible = true
  }

  // ---------- events from the integrated server
  let hooked: any = null; let lastUse = 0
  const hook = () => {
    const serv = (window as any).localServer
    if (!serv?.blockmash?.yorg || serv === hooked) return
    hooked = serv
    serv.on('blockmashYorg', (ev: any) => {
      if (ev.player !== bot?.entity?.id) return
      if (ev.type === 'drive') void startDrive(ev.car ?? CARS[selected])
      if (ev.type === 'stop') { endRace(); stopDrive() }
      if (ev.type === 'race') void startRace(ev.track, ev.laps)
      if (ev.type === 'use') {
        const now = performance.now(); if (now - lastUse < 350) return; lastUse = now
        if (drive) { if (!race) stopDrive(); return }
        if (ev.key && ev.sneak) { selected = (selected + 1) % CARS.length; localStorage.setItem('blockmash-yorg-car', String(selected)); say(CARS[selected].toUpperCase(), 1000); return }
        const pos = bot.entity.position
        let bi = -1; let bd = 3
        parked.forEach((p, i) => { const d = Math.hypot(p.x - pos.x, p.z - pos.z); if (d < bd && Math.abs(p.y - pos.y) < 2) { bd = d; bi = i } })
        if (bi >= 0) { const p = parked[bi]; selected = CARS.indexOf(p.car); void startDrive(p.car, { x: p.x, y: p.y, z: p.z, yaw: p.yaw }, bi); return }
        if (ev.key) void startDrive(CARS[selected])
      }
    })
  }

  const isTouch = () => !!(window as any).miscUiState?.currentTouch || matchMedia('(pointer: coarse)').matches
  exitBtn.addEventListener('touchstart', (e) => { e.preventDefault(); e.stopPropagation(); endRace(); stopDrive() })
  brakeBtn.addEventListener('touchstart', (e) => { e.preventDefault(); e.stopPropagation(); if (drive) drive.touchBrake = true })
  brakeBtn.addEventListener('touchend', (e) => { e.preventDefault(); if (drive) drive.touchBrake = false })

  // ---------- simulation loop
  let last = performance.now(); let lastTrack = 0
  const loop = () => {
    requestAnimationFrame(loop)
    const now = performance.now(); const dt = Math.min(0.05, (now - last) / 1000); last = now
    if (!bot?.entity) return
    hook()
    if (now - lastTrack > 2000) { lastTrack = now; refreshTrack(); shade() }
    const touch = isTouch()
    exitBtn.style.display = drive && touch ? 'flex' : 'none'
    brakeBtn.style.display = drive && touch ? 'flex' : 'none'
    hud.style.top = touch ? '46px' : '8px'
    speedo.style.bottom = touch ? 'auto' : '80px'; speedo.style.top = touch ? '40px' : 'auto'; speedo.style.right = touch ? 'auto' : '16px'; speedo.style.left = touch ? '12px' : 'auto'; speedo.style.fontSize = touch ? '20px' : '28px'
    if ((bot as any).health !== undefined && bot.health <= 0 && drive) { endRace(); stopDrive(false) }
    const d = drive
    if (d) {
      const c = bot.controlState
      if (c.sneak && !d.sneakWas && !race) { stopDrive(); return }
      d.sneakWas = c.sneak
      const locked = !!race && now < race.goAt
      const vmax = vmaxOf(d.info); const acc = accOf(d.info)
      const under = bot.blockAt(new Vec3(Math.floor(d.pos.x), Math.floor(d.pos.y - 0.2), Math.floor(d.pos.z)))
      const ysf = getYorg()?.surf(d.pos.x, d.pos.z)
      const off = ysf ? ysf.kind === 2 : under ? OFFROAD.test(under.name) : false
      const cap = off ? vmax * 0.5 : vmax
      const handbrake = c.jump || d.touchBrake
      if (!locked && c.forward) d.speed += (d.speed < 0 ? acc * 2.5 : acc * (1 - Math.max(0, d.speed) / cap * 0.6)) * dt
      else if (!locked && c.back) d.speed -= (d.speed > 0 ? 28 : acc * 0.6) * dt
      else d.speed -= Math.sign(d.speed) * Math.min(Math.abs(d.speed), 5 * dt)
      if (d.speed > cap) d.speed = Math.max(cap, d.speed - 18 * dt)
      d.speed = Math.max(-6, d.speed)
      if (handbrake) d.speed -= Math.sign(d.speed) * Math.min(Math.abs(d.speed), 9 * dt)
      const steerIn = (c.left ? 1 : 0) - (c.right ? 1 : 0)
      d.steer += (steerIn - d.steer) * Math.min(1, dt * 8)
      const grip = Math.min(1, Math.abs(d.speed) / 5) * (1 - Math.min(0.45, Math.abs(d.speed) / vmax * 0.45))
      d.yaw += d.steer * grip * (handbrake ? 3.2 : 2.1) * dt * Math.sign(d.speed || 1)
      const fx = -Math.sin(d.yaw); const fz = -Math.cos(d.yaw)
      // move in small sub-steps; probe bumper corners + body sides at body height (thin tyre walls)
      const dir = Math.sign(d.speed) || 1
      const rx = -fz; const rz = fx // right vector
      const hit = (x: number, z: number) => {
        const lo = solidTop(x, d.pos.y + 0.3, z); const hi = solidTop(x, d.pos.y + 1.3, z)
        if (hi !== null) return 2
        if (lo !== null && lo > d.pos.y + 0.6) return lo - d.pos.y <= 1.01 && solidTop(x, d.pos.y + 2.3, z) === null ? 1 : 2
        return 0
      }
      const dist = d.speed * dt; const steps = Math.max(1, Math.ceil(Math.abs(dist) / 0.25))
      let blocked = false
      for (let i = 0; i < steps && !blocked; i++) {
        const nx = d.pos.x + fx * dist / steps; const nz = d.pos.z + fz * dist / steps
        let worst = 0; let stepTo = 0
        for (const [a, b] of [[1.75, 0], [1.6, 0.7], [1.6, -0.7], [0.4, 0.85], [0.4, -0.85], [-0.9, 0.85], [-0.9, -0.85]]) {
          const fwd = a * (a > 1 ? dir : 1)
          const h = hit(nx + fx * fwd + rx * b, nz + fz * fwd + rz * b)
          if (h > worst) { worst = h; if (h === 1) stepTo = solidTop(nx + fx * fwd + rx * b, d.pos.y + 0.3, nz + fz * fwd + rz * b) ?? 0 }
        }
        if (worst === 1 && Math.abs(d.speed) < 5) { d.pos.y = stepTo; d.pos.x = nx; d.pos.z = nz } else if (worst) blocked = true
        else { d.pos.x = nx; d.pos.z = nz }
      }
      if (blocked) {
        if (Math.abs(d.speed) > 3 && now - d.lastBump > 500) { play(Math.abs(d.speed) > 14 ? 'crash_high_speed' : 'crash', 0.6); d.lastBump = now }
        d.speed = -d.speed * 0.3
      }
      // AI kart bumps
      if (race) {
        for (const a of race.ai) {
          const ap = along(race.t, a.total, a.lat)
          const dd = Math.hypot(ap.x - d.pos.x, ap.z - d.pos.z)
          if (dd < 2.2) {
            const k = (2.2 - dd) / 2.2; d.pos.x += (d.pos.x - ap.x) * k * 0.5; d.pos.z += (d.pos.z - ap.z) * k * 0.5
            if (now - d.lastBump > 600) { play('hit', 0.5); d.lastBump = now; if (a.total > race.total) d.speed *= 0.8; else a.speed *= 0.75 }
          }
        }
      }
      // ground following + gravity
      const g = groundBelow(d.pos.x, d.pos.y, d.pos.z)
      if (g !== null && g >= d.pos.y - 0.05 - Math.max(0, -d.vy) * dt) { if (d.vy < -8) play('landing', 0.5); d.pos.y = g; d.vy = 0 } else { d.vy -= 28 * dt; d.pos.y += d.vy * dt }
      if (d.pos.y < -60) { stopDrive(false); return }
      bot.entity.position.set(d.pos.x, d.pos.y, d.pos.z)
      bot.entity.velocity.set(0, 0, 0)
      bot.entity.yaw = d.yaw; bot.entity.onGround = true
      if (d.kart) placeKart(d.kart, d.pos.x, d.pos.y, d.pos.z, d.yaw, d.speed, d.steer, dt)
      viewer.setFirstPersonCamera(bot.entity.position, d.yaw, -0.22)
      if (d.engine) { d.engine.playbackRate = 0.6 + Math.min(1.6, Math.abs(d.speed) / vmax * 1.4); d.engine.volume = 0.25 + Math.min(0.3, Math.abs(d.speed) / vmax * 0.3) }
      speedo.textContent = `${Math.round(Math.abs(d.speed) * 3.6)} km/h${off ? '  OFF-ROAD' : ''}`
    }
    // ---------- race logic
    const r = race
    if (r) {
      const t = r.t; const L = trackLen(t)
      if (now < r.goAt) {
        const n = Math.ceil((r.goAt - now) / 1200)
        if (n !== r.lastCount && n <= 3) { r.lastCount = n; say(String(n), 900); play('countdown', 0.7) }
      } else if (r.lastCount !== 0) { r.lastCount = 0; say('GO!', 900); r.lapStart = now }
      if (d && !r.finished) {
        const p = progress(t, d.pos.x, d.pos.z)
        let dp = p - r.prevP; if (dp > L / 2) dp -= L; if (dp < -L / 2) dp += L
        r.prevP = p; r.total += dp
        const done = Math.floor(r.total / L)
        if (done > r.laps_done) {
          if (r.laps_done >= 0 && now > r.goAt) {
            const lt = now - r.lapStart; r.lapTimes.push(lt); r.lapStart = now; play('lap', 0.7)
            if (!best() || lt < best()) localStorage.setItem('blockmash-yorg-best', String(Math.round(lt)))
            if (r.lapTimes.length >= r.laps) {
              r.finished = now
              const pos = 1 + r.ai.filter(a => a.done && a.done < now).length
              say(`FINISH  P${pos}`, 4000)
              hud.dataset.result = `P${pos}/4 · total ${fmt(now - r.goAt)} · best lap ${fmt(Math.min(...r.lapTimes))}`
              console.log('[blockmash] Yorg race result', hud.dataset.result)
              setTimeout(() => endRace(), 6000)
            } else if (r.lapTimes.length === r.laps - 1) say('FINAL LAP', 1200)
          }
          r.laps_done = done
        }
      }
      // AI drivers
      for (const a of r.ai) {
        if (now > r.goAt && !(a.done && now - a.done > 4000)) {
          const p = ((a.total % L) + L) % L
          let inCurve: boolean
          if (t.real) { const y0 = along(t, p, 0).yaw; const y1 = along(t, p + 18, 0).yaw; let dy = Math.abs(y1 - y0) % (2 * Math.PI); if (dy > Math.PI) dy = 2 * Math.PI - dy; inCurve = dy > 0.3 } else inCurve = Math.abs(along(t, p, 0).x - t.cx) > t.A
          const target = a.vmax * (inCurve ? 0.93 : 1)
          a.speed += Math.max(-12 * dt, Math.min(8 * dt, target - a.speed))
          a.total += a.speed * dt
          a.lat = Math.max(-t.HW + 1.5, Math.min(t.HW - 1.5, a.lat + Math.sin(now / 1700 + a.phase) * dt * 0.6))
          if (!a.done && a.total >= r.laps * L) a.done = now
        } else a.speed = Math.max(0, a.speed - 10 * dt)
        const ap = along(t, a.total, a.lat)
        if (a.kart) placeKart(a.kart, ap.x, t.real ? surfY(ap.x, ap.z, t.G + 1) : t.G + 1, ap.z, ap.yaw, a.speed, 0, dt)
      }
      if (d) {
        const ranking = [r.total, ...r.ai.map(a => a.total)].sort((x, y) => y - x)
        const pos = ranking.indexOf(r.total) + 1
        const lap = Math.min(r.laps, Math.max(1, r.lapTimes.length + 1))
        const cur = now > r.goAt ? now - r.lapStart : 0
        const b = best()
        hud.textContent = `YORG RACE · LAP ${lap}/${r.laps} · POS ${pos}/4\n${fmt(r.finished ? 0 : cur)}${r.lapTimes.length ? `  last ${fmt(r.lapTimes[r.lapTimes.length - 1])}` : ''}${b ? `  best ${fmt(b)}` : ''}`
      } else endRace()
    }
  }
  requestAnimationFrame(loop)
  ;(window as any).blockmashYorg = { startDrive, stopDrive, startRace, get drive () { return drive }, get race () { return race }, get track () { return track }, progress, along }
}
