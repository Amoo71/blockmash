// BlockMash phase 3 client: Duke3D shareware sprites for enemies, explosions, rockets, HUD weapons + sounds.
// Data comes from ./duke/ (extracted locally from the user's unmodified shareware GRP); without it the
// game falls back to normal Minecraft-style models and silent weapons.
import * as THREE from 'three'
import { makeSprite, setTile, rotation, Manifest } from './sprites'
import { dukeUrl, getDukeManifest } from './dukedata'

const BASE = './duke'
type Anim = { idle: number, walk?: [number, number, number], attack?: number, death: number[], rots?: number, px?: number }
const ACTORS: Record<string, Anim> = {
  trooper: { idle: 1680, walk: [1685, 5, 4], attack: 1715, death: [1730, 1731, 1732, 1733, 1734] },
  pigcop: { idle: 2000, walk: [2005, 5, 3], attack: 2030, death: [2045, 2046, 2047, 2048, 2049] },
  octabrain: { idle: 1820, attack: 1840, death: [1850, 1851, 1852, 1853, 1854, 1855] },
  battlelord: { idle: 2630, walk: [2640, 5, 2], attack: 2655, death: [2680, 2681, 2682, 2683, 2684, 2685, 2686], px: 28 }
}
const HUD: Record<string, { idle: number, fire: number[], x?: number }> = {
  iron_horse_armor: { idle: 2524, fire: [2525, 2526, 2524] },
  golden_horse_armor: { idle: 2613, fire: [2614, 2616, 2617, 2618, 2619] },
  diamond_horse_armor: { idle: 2536, fire: [2537, 2538, 2539] },
  leather_horse_armor: { idle: 2544, fire: [2546, 2545] },
  firework_star: { idle: 2573, fire: [2572, 2574] }
}
const DETONATOR = { idle: 2568, fire: [2570, 2571, 2568] }
const EXPLOSION = Array.from({ length: 21 }, (_, i) => 1890 + i)

export async function initDuke () {
  let manifest: Manifest
  try {
    manifest = await getDukeManifest()
    if (!manifest) throw new Error('no data')
  } catch {
    console.log('[blockmash] Duke3D shareware data not installed – using fallbacks')
    return
  }
  const sounds = new Set(manifest.sounds)
  const play = (name: string, at?: { x: number, y: number, z: number }) => {
    if (!name || !sounds.has(name)) return
    let vol = 1
    if (at && bot?.entity) vol = Math.max(0, 1 - bot.entity.position.distanceTo(at as any) / 48)
    if (vol <= 0.02) return
    const a = new Audio(dukeUrl(`${BASE}/sounds/${name}.${manifest.soundExt ?? "ogg"}`))
    a.volume = vol * 0.8
    void a.play().catch(() => {})
  }

  // ----- HUD
  const hud = document.createElement('div')
  hud.id = 'blockmash-duke-hud'
  hud.style.cssText = 'position:fixed;left:0;right:0;bottom:0;height:0;pointer-events:none;z-index:5'
  const weapon = document.createElement('img')
  weapon.style.cssText = 'position:absolute;bottom:0;left:56%;transform:translateX(-50%);image-rendering:pixelated;display:none'
  const ammo = document.createElement('div')
  ammo.style.cssText = 'position:absolute;bottom:74px;right:14px;font:bold 22px blockmash,monospace;color:#ff3b1f;text-shadow:2px 2px #000;display:none'
  hud.append(weapon, ammo)
  document.body.append(hud)
  const fireBtn = document.createElement('div')
  fireBtn.textContent = 'FIRE'
  fireBtn.style.cssText = 'position:fixed;right:110px;bottom:150px;width:74px;height:74px;border-radius:50%;background:rgba(200,30,20,.55);color:#fff;font:bold 15px blockmash,sans-serif;display:none;align-items:center;justify-content:center;z-index:30;user-select:none;touch-action:none'
  document.body.append(fireBtn)

  let hudState = { ammo: {} as Record<string, number>, bombs: 0 }
  let anim: { frames: number[], t0: number } | null = null
  const AMMO_KEY: Record<string, string> = { iron_horse_armor: 'pistol', golden_horse_armor: 'shotgun', diamond_horse_armor: 'chaingun', leather_horse_armor: 'rpg' }
  const setImg = (tile: number) => {
    const m = manifest.tiles[tile]; if (!m) return
    const scale = Math.max(2, Math.round(innerHeight / 200 * 0.9))
    if ((weapon as any).__tile !== tile) { (weapon as any).__tile = tile; weapon.src = dukeUrl(`${BASE}/tiles/${tile}.png`) }
    weapon.style.width = `${m.w * scale}px`
    weapon.style.height = `${m.h * scale}px`
  }
  const updateHud = (now: number) => {
    const held = bot?.heldItem?.name
    const def = held === 'firework_star' && hudState.bombs > 0 ? DETONATOR : held ? HUD[held] : undefined
    const touch = !!(window as any).miscUiState?.currentTouch || matchMedia('(pointer: coarse)').matches
    fireBtn.style.display = def && touch ? 'flex' : 'none'
    if (!def) { weapon.style.display = 'none'; ammo.style.display = 'none'; return }
    weapon.style.display = 'block'
    let tile = def.idle
    if (anim) {
      const i = Math.floor((now - anim.t0) / 70)
      if (i < anim.frames.length) tile = anim.frames[i]; else anim = null
    }
    setImg(tile)
    const key = AMMO_KEY[held!]
    ammo.style.display = 'block'
    ammo.textContent = key ? String(hudState.ammo[key] ?? 0) : held === 'firework_star' ? `${bot.heldItem?.count ?? 0}${hudState.bombs ? ` · ${hudState.bombs} armed` : ''}` : ''
  }

  // ----- world sprites
  const tracked = new Map<number, { kind: string, sprite: THREE.Sprite, last: THREE.Vector3, moving: number, dead?: number, attack?: number, hurt?: number }>()
  const fx: Array<{ sprite: THREE.Sprite, frames: number[], t0: number, fps: number, px: number }> = []
  const rockets = new Map<string, THREE.Sprite>()
  const getServer = () => (window as any).localServer
  const dukeKind = (id: number) => getServer()?.blockmash?.mobs?.get(id)?.duke as string | undefined

  const attach = (id: number) => {
    const kind = dukeKind(id)
    const group = viewer.entities.entities[id]
    if (!kind || !group || tracked.has(id)) return
    for (const c of group.children) c.visible = false
    const a = ACTORS[kind]
    const sprite = makeSprite(manifest, BASE, a.idle, a.px)
    group.add(sprite)
    tracked.set(id, { kind, sprite, last: group.position.clone(), moving: 0 })
  }
  viewer.entities.on('add', (e: any) => attach(e.id))
  viewer.entities.on('remove', (e: any) => tracked.delete(e.id))
  for (const id of Object.keys(viewer.entities.entities)) attach(+id)
  bot.on('entityDead', (e: any) => { const t = tracked.get(e.id); if (t) t.dead = performance.now() })
  bot.on('entityHurt', (e: any) => { const t = tracked.get(e.id); if (t) t.hurt = performance.now() })

  const spawnFx = (frames: number[], at: { x: number, y: number, z: number }, px: number, fps = 24) => {
    const s = makeSprite(manifest, BASE, frames[0], px)
    s.center.set(0.5, 0.35)
    s.position.set(at.x, at.y, at.z)
    viewer.scene.add(s)
    fx.push({ sprite: s, frames, t0: performance.now(), fps, px })
  }

  // ----- server events (integrated singleplayer server)
  let hooked: any = null
  const hookServer = () => {
    const serv = getServer()
    if (!serv || serv === hooked || !serv.blockmash) return
    hooked = serv
    serv.on('blockmashDuke', (ev: any) => {
      const me = bot?.entity?.id
      if (ev.type === 'hud' && ev.player === me) hudState = { ammo: ev.ammo, bombs: ev.bombs }
      if ((ev.type === 'fire' || ev.type === 'throw' || ev.type === 'detonate') && ev.player === me) {
        const held = bot.heldItem?.name
        const def = ev.type === 'detonate' ? DETONATOR : held ? HUD[held] : undefined
        if (def) anim = { frames: def.fire, t0: performance.now() }
      }
      if (ev.sound) play(ev.sound, ev.player === me ? undefined : ev.at)
      if (ev.type === 'enemyFire') { const t = tracked.get(ev.entity); if (t) t.attack = performance.now() }
      if (ev.type === 'impact' || ev.type === 'hit') spawnFx([2595, 2596, 2597], ev.at, 64, 20)
      if (ev.type === 'rocket') {
        let r = rockets.get(ev.id)
        if (!r) { r = makeSprite(manifest, BASE, 2605, 48); r.center.set(0.5, 0.5); viewer.scene.add(r); rockets.set(ev.id, r) }
        r.position.set(ev.at.x, ev.at.y, ev.at.z)
      }
      if (ev.type === 'rocketEnd') { const r = rockets.get(ev.id); if (r) { viewer.scene.remove(r); rockets.delete(ev.id) } }
    })
    serv.on('blockmashExplosion', ({ center, radius }: any) => {
      spawnFx(EXPLOSION, center, Math.max(12, 30 - radius * 4))
      play('bombexpl', center)
    })
  }

  // fire button for touch screens
  let fireTimer: any = null
  const touchFire = () => {
    const serv = getServer(); const held = bot?.heldItem?.name
    const pl = serv?.players?.find((p: any) => p.id === bot.entity.id)
    if (pl && held) void serv.blockmash.duke.fire(pl, held)
  }
  fireBtn.addEventListener('touchstart', (e) => { e.preventDefault(); e.stopPropagation(); touchFire(); fireTimer = setInterval(touchFire, 120) })
  fireBtn.addEventListener('touchend', (e) => { e.preventDefault(); clearInterval(fireTimer) })

  const camPos = new THREE.Vector3()
  const loop = () => {
    requestAnimationFrame(loop)
    if (!bot?.entity) return
    hookServer()
    const now = performance.now()
    updateHud(now)
    viewer.camera.getWorldPosition(camPos)
    for (const [id, t] of tracked) {
      const group = viewer.entities.entities[id]
      const ent = bot.entities[id]
      if (!group || !ent) continue
      const a = ACTORS[t.kind]
      const moved = group.position.distanceTo(t.last)
      t.last.copy(group.position)
      t.moving = moved > 0.005 ? now : t.moving
      let tile: number; let mirror = false
      if (t.dead) {
        const i = Math.min(a.death.length - 1, Math.floor((now - t.dead) / 110))
        tile = a.death[i]
      } else {
        const [rot, m] = rotation(ent.yaw, group.position, camPos)
        mirror = m
        if (t.attack && now - t.attack < 350 && a.attack) tile = a.attack + (manifest.tiles[a.attack + rot] ? rot : 0)
        else if (a.walk && now - t.moving < 200) tile = a.walk[0] + Math.floor(now / 160) % a.walk[2] * a.walk[1] + rot
        else tile = a.idle + rot
        if (!manifest.tiles[tile]) tile = a.idle
      }
      setTile(t.sprite, manifest, BASE, tile, mirror, a.px)
      t.sprite.material.color.set(t.hurt && now - t.hurt < 150 ? 0xff6666 : 0xffffff)
      if (t.kind === 'octabrain') t.sprite.position.y = Math.sin(now / 300) * 0.15
    }
    for (let i = fx.length - 1; i >= 0; i--) {
      const f = fx[i]
      const k = Math.floor((now - f.t0) / (1000 / f.fps))
      if (k >= f.frames.length) { viewer.scene.remove(f.sprite); f.sprite.material.dispose(); fx.splice(i, 1); continue }
      setTile(f.sprite, manifest, BASE, f.frames[k], false, f.px)
    }
  }
  loop()
  console.log('[blockmash] Duke3D shareware content active')
}
