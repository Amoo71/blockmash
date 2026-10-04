// Places the locally extracted Duke3D E1L1 map into the nearest Duke zone of the world (per seed).
// Raw map JSON is fetched by the client before the integrated server starts (globalThis.blockmashDukeRaw).
'use strict'
const layout = require('../layout')
const { prepare } = require('./dukemap')

let cache = null
function getDuke (seed) {
  const raw = globalThis.blockmashDukeRaw
  if (!raw) return null
  if (cache && cache.seed === seed) return cache.dm
  const z = layout.findZone('duke', seed, 0, 0)
  if (!z) return null
  let x0 = Infinity; let x1 = -Infinity; let y0 = Infinity; let y1 = -Infinity
  for (const w of raw.walls) { x0 = Math.min(x0, w.x); x1 = Math.max(x1, w.x); y0 = Math.min(y0, w.y); y1 = Math.max(y1, w.y) }
  const ox = z.x - ((x0 + x1) / 2) / 512; const oz = z.z - ((y0 + y1) / 2) / 512
  const dm = prepare(raw, { ox, oz, G: layout.ZONE_G })
  dm.zone = z
  cache = { seed, dm }
  globalThis.blockmashDuke = dm
  return dm
}
module.exports = { getDuke }
