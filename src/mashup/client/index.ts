// BlockMash client-side mashup features (singleplayer, integrated server)
import { initDuke } from './duke'
import { initDarkMod } from './darkmod'

let started = false
const tryStart = () => {
  if (started) return
  if (!globalThis.bot?.entity || !globalThis.viewer?.entities || !(globalThis as any).localServer?.blockmash) return
  started = true
  void initDuke()
  void initDarkMod()
}
setInterval(tryStart, 1000)
