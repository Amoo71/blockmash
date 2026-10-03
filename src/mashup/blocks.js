// Resolve 'name[prop=value,...]' strings to 1.14+ block state ids (cached)
'use strict'
module.exports = function makeResolver (mcData) {
  const cache = new Map()
  function decode (block, stateId) {
    const props = {}
    let data = stateId - block.minStateId
    const states = block.states || []
    for (let i = states.length - 1; i >= 0; i--) {
      const st = states[i]
      const idx = data % st.num_values
      data = Math.floor(data / st.num_values)
      props[st.name] = st.type === 'bool' ? String(idx === 0) : st.type === 'int' ? String((st.values ? +st.values[0] : 0) + idx) : st.values[idx]
    }
    return props
  }
  function encode (block, props) {
    const states = block.states || []
    let id = 0
    for (const st of states) {
      const val = props[st.name]
      let idx
      if (st.type === 'bool') idx = val === 'true' ? 0 : 1
      else if (st.type === 'int') idx = +val - (st.values ? +st.values[0] : 0)
      else idx = Math.max(0, st.values.indexOf(val))
      id = id * st.num_values + idx
    }
    return block.minStateId + id
  }
  return function S (spec) {
    if (typeof spec === 'number') return spec
    let id = cache.get(spec)
    if (id !== undefined) return id
    const m = /^([a-z_0-9]+)(?:\[(.*)\])?$/.exec(spec)
    const block = m && mcData.blocksByName[m[1]]
    if (!block) {
      console.warn('[blockmash] unknown block', spec)
      id = mcData.blocksByName.stone.defaultState
    } else if (!m[2]) {
      id = block.defaultState
    } else {
      const props = decode(block, block.defaultState)
      for (const kv of m[2].split(',')) { const [k, v] = kv.split('='); props[k] = v }
      id = encode(block, props)
    }
    cache.set(spec, id)
    return id
  }
}
