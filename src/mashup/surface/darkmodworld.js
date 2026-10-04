// BlockMash: real The Dark Mod building prefabs (tdm_prefabs01.pk4, converted by tools/darkmod/fetch_prefabs.py)
// placed on the lots of the Dark Mod quarter. Shared by the world generator (barrier collision voxels),
// the server (loot/guards) and the client renderer.
// Data: globalThis.blockmashDarkmodPrefabs = mesh.json, preloaded by index.ts.
'use strict'
const HOUSES = ['house_01', 'house_02', 'house_03', 'house_04', 'house_06', 'house_07', 'house_08', 'house_09']
const TOWERS = ['tower_round_brick', 'tower_octagonal_blocks']
const MANOR = 'house_10'
let cache = null

function getPrefabs () {
  const meta = globalThis.blockmashDarkmodPrefabs
  if (!meta?.prefabs?.length) return null
  if (cache?.meta === meta) return cache
  const byName = new Map(meta.prefabs.map(p => [p.name, p]))
  const pick = (names, h) => { const l = names.filter(n => byName.has(n)); return l.length ? byName.get(l[h % l.length]) : null }
  /** lot footprint (integer blocks) of a prefab with rotation r (0..3, quarter turns) */
  const foot = (p, r) => { const sx = Math.ceil(p.size[0]); const sz = Math.ceil(p.size[2]); return r & 1 ? [sz, sx] : [sx, sz] }
  /** lot cell (bu, bv) -> prefab cell (x, z) */
  const toPrefab = (p, r, bu, bv) => {
    const sx = Math.ceil(p.size[0]); const sz = Math.ceil(p.size[2])
    if (r === 0) return [bu, bv]
    if (r === 1) return [bv, sz - 1 - bu]
    if (r === 2) return [sx - 1 - bu, sz - 1 - bv]
    return [sx - 1 - bv, bu]
  }
  /** solid y runs [y0, y1) (relative to the prefab base) of lot column (bu, bv) */
  const solid = (p, r, bu, bv) => { const [x, z] = toPrefab(p, r, bu, bv); return p.cols[`${x},${z}`] ?? null }
  cache = { meta, byName, foot, toPrefab, solid, house: h => pick(HOUSES, h), tower: h => pick(TOWERS, h), manor: () => byName.get(MANOR) ?? pick(HOUSES, 0) }
  return cache
}
module.exports = { getPrefabs }
