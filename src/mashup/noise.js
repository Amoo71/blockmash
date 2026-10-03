// Small, fast, seeded hash + value noise (own code, CC0/MIT with the project)
'use strict'
function hash3 (x, y, z, s) {
  let h = Math.imul(x | 0, 0x27d4eb2d) ^ Math.imul(y | 0, 0x165667b1) ^ Math.imul(z | 0, 0x9e3779b1) ^ Math.imul(s | 0, 0x85ebca6b)
  h = Math.imul(h ^ (h >>> 15), 0x2c1b3c6d)
  h = Math.imul(h ^ (h >>> 12), 0x297a2d39)
  return (h ^ (h >>> 15)) >>> 0
}
const hash2 = (x, z, s) => hash3(x, 0x5bd1, z, s)
const rnd2 = (x, z, s) => hash2(x, z, s) / 4294967296
const rnd3 = (x, y, z, s) => hash3(x, y, z, s) / 4294967296
const fade = t => t * t * (3 - 2 * t)
const lerp = (a, b, t) => a + (b - a) * t

function value2 (x, z, s) {
  const xi = Math.floor(x); const zi = Math.floor(z)
  const tx = fade(x - xi); const tz = fade(z - zi)
  const a = rnd2(xi, zi, s); const b = rnd2(xi + 1, zi, s)
  const c = rnd2(xi, zi + 1, s); const d = rnd2(xi + 1, zi + 1, s)
  return lerp(lerp(a, b, tx), lerp(c, d, tx), tz) * 2 - 1
}
function fbm2 (x, z, s, oct = 4) {
  let sum = 0; let amp = 1; let norm = 0
  for (let i = 0; i < oct; i++) {
    sum += value2(x, z, s + i * 1013) * amp
    norm += amp; amp *= 0.5; x *= 2; z *= 2
  }
  return sum / norm
}
function value3 (x, y, z, s) {
  const xi = Math.floor(x); const yi = Math.floor(y); const zi = Math.floor(z)
  const tx = fade(x - xi); const ty = fade(y - yi); const tz = fade(z - zi)
  const c = (i, j, k) => rnd3(xi + i, yi + j, zi + k, s)
  return lerp(
    lerp(lerp(c(0, 0, 0), c(1, 0, 0), tx), lerp(c(0, 1, 0), c(1, 1, 0), tx), ty),
    lerp(lerp(c(0, 0, 1), c(1, 0, 1), tx), lerp(c(0, 1, 1), c(1, 1, 1), tx), ty), tz) * 2 - 1
}
const smoothstep = t => t <= 0 ? 0 : t >= 1 ? 1 : t * t * (3 - 2 * t)
module.exports = { hash2, hash3, rnd2, rnd3, value2, fbm2, value3, smoothstep, lerp }
