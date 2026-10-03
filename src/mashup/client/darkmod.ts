// BlockMash phase 4 client: Dark Mod HUD (light gem, loot, arrows), guard alert markers, sounds, flashbomb, spyglass.
// Icons/sounds from ./darkmod/ (The Dark Mod, CC BY-NC-SA 3.0, fetched at install time).
import * as THREE from 'three'

const BASE = './darkmod'
export async function initDarkMod () {
  let manifest: { icons: string[], sounds: string[], lightgem: number }
  try { const r = await fetch(`${BASE}/manifest.json`); if (!r.ok) throw new Error(); manifest = await r.json() } catch { manifest = { icons: [], sounds: [], lightgem: 0 } }
  const sounds = new Set(manifest.sounds)
  const play = (name: string, at?: any) => {
    if (!sounds.has(name)) return
    let vol = 1
    if (at && bot?.entity) vol = Math.max(0, 1 - bot.entity.position.distanceTo(at) / 32)
    if (vol < 0.03) return
    const a = new Audio(`${BASE}/sounds/${name}.ogg`); a.volume = vol * 0.9; void a.play().catch(() => {})
  }
  const TOOL_ITEMS = new Set(['music_disc_mellohi', 'music_disc_stal', 'music_disc_strad', 'music_disc_ward', 'music_disc_11', 'music_disc_wait'])

  const box = document.createElement('div')
  box.style.cssText = 'position:fixed;left:50%;bottom:64px;transform:translateX(-50%);display:none;flex-direction:column;align-items:center;pointer-events:none;z-index:5;font:14px blockmash,sans-serif;color:#d8c9a0;text-shadow:1px 1px #000'
  const gem = document.createElement('img'); gem.style.cssText = 'width:96px;height:48px;object-fit:contain'
  const info = document.createElement('div')
  box.append(gem, info); document.body.append(box)
  const flash = document.createElement('div'); flash.style.cssText = 'position:fixed;inset:0;background:#fff;opacity:0;pointer-events:none;z-index:6;transition:opacity 1.2s'
  document.body.append(flash)
  const toast = document.createElement('div'); toast.style.cssText = 'position:fixed;top:18%;left:50%;transform:translateX(-50%);font:20px blockmash,serif;color:#e8d8a8;text-shadow:2px 2px #000;pointer-events:none;z-index:6;display:none'
  document.body.append(toast)

  let hud: any = null
  const markers = new Map<number, THREE.Sprite>()
  const markerTex = (ch: string, color: string) => {
    const c = document.createElement('canvas'); c.width = 32; c.height = 32
    const g = c.getContext('2d')!; g.font = 'bold 28px sans-serif'; g.textAlign = 'center'; g.fillStyle = color; g.strokeStyle = '#000'; g.lineWidth = 3
    g.strokeText(ch, 16, 27); g.fillText(ch, 16, 27)
    const t = new THREE.CanvasTexture(c); t.magFilter = THREE.NearestFilter; return t
  }
  const TEX: Record<string, THREE.Texture> = { suspicious: markerTex('?', '#ffd23f'), search: markerTex('?', '#ff8c1a'), combat: markerTex('!', '#ff3030'), blinded: markerTex('*', '#ffffff'), ko: markerTex('z', '#9fb4ff') }

  let hooked: any = null
  const hook = () => {
    const serv = (window as any).localServer
    if (!serv?.blockmash?.darkmod || serv === hooked) return
    hooked = serv
    serv.on('blockmashDarkMod', (ev: any) => {
      const me = bot?.entity?.id
      if (ev.type === 'hud' && ev.player === me) hud = ev
      if (ev.sound) play(ev.sound, ev.player === me ? undefined : ev.at)
      if (ev.type === 'flash' && bot.entity.position.distanceTo(ev.at) < 14) { flash.style.transition = 'none'; flash.style.opacity = '0.9'; requestAnimationFrame(() => { flash.style.transition = 'opacity 1.4s'; flash.style.opacity = '0' }) }
      if (ev.type === 'objective' && ev.player === me) { toast.textContent = ev.text; toast.style.display = 'block'; setTimeout(() => { toast.style.display = 'none' }, 5000) }
      if (ev.type === 'alert') {
        const group = viewer.entities.entities[ev.entity]
        let s = markers.get(ev.entity)
        if (ev.state === 'patrol') { if (s) { s.parent?.remove(s); markers.delete(ev.entity) } return }
        if (!group) return
        if (!s) { s = new THREE.Sprite(new THREE.SpriteMaterial({ transparent: true, depthTest: false })); s.scale.set(0.6, 0.6, 1); s.position.y = 2.5; group.add(s); markers.set(ev.entity, s) }
        s.material.map = TEX[ev.state] ?? TEX.suspicious; s.material.needsUpdate = true
      }
    })
  }

  let baseFov: number | null = null
  const loop = () => {
    requestAnimationFrame(loop)
    if (!bot?.entity) return
    hook()
    const held = bot.heldItem?.name
    const show = !!hud && (hud.quarter || (held && TOOL_ITEMS.has(held)))
    box.style.display = show ? 'flex' : 'none'
    if (show) {
      const frame = Math.max(0, Math.min(manifest.lightgem - 1, Math.round(hud.light * (manifest.lightgem - 1))))
      if (manifest.lightgem) { const src = `${BASE}/icons/lightgem_${String(frame).padStart(2, '0')}.png`; if (!gem.src.endsWith(src.slice(1))) gem.src = src }
      const parts = [`Loot ${hud.loot}`]
      if (hud.quarter) parts.push(`quarter ${hud.quarter.found}/${hud.quarter.total}`)
      if (held === 'music_disc_stal') parts.push(`broadheads ${hud.arrows.broadhead}`)
      if (held === 'music_disc_strad') parts.push(`water arrows ${hud.arrows.water}`)
      if (held === 'music_disc_ward') parts.push(`flashbombs ${hud.flashbombs}`)
      info.textContent = parts.join(' · ')
    }
    // spyglass zoom
    const cam = viewer.camera as THREE.PerspectiveCamera
    if (held === 'music_disc_wait') { baseFov ??= cam.fov; if (cam.fov !== 22) { cam.fov = 22; cam.updateProjectionMatrix() } } else if (baseFov !== null) { cam.fov = baseFov; cam.updateProjectionMatrix(); baseFov = null }
  }
  loop()
}
