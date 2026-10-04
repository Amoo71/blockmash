// Play the placed Duke3D levels like Duke: Build-style player movement (walls, steps, slopes, ceilings, crouch
// through vents), doors / lifts / bridges that open on touch (Build sector lotags), and the nuke button that
// leads to the next level. The MC block layer under the floors stays for mining/explosions: over a hole the
// controller lets go and vanilla physics takes over (you fall into the Minecraft world below).
import { inHole } from './surfmat'
// eslint-disable-next-line @typescript-eslint/no-require-imports
const { makePhys, doorOpen, liftTarget, transports, explosives, STEP } = require('../surface/dukephys')

type Door = { si: number, kind: 'door' | 'lift', c0: number, c1: number, f0: number, f1: number, t: number, target: number, armed: boolean, onFor: number, bb: [number, number, number, number], barriersCleared?: boolean }

export function initDukePlay (dm: any, levels: any[]) {
  const bot = (globalThis as any).bot; const server = (globalThis as any).localServer
  // ---------------- moving sectors
  const doorsOf = new Map<any, Door[]>()
  const setupDoors = (d: any) => {
    let list = doorsOf.get(d); if (list) return list
    list = []
    const S = d.m.sectors; const W = d.m.walls
    S.forEach((s: any, si: number) => {
      const lt = s.lotag
      const nb = new Set<number>(); for (let i = s.wallptr; i < s.wallptr + s.wallnum; i++) if (W[i].ns >= 0) nb.add(W[i].ns)
      let a = Infinity; let b = Infinity; let c = -Infinity; let e = -Infinity
      for (let i = s.wallptr; i < s.wallptr + s.wallnum; i++) { const p = d.toWorld(W[i].x, W[i].y); a = Math.min(a, p.x); c = Math.max(c, p.x); b = Math.min(b, p.z); e = Math.max(e, p.z) }
      const bb: [number, number, number, number] = [a, b, c, e]
      const o = doorOpen(d.m, si)
      if (o) { list!.push({ si, kind: 'door', c0: s.cz, c1: o.c1, f0: s.fz, f1: o.f1, t: 0, target: 0, armed: true, onFor: 0, bb }); return }
      const lf = liftTarget(d.m, si)
      if (lf) list!.push({ si, kind: 'lift', c0: s.cz, c1: lf.moveC ? s.cz + (lf.f1 - s.fz) : s.cz, f0: s.fz, f1: lf.f1, t: 0, target: 0, armed: true, onFor: 0, bb })
    })
    // C-9 explosive sectors (SE13): open when something blows up next to them
    for (const b of explosives(d)) {
      const s = S[b.si]
      list.push({ si: b.si, kind: 'boom' as any, c0: s.cz, c1: b.c1, f0: s.fz, f1: b.f1, t: 0, target: 0, armed: true, onFor: 0, bb: [b.x - 0.5, b.z - 0.5, b.x + 0.5, b.z + 0.5], bx: b.x, bz: b.z, by: b.y } as any)
    }
    doorsOf.set(d, list)
    return list
  }
  const clearBarriers = (d: any, D: Door) => {
    if (D.barriersCleared || !server?.overworld) return
    D.barriersCleared = true
    for (let x = Math.floor(D.bb[0]) - 1; x <= Math.ceil(D.bb[2]); x++) {
      for (let z = Math.floor(D.bb[1]) - 1; z <= Math.ceil(D.bb[3]); z++) {
        const c = d.col(x + 0.5, z + 0.5); if (!c || c.sect !== D.si || c.bar1 <= c.bar0) continue
        for (let y = c.bar0; y < c.bar1; y++) server.setBlock(server.overworld, new (bot.entity.position.constructor)(x, y, z), 0)
      }
    }
  }
  const animate = (d: any, dt: number, p: any, sect: number, onGround: boolean) => {
    const list = setupDoors(d); const S = d.m.sectors
    const L = levels.find(l => l.sub === d)
    for (const D of list) {
      const dx = Math.max(D.bb[0] - p.x, 0, p.x - D.bb[2]); const dz = Math.max(D.bb[1] - p.z, 0, p.z - D.bb[3])
      const near = Math.hypot(dx, dz) < 1.6
      if (D.kind === 'door') {
        if (near && D.target === 0) { D.target = 1; S[D.si].__open = true; clearBarriers(d, D) }
      } else if (D.kind === 'lift') {
        const on = sect === D.si && onGround
        D.onFor = on ? D.onFor + dt : 0
        if (!on) D.armed = true
        if (on && D.armed && D.onFor > 0.4 && D.t === D.target) { D.target = 1 - D.target; D.armed = false }
        // call the lift: standing next to it while it is at the other level brings it to you
        if (!on && near && D.t === D.target) {
          const fNow = d.zToY(S[D.si].fz); const want = Math.abs(d.zToY(D.f0) - p.y) < Math.abs(d.zToY(D.f1) - p.y) ? 0 : 1
          if (Math.abs(fNow - p.y) > 0.5 && want !== D.target) D.target = want
        }
      }
      if (D.t !== D.target) {
        const span = Math.max(Math.abs(D.c1 - D.c0), Math.abs(D.f1 - D.f0)) / 8192 || 1
        const k = dt * (D.kind === 'door' ? 5 : 3) / span
        D.t = D.target > D.t ? Math.min(D.target, D.t + k) : Math.max(D.target, D.t - k)
        S[D.si].cz = Math.round(D.c0 + (D.c1 - D.c0) * D.t); S[D.si].fz = Math.round(D.f0 + (D.f1 - D.f0) * D.t)
        L?.updateDyn?.(D.si)
      }
    }
  }
  server?.on?.('blockmashExplosion', ({ center, radius }: any) => {
    for (const [d, list] of doorsOf) for (const D of list as any[]) if (D.kind === 'boom' && D.target === 0 && Math.hypot(D.bx - center.x, D.bz - center.z, (D.by - center.y) * 0.5) < (radius ?? 3) + 2.5) { D.target = 1; d.m.sectors[D.si].__open = true; clearBarriers(d, D) }
  })
  ;(globalThis as any).blockmashDukeBoom = (all = false) => { // debug: blow every C-9 wall (or the nearest)
    for (const [d, list] of doorsOf) for (const D of list as any[]) if (D.kind === 'boom' && (all || Math.hypot(D.bx - st.x, D.bz - st.z) < 6)) { D.target = 1; d.m.sectors[D.si].__open = true; clearBarriers(d, D) }
  }
  const sound = (name: string, at: any) => { try { server?.emit('blockmashDuke', { type: 'sound', sound: name, at }) } catch {} }

  // ---------------- exits: the nuke button of each level
  const exits = new Map<any, Array<{ x: number, z: number, y: number }>>()
  const exitsOf = (d: any) => {
    let l = exits.get(d); if (l) return l
    l = d.m.sprites.filter((sp: any) => sp.pic === 142 && Math.abs(sp.x) < 1e6).map((sp: any) => { const w = d.toWorld(sp.x, sp.y); return { x: w.x, z: w.z, y: d.zToY(sp.z) } })
    exits.set(d, l!); return l!
  }
  let exitCooldown = 0; let teleUntil = 0

  // ---------------- Duke death: the server restarts the level; never the MC respawn (world spawn + death screen)
  const origRespawn = bot.respawn?.bind(bot)
  bot.respawn = () => { if (!(globalThis as any).blockmashDuke?.maps?.length) origRespawn?.() }
  const me = () => server?.players?.find((q: any) => q.username === bot.username) ?? server?.players?.[0]
  const hurt = (dmg: number, cause: string) => { const pl = me(); if (pl) server.blockmash?.duke?.hurt?.(pl, dmg, cause) }
  const HURT_FLOORS = new Set([200, 1082, 4240, 859]) // slime, plasma/lava, purple lava, hurt rail
  let autoCrouch = false; let peakY = -Infinity; let hazardT = 0; let air = 0

  // ---------------- player controller
  let act = false; let last: any = null
  const st = { x: 0, y: 0, z: 0, vx: 0, vy: 0, vz: 0, on: false }
  let lastT = performance.now()
  ;(globalThis as any).blockmashDukePlay = () => ({ act, st: { ...st }, doors: [...doorsOf.values()].flat().map(D => ({ si: D.si, kind: D.kind, t: D.t })) })
  bot.on('physicsTick', () => {
    const now = performance.now(); const dt = Math.min(0.1, (now - lastT) / 1000); lastT = now
    const e = bot.entity; if (!e) return
    const viewer = (globalThis as any).viewer
    const off = () => { act = false; (globalThis as any).blockmashDukeAct = false; if (viewer) viewer.playerHeight = 1.62 }
    if (bot.game?.gameMode === 'spectator' || (globalThis as any).blockmashYorg?.drive || (bot.game?.gameMode === 'creative' && bot.physics?.gravity === 0)) return off()
    // teleported / respawned since our last tick -> start again from the real position
    if (act && last && Math.hypot(e.position.x - last.x, e.position.y - last.y, e.position.z - last.z) > 2.5) act = false
    const src = act ? st : e.position
    const d = dm.mapAt(src.x, src.z); if (!d) return off()
    const P = makePhys(d)
    if (!act) {
      const g = P.ground(e.position.x, e.position.z, e.position.y, 0.3, STEP)
      if (!g || e.position.y < g.floor - 0.6 || (e.position.y < g.floor + 0.3 && inHole(e.position.x, g.floor, e.position.z, 0.25))) return off()
      peakY = -Infinity
      Object.assign(st, { x: e.position.x, y: Math.max(e.position.y, g.floor), z: e.position.z, vx: 0, vy: Math.max(0, e.velocity.y), vz: 0, on: false })
      act = true
    }
    ;(globalThis as any).blockmashDukeAct = true
    const c = bot.health > 0 ? bot.controlState : ({} as any)
    const f = (c.forward ? 1 : 0) - (c.back ? 1 : 0); const s = (c.right ? 1 : 0) - (c.left ? 1 : 0)
    // crouch: the sneak key, or automatically in vents / under low ceilings (no crouch button needed on phones)
    const gNow = P.ground(st.x, st.z, st.y, 0.3, STEP)
    if (autoCrouch && gNow && gNow.ceil - st.y >= 1.55) autoCrouch = false
    const crouch = !!c.sneak || autoCrouch; let h = crouch ? 0.9 : 1.5
    const speed = crouch ? (c.sneak ? 0.1 : 0.18) : c.sprint ? 0.34 : 0.25
    const yaw = Math.PI - e.yaw; const sn = Math.sin(yaw); const cs = Math.cos(yaw)
    let wx = -(s * cs + f * sn); let wz = f * cs - s * sn
    const wl = Math.hypot(wx, wz); if (wl > 0) { wx = wx / wl * speed; wz = wz / wl * speed }
    const acc = st.on ? 0.55 : 0.12
    st.vx += (wx - st.vx) * acc; st.vz += (wz - st.vz) * acc
    if (c.jump && st.on) { st.vy = 0.5; st.on = false } // Duke jumps ~1.7 blocks
    st.vy = (st.vy - 0.08) * 0.98
    let r = P.slide(st.x, st.z, st.y, st.vx, st.vz, 0.3, h, STEP)
    if (!crouch && st.on && Math.hypot(st.vx, st.vz) > 0.05 && Math.hypot(r.x - st.x, r.z - st.z) < Math.hypot(st.vx, st.vz) * 0.5) {
      const r2 = P.slide(st.x, st.z, st.y, st.vx, st.vz, 0.3, 0.9, STEP)
      if (Math.hypot(r2.x - st.x, r2.z - st.z) > Math.hypot(r.x - st.x, r.z - st.z) + 0.02) { r = r2; autoCrouch = true; h = 0.9 }
    }
    st.x = r.x; st.z = r.z
    const g = P.ground(st.x, st.z, st.y, 0.3, STEP)
    st.y += st.vy
    if (g) {
      const hole = inHole(st.x, g.floor, st.z, 0.25)
      if (!hole && st.y <= g.floor) { st.y = g.floor; st.vy = 0; st.on = true } else st.on = false
      if (st.y + h > g.ceil && g.ceil - h >= g.floor - 0.01) { st.y = Math.min(st.y, g.ceil - h); if (st.vy > 0) st.vy = 0 }
      animate(d, dt, st, g.sect, st.on)
      // falls: Duke shrugs off normal drops, long ones hurt, very long ones kill (not into SE7 drop shafts)
      if (!st.on) peakY = Math.max(peakY, st.y)
      else {
        const drop = peakY - st.y; peakY = -Infinity
        const shaft = transports(d).some((t: any) => t.from === g.sect)
        if (!shaft && drop > 9 && bot.health > 0) hurt(drop >= 18 ? 999 : Math.ceil((drop - 9) * 2), 'fall')
      }
      // slime / lava floors hurt while you stand in them; deep water (lotag 2) drowns you after ~15 s
      const sec = d.m.sectors[g.sect]
      if (st.on && HURT_FLOORS.has(sec.fpic) && st.y <= g.floor + 0.05) { hazardT += dt; if (hazardT > 0.5) { hazardT = 0; hurt(sec.fpic === 1082 || sec.fpic === 4240 ? 3 : 1, 'slime') } } else hazardT = 0
      if (sec.lotag === 2 && st.y + 1.4 < g.ceil) { air += dt; if (air > 15) { air = 14; hurt(2, 'drown') } } else air = 0
      // SE7 drop shafts: falling into one lands you in the paired sector (Duke's room-over-room trick)
      for (const t of now > teleUntil ? transports(d) : []) {
        if (t.from === g.sect && st.y < d.zToY(d.m.sectors[t.from].fz) + 1.2) {
          const nx = st.x + t.dx; const nz = st.z + t.dz; let ny = st.y + t.dy
          const g2 = P.ground(nx, nz, ny, 0.3, STEP); if (g2 && ny < g2.floor) ny = g2.floor
          // a real server teleport: the target is often outside the loaded chunks (mineflayer would freeze there)
          const pl = server?.players?.find((q: any) => q.username === bot.username) ?? server?.players?.[0]
          if (pl && server.blockmash?.teleport) server.blockmash.teleport(pl, new (e.position.constructor)(nx, ny + 0.05, nz))
          else bot.chat(`/tp ${nx.toFixed(2)} ${(ny + 0.05).toFixed(2)} ${nz.toFixed(2)}`)
          teleUntil = now + 1500; act = false; last = null; (globalThis as any).blockmashDukeAct = false
          return
        }
      }
      // nuke button -> next level
      if (now > exitCooldown) {
        for (const x of exitsOf(d)) {
          if (Math.hypot(x.x - st.x, x.z - st.z) < 1.4 && Math.abs(x.y - (st.y + 1)) < 2.5) {
            exitCooldown = now + 5000
            const i = dm.maps.indexOf(d)
            const next = i + 2 > dm.maps.length ? 1 : i + 2
            sound('groovy02', st)
            bot.chat(`/mashup tp duke ${next}`)
            break
          }
        }
      }
    }
    // eye height inside the Duke body (1.5 standing / 0.9 crouched; the viewer subtracts 0.3 itself while sneaking)
    if (viewer) viewer.playerHeight = autoCrouch && !c.sneak ? 0.75 : c.sneak ? 1.05 : 1.35
    e.position.set(st.x, st.y, st.z); e.velocity.set(st.vx, st.vy, st.vz); e.onGround = st.on
    last = { x: st.x, y: st.y, z: st.z }
  })
}
