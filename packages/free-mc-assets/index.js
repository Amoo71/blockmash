// BlockMash: API-compatible replacement for the `minecraft-assets` package.
// Only one asset version is generated (FREE_VERSION); every other version name
// resolves to it. Contents are produced by tools/free-assets/build_free_assets.py.
const fs = require('fs')
const path = require('path')

const FREE_VERSION = '1.14.4'
const base = path.join(__dirname, 'minecraft-assets', 'data', FREE_VERSION)
let cached

function readJson (name, fallback) {
  try { return JSON.parse(fs.readFileSync(path.join(base, name), 'utf8')) } catch { return fallback }
}

function load () {
  if (cached) return cached
  const blocksArray = readJson('blocks_textures.json', [])
  const itemsArray = readJson('items_textures.json', [])
  const byName = arr => Object.fromEntries(arr.map(x => [x.name, x]))
  const blocks = byName(blocksArray)
  const items = byName(itemsArray)
  const findItemOrBlockByName = name => items[name] ?? blocks[name]
  const getTexture = name => findItemOrBlockByName(name)?.texture
  cached = {
    blocks,
    blocksArray,
    items,
    itemsArray,
    textureContent: {},
    textureContentArray: [],
    blocksStates: readJson('blocks_states.json', {}),
    blocksModels: readJson('blocks_models.json', {}),
    directory: base + '/',
    version: FREE_VERSION,
    findItemOrBlockByName,
    getTexture,
    getImageContent (name) {
      const texture = getTexture(name)
      if (texture == null) return null
      return 'data:image/png;base64,' + fs.readFileSync(path.join(base, texture + '.png'), 'base64')
    }
  }
  return cached
}

module.exports = function () { return load() }
module.exports.versions = [FREE_VERSION]
module.exports.FREE_VERSION = FREE_VERSION
