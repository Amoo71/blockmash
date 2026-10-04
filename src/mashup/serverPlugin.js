// BlockMash server-side gameplay for the integrated flying-squid server:
// spawn in the start village, simple mob population + AI (villagers, iron golems, animals, night monsters),
// TNT ignition + explosions (break blocks, chain reactions, damage, knockback), /mashup command.
'use strict'
const { Vec3 } = require('vec3')
const layout = require('./layout')
const makeResolver = require('./blocks')
const { getDuke } = require('./surface/dukeworld')

const TP = {
  village: (c) => ({ x: c.x - 96 + 64 + 38, z: c.z - 96 + 64 + 32 }),
  duke: (c) => ({ x: c.x - 96 + 32 + 68, z: c.z - 96 + 32 + 64 }),
  darkmod: (c) => ({ x: c.x - 96 + 32 + 64, z: c.z - 96 + 32 + 75 }),
  yorg: (c) => ({ x: c.x - 96 + 32 + 50, z: c.z - 96 + 32 + 98 }),
  vanilla: (c) => ({ x: c.x, z: c.z })
}

module.exports = function installBlockMash (serv) {
  const mcData = serv.mcData
  const S = makeResolver(mcData)
  const seed = () => serv.overworld.seed | 0
  const E = (n) => mcData.entitiesByName[n]?.id
  const mobs = new Map() // id -> { kind, ai, home, target, ... }
  const populated = new Set()
  const bm = serv.blockmash = { mobs, layout, S }

  const surfaceY = async (x, z) => {
    const info = layout.columnInfo(x, z, seed())
    let y = Math.max(info.h + 1, 2)
    for (let i = 0; i < 24; i++) {
      const a = await serv.overworld.getBlockStateId(new Vec3(x, y, z))
      const b = await serv.overworld.getBlockStateId(new Vec3(x, y + 1, z))
      if (a === 0 && b === 0) return y
      y++
    }
    return y
  }

  // ---- spawn point: the start village well
  const spawnFor = () => {
    const c = layout.regionCenter(0, 0)
    const p = TP.village(c)
    const G = layout.zoneGround(0, 0, 'village', seed())
    return new Vec3(p.x + 0.5, G + 1, p.z + 0.5)
  }
  serv.getSpawnPoint = async () => spawnFor()

  // teleport + make sure the new area's chunks get sent (flying-squid skips it while still streaming)
  bm.teleport = (pl, pos) => {
    pl.teleport(pos)
    const resend = () => { if (pl.sendingChunks) setTimeout(resend, 250); else pl.sendRestMap() }
    setTimeout(resend, 100)
  }

  // ---- mobs
  bm.spawn = (name, pos, opts = {}) => {
    const id = E(name)
    if (id === undefined) return null
    const m = serv.spawnMob(id, serv.overworld, pos.clone(), { yaw: Math.floor(Math.random() * 256) - 128 })
    m.health = opts.health ?? ({ iron_golem: 100, villager: 20, zombie: 20, skeleton: 20, creeper: 20, spider: 16 }[name] ?? 10)
    m.size = name === 'iron_golem' ? new Vec3(1.4, 2.7, 1.4) : m.size
    mobs.set(m.id, { name, kind: opts.kind || 'passive', home: pos.clone(), dir: null, next: 0, cooldown: 0, ...opts })
    return m
  }
  const HOSTILE = ['zombie', 'skeleton', 'creeper', 'spider']
  const ANIMALS = ['cow', 'sheep', 'pig', 'chicken']

  async function populate (player) {
    const p = player.position
    const rx0 = Math.floor(p.x / layout.REGION); const rz0 = Math.floor(p.z / layout.REGION)
    for (let dx = -1; dx <= 1; dx++) {
      for (let dz = -1; dz <= 1; dz++) {
        const rx = rx0 + dx; const rz = rz0 + dz
        const key = rx + ',' + rz
        if (populated.has(key)) continue
        const type = layout.zoneType(rx, rz, seed())
        const c = layout.regionCenter(rx, rz)
        if (Math.hypot(c.x - p.x, c.z - p.z) > 150) continue
        populated.add(key)
        if (type === 'village') {
          const G = layout.zoneGround(rx, rz, 'village', seed())
          const base = TP.village(c)
          const spots = [[0, 4], [-12, 0], [6, -10], [-6, 12], [10, 8]]
          for (const [ox, oz] of spots) bm.spawn('villager', new Vec3(base.x - 6 + ox + 0.5, G + 1, base.z + oz + 0.5), { kind: 'villager' })
          bm.spawn('iron_golem', new Vec3(base.x - 6 + 0.5, G + 1, base.z + 6 + 0.5), { kind: 'golem' })
          bm.spawn('cat', new Vec3(base.x - 2.5, G + 1, base.z - 3.5), { kind: 'passive' })
        } else if (type === 'vanilla') {
          for (let i = 0; i < 8; i++) {
            const x = Math.floor(c.x + (Math.random() - 0.5) * 120); const z = Math.floor(c.z + (Math.random() - 0.5) * 120)
            const info = layout.columnInfo(x, z, seed())
            if (info.h <= layout.WATER || info.biome === 'desert') continue
            const name = ANIMALS[Math.floor(Math.random() * ANIMALS.length)]
            for (let j = 0; j < 2; j++) bm.spawn(name, new Vec3(x + j + 0.5, await surfaceY(x + j, z), z + 0.5), { kind: 'passive' })
          }
        }
        serv.emit('blockmashPopulate', { rx, rz, type, center: c, player })
      }
    }
  }

  const isNight = () => { const t = (serv.time || 0) % 24000; return t > 13000 && t < 23000 }
  async function nightSpawns (player) {
    if (!isNight() || player.gameMode !== 0) return
    let near = 0
    for (const [id, m] of mobs) if (m.kind === 'hostile' && serv.entities[id] && serv.entities[id].position.distanceTo(player.position) < 64) near++
    if (near >= 8) return
    const a = Math.random() * Math.PI * 2; const r = 24 + Math.random() * 16
    const x = Math.floor(player.position.x + Math.cos(a) * r); const z = Math.floor(player.position.z + Math.sin(a) * r)
    const name = HOSTILE[Math.floor(Math.random() * HOSTILE.length)]
    bm.spawn(name, new Vec3(x + 0.5, await surfaceY(x, z), z + 0.5), { kind: 'hostile' })
  }

  const nearestPlayer = (pos, max) => {
    let best = null; let bd = max
    for (const pl of serv.players) {
      if (pl.gameMode !== 0 && pl.gameMode !== 2) continue
      const d = pl.position.distanceTo(pos)
      if (d < bd) { bd = d; best = pl }
    }
    return best && { pl: best, d: bd }
  }
  const moveTowards = (e, target, speed) => {
    const dx = target.x - e.position.x; const dz = target.z - e.position.z
    const len = Math.hypot(dx, dz) || 1
    e.velocity.x = dx / len * speed; e.velocity.z = dz / len * speed
    let b = Math.round(Math.atan2(-dx, dz) * 128 / Math.PI)
    if (b > 127) b -= 256
    if (b < -128) b += 256
    e.yaw = b
  }
  bm.moveTowards = moveTowards
  bm.nearestPlayer = nearestPlayer

  function aiTick () {
    const now = Date.now()
    for (const [id, m] of mobs) {
      const e = serv.entities[id]
      if (!e || e.health <= 0) { mobs.delete(id); continue }
      if (m.ai) { m.ai(e, m, now); continue }
      const stuck = e.velocity.x === 0 && e.velocity.z === 0 && m.moving
      if (stuck && e.onGround !== false) e.velocity.y = 7
      if (m.kind === 'hostile') {
        const t = nearestPlayer(e.position, 24)
        if (!t) { m.moving = false; continue }
        if (m.name === 'creeper') {
          if (t.d < 2.5) { m.fuse = m.fuse || now; if (now - m.fuse > 1500) { mobs.delete(id); serv.destroyEntity(e); bm.explode(e.position, 3); continue } } else m.fuse = 0
        }
        if (m.name === 'skeleton' && t.d < 14 && t.d > 4) {
          e.velocity.x = 0; e.velocity.z = 0
          if (now > m.cooldown) { m.cooldown = now + 2000; serv.playSound('entity.arrow.shoot', e.world, e.position); t.pl.takeDamage({ damage: 2, velocity: t.pl.position.minus(e.position).normalize().scaled(2) }) }
          continue
        }
        moveTowards(e, t.pl.position, m.name === 'spider' ? 4 : 3); m.moving = true
        if (t.d < 1.7 && now > m.cooldown && m.name !== 'creeper') { m.cooldown = now + 1000; t.pl.takeDamage({ damage: 3, velocity: t.pl.position.minus(e.position).normalize().scaled(3) }) }
        // burn in daylight
        if (!isNight() && (m.name === 'zombie' || m.name === 'skeleton') && Math.random() < 0.02) e.takeDamage({ damage: 4 })
      } else if (m.kind === 'golem') {
        let foe = null; let fd = 16
        for (const [oid, om] of mobs) {
          if (om.kind !== 'hostile' && om.kind !== 'enemy') continue
          const oe = serv.entities[oid]; if (!oe) continue
          const d = oe.position.distanceTo(e.position); if (d < fd) { fd = d; foe = oe }
        }
        if (foe) {
          moveTowards(e, foe.position, 2.5); m.moving = true
          if (fd < 2.5 && now > m.cooldown) { m.cooldown = now + 1200; foe.takeDamage({ damage: 10, velocity: new Vec3(0, 6, 0) }) }
        } else wander(e, m, now, 1.5, 12)
      } else {
        wander(e, m, now, m.kind === 'villager' ? 1.8 : 1.4, m.kind === 'villager' ? 14 : 24)
      }
    }
  }
  function wander (e, m, now, speed, radius) {
    if (now > m.next) {
      m.next = now + 2000 + Math.random() * 4000
      if (Math.random() < 0.4) { m.dir = null } else {
        const a = Math.random() * Math.PI * 2
        m.dir = { x: m.home.x + Math.cos(a) * radius * Math.random(), z: m.home.z + Math.sin(a) * radius * Math.random() }
      }
    }
    if (m.dir && Math.hypot(m.dir.x - e.position.x, m.dir.z - e.position.z) > 0.8) { moveTowards(e, m.dir, speed); m.moving = true } else m.moving = false
  }

  // ---- explosions
  const UNBREAKABLE = new Set(['bedrock', 'water', 'lava', 'air'])
  bm.explode = async (center, radius = 4, { source, damage = 1 } = {}) => {
    const world = serv.overworld
    serv.playSound('entity.generic.explode', world, center, { radius: 64 })
    const pid = mcData.particlesByName?.explosion_emitter?.id ?? mcData.particlesByName?.explosion?.id
    if (pid !== undefined) serv.emitParticle(pid, world, center, { count: 1, size: new Vec3(0, 0, 0) })
    const c = center.floored()
    const tnts = []
    const r2 = radius * radius
    for (let dx = -radius; dx <= radius; dx++) {
      for (let dy = -radius; dy <= radius; dy++) {
        for (let dz = -radius; dz <= radius; dz++) {
          const d2 = dx * dx + dy * dy + dz * dz
          if (d2 > r2 + (Math.random() - 0.5) * radius) continue
          const p = c.offset(dx, dy, dz)
          if (p.y < 1 || p.y > 255) continue
          const id = await world.getBlockStateId(p)
          if (!id) continue
          const b = mcData.blocks[await world.getBlockType(p)]
          if (!b || UNBREAKABLE.has(b.name)) continue
          if (b.name === 'tnt') { tnts.push(p); continue }
          if (b.name !== 'barrier' && (b.resistance ?? 0) > 1000) continue
          serv.setBlock(world, p, 0)
        }
      }
    }
    for (const p of tnts) { serv.setBlock(world, p, 0); bm.primeTnt(p, 400 + Math.random() * 600) }
    // damage entities + players
    const reach = radius * 2
    for (const e of Object.values(serv.entities)) {
      if (!e.position || e.world !== world) continue
      const d = e.position.distanceTo(center)
      if (d > reach) continue
      const f = 1 - d / reach
      const dmg = Math.round(f * f * 22 * damage) + 1
      const kb = e.position.minus(center).normalize().scaled(12 * f).offset(0, 6 * f, 0)
      if (e.type === 'player') { if (e.gameMode === 0 || e.gameMode === 2) e.takeDamage({ damage: dmg, velocity: kb, maxVelocity: new Vec3(20, 20, 20) }) } else if (e.takeDamage && e.type === 'mob') e.takeDamage({ damage: dmg, velocity: kb, maxVelocity: new Vec3(20, 20, 20) })
    }
    serv.emit('blockmashExplosion', { center, radius, source })
  }
  bm.primeTnt = (p, fuseMs = 4000) => {
    const id = E('tnt')
    let obj = null
    try { if (id !== undefined) obj = serv.spawnObject(id, serv.overworld, p.offset(0.5, 0, 0.5), { velocity: new Vec3(0, 3, 0) }) } catch {} // entity cap: still explode
    serv.playSound('entity.tnt.primed', serv.overworld, p)
    setTimeout(() => {
      if (obj) serv.destroyEntity(obj)
      bm.explode((obj ? obj.position : p).offset(0, 0.5, 0), 4)
    }, fuseMs)
  }

  serv.on('newPlayer', (player) => {
    player._client.on('block_place', async (packet) => {
      const held = player.inventory.slots[36 + player.heldItemSlot]
      if (!held || !packet.location) return
      const loc = new Vec3(packet.location.x, packet.location.y, packet.location.z)
      const b = mcData.blocks[await player.world.getBlockType(loc)]
      if (b?.name === 'tnt' && (held.name === 'flint_and_steel' || held.name === 'fire_charge')) {
        serv.setBlock(player.world, loc, 0)
        bm.primeTnt(loc)
      }
    })
    player.on('spawned', () => {
      player.chat('§6BlockMash§r – mine it, blow it up, build it. §7/mashup tp duke|darkmod|yorg|village, /mashup where')
    })
  })

  serv.commands.add({
    base: 'mashup',
    info: 'BlockMash zones: /mashup where | /mashup tp <village|duke|darkmod|yorg|vanilla> | /mashup boom',
    usage: '/mashup where|tp <zone>|boom',
    onlyPlayer: true,
    parse: (s) => s.trim().split(/\s+/),
    async action ([sub, arg], ctx) {
      const pl = ctx.player
      if (sub === 'where' || !sub) {
        const i = layout.columnInfo(Math.floor(pl.position.x), Math.floor(pl.position.z), seed())
        return `Zone: ${i.type} (region ${i.rx},${i.rz}), biome ${i.biome}`
      }
      if (sub === 'tp') {
        const z = layout.findZone(arg || 'duke', seed(), pl.position.x, pl.position.z)
        if (!z || !TP[arg || 'duke']) return 'No such zone nearby'
        const dm = getDuke(seed())
        if ((arg || 'duke') === 'duke' && dm) {
          bm.teleport(pl, new Vec3(dm.start.x, dm.start.y + 0.2, dm.start.z))
          return 'Teleported to Duke Nukem 3D E1L1 (Hollywood Holocaust)'
        }
        const p = TP[arg || 'duke'](z)
        const y = await surfaceY(p.x, p.z)
        bm.teleport(pl, new Vec3(p.x + 0.5, y, p.z + 0.5))
        return `Teleported to ${arg} at ${p.x} ${y} ${p.z}`
      }
      if (sub === 'boom') { bm.primeTnt(pl.position.floored().offset(3, 0, 0), 1500); return 'Boom in 1.5 s' }
      return 'Unknown subcommand'
    }
  })

  // polygon surface: holes (explosions/mining) clip the surface meshes on the client; mesh-to-voxel rims come back here
  bm.surfaceHoles = []
  bm.addHole = (x, y, z, r) => { bm.surfaceHoles.push({ x, y, z, r }); if (bm.surfaceHoles.length > 256) bm.surfaceHoles.shift(); serv.emit('blockmashHole', { x, y, z, r }) }
  serv.on('blockmashExplosion', ({ center, radius }) => bm.addHole(center.x, center.y, center.z, radius + 0.6))
  bm.surfaceVoxels = async (cells) => {
    const world = serv.overworld
    for (const [x, y, z, name] of cells) {
      const p = new Vec3(x, y, z)
      if ((await world.getBlockStateId(p)) === 0) serv.setBlock(world, p, S(name))
    }
  }

  require('./duke')(serv, bm)
  require('./darkmod')(serv, bm)
  require('./yorg')(serv, bm)

  const iv1 = setInterval(aiTick, 150)
  const iv2 = setInterval(() => { for (const pl of serv.players) { populate(pl).catch(() => {}); nightSpawns(pl).catch(() => {}) } }, 3000)
  serv.cleanupFunctions?.push(() => { clearInterval(iv1); clearInterval(iv2) })
  return bm
}
