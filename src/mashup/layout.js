// World layout: regions, zone types, natural terrain height. Pure functions shared by generator + server plugin.
'use strict'
const { hash2, fbm2, smoothstep, lerp } = require('./noise')

const REGION = 192
const WATER = 62
const ZONE_G = 66
const ZONES = ['vanilla', 'village', 'duke', 'darkmod', 'yorg']
// fixed zones around spawn so everything is reachable quickly
const FIXED = { '0,0': 'village', '1,0': 'duke', '-1,0': 'darkmod', '0,1': 'yorg', '0,-1': 'vanilla', '1,1': 'vanilla', '-1,1': 'village' }

function zoneType (rx, rz, seed) {
  const f = FIXED[rx + ',' + rz]
  if (f) return f
  const h = hash2(rx, rz, seed ^ 0x2017) % 100
  if (h < 40) return 'vanilla'
  if (h < 55) return 'village'
  if (h < 70) return 'duke'
  if (h < 85) return 'darkmod'
  return 'yorg'
}

function naturalHeight (x, z, seed) {
  let h = 66 + fbm2(x / 160, z / 160, seed, 4) * 22 + fbm2(x / 40, z / 40, seed + 7, 2) * 4
  const m = fbm2(x / 320, z / 320, seed + 99, 3)
  if (m > 0.2) h += (m - 0.2) * 110
  return h
}

function biomeAt (x, z, seed, h) {
  if (h < WATER - 1) return 'ocean'
  if (h < WATER + 2) return 'beach'
  const t = fbm2(x / 420, z / 420, seed + 500, 2)
  if (h > 100 || t < -0.3) return 'snowy'
  if (t > 0.3) return 'desert'
  const hum = fbm2(x / 300, z / 300, seed + 900, 2)
  return hum > 0.05 ? 'forest' : 'plains'
}

// core rectangle of a region (local coords)
function coreOf (type) {
  if (type === 'village') return { c0: 64, c1: 128, blend: 28 }
  if (type === 'vanilla') return null
  return { c0: 32, c1: 160, blend: 28 }
}

const groundCache = new Map()
function zoneGround (rx, rz, type, seed) {
  if (type !== 'village') return ZONE_G
  const k = rx + ',' + rz
  if (!groundCache.has(k)) {
    const h = naturalHeight(rx * REGION + 96, rz * REGION + 96, seed)
    groundCache.set(k, Math.round(Math.max(WATER + 2, Math.min(88, h))))
  }
  return groundCache.get(k)
}

/** full info for a world column */
function columnInfo (x, z, seed) {
  const rx = Math.floor(x / REGION); const rz = Math.floor(z / REGION)
  const lx = x - rx * REGION; const lz = z - rz * REGION
  const type = zoneType(rx, rz, seed)
  const nat = naturalHeight(x, z, seed)
  const core = coreOf(type)
  let w = 0; let G = 0
  if (core) {
    G = zoneGround(rx, rz, type, seed)
    const dx = Math.max(core.c0 - lx, 0, lx - (core.c1 - 1))
    const dz = Math.max(core.c0 - lz, 0, lz - (core.c1 - 1))
    w = smoothstep(1 - Math.hypot(dx, dz) / core.blend)
  }
  const h = Math.round(lerp(nat, G, w))
  const inCore = !!core && lx >= core.c0 && lx < core.c1 && lz >= core.c0 && lz < core.c1
  const biome = w > 0.5 ? (biomeAt(x, z, seed, h) === 'snowy' ? 'snowy' : 'plains') : biomeAt(x, z, seed, h)
  return { rx, rz, lx, lz, type, w, h, G, inCore, u: core ? lx - core.c0 : 0, v: core ? lz - core.c0 : 0, biome }
}

function regionCenter (rx, rz) { return { x: rx * REGION + 96, z: rz * REGION + 96 } }
function findZone (type, seed, fromX = 0, fromZ = 0) {
  const rx0 = Math.floor(fromX / REGION); const rz0 = Math.floor(fromZ / REGION)
  for (let r = 0; r < 12; r++) {
    for (let dx = -r; dx <= r; dx++) {
      for (let dz = -r; dz <= r; dz++) {
        if (Math.max(Math.abs(dx), Math.abs(dz)) !== r) continue
        if (zoneType(rx0 + dx, rz0 + dz, seed) === type) return { rx: rx0 + dx, rz: rz0 + dz, ...regionCenter(rx0 + dx, rz0 + dz) }
      }
    }
  }
  return null
}

module.exports = { REGION, WATER, ZONE_G, ZONES, zoneType, naturalHeight, biomeAt, columnInfo, zoneGround, regionCenter, findZone, coreOf }
