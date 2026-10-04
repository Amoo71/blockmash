// BlockMash phase 4: The Dark Mod-style stealth in the medieval/steampunk quarters (server side).
// Guards with patrol / suspicious / combat / search / blinded / knocked-out states, a light gem
// (time of day, crouching, nearby lights), blackjack knock-outs, broadhead + water arrows (douse lights),
// flashbombs, lockpicks for the manor vault, loot with a per-quarter loot goal. Own code (MIT).
'use strict'
const { Vec3 } = require('vec3')
const layout = require('./layout')
const { cellInfo } = require('./zones/darkmod')

const TOOLS = { music_disc_mellohi: 'blackjack', music_disc_stal: 'broadhead', music_disc_strad: 'water', music_disc_ward: 'flashbomb', music_disc_11: 'lockpick', music_disc_wait: 'spyglass' }
const LOOT = { music_disc_13: 25, music_disc_cat: 100, music_disc_blocks: 150, music_disc_chirp: 200, music_disc_far: 300, music_disc_mall: 500 }
const LIGHTS = new Set(['lantern', 'campfire', 'torch', 'wall_torch', 'glowstone', 'sea_lantern', 'jack_o_lantern', 'redstone_lamp', 'fire'])

module.exports = function installDarkMod (serv, bm) {
  const mcData = serv.mcData
  const Item = require('prismarine-item')(mcData.version.minecraftVersion)
  const itemId = (n) => mcData.itemsByName[n].id
  const emit = (ev) => serv.emit('blockmashDarkMod', ev)
  const players = new Map()
  const quarters = new Map() // "rx,rz" -> { total, found }
  const dm = bm.darkmod = { TOOLS, LOOT, players, quarters }
  const st = (pl) => {
    let s = players.get(pl.id)
    if (!s) { s = { arrows: { broadhead: 0, water: 0 }, flashbombs: 0, loot: 0, light: 1, yaw: 0, pitch: 0, last: 0, kitGiven: new Set() }; players.set(pl.id, s) }
    return s
  }
  dm.state = st
  const isNight = () => { const t = (serv.time || 0) % 24000; return t > 12500 && t < 23500 }
  const dirFrom = (yawDeg, pitchDeg) => {
    const y = yawDeg * Math.PI / 180; const p = pitchDeg * Math.PI / 180
    return new Vec3(-Math.sin(y) * Math.cos(p), -Math.sin(p), Math.cos(y) * Math.cos(p))
  }
  const blockAt = async (p) => mcData.blocks[await serv.overworld.getBlockType(p.floored())]
  const hud = (pl) => {
    const s = st(pl); const q = s.quarter && quarters.get(s.quarter)
    emit({ type: 'hud', player: pl.id, light: s.light, arrows: { ...s.arrows }, flashbombs: s.flashbombs, loot: s.loot, quarter: q ? { found: q.found, total: q.total } : null })
  }
  const give = (pl, name, count = 1) => { const slot = pl.inventory.firstEmptyInventorySlot(); if (slot) pl.inventory.updateSlot(slot, new Item(itemId(name), count)) }
  const dropItem = (name, pos, extra = {}) => serv.spawnObject(mcData.entitiesByName.item.id, serv.overworld, pos, { velocity: new Vec3(0, 0, 0), itemId: itemId(name), itemCount: 1, pickupTime: 300, ...extra })

  // ---------- light gem
  async function lightLevel (pl) {
    let l = isNight() ? 0.2 : 0.85
    const p = pl.position.floored()
    let near = 99
    for (let dx = -4; dx <= 4; dx++) for (let dy = -2; dy <= 3; dy++) for (let dz = -4; dz <= 4; dz++) {
      const b = await blockAt(p.offset(dx, dy, dz))
      if (b && LIGHTS.has(b.name)) {
        if (b.name === 'campfire') { const lit = (await serv.overworld.getBlockStateId(p.offset(dx, dy, dz)) - b.minStateId) % 8 < 4; if (!lit) continue }
        near = Math.min(near, Math.hypot(dx, dy, dz))
      }
    }
    if (near < 99) l += Math.max(0, 0.6 - near * 0.12)
    // roofs/indoors darken
    let roof = false
    for (let y = 2; y < 12 && !roof; y++) { const b = await blockAt(p.offset(0, y, 0)); if (b && b.boundingBox === 'block') roof = true }
    if (roof) l -= 0.25
    if (pl.crouching) l -= 0.15
    return Math.max(0, Math.min(1, l))
  }

  // ---------- guards
  dm.spawnGuard = (pos, route, archer = false) => {
    const m = bm.spawn(archer ? 'pillager' : 'vindicator', pos, { kind: 'enemy', health: 24, dark: archer ? 'archer' : 'guard' })
    if (!m) return null
    const info = bm.mobs.get(m.id)
    Object.assign(info, { ai: guardAi, route, wp: 0, alert: 0, state: 'patrol', since: Date.now() })
    const takeDamage = m.takeDamage
    m.takeDamage = (o) => {
      if (info.state === 'ko') return
      takeDamage(o)
      if (m.health <= 0) { info.state = 'dead'; emit({ type: 'sound', sound: 'vo_die', at: m.position }); return }
      emit({ type: 'sound', sound: 'vo_pain', at: m.position })
      setState(info, m, 'combat')
    }
    return m
  }
  const setState = (info, e, s) => {
    if (info.state === s || info.state === 'ko' || info.state === 'dead') return
    info.state = s; info.since = Date.now()
    const vo = { suspicious: 'vo_huh', combat: 'vo_spotted', search: 'vo_suspicious', patrol: 'vo_lost', blinded: 'vo_blinded' }[s]
    if (vo) emit({ type: 'sound', sound: vo, at: e.position })
    emit({ type: 'alert', entity: e.id, state: s })
  }
  dm.knockOut = (e, info) => {
    info.state = 'ko'
    e.velocity.x = 0; e.velocity.z = 0
    emit({ type: 'sound', sound: 'bj_hit', at: e.position })
    emit({ type: 'sound', sound: 'vo_ko', at: e.position })
    emit({ type: 'alert', entity: e.id, state: 'ko' })
    e._writeOthersNearby('entity_status', { entityId: e.id, entityStatus: 3 })
    setTimeout(() => { e._writeOthersNearby('entity_destroy', { entityIds: [e.id] }); serv.destroyEntity(e); bm.mobs.delete(e.id) }, 1500)
    if (Math.random() < 0.5) dropItem(Math.random() < 0.6 ? 'music_disc_13' : 'music_disc_blocks', e.position.offset(0, 0.3, 0))
  }

  function guardAi (e, m, now) {
    if (m.state === 'ko' || m.state === 'dead') return
    if (m.state === 'blinded') { e.velocity.x = 0; e.velocity.z = 0; if (now - m.since > 6000) setState(m, e, 'search'); return }
    const t = bm.nearestPlayer(e.position, 40)
    // perception (async LOS cached)
    if (t && (!m.losCheck || now - m.losCheck > 400)) {
      m.losCheck = now
      bm.duke.lineOfSight(e.position.offset(0, 1.6, 0), t.pl.position.offset(0, 1.5, 0)).then(v => { m.los = v }).catch(() => {})
    }
    if (t) {
      const s = st(t.pl)
      const facing = new Vec3(-Math.sin(e.yaw * Math.PI / 128), 0, Math.cos(e.yaw * Math.PI / 128))
      const to = t.pl.position.minus(e.position); to.y = 0
      const inFov = to.norm() < 2 || facing.dot(to.normalize()) > 0.35
      const range = 2 + s.light * 20
      const seen = m.los && inFov && t.d < range
      if (seen) m.alert += (1.4 - t.d / range) * (s.light + 0.2) * 0.6
      else m.alert -= 0.04
      if (t.d < 1.6 && !pl0crouch(t.pl)) m.alert += 0.3 // bumping into a guard
      m.alert = Math.max(0, Math.min(3, m.alert))
      if (m.alert > 2 && m.state !== 'combat') setState(m, e, 'combat')
      else if (m.alert > 0.8 && m.state === 'patrol') setState(m, e, 'suspicious')
      if (m.state === 'combat') {
        m.lastSeen = seen ? t.pl.position.clone() : m.lastSeen
        if (!seen && now - (m.seenAt || 0) > 5000) { setState(m, e, 'search'); return }
        if (seen) m.seenAt = now
        if (m.dark === 'archer' && t.d > 5 && seen) {
          e.velocity.x = 0; e.velocity.z = 0; bm.moveTowards(e, t.pl.position, 0)
          if (now > (m.cooldown || 0)) {
            m.cooldown = now + 2200
            emit({ type: 'sound', sound: 'bow_fire', at: e.position })
            if (Math.random() < 0.6 && (t.pl.gameMode === 0 || t.pl.gameMode === 2)) t.pl.takeDamage({ damage: 3, velocity: to.normalize().scaled(1) })
          }
          return
        }
        bm.moveTowards(e, (m.lastSeen || t.pl.position), 3.2)
        if (e.velocity.x === 0 && e.velocity.z === 0) e.velocity.y = 7
        if (t.d < 1.9 && now > (m.cooldown || 0)) {
          m.cooldown = now + 1100
          emit({ type: 'sound', sound: Math.random() < 0.3 ? 'vo_melee' : 'bj_swing', at: e.position })
          if (t.pl.gameMode === 0 || t.pl.gameMode === 2) t.pl.takeDamage({ damage: 3, velocity: to.normalize().scaled(3) })
        }
        return
      }
      if (m.state === 'suspicious') {
        e.velocity.x = 0; e.velocity.z = 0
        bm.moveTowards(e, t.pl.position, 0)
        if (m.alert < 0.3 && now - m.since > 3000) setState(m, e, 'patrol')
        return
      }
    }
    if (m.state === 'search') {
      const target = m.lastSeen || m.route[m.wp]
      if (target && Math.hypot(target.x - e.position.x, target.z - e.position.z) > 1) bm.moveTowards(e, target, 1.8)
      else { e.velocity.x = 0; e.velocity.z = 0 }
      if (now - m.since > 9000) { m.lastSeen = null; setState(m, e, 'patrol') }
      return
    }
    // patrol
    const wp = m.route[m.wp]
    if (!wp) return
    if (Math.hypot(wp.x - e.position.x, wp.z - e.position.z) < 1) {
      if (!m.wait) m.wait = now + 1500 + Math.random() * 2500
      e.velocity.x = 0; e.velocity.z = 0
      if (now > m.wait) { m.wait = 0; m.wp = (m.wp + 1) % m.route.length; if (Math.random() < 0.15) emit({ type: 'sound', sound: Math.random() < 0.5 ? 'vo_idle' : 'vo_idle2', at: e.position }) }
    } else { bm.moveTowards(e, wp, 1.4); if (e.velocity.x === 0 && e.velocity.z === 0) e.velocity.y = 6 }
  }
  const pl0crouch = (pl) => !!pl.crouching

  // ---------- player tools
  async function useTool (pl, name, target) {
    const s = st(pl); const tool = TOOLS[name]; const now = Date.now()
    if (now - s.last < 600) return
    s.last = now
    const eye = pl.position.offset(0, 1.62, 0)
    const dir = dirFrom(s.yaw, s.pitch)
    if (tool === 'broadhead' || tool === 'water') {
      if (pl.gameMode !== 1 && s.arrows[tool] <= 0) return
      if (pl.gameMode !== 1) s.arrows[tool]--
      emit({ type: 'sound', sound: 'bow_fire', at: eye, player: pl.id })
      emit({ type: 'arrow', player: pl.id, kind: tool, from: eye, dir })
      let hitBlock = null; let tHit = 60
      for (let t = 0; t < 60; t += 0.25) {
        const p = eye.plus(dir.scaled(t)); const b = await blockAt(p)
        if (b && (b.boundingBox === 'block' || LIGHTS.has(b.name))) { hitBlock = { p: p.floored(), b }; tHit = t; break }
      }
      let hitE = null
      for (const e of Object.values(serv.entities)) {
        if (e === pl || !e.position || e.type === 'object') continue
        const c = e.position.offset(0, 0.9, 0); const tt = c.minus(eye).dot(dir)
        if (tt < 0 || tt > tHit) continue
        const cl = eye.plus(dir.scaled(tt))
        if (Math.hypot(cl.x - c.x, cl.z - c.z) < 0.55 && Math.abs(cl.y - c.y) < 1.0 && (!hitE || tt < hitE.t)) hitE = { e, t: tt }
      }
      setTimeout(async () => {
        if (tool === 'broadhead') {
          if (hitE) { hitE.e.takeDamage({ damage: 9, velocity: dir.scaled(2) }); emit({ type: 'sound', sound: 'arrow_flesh', at: hitE.e.position }) } else if (hitBlock) emit({ type: 'sound', sound: 'arrow_wood', at: hitBlock.p })
        } else {
          const at = hitBlock ? hitBlock.p : eye.plus(dir.scaled(tHit)).floored()
          emit({ type: 'sound', sound: 'arrow_water', at })
          for (let dx = -1; dx <= 1; dx++) for (let dy = -1; dy <= 1; dy++) for (let dz = -1; dz <= 1; dz++) {
            const p = at.offset(dx, dy, dz); const b = await blockAt(p)
            if (!b || !LIGHTS.has(b.name)) continue
            if (b.name === 'campfire') serv.setBlock(serv.overworld, p, bm.S('campfire[lit=false]'))
            else if (b.name === 'lantern' || b.name === 'torch' || b.name === 'wall_torch' || b.name === 'fire') serv.setBlock(serv.overworld, p, 0)
            emit({ type: 'doused', at: p })
          }
        }
        hud(pl)
      }, Math.min(1200, (hitE ? hitE.t : tHit) / 40 * 1000))
      hud(pl); return
    }
    if (tool === 'flashbomb') {
      if (pl.gameMode !== 1 && s.flashbombs <= 0) return
      if (pl.gameMode !== 1) s.flashbombs--
      const obj = serv.spawnObject(mcData.entitiesByName.item.id, pl.world, eye.plus(dir.scaled(0.6)), { velocity: dir.scaled(12).offset(0, 3, 0), itemId: itemId('music_disc_ward'), itemCount: 1 })
      obj.blockmashBomb = true
      setTimeout(() => {
        const at = obj.position.clone(); serv.destroyEntity(obj)
        emit({ type: 'flash', at }); emit({ type: 'sound', sound: 'flashbomb', at })
        for (const [id, m] of bm.mobs) { const e = serv.entities[id]; if (e && m.dark && e.position.distanceTo(at) < 9) setState(m, e, 'blinded') }
      }, 1100)
      hud(pl); return
    }
    if (tool === 'lockpick' && target) {
      const b = await blockAt(target)
      if (b && (b.name === 'iron_bars' || b.name === 'iron_door')) {
        emit({ type: 'sound', sound: 'coins', at: target, player: pl.id })
        emit({ type: 'picking', player: pl.id })
        setTimeout(() => { serv.setBlock(serv.overworld, target, 0); emit({ type: 'sound', sound: 'loot', at: target }) }, 1800)
      }
    }
  }
  dm.useTool = useTool

  serv.on('newPlayer', (pl) => {
    const s = st(pl)
    const look = ({ yaw, pitch }) => { if (yaw !== undefined) { s.yaw = yaw; s.pitch = pitch } }
    pl._client.on('look', look); pl._client.on('position_look', look)
    const onUse = (pkt) => {
      const held = pl.inventory.slots[36 + pl.heldItemSlot]
      if (held && TOOLS[held.name]) useTool(pl, held.name, pkt?.location ? new Vec3(pkt.location.x, pkt.location.y, pkt.location.z) : null).catch(e => console.warn('[darkmod]', e))
    }
    pl._client.on('use_item', onUse); pl._client.on('block_place', onUse)
    pl._client.on('use_entity', ({ target, mouse }) => {
      if (mouse !== 1) return
      const held = pl.inventory.slots[36 + pl.heldItemSlot]
      const info = bm.mobs.get(target); const e = serv.entities[target]
      if (!e || !held || held.name !== 'music_disc_mellohi') return
      emit({ type: 'sound', sound: 'bj_swing', at: pl.position, player: pl.id })
      if (info?.dark && info.state !== 'combat' && info.state !== 'ko') dm.knockOut(e, info)
    })
    pl.on('spawned', () => {
      const collect = pl.collect
      pl.collect = (ent) => {
        const name = mcData.items[ent.itemId]?.name
        if (ent.blockmashBomb) return
        if (LOOT[name] || name === 'arrow' && ent.blockmashQuiver) {
          ent._writeOthersNearby('collect', { collectedEntityId: ent.id, collectorEntityId: pl.id })
          ent.destroy()
          s.loot += LOOT[name]
          if (ent.blockmashQuarter) { const q = quarters.get(ent.blockmashQuarter); if (q) { q.found += LOOT[name]; if (q.found >= q.total) emit({ type: 'objective', player: pl.id, text: 'Objective complete: all loot of this quarter stolen!' }) } }
          emit({ type: 'sound', sound: name === 'music_disc_13' ? 'coins' : 'loot', player: pl.id })
          hud(pl); return
        }
        const tool = TOOLS[name]
        if (tool === 'broadhead') s.arrows.broadhead += 12
        if (tool === 'water') s.arrows.water += 6
        if (tool === 'flashbomb') s.flashbombs += 3
        if (tool) emit({ type: 'sound', sound: 'loot', player: pl.id })
        // only one copy of each tool item in the inventory
        if (tool && pl.inventory.slots.some(i => i && i.name === name)) { ent._writeOthersNearby('collect', { collectedEntityId: ent.id, collectorEntityId: pl.id }); ent.destroy(); hud(pl); return }
        collect(ent)
        hud(pl)
      }
    })
  })

  // light gem + quarter tracking
  const iv = setInterval(async () => {
    for (const pl of serv.players) {
      const s = st(pl)
      const i = layout.columnInfo(Math.floor(pl.position.x), Math.floor(pl.position.z), serv.overworld.seed | 0)
      s.quarter = i.type === 'darkmod' ? `${i.rx},${i.rz}` : null
      try { s.light = await lightLevel(pl) } catch {}
      hud(pl)
    }
  }, 700)
  serv.cleanupFunctions?.push(() => clearInterval(iv))

  // ---------- populate quarters
  serv.on('blockmashPopulate', ({ rx, rz, type }) => {
    if (type !== 'darkmod') return
    const key = `${rx},${rz}`
    const ox = rx * layout.REGION + 32; const oz = rz * layout.REGION + 32
    const G = layout.ZONE_G
    const at = (u, v, y = G + 1) => new Vec3(ox + u + 0.5, y, oz + v + 0.5)
    const roadAz = (u) => 64 + 5 * Math.sin(u / 13); const roadBx = (v) => 64 + 5 * Math.sin(v / 11)
    // patrol routes along the lanes
    const routes = [
      [12, 30, 50, 78, 98, 116].map(u => at(u, roadAz(u))),
      [12, 30, 50, 78, 98, 116].map(v => at(roadBx(v), v)),
      [at(57, 57), at(71, 57), at(71, 71), at(57, 71)] // round the fountain plaza
    ]
    dm.spawnGuard(at(12, roadAz(12)), routes[0])
    dm.spawnGuard(at(116, roadAz(116)), [...routes[0]].reverse())
    dm.spawnGuard(at(roadBx(12), 12), routes[1])
    dm.spawnGuard(at(roadBx(116), 116), [...routes[1]].reverse(), true)
    dm.spawnGuard(at(57, 57), routes[2])
    // loot at the buildings
    const ctx = { seed: serv.overworld.seed | 0, rx, rz }
    const lootNames = Object.keys(LOOT)
    let total = 0
    const place = (name, pos) => { const o = dropItem(name, pos, { pickupTime: 300 }); o.blockmashQuarter = key; total += LOOT[name] }
    for (let ci = 0; ci < 6; ci++) for (let cj = 0; cj < 6; cj++) {
      const c = cellInfo(ci, cj, ctx)
      if (!c.ok) continue
      // the prefabs are solid facades: loot lies at the foot of the building, guards circle the manor
      const front = (k) => at(c.u0 + ((c.w * (k + 1) / 5) | 0), c.v0 - 1)
      if (c.type === 'manor') {
        for (let k = 0; k < 4; k++) place(lootNames[2 + k], front(k))
        const r = [at(c.u0 - 2, c.v0 - 2), at(c.u0 + c.w + 1, c.v0 - 2), at(c.u0 + c.w + 1, c.v0 + c.d + 1), at(c.u0 - 2, c.v0 + c.d + 1)]
        dm.spawnGuard(r[0], r)
      } else if (c.type === 'house') {
        place(lootNames[(ci + cj * 3) % 3], front(1))
      } else place('music_disc_13', front(2))
    }
    quarters.set(key, { total, found: 0 })
    // thief kit at the south gate
    const gate = at(roadBx(124), 124)
    for (const [k, n] of ['music_disc_mellohi', 'music_disc_stal', 'music_disc_strad', 'music_disc_ward', 'music_disc_11', 'music_disc_wait'].entries()) dropItem(n, gate.offset(k - 2.5, 0.5, 0), { pickupTime: 300 })
  })

  serv.commands.add({
    base: 'darkmod',
    info: 'Thief kit: /darkmod give | /darkmod guard | /darkmod loot',
    usage: '/darkmod give|guard|loot',
    onlyPlayer: true,
    parse: (s) => s.trim().split(/\s+/),
    action ([sub], ctx) {
      const pl = ctx.player; const s = st(pl)
      if (sub === 'give') {
        for (const n of Object.keys(TOOLS)) if (!pl.inventory.slots.some(i => i && i.name === n)) give(pl, n)
        s.arrows = { broadhead: 24, water: 12 }; s.flashbombs = 5; hud(pl)
        return 'You take the thief\'s tools.'
      }
      if (sub === 'guard') {
        const d = dirFrom(s.yaw, 0); const p = pl.position.plus(d.scaled(10)).offset(0, 0.5, 0)
        dm.spawnGuard(p, [p.clone(), p.plus(d.scaled(-6)), p.plus(new Vec3(d.z, 0, -d.x).scaled(6))])
        return 'guard spawned'
      }
      if (sub === 'loot') { const q = s.quarter && quarters.get(s.quarter); return `Loot ${s.loot}${q ? ` (quarter ${q.found}/${q.total})` : ''}` }
      return 'usage: /darkmod give|guard|loot'
    }
  })
  return dm
}
