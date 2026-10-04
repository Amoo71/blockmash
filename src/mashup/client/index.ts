// BlockMash client-side mashup features (singleplayer, integrated server)
import { initDuke } from './duke'
import { initDarkMod } from './darkmod'
import { initYorg } from './yorg'
import { initSurface } from './surface'
import { initAtmosphere } from './atmosphere'
import { initYorgTrack } from './yorgtrack'
import { initDarkmodPrefabs } from './dmprefabs'
// eslint-disable-next-line @typescript-eslint/no-require-imports
const ownNames: Record<string, string> = require('../../lang/blockmash-en.json')

// hotbar/tooltips read prismarine-item displayName from the registry: give mashup items their names
const patchNames = () => {
  for (const reg of [(globalThis as any).bot?.registry, (globalThis as any).loadedData]) {
    if (!reg?.itemsByName) continue
    for (const [k, v] of Object.entries(ownNames)) {
      const m = /^item\.minecraft\.(.+)$/.exec(k)
      const it = m && reg.itemsByName[m[1]]
      if (it) { it.displayName = v; if (reg.items?.[it.id]) reg.items[it.id].displayName = v }
    }
  }
}

let started = false
let namedBot: any = null
const tryStart = () => {
  if (globalThis.bot?.registry && globalThis.bot !== namedBot) { namedBot = globalThis.bot; patchNames() }
  if (started) return
  if (!globalThis.bot?.entity || !globalThis.viewer?.entities || !(globalThis as any).localServer?.blockmash) return
  started = true
  void initDuke()
  void initDarkMod()
  void initYorg()
  void initSurface().catch(e => console.warn('[blockmash] surface failed', e))
  void initYorgTrack().catch(e => console.warn('[blockmash] yorg track failed', e))
  void initDarkmodPrefabs().catch(e => console.warn('[blockmash] dark mod prefabs failed', e))
  try { initAtmosphere() } catch (e) { console.warn('[blockmash] atmosphere failed', e) }
}
setInterval(tryStart, 1000)
