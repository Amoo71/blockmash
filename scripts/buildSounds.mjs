//@ts-check
// BlockMash: CC0 sound set (Kenney.nl) mapped onto the game's sound event names.
// Replaces upstream's sounds.js, which streamed the original Mojang sound files.
// Output: dist/sounds.js + dist/sounds/minecraft/sounds/<group>/<file>.ogg
import fs from 'fs'
import path from 'path'
import Module from 'node:module'
const require = Module.createRequire(import.meta.url)
const mcData = require('minecraft-data')('1.14.4')

const SRC = 'assets-src/sounds' // committed CC0 files (copied from .cache/kenney by tools/free-assets/fetch_sounds.sh)
const OUT = 'dist/sounds/minecraft/sounds'

/** [regex on event name, file group, volume] - first match wins */
const rules = [
  [/^ui\.button\.click$/, 'ui/click', 0.5],
  [/^block\.(glass|ice)\.(break)$/, 'glass/break', 1],
  [/^block\.(glass|ice)\./, 'glass/hit', 0.6],
  [/^block\.(wood|ladder|scaffolding|bamboo)\.(step|fall)$/, 'step/wood', 0.4],
  [/^block\.(grass|crop|sweet_berry_bush|bamboo_sapling|wet_grass|lily_pad)\.(step|fall)$/, 'step/grass', 0.4],
  [/^block\.(wool|snow|honey)\.(step|fall)$/, 'step/snow', 0.4],
  [/^block\.(sand|gravel)\.(step|fall)$/, 'step/snow', 0.45],
  [/^block\..+\.(step|fall)$/, 'step/stone', 0.4],
  [/^block\.(wood|ladder|scaffolding|bamboo)\.(break|place|hit)$/, 'dig/wood', 0.8],
  [/^block\.(grass|crop|wet_grass|sweet_berry_bush|lily_pad|wool|snow|sand|gravel|slime_block|honey_block)\.(break|place|hit)$/, 'dig/soft', 0.8],
  [/^block\.(metal|anvil|lantern|chain|iron|bell)\.(break|place|hit|land)$/, 'dig/metal', 0.7],
  [/^block\..+\.(break|place|hit)$/, 'dig/stone', 0.8],
  [/door\.open$|trapdoor\.open$|fence_gate\.open$|chest\.open$|barrel\.open$|shulker_box\.open$/, 'door/open', 0.7],
  [/door\.close$|trapdoor\.close$|fence_gate\.close$|chest\.close$|barrel\.close$|shulker_box\.close$/, 'door/close', 0.7],
  [/^(entity\.generic\.explode|entity\.dragon_fireball\.explode)$/, 'boom/explode', 1],
  [/^entity\.(tnt|creeper)\.primed$/, 'boom/fuse', 0.8],
  [/^entity\.player\.levelup$/, 'ui/levelup', 0.6],
  [/^entity\.experience_orb\.pickup$/, 'ui/tick', 0.4],
  [/^entity\.item\.pickup$/, 'ui/pluck', 0.4],
  [/^entity\.(arrow|snowball|egg|ender_pearl|trident)\.(shoot|throw)$|^item\.crossbow\.shoot$/, 'combat/shoot', 0.6],
  [/^entity\.(player|generic)\.(attack\.(strong|sweep|crit|knockback)|hurt)$/, 'combat/hit', 0.7],
  [/^entity\.[a-z_]+\.hurt$/, 'combat/hit', 0.6],
  [/^entity\.[a-z_]+\.death$/, 'combat/death', 0.6],
  [/^entity\.player\.attack\./, 'combat/swing', 0.4],
  [/^entity\.generic\.eat$|^entity\.player\.burp$/, 'misc/eat', 0.5],
  [/^item\.armor\.equip/, 'misc/equip', 0.5],
  [/^entity\.(player|generic)\.splash|^ambient\.underwater\.enter$/, 'misc/splash', 0.5],
]

const groups = fs.readdirSync(SRC, { recursive: true }).map(String).filter(f => f.endsWith('.ogg'))
const byGroup = {}
for (const f of groups) {
  const g = path.dirname(f).split(path.sep).join('/') + '/' + path.basename(f).replace(/_?\d*\.ogg$/, '')
  ;(byGroup[path.dirname(f).split(path.sep).join('/')] ??= []).push(f.replace(/\.ogg$/, '').split(path.sep).join('/'))
}

const map = {}
let n = 0
for (const s of mcData.soundsArray) {
  for (const [re, group, vol] of rules) {
    if (!re.test(s.name)) continue
    const files = byGroup[group]
    if (!files?.length) break
    // deterministic pick per event so the same block always sounds the same
    let h = 0
    for (const c of s.name) h = (h * 31 + c.charCodeAt(0)) >>> 0
    map[`${s.id};${s.name}`] = `${vol};${files[h % files.length]}`
    n++
    break
  }
}

fs.mkdirSync(OUT, { recursive: true })
fs.cpSync(SRC, OUT, { recursive: true })
const js = `window.allSoundsMap = ${JSON.stringify({ '1.14.4': map })};\nwindow.allSoundsVersionedMap = {};\nwindow.allSoundsMeta = { format: 'ogg', baseUrl: './sounds/' };\n`
fs.writeFileSync('dist/sounds.js', js)
console.log(`sounds: mapped ${n}/${mcData.soundsArray.length} events onto ${groups.length} CC0 files`)
