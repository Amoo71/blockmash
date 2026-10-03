// BlockMash phase 3: Duke Nukem 3D-style enemies, weapons, pickups and remote pipebombs (server side).
// Gameplay rules are re-implemented (behaviour modelled on the GPL Duke3D source: weapon set, pipebomb remote
// detonation, enemy roster of the shareware episode). Sprites/sounds come from the user's local shareware GRP.
'use strict'
const { Vec3 } = require('vec3')
const layout = require('./layout')
const { lotInfo, P } = require('./zones/duke')

const WEAPONS = {
  iron_horse_armor: { id: 'pistol', ammo: 'pistol', dmg: 6, range: 48, cooldown: 280, pellets: 1, spread: 0.01, sound: 'pistol', start: 48 },
  golden_horse_armor: { id: 'shotgun', ammo: 'shotgun', dmg: 4, range: 24, cooldown: 900, pellets: 7, spread: 0.07, sound: 'shotgun7', start: 10 },
  diamond_horse_armor: { id: 'chaingun', ammo: 'chaingun', dmg: 4, range: 40, cooldown: 110, pellets: 1, spread: 0.035, sound: 'chaingun', start: 50 },
  leather_horse_armor: { id: 'rpg', ammo: 'rpg', dmg: 0, range: 80, cooldown: 1100, rocket: true, sound: 'rpgfire', start: 5 },
  firework_star: { id: 'pipebomb' }
}
const AMMO_ITEM = 'nautilus_shell'
const MEDKIT = 'heart_of_the_sea'
const ATOMIC = 'nether_star'
const ENEMIES = {
  trooper: { hp: 30, speed: 2.6, range: 22, dmg: 2, cooldown: 1600, sound: 'lizspit', see: 'predrg', die: 'preddy', pain: 'predpn' },
  pigcop: { hp: 50, speed: 2.2, range: 12, dmg: 5, cooldown: 2200, sound: 'shotgun7', see: 'pigrg', die: 'pigdy', pain: 'pigpn' },
  octabrain: { hp: 40, speed: 2.0, range: 18, dmg: 4, cooldown: 2600, fly: true, sound: 'octaat1', see: 'octarg', die: 'octady', pain: 'octapn' },
  battlelord: { hp: 300, speed: 1.6, range: 26, dmg: 3, cooldown: 500, sound: 'chaingun', see: 'bos1rg', die: 'bos1dy', pain: 'bos1pn', boss: true }
}

module.exports = function installDuke (serv, bm) {
  const mcData = serv.mcData
  const Item = require('prismarine-item')(serv._server?.version ?? '1.14.4')
  const itemId = (n) => mcData.itemsByName[n].id
  const ITEM_BY_ID = Object.fromEntries(Object.keys(WEAPONS).map(n => [itemId(n), n]))
  const players = new Map() // player.id -> state
  const emit = (ev) => serv.emit('blockmashDuke', ev)
  const duke = bm.duke = { WEAPONS, ENEMIES, players, emit }

  const state = (pl) => {
    let s = players.get(pl.id)
    if (!s) { s = { ammo: { pistol: 0, shotgun: 0, chaingun: 0, rpg: 0 }, bombs: [], last: 0, yaw: 0, pitch: 0 }; players.set(pl.id, s) }
    return s
  }
  duke.state = state
  const hud = (pl) => emit({ type: 'hud', player: pl.id, ammo: { ...state(pl).ammo }, bombs: state(pl).bombs.length })

  // ---------- geometry helpers
  const solidAt = async (p) => {
    const t = await serv.overworld.getBlockType(p.floored())
    const b = mcData.blocks[t]
    return b && b.boundingBox === 'block' ? b : null
  }
  async function traceBlocks (from, dir, range) {
    for (let t = 0; t < range; t += 0.25) {
      const p = from.plus(dir.scaled(t))
      const b = await solidAt(p)
      if (b) return { t, p, block: b }
    }
    return { t: range }
  }
  function traceEntities (from, dir, maxT, exclude) {
    let best = null
    for (const e of Object.values(serv.entities)) {
      if (e === exclude || !e.position || e.type === 'object') continue
      if (e.type === 'player' && e === exclude) continue
      const h = e.size?.y ?? 1.8
      const c = e.position.offset(0, h / 2, 0)
      const rel = c.minus(from)
      const t = rel.dot(dir)
      if (t < 0 || t > maxT) continue
      const closest = from.plus(dir.scaled(t))
      const dxz = Math.hypot(closest.x - c.x, closest.z - c.z)
      if (dxz < Math.max(0.5, (e.size?.x ?? 0.6) * 0.7) && Math.abs(closest.y - c.y) < h / 2 + 0.1) {
        if (!best || t < best.t) best = { t, e }
      }
    }
    return best
  }
  duke.lineOfSight = async (a, b) => {
    const d = b.minus(a); const len = d.norm(); const dir = d.scaled(1 / len)
    for (let t = 1; t < len - 0.5; t += 0.5) if (await solidAt(a.plus(dir.scaled(t)))) return false
    return true
  }
  const dirFrom = (yawDeg, pitchDeg) => {
    const y = yawDeg * Math.PI / 180; const p = pitchDeg * Math.PI / 180
    return new Vec3(-Math.sin(y) * Math.cos(p), -Math.sin(p), Math.cos(y) * Math.cos(p))
  }
  const GLASS = /glass/

  // ---------- player weapons
  async function fire (pl, itemName) {
    const w = WEAPONS[itemName]; const s = state(pl)
    const now = Date.now()
    if (w.id === 'pipebomb') return pipebomb(pl, s)
    if (now - s.last < w.cooldown) return
    if (pl.gameMode !== 1 && s.ammo[w.ammo] <= 0) { emit({ type: 'sound', sound: 'clipout', at: pl.position, player: pl.id }); return }
    s.last = now
    if (pl.gameMode !== 1) s.ammo[w.ammo]--
    const eye = pl.position.offset(0, 1.62, 0)
    const dir = dirFrom(s.yaw, s.pitch)
    emit({ type: 'fire', weapon: w.id, player: pl.id, sound: w.sound, at: eye })
    if (w.rocket) { rocket(pl, eye.plus(dir.scaled(0.8)), dir); hud(pl); return }
    for (let i = 0; i < w.pellets; i++) {
      const d = dir.offset((Math.random() - 0.5) * w.spread * 2, (Math.random() - 0.5) * w.spread * 2, (Math.random() - 0.5) * w.spread * 2).normalize()
      const hitB = await traceBlocks(eye, d, w.range)
      const hitE = traceEntities(eye, d, hitB.t, pl)
      if (hitE) {
        const e = hitE.e
        if (e.type === 'player' && e.gameMode !== 0) continue
        e.takeDamage({ damage: w.dmg, velocity: d.scaled(2), sound: 'entity.generic.hurt' })
        emit({ type: 'hit', at: eye.plus(d.scaled(hitE.t)), entity: e.id })
      } else if (hitB.block) {
        emit({ type: 'impact', at: hitB.p })
        if (GLASS.test(hitB.block.name)) { serv.setBlock(serv.overworld, hitB.p.floored(), 0); emit({ type: 'sound', sound: 'glass', at: hitB.p }) }
      }
    }
    hud(pl)
  }

  function rocket (pl, pos, dir) {
    const speed = 28
    const id = Math.random().toString(36).slice(2)
    let p = pos.clone(); let travelled = 0
    const step = async () => {
      for (let i = 0; i < 4; i++) {
        const next = p.plus(dir.scaled(speed / 20 / 4))
        travelled += speed / 20 / 4
        const hitE = traceEntities(p, dir, speed / 20 / 4 + 0.3, pl)
        if (hitE || await solidAt(next) || travelled > 90) {
          emit({ type: 'rocketEnd', id })
          bm.explode(hitE ? hitE.e.position.offset(0, 1, 0) : p, 3, { source: 'rpg' })
          return
        }
        p = next
      }
      emit({ type: 'rocket', id, at: p, dir })
      setTimeout(step, 50)
    }
    step()
  }

  function pipebomb (pl, s) {
    const now = Date.now()
    if (now - s.last < 350) return
    s.last = now
    const held = pl.inventory.slots[36 + pl.heldItemSlot]
    // Duke rule: with bombs out, "fire" = remote detonate (sneak to throw another)
    if (s.bombs.length && !pl.crouching) {
      const bombs = s.bombs.splice(0)
      emit({ type: 'detonate', player: pl.id })
      bombs.forEach((b, i) => setTimeout(() => { serv.destroyEntity(b); bm.explode(b.position.offset(0, 0.3, 0), 4, { source: 'pipebomb' }) }, 120 + i * 90))
      hud(pl); return
    }
    if (!held || held.name !== 'firework_star') return
    if (pl.gameMode !== 1) { held.count--; pl.inventory.updateSlot(36 + pl.heldItemSlot, held.count > 0 ? held : null) }
    const dir = dirFrom(s.yaw, s.pitch)
    const obj = serv.spawnObject(mcData.entitiesByName.item.id, pl.world, pl.position.offset(0, 1.5, 0).plus(dir.scaled(0.6)), {
      velocity: dir.scaled(14).offset(0, 4, 0), itemId: itemId('firework_star'), itemCount: 1
    })
    obj.friction = new Vec3(8, 0, 8)
    obj.blockmashBomb = true
    s.bombs.push(obj)
    emit({ type: 'throw', player: pl.id, sound: 'pbombbnc', at: pl.position })
    hud(pl)
  }
  duke.fire = fire

  serv.on('newPlayer', (pl) => {
    const s = state(pl)
    const look = ({ yaw, pitch }) => { if (yaw !== undefined) { s.yaw = yaw; s.pitch = pitch } }
    pl._client.on('look', look)
    pl._client.on('position_look', look)
    pl._client.on('entity_action', ({ actionId }) => { if (actionId === 0) pl.crouching = true; if (actionId === 1) pl.crouching = false })
    const onUse = () => {
      const held = pl.inventory.slots[36 + pl.heldItemSlot]
      if (held && WEAPONS[held.name]) fire(pl, held.name).catch(e => console.warn('[duke]', e))
    }
    pl._client.on('use_item', onUse)
    pl._client.on('block_place', onUse)
    pl.on('spawned', () => {
      // ammo / health pickups are consumed instead of stored
      const collect = pl.collect
      pl.collect = (ent) => {
        const name = mcData.items[ent.itemId]?.name
        if (ent.blockmashBomb) return
        if (name === AMMO_ITEM || name === MEDKIT || name === ATOMIC) {
          ent._writeOthersNearby('collect', { collectedEntityId: ent.id, collectorEntityId: pl.id })
          ent.destroy()
          if (name === AMMO_ITEM) { s.ammo.pistol += 24; s.ammo.shotgun += 6; s.ammo.chaingun += 40; s.ammo.rpg += 2 }
          if (name === MEDKIT) pl.updateHealth(Math.min(20, pl.health + 10))
          if (name === ATOMIC) pl.updateHealth(20)
          emit({ type: 'pickup', player: pl.id, item: name, sound: name === AMMO_ITEM ? 'getitm19' : 'item15' })
          hud(pl); return
        }
        const w = WEAPONS[name]
        if (w && w.ammo) s.ammo[w.ammo] += w.start
        if (w) emit({ type: 'pickup', player: pl.id, item: name, sound: 'wpnsel21' })
        collect(ent)
        hud(pl)
      }
      hud(pl)
    })
  })

  // ---------- enemies
  duke.spawnEnemy = (kind, pos) => {
    const def = ENEMIES[kind]
    const m = bm.spawn('zombie', pos, { kind: 'enemy', health: def.hp, duke: kind })
    if (!m) return null
    m.health = def.hp
    if (def.fly) { m.gravity = new Vec3(0, 0, 0); m.position.y += 2 }
    if (def.boss) m.size = new Vec3(1.6, 3.2, 1.6)
    const info = bm.mobs.get(m.id)
    info.ai = enemyAi
    info.def = def
    info.los = false
    const takeDamage = m.takeDamage
    m.takeDamage = (o) => {
      takeDamage(o)
      if (m.health <= 0 && !info.dead) {
        info.dead = true
        emit({ type: 'sound', sound: def.die, at: m.position })
        emit({ type: 'death', entity: m.id, duke: kind })
        drop(m.position, def.boss ? 4 : 1)
        setTimeout(() => m._writeOthersNearby('entity_destroy', { entityIds: [m.id] }), 1500)
      } else if (Math.random() < 0.4) emit({ type: 'sound', sound: def.pain, at: m.position })
    }
    return m
  }

  function enemyAi (e, m, now) {
    const def = m.def
    const t = bm.nearestPlayer(e.position, 40)
    if (!t) { e.velocity.x = 0; e.velocity.z = 0; return }
    if (!m.losCheck || now - m.losCheck > 500) {
      m.losCheck = now
      duke.lineOfSight(e.position.offset(0, 1.5, 0), t.pl.position.offset(0, 1.5, 0)).then(v => {
        if (v && !m.alerted) { m.alerted = true; emit({ type: 'sound', sound: def.see, at: e.position }) }
        m.los = v
      }).catch(() => {})
    }
    if (!m.alerted) return
    if (def.fly) {
      const wantY = t.pl.position.y + 2.5
      e.velocity.y = Math.max(-2, Math.min(2, (wantY - e.position.y) * 1.5))
    }
    const keep = def.range * 0.5
    if (t.d > keep || !m.los) { bm.moveTowards(e, t.pl.position, def.speed); if (!def.fly && e.velocity.x === 0 && e.velocity.z === 0) e.velocity.y = 7 } else {
      e.velocity.x = 0; e.velocity.z = 0
      bm.moveTowards(e, t.pl.position, 0)
    }
    if (m.los && t.d < def.range && now > m.cooldown) {
      m.cooldown = now + def.cooldown * (0.8 + Math.random() * 0.4)
      emit({ type: 'enemyFire', entity: e.id, sound: def.sound, at: e.position })
      const miss = Math.min(0.75, t.d / (def.range * 1.6))
      if (Math.random() > miss && (t.pl.gameMode === 0 || t.pl.gameMode === 2)) {
        t.pl.takeDamage({ damage: def.dmg, velocity: t.pl.position.minus(e.position).normalize().scaled(1.5) })
      }
      if (def.boss && Math.random() < 0.25) {
        // Battlelord mortar
        const target = t.pl.position.clone()
        setTimeout(() => bm.explode(target, 2, { source: 'mortar', damage: 0.6 }), 1200)
      }
    }
  }

  function drop (pos, n) {
    for (let i = 0; i < n; i++) {
      const r = Math.random()
      const name = r < 0.45 ? AMMO_ITEM : r < 0.7 ? 'firework_star' : r < 0.85 ? MEDKIT : r < 0.93 ? 'golden_horse_armor' : 'diamond_horse_armor'
      serv.spawnObject(mcData.entitiesByName.item.id, serv.overworld, pos.offset(0, 0.5, 0), {
        velocity: new Vec3((Math.random() - 0.5) * 4, 5, (Math.random() - 0.5) * 4), itemId: itemId(name), itemCount: 1, pickupTime: 400, deathTime: 5 * 60 * 1000
      })
    }
  }
  duke.drop = drop

  // populate Duke city zones with enemies and pickups
  serv.on('blockmashPopulate', ({ rx, rz, type }) => {
    if (type !== 'duke') return
    const ox = rx * layout.REGION + 32; const oz = rz * layout.REGION + 32
    const G = layout.ZONE_G
    const at = (u, v, y = G + 1) => new Vec3(ox + u + 0.5, y, oz + v + 0.5)
    const rnd = (n) => Math.floor(Math.random() * n)
    // street enemies
    for (let i = 0; i < 10; i++) {
      const alongU = Math.random() < 0.5
      const lane = rnd(4) * P + 2 + rnd(4)
      const pos = rnd(120) + 4
      const kind = i < 5 ? 'trooper' : i < 8 ? 'pigcop' : 'octabrain'
      duke.spawnEnemy(kind, alongU ? at(pos, lane) : at(lane, pos))
    }
    // pickups on sidewalks and in plazas
    const ctx = { seed: serv.overworld.seed | 0, rx, rz }
    const items = ['iron_horse_armor', AMMO_ITEM, 'firework_star', 'firework_star', MEDKIT, 'golden_horse_armor', AMMO_ITEM, 'leather_horse_armor', 'diamond_horse_armor', ATOMIC]
    let k = 0; let bossDone = false
    for (let li = 0; li < 4; li++) {
      for (let lj = 0; lj < 4; lj++) {
        const L = lotInfo(li, lj, ctx)
        const u = li * P + 8; const v = lj * P + 9
        const name = items[k++ % items.length]
        serv.spawnObject(mcData.entitiesByName.item.id, serv.overworld, at(u, v, G + 2), { velocity: new Vec3(0, 0, 0), itemId: itemId(name), itemCount: 1, pickupTime: 300 })
        if (L.type === 'plaza' && !bossDone && Math.random() < 0.7) { bossDone = true; duke.spawnEnemy('battlelord', at(li * P + 20, lj * P + 20)) }
        if (L.type === 'tower' && Math.random() < 0.5) duke.spawnEnemy('trooper', at(li * P + 15, lj * P + 15, G + 1 + 4 * (1 + rnd(Math.max(1, L.floors - 1)))))
      }
    }
  })

  serv.commands.add({
    base: 'duke',
    info: 'Duke kit: /duke give | /duke spawn <trooper|pigcop|octabrain|battlelord>',
    usage: '/duke give|spawn <kind>',
    onlyPlayer: true,
    parse: (s) => s.trim().split(/\s+/),
    action ([sub, kind], ctx) {
      const pl = ctx.player
      if (sub === 'give') {
        const s = state(pl)
        const give = (n, c) => { const slot = pl.inventory.firstEmptyInventorySlot(); if (slot) pl.inventory.updateSlot(slot, new Item(itemId(n), c)) }
        for (const n of ['iron_horse_armor', 'golden_horse_armor', 'diamond_horse_armor', 'leather_horse_armor']) give(n, 1)
        give('firework_star', 16)
        s.ammo = { pistol: 200, shotgun: 50, chaingun: 400, rpg: 20 }
        hud(pl)
        return 'Come get some!'
      }
      if (sub === 'spawn') {
        const s = state(pl)
        const d = dirFrom(s.yaw, 0)
        duke.spawnEnemy(ENEMIES[kind] ? kind : 'trooper', pl.position.plus(d.scaled(8)).offset(0, 0.5, 0))
        return 'spawned ' + (kind || 'trooper')
      }
      return 'usage: /duke give | /duke spawn <kind>'
    }
  })
  return duke
}
