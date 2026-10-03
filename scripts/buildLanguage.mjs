//@ts-check
// BlockMash: build our own language table (no Mojang en_us). Own strings from src/lang +
// object names derived from minecraft-data displayName fields (MIT, PrismarineJS).
import fs from 'fs'
import Module from 'node:module'
const require = Module.createRequire(import.meta.url)
const mcData = require('minecraft-data')('1.14.4')
const own = JSON.parse(fs.readFileSync('src/lang/blockmash-en.json', 'utf8'))
delete own._comment
const out = {}
for (const b of mcData.blocksArray) out[`block.minecraft.${b.name}`] = b.displayName
for (const i of mcData.itemsArray) out[`item.minecraft.${i.name}`] ??= i.displayName
for (const e of mcData.entitiesArray) out[`entity.minecraft.${e.name}`] = e.displayName
for (const e of mcData.effectsArray ?? []) out[`effect.minecraft.${e.name.replace(/([a-z])([A-Z])/g, '$1_$2').toLowerCase()}`] = e.displayName
for (const e of mcData.enchantmentsArray ?? []) out[`enchantment.minecraft.${e.name}`] = e.displayName
Object.assign(out, own)
fs.mkdirSync('generated', { recursive: true })
fs.writeFileSync('generated/language.json', JSON.stringify(out))
console.log('language entries', Object.keys(out).length)
