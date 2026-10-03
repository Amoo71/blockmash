// BlockMash phase 5: Yorg kart racing on the race-track zones (server side).
// Driving physics, AI opponents, lap timing and Yorg car models live on the client
// (src/mashup/client/yorg.ts); the server provides the track geometry, commands, the kart key
// item (knowledge_book) and forwards right-clicks. Own code (MIT), inspired by Yorg (Ya2, GPLv3).
'use strict'
const layout = require('./layout')
const { A, R, HW } = require('./zones/yorg')

const CARS = ['kronos', 'themis', 'diones', 'iapeto', 'iperion', 'phoibe', 'rea', 'teia']

module.exports = function installYorg (serv, bm) {
  const mcData = serv.mcData
  const Item = require('prismarine-item')(mcData.version.minecraftVersion)
  const emit = (ev) => serv.emit('blockmashYorg', ev)
  const seed = () => serv.overworld.seed | 0
  const trackNear = (pos) => {
    const z = layout.findZone('yorg', seed(), pos.x, pos.z)
    if (!z) return null
    const cx = z.x - 96 + 32 + 63.5; const cz = z.z - 96 + 32 + 63.5
    return { cx, cz, G: layout.ZONE_G, A, R, HW, dist: Math.hypot(pos.x - cx, pos.z - cz) }
  }
  const yg = bm.yorg = { CARS, trackNear, emit }
  const give = (pl, name) => { const slot = pl.inventory.firstEmptyInventorySlot(); if (slot) pl.inventory.updateSlot(slot, new Item(mcData.itemsByName[name].id, 1)) }

  serv.on('newPlayer', (pl) => {
    const onUse = () => {
      const held = pl.inventory.slots[36 + pl.heldItemSlot]
      emit({ type: 'use', player: pl.id, key: held?.name === 'knowledge_book', sneak: !!pl.crouching })
    }
    pl._client.on('use_item', onUse)
    pl._client.on('block_place', (p) => { if (p.hand === 0 || p.hand === undefined) onUse() })
  })

  serv.commands.add({
    base: 'yorg',
    info: 'Yorg karts: /yorg give | /yorg drive [car] | /yorg race [laps] | /yorg stop | /yorg cars',
    usage: '/yorg give|drive [car]|race [laps]|stop|cars',
    onlyPlayer: true,
    parse: (s) => s.trim().split(/\s+/),
    action ([sub, arg], ctx) {
      const pl = ctx.player
      if (sub === 'give') { if (!pl.inventory.slots.some(i => i && i.name === 'knowledge_book')) give(pl, 'knowledge_book'); return 'Yorg kart key: right-click to get in/out, sneak+right-click to pick the next car.' }
      if (sub === 'cars') return 'Cars: ' + CARS.join(', ')
      if (sub === 'drive') {
        if (arg && !CARS.includes(arg)) return 'Unknown car. ' + 'Cars: ' + CARS.join(', ')
        emit({ type: 'drive', player: pl.id, car: arg || null }); return 'Engine on – W/S throttle, A/D steer, jump = handbrake, sneak = get out'
      }
      if (sub === 'stop') { emit({ type: 'stop', player: pl.id }); return 'Engine off' }
      if (sub === 'race') {
        const t = trackNear(pl.position)
        if (!t || t.dist > 150) return 'No race track nearby – /mashup tp yorg'
        const laps = Math.max(1, Math.min(10, parseInt(arg || '3', 10) || 3))
        emit({ type: 'race', player: pl.id, laps, track: t }); return `Race: ${laps} laps against 3 Yorg drivers`
      }
      return 'usage: /yorg give|drive [car]|race [laps]|stop|cars'
    }
  })
  return yg
}
