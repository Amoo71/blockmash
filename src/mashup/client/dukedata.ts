// BlockMash: Duke Nukem 3D shareware data, loaded IN THE BROWSER from the user's own file (never shipped/uploaded).
// The user picks 3dduke13.zip (or DUKE3D.GRP); this is a JS port of tools/duke3d/{dukegrp,buildmap,extract_duke}.py:
// GRP directory, PALETTE.DAT (+ shade tables for the fullbright mask), ART tiles -> PNG, MAP v7 -> JSON,
// VOC -> WAV, parallax sky panoramas. The generated files are cached in IndexedDB and served as blob: URLs, so
// everything that used ./duke/<path> (local build with get-duke-shareware.py) works the same via dukeUrl().
import JSZip from 'jszip'
import { zlibSync } from 'fflate'

const DB = 'blockmash-duke'; const STORE = 'files'
const files = new Map<string, string>() // relative path -> blob URL
let manifestP: Promise<any> | null = null

const idb = async () => new Promise<IDBDatabase>((resolve, reject) => {
  const r = indexedDB.open(DB, 1)
  r.onupgradeneeded = () => { r.result.createObjectStore(STORE) }
  r.onsuccess = () => resolve(r.result); r.onerror = () => reject(r.error)
})
const tx = async <T>(mode: IDBTransactionMode, fn: (s: IDBObjectStore) => IDBRequest<T> | void) => {
  const db = await idb()
  return new Promise<T>((resolve, reject) => {
    const t = db.transaction(STORE, mode); const s = t.objectStore(STORE); const req = fn(s)
    t.oncomplete = () => { resolve(req ? req.result : undefined as any); db.close() }
    t.onerror = () => { reject(t.error); db.close() }
  })
}

/** ./duke/<path> -> blob URL of the browser-imported data, or the path itself (local build with www/duke on disk) */
export const dukeUrl = (p: string) => files.get(p.replace(/^\.?\/?duke\//, '')) ?? p
export const dukeImported = () => files.size > 0

/** load the IndexedDB cache into blob URLs (call once before the game starts) */
export async function loadDukeCache () {
  if (files.size || typeof indexedDB === 'undefined') return files.size > 0
  try {
    const keys = await tx<IDBValidKey[]>('readonly', s => s.getAllKeys())
    const vals = await tx<Blob[]>('readonly', s => s.getAll())
    keys.forEach((k, i) => files.set(String(k), URL.createObjectURL(vals[i])))
  } catch (e) { console.warn('[blockmash] Duke cache unavailable', e) }
  return files.size > 0
}

/** Duke manifest (browser import or ./duke on disk), null when there is no Duke data. Memoised. */
export async function getDukeManifest (): Promise<any> {
  manifestP ??= (async () => {
    await loadDukeCache()
    const imported = files.get('manifest.json')
    if (!imported && (globalThis as any).blockmashNoDukeOnDisk) return null
    try { const r = await fetch(imported ?? './duke/manifest.json'); return r.ok ? await r.json() : null } catch { return null }
  })()
  return manifestP
}

export async function clearDuke () {
  await tx('readwrite', s => { s.clear() })
  for (const u of files.values()) URL.revokeObjectURL(u)
  files.clear(); manifestP = null
}

// ---------------------------------------------------------------- GRP / ART / MAP / VOC parsing
const MAPS = ['E1L1', 'E1L2', 'E1L3', 'E1L4', 'E1L5', 'E1L6']
const RANGES = [[21, 62], [100, 116], [1680, 1780], [1820, 1856], [1890, 1911], [1960, 1974], [2000, 2062], [2066, 2080],
  [2521, 2620], [2630, 2687], [2440, 2442], [2472, 2482], [2497, 2500], [2930, 2950]]
const SOUNDS = ['PISTOL', 'SHOTGUN7', 'SHOTGNCK', 'CHAINGUN', 'RPGFIRE', 'BOMBEXPL', 'PBOMBBNC', 'RICOCHET', 'BULITHIT', 'GLASS',
  'GLASHEVY', 'PIGRG', 'PIGDY', 'PIGPN', 'PIGRM', 'PIGWRN', 'OCTARG', 'OCTADY', 'OCTAPN', 'OCTAAT1', 'OCTAAT2', 'BOS1RG',
  'BOS1DY', 'BOS1PN', 'BOS1RM', 'LIZSPIT', 'GETITM19', 'ITEM15', 'WPNSEL21', 'CLIPIN', 'CLIPOUT', 'KICKHIT', 'PAIN39',
  'DMDEATH', 'LETSRK03', 'COMEON02', 'GROOVY02', 'DAMNIT04', 'BLOWIT01', 'HAIL01', 'PIECE02', 'RIPEM08', 'COOL01',
  'EATSHT01', 'ROCKIN02', 'BITCHN04', 'GBLASR01', 'CATFIRE', 'DSCREM04', 'DSCREM15', 'PREDRG', 'PREDDY', 'PREDPN', 'BONUS', 'SECRET']
const PSKY: Record<number, number[]> = { 80: [0, 2, 3, 0, 2, 0, 1, 0], 84: [0, 0, 4, 0, 0, 1, 2, 3], 89: [1, 2, 1, 3, 4, 0, 2, 3] }

function readGrp (grp: Uint8Array) {
  const dv = new DataView(grp.buffer, grp.byteOffset, grp.byteLength)
  if (new TextDecoder().decode(grp.subarray(0, 12)) !== 'KenSilverman') throw new Error('not a Build GRP file')
  const n = dv.getUint32(12, true); const out = new Map<string, Uint8Array>()
  let off = 16 + n * 16
  for (let i = 0; i < n; i++) {
    const nm = new TextDecoder().decode(grp.subarray(16 + i * 16, 28 + i * 16)).replace(/\0.*$/, '').toUpperCase()
    const size = dv.getUint32(28 + i * 16, true)
    out.set(nm, grp.subarray(off, off + size)); off += size
  }
  return out
}

type Tile = { w: number, h: number, anm: number, px: Uint8Array }
function readTiles (F: Map<string, Uint8Array>) {
  const T = new Map<number, Tile>()
  for (const name of [...F.keys()].filter(k => /^TILES\d+\.ART$/.test(k)).sort()) {
    const d = F.get(name)!; const dv = new DataView(d.buffer, d.byteOffset, d.byteLength)
    const start = dv.getInt32(8, true); const end = dv.getInt32(12, true); const cnt = end - start + 1
    let off = 16 + cnt * 8
    for (let i = 0; i < cnt; i++) {
      const w = dv.getInt16(16 + i * 2, true); const h = dv.getInt16(16 + cnt * 2 + i * 2, true); const anm = dv.getUint32(16 + cnt * 4 + i * 4, true)
      if (w > 0 && h > 0) { T.set(start + i, { w, h, anm, px: d.subarray(off, off + w * h) }); off += w * h }
    }
  }
  return T
}

const tileOffset = (anm: number): [number, number] => { const xo = (anm >> 8) & 0xff; const yo = (anm >> 16) & 0xff; return [xo > 127 ? xo - 256 : xo, yo > 127 ? yo - 256 : yo] }

function readMap (data: Uint8Array) {
  const dv = new DataView(data.buffer, data.byteOffset, data.byteLength); let o = 0
  const i32 = () => { const v = dv.getInt32(o, true); o += 4; return v }; const i16 = () => { const v = dv.getInt16(o, true); o += 2; return v }
  const u16 = () => { const v = dv.getUint16(o, true); o += 2; return v }; const i8 = () => dv.getInt8(o++); const u8 = () => dv.getUint8(o++)
  const version = i32(); const start = { x: i32(), y: i32(), z: i32(), ang: i16(), sect: i16() }
  const sectors = []; const walls = []; const sprites = []
  for (let n = u16(), k = 0; k < n; k++) {
    const wallptr = i16(); const wallnum = i16(); const cz = i32(); const fz = i32(); const cstat = i16(); const fstat = i16(); const cpic = i16(); const cheinum = i16()
    const cshade = i8(); const cpal = u8(); const cxpan = u8(); const cypan = u8(); const fpic = i16(); const fheinum = i16(); const fshade = i8(); const fpal = u8()
    const fxpan = u8(); const fypan = u8(); const vis = u8(); u8(); const lotag = i16(); const hitag = i16(); i16()
    sectors.push({ wallptr, wallnum, cz, fz, cstat, fstat, cpic, cheinum, cshade, cpal, cxpan, cypan, fpic, fheinum, fshade, fpal, fxpan, fypan, vis, lotag, hitag })
  }
  for (let n = u16(), k = 0; k < n; k++) {
    const x = i32(); const y = i32(); const p2 = i16(); const nw = i16(); const ns = i16(); const cstat = i16(); const pic = i16(); const opic = i16()
    const shade = i8(); const pal = u8(); const xr = u8(); const yr = u8(); const xp = u8(); const yp = u8(); const lotag = i16(); const hitag = i16(); i16()
    walls.push({ x, y, p2, nw, ns, cstat, pic, opic, shade, pal, xr, yr, xp, yp, lotag, hitag })
  }
  for (let n = u16(), k = 0; k < n; k++) {
    const x = i32(); const y = i32(); const z = i32(); const cstat = i16(); const pic = i16(); const shade = i8(); const pal = u8(); const clip = u8(); u8()
    const xr = u8(); const yr = u8(); const xo = i8(); const yo = i8(); const sect = i16(); const stat = i16(); const ang = i16(); i16(); i16(); i16(); i16()
    const lotag = i16(); const hitag = i16(); i16()
    sprites.push({ x, y, z, cstat, pic, shade, pal, clip, xr, yr, xo, yo, sect, stat, ang, lotag, hitag })
  }
  return { version, start, sectors, walls, sprites }
}

function vocToWav (d: Uint8Array) {
  const dv = new DataView(d.buffer, d.byteOffset, d.byteLength)
  let pos = dv.getUint16(20, true); let rate = 11025; let bits = 8; const parts: Uint8Array[] = []
  while (pos < d.length) {
    const t = d[pos]; if (t === 0) break
    const size = d[pos + 1] | d[pos + 2] << 8 | d[pos + 3] << 16; const body = d.subarray(pos + 4, pos + 4 + size)
    if (t === 1) { rate = Math.floor(1000000 / (256 - body[0])); parts.push(body.subarray(2)) } else if (t === 2) parts.push(body)
    else if (t === 9) { rate = new DataView(body.buffer, body.byteOffset).getUint32(0, true); bits = body[4]; parts.push(body.subarray(12)) }
    pos += 4 + size
  }
  const len = parts.reduce((a, p) => a + p.length, 0); const bps = bits / 8
  const out = new Uint8Array(44 + len); const o = new DataView(out.buffer)
  const str = (at: number, s: string) => { for (let i = 0; i < 4; i++) out[at + i] = s.charCodeAt(i) }
  str(0, 'RIFF'); o.setUint32(4, 36 + len, true); str(8, 'WAVE'); str(12, 'fmt '); o.setUint32(16, 16, true); o.setUint16(20, 1, true); o.setUint16(22, 1, true)
  o.setUint32(24, rate, true); o.setUint32(28, rate * bps, true); o.setUint16(32, bps, true); o.setUint16(34, bits, true); str(36, 'data'); o.setUint32(40, len, true)
  let p = 44; for (const part of parts) { out.set(part, p); p += part.length }
  return new Blob([out], { type: 'audio/wav' })
}

// small own PNG encoder (RGBA, filter 0, fflate zlib): canvas.toBlob is far too slow for ~1000 tiles on phones
const CRC = (() => { const t = new Uint32Array(256); for (let n = 0; n < 256; n++) { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; t[n] = c >>> 0 } return t })()
const crc32 = (d: Uint8Array) => { let c = 0xffffffff; for (let i = 0; i < d.length; i++) c = CRC[(c ^ d[i]) & 0xff] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0 }
function encodePng (w: number, h: number, rgba: Uint8ClampedArray | Uint8Array) {
  const raw = new Uint8Array((w * 4 + 1) * h)
  for (let y = 0; y < h; y++) raw.set(rgba.subarray(y * w * 4, (y + 1) * w * 4), y * (w * 4 + 1) + 1)
  const chunk = (type: string, data: Uint8Array) => {
    const c = new Uint8Array(12 + data.length); const dv = new DataView(c.buffer)
    dv.setUint32(0, data.length); for (let i = 0; i < 4; i++) c[4 + i] = type.charCodeAt(i)
    c.set(data, 8); dv.setUint32(8 + data.length, crc32(c.subarray(4, 8 + data.length))); return c
  }
  const ihdr = new Uint8Array(13); const dv = new DataView(ihdr.buffer); dv.setUint32(0, w); dv.setUint32(4, h); ihdr.set([8, 6, 0, 0, 0], 8)
  return new Blob([new Uint8Array([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', ihdr), chunk('IDAT', zlibSync(raw, { level: 4 })), chunk('IEND', new Uint8Array())], { type: 'image/png' })
}
const canvasToPng = async (c: HTMLCanvasElement) => new Promise<Blob>((resolve, reject) => c.toBlob(b => b ? resolve(b) : reject(new Error('toBlob failed')), 'image/png'))

/** Parse the user's file and store the generated Duke data in IndexedDB. */
export async function importDuke (file: Blob & { name?: string }, progress: (msg: string) => void = () => {}) {
  progress('reading file')
  let bytes = new Uint8Array(await file.arrayBuffer())
  let license: string | null = null
  if (new TextDecoder().decode(bytes.subarray(0, 12)) !== 'KenSilverman') {
    progress('unpacking zip')
    let z = await JSZip.loadAsync(bytes)
    const find = (zz: JSZip, re: RegExp) => Object.values(zz.files).find(f => !f.dir && re.test(f.name.split('/').pop()!))
    const shr = find(z, /^DN3DSW13\.SHR$/i)
    if (shr) z = await JSZip.loadAsync(await shr.async('uint8array'))
    const g = find(z, /^DUKE3D\.GRP$/i)
    if (!g) throw new Error('no DUKE3D.GRP inside this zip (expected the shareware 3dduke13.zip)')
    const lic = find(z, /^LICENSE\.TXT$/i); if (lic) license = await lic.async('string')
    bytes = await g.async('uint8array')
  }
  const F = readGrp(bytes)
  if (!F.has('E1L1.MAP') || !F.has('PALETTE.DAT')) throw new Error('GRP without the E1 shareware levels')
  const palD = F.get('PALETTE.DAT')!; const pal = Array.from(palD.subarray(0, 768), v => Math.min(255, v * 4 + (v >> 4)))
  const nsh = new DataView(palD.buffer, palD.byteOffset).getInt16(768, true); const lk = palD.subarray(770, 770 + nsh * 256); const dark = (nsh - 2) * 256
  const FB = new Set<number>(); for (let i = 0; i < 255; i++) if (lk[dark + i] === i && pal[i * 3] + pal[i * 3 + 1] + pal[i * 3 + 2] > 120) FB.add(i)
  progress('reading tiles'); const T = readTiles(F)
  const out = new Map<string, Blob>(); const meta: Record<number, any> = {}
  const canvas = document.createElement('canvas'); const ctx = canvas.getContext('2d')!
  const tileImage = (t: Tile, glow: boolean) => {
    const id = new ImageData(t.w, t.h); const d = id.data; let nb = 0; let r = 0; let g = 0; let b = 0; let a = 0
    for (let x = 0; x < t.w; x++) {
      for (let y = 0; y < t.h; y++) {
        const c = t.px[x * t.h + y]; if (c === 255) continue
        const k = (y * t.w + x) * 4; d[k] = pal[c * 3]; d[k + 1] = pal[c * 3 + 1]; d[k + 2] = pal[c * 3 + 2]
        const isG = glow && FB.has(c); d[k + 3] = isG ? 250 : 255; if (isG) nb++
        r += d[k]; g += d[k + 1]; b += d[k + 2]; a++
      }
    }
    return { id, nb, avg: a ? [Math.round(r / a), Math.round(g / a), Math.round(b / a)] : [0, 0, 0] }
  }
  const putImage = async (path: string, id: ImageData) => { out.set(path, encodePng(id.width, id.height, id.data)) }
  const ranged: number[] = []; for (const [a, b] of RANGES) for (let i = a; i < b; i++) if (T.has(i)) ranged.push(i)
  let done = 0
  for (const i of ranged) {
    const t = T.get(i)!; const im = tileImage(t, false)
    await putImage(`tiles/${i}.png`, im.id); meta[i] = { w: t.w, h: t.h, off: tileOffset(t.anm) }
    if (++done % 40 === 0) { progress(`sprites ${done}/${ranged.length}`); await new Promise(r => setTimeout(r, 0)) }
  }
  const skies = new Set<number>()
  for (const mn of MAPS) {
    const md = F.get(mn + '.MAP'); if (!md) continue
    progress(`level ${mn}`); await new Promise(r => setTimeout(r, 0))
    const m = readMap(md); const need = new Set<number>()
    for (const s of m.sectors) { need.add(s.fpic); need.add(s.cpic); if (s.cstat & 1) skies.add(s.cpic) }
    for (const w of m.walls) { need.add(w.pic); need.add(w.opic) }
    for (const sp of m.sprites) if (!(sp.cstat & 32768)) need.add(sp.pic)
    for (const i of [...need].sort((a, b) => a - b)) {
      const t = T.get(i); if (!t) continue
      if (meta[i]?.avg) continue // already written with its glow mask by an earlier level
      const im = tileImage(t, true)
      await putImage(`tiles/${i}.png`, im.id)
      meta[i] = { w: t.w, h: t.h, off: tileOffset(t.anm), avg: im.avg }
      if (im.nb) meta[i].glow = Math.round(im.nb / (t.w * t.h) * 1e4) / 1e4
    }
    out.set(`maps/${mn}.json`, new Blob([JSON.stringify(m)], { type: 'application/json' }))
  }
  progress('skies'); const metaSky: Record<number, any> = {}
  for (const p of [...skies].sort((a, b) => a - b)) {
    const ims = (PSKY[p] ?? Array.from({ length: 8 }, () => 0)).map(o => T.get(p + o)).filter(Boolean) as Tile[]
    if (ims.length !== 8) continue
    const h = Math.max(...ims.map(t => t.h)); const W = ims.reduce((a, t) => a + t.w, 0)
    canvas.width = W; canvas.height = h; ctx.clearRect(0, 0, W, h); let x = 0
    for (const t of ims) { ctx.putImageData(tileImage(t, true).id, x, h - t.h); x += t.w }
    out.set(`tiles/sky_${p}.png`, await canvasToPng(canvas)); metaSky[p] = { w: W, h }
  }
  progress('sounds'); const snd: string[] = []
  for (const s of SOUNDS) { const v = F.get(s + '.VOC'); if (!v) continue; out.set(`sounds/${s.toLowerCase()}.wav`, vocToWav(v)); snd.push(s.toLowerCase()) }
  out.set('manifest.json', new Blob([JSON.stringify({
    source: 'Duke Nukem 3D shareware v1.3d – imported in this browser from the user\'s own file',
    notice: '(c) 1996 3D Realms. Stored only in this browser (IndexedDB); never uploaded.',
    tiles: meta, skies: metaSky, soundExt: 'wav', sounds: snd.sort()
  })], { type: 'application/json' }))
  if (license) out.set('LICENSE-3DREALMS-SHAREWARE.TXT', new Blob([license], { type: 'text/plain' }))
  progress(`saving ${out.size} files`)
  await clearDuke()
  await tx('readwrite', s => { for (const [k, v] of out) s.put(v, k) })
  return { files: out.size, tiles: Object.keys(meta).length, sounds: snd.length }
}

// ---------------------------------------------------------------- subtle loader button (like the sm64 "Load ROM…")
export function initDukeButton () {
  if (document.getElementById('bm-duke')) return
  const bar = document.createElement('div'); bar.id = 'bm-duke'
  bar.style.cssText = 'position:fixed;left:6px;bottom:6px;z-index:100;display:flex;align-items:center;gap:6px;font:11px sans-serif;color:#bbb;opacity:.45;transition:opacity .2s;pointer-events:auto'
  bar.onpointerenter = () => { bar.style.opacity = '1' }; bar.onpointerleave = () => { bar.style.opacity = '.45' }
  const btn = document.createElement('label')
  btn.style.cssText = 'height:24px;padding:0 8px;line-height:22px;color:#ccc;background:#111;border:1px solid #333;border-radius:4px;cursor:pointer;white-space:nowrap'
  const input = document.createElement('input'); input.type = 'file'; input.accept = '.zip,.grp,.ZIP,.GRP,application/zip,application/octet-stream'
  input.style.cssText = 'position:absolute;width:1px;height:1px;opacity:0;overflow:hidden'
  const msg = document.createElement('span'); msg.style.cssText = 'max-width:260px;text-shadow:1px 1px #000'
  btn.append(input); const txt = document.createElement('span'); btn.prepend(txt)
  bar.append(btn, msg); document.body.append(bar)
  const refresh = () => {
    const have = dukeImported()
    txt.textContent = have ? 'Duke3D ✓' : 'Duke3D data…'
    btn.title = have ? 'Duke Nukem 3D shareware data is stored in this browser. Tap to replace; long-press/right-click to remove.' : 'Pick your Duke Nukem 3D shareware 3dduke13.zip (or DUKE3D.GRP). It is read locally and never uploaded.'
  }
  refresh()
  let busy = false
  const onPick = async (inp: HTMLInputElement) => {
    const f = inp.files?.[0]; if (!f || busy) return
    busy = true
    bar.style.opacity = '1'
    try {
      const r = await importDuke(f, m => { msg.textContent = 'Duke3D: ' + m })
      msg.textContent = `Duke3D: ${r.tiles} tiles, ${r.sounds} sounds stored – restarting…`
      setTimeout(() => location.reload(), 900)
    } catch (e: any) { msg.textContent = 'Duke3D: ' + (e?.message ?? e); console.warn('[blockmash] Duke import failed', e); busy = false }
    inp.value = ''
  }
  input.onchange = () => onPick(input)
  // no Duke data at all: BlockMash *is* Duke Nukem 3D -> a clear prompt instead of a plain Minecraft world
  const prompt = () => {
    if (document.getElementById('bm-duke-prompt') || sessionStorage.getItem('bm-noduke')) return
    const ov = document.createElement('div'); ov.id = 'bm-duke-prompt'
    ov.style.cssText = 'position:fixed;inset:0;z-index:200;display:flex;align-items:center;justify-content:center;background:#000;font:14px sans-serif;color:#ddd;text-align:center;padding:16px'
    ov.innerHTML = `<div style="max-width:420px;background:#14100c;border:2px solid #b8860b;border-radius:8px;padding:20px 18px">
      <div style="font:bold 22px sans-serif;color:#ffcc33;margin-bottom:10px">Load Duke Nukem 3D</div>
      <div style="line-height:1.45;margin-bottom:16px">BlockMash plays the real Duke Nukem 3D shareware levels (E1L1–E1L6) – Minecraft is only underneath, where you blow holes into them.<br><br>Pick <b>3dduke13.zip</b> (or <b>DUKE3D.GRP</b>) from your device. It is unpacked in your browser, stored locally and never uploaded.</div>
      <label id="bm-duke-prompt-btn" style="display:inline-block;padding:12px 20px;background:#b8860b;color:#000;font:bold 16px sans-serif;border-radius:6px;cursor:pointer">Choose 3dduke13.zip…</label>
      <div id="bm-duke-prompt-msg" style="min-height:18px;margin-top:12px;color:#ffcc33"></div>
      <a href="#" id="bm-duke-prompt-skip" style="display:inline-block;margin-top:10px;color:#777;font-size:12px">continue without Duke (plain Minecraft)</a></div>`
    document.body.append(ov)
    const inp = document.createElement('input'); inp.type = 'file'; inp.accept = input.accept; inp.style.cssText = input.style.cssText
    ov.querySelector('#bm-duke-prompt-btn')!.append(inp)
    const pm = ov.querySelector('#bm-duke-prompt-msg') as HTMLElement
    new MutationObserver(() => { pm.textContent = msg.textContent }).observe(msg, { childList: true, characterData: true, subtree: true })
    inp.onchange = () => onPick(inp)
    ;(ov.querySelector('#bm-duke-prompt-skip') as HTMLElement).onclick = (e) => { e.preventDefault(); sessionStorage.setItem('bm-noduke', '1'); ov.remove() }
  }
  btn.oncontextmenu = (e) => {
    if (!dukeImported()) return
    e.preventDefault()
    if (confirm('Remove the Duke3D data from this browser?')) void clearDuke().then(() => location.reload())
  }
  // visible on the menu / loading screen and in the pause menu; hidden while playing (it would sit on the touch stick)
  setInterval(() => {
    const playing = !!(globalThis as any).bot?.entity && !((globalThis as any).activeModalStack?.length)
    bar.style.display = playing && !msg.textContent ? 'none' : 'flex'
  }, 500)
  ;(globalThis as any).blockmashDukeImport = importDuke
  void loadDukeCache().then(async () => { refresh(); if (!dukeImported() && !(await getDukeManifest())) prompt() })
}
