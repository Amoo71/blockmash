"""BlockMash: use the Duke Nukem 3D *shareware* episode (v1.3d) like a source port does.

The unmodified 3dduke13.zip is downloaded from the Internet Archive mirror of the official 3D Realms release
(md5-checked) into vendor/duke3d/ and read locally at install time. Sprites/sounds are converted into
assets/duke/ (gitignored) for the LOCAL build only. Nothing from the GRP is committed to the repository.
The shareware licence (LICENSE.TXT in the zip) only allows redistribution of the complete unmodified package,
so builds containing assets/duke/ must not be published.
"""
import json, os, subprocess, sys, urllib.request, shutil, tempfile
from PIL import Image
sys.path.insert(0, os.path.dirname(__file__))
from dukegrp import open_grp, palette, tiles, tile_image, tile_offset, SHAREWARE_MD5
from buildmap import read_map
MAPS = ['E1L1']

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
ZIP = os.environ.get('DUKE3D_SHAREWARE_ZIP', os.path.join(ROOT, 'vendor', 'duke3d', '3dduke13.zip'))
URL = 'https://archive.org/download/3dduke13/3dduke13.zip'
OUT = os.environ.get('DUKE3D_OUT', os.path.join(ROOT, 'assets', 'duke'))
ITEMS = os.environ.get('DUKE3D_ITEMS') or os.path.join(ROOT, 'packages', 'free-mc-assets', 'minecraft-assets', 'data', '1.14.4', 'items')

RANGES = [(21, 62), (100, 116), (1680, 1780), (1820, 1856), (1890, 1911), (1960, 1974), (2000, 2062), (2066, 2080),
          (2521, 2620), (2630, 2687), (2440, 2442), (2472, 2482), (2497, 2500), (2930, 2950)]
SOUNDS = ['PISTOL', 'SHOTGUN7', 'SHOTGNCK', 'CHAINGUN', 'RPGFIRE', 'BOMBEXPL', 'PBOMBBNC', 'RICOCHET', 'BULITHIT', 'GLASS',
          'GLASHEVY', 'PIGRG', 'PIGDY', 'PIGPN', 'PIGRM', 'PIGWRN', 'OCTARG', 'OCTADY', 'OCTAPN', 'OCTAAT1', 'OCTAAT2', 'BOS1RG',
          'BOS1DY', 'BOS1PN', 'BOS1RM', 'LIZSPIT', 'GETITM19', 'ITEM15', 'WPNSEL21', 'CLIPIN', 'CLIPOUT', 'KICKHIT', 'PAIN39',
          'DMDEATH', 'LETSRK03', 'COMEON02', 'GROOVY02', 'DAMNIT04', 'BLOWIT01', 'HAIL01', 'PIECE02', 'RIPEM08', 'COOL01',
          'EATSHT01', 'ROCKIN02', 'BITCHN04', 'GBLASR01', 'CATFIRE', 'DSCREM04', 'DSCREM15', 'PREDRG', 'PREDDY', 'PREDPN', 'BONUS', 'SECRET']
# MC items repurposed as Duke pickups (inventory icon = Duke sprite)
ITEM_ICONS = {'iron_horse_armor': 21, 'golden_horse_armor': 28, 'diamond_horse_armor': 22, 'leather_horse_armor': 23,
              'firework_star': 26, 'nautilus_shell': 40, 'heart_of_the_sea': 53, 'nether_star': 100}

def fetch():
    if os.path.exists(ZIP):
        return True
    os.makedirs(os.path.dirname(ZIP), exist_ok=True)
    print('duke3d: downloading unmodified shareware 3dduke13.zip from', URL)
    try:
        with urllib.request.urlopen(URL, timeout=120) as r, open(ZIP + '.part', 'wb') as f:
            shutil.copyfileobj(r, f)
        os.replace(ZIP + '.part', ZIP)
        return True
    except Exception as e:
        print('duke3d: download failed, Duke content will use fallbacks:', e)
        return False

def icon(img, size=64):
    w, h = img.size
    s = max(w, h)
    sq = Image.new('RGBA', (s, s))
    sq.paste(img, ((s - w) // 2, (s - h) // 2))
    return sq.resize((size, size), Image.NEAREST)

def voc_to_wav(data, dst):
    """Pure-Python Creative VOC (8-bit PCM) -> WAV, used when ffmpeg is not installed."""
    import struct, wave
    pos = struct.unpack_from('<H', data, 20)[0]; rate = 11025; pcm = bytearray(); bits = 8
    while pos < len(data):
        t = data[pos]
        if t == 0: break
        size = data[pos + 1] | data[pos + 2] << 8 | data[pos + 3] << 16; body = data[pos + 4:pos + 4 + size]
        if t == 1: rate = int(1000000 / (256 - body[0])); pcm += body[2:]
        elif t == 2: pcm += body
        elif t == 9: rate, bits = struct.unpack_from('<IB', body, 0); pcm += body[12:]
        pos += 4 + size
    with wave.open(dst, 'wb') as w:
        w.setnchannels(1); w.setsampwidth(bits // 8); w.setframerate(rate); w.writeframes(bytes(pcm))

def main():
    if os.environ.get('BLOCKMASH_NO_DUKE') or not fetch():
        return
    files, shr = open_grp(ZIP)
    pal = palette(files)
    T = tiles(files)
    if os.path.exists(OUT):
        shutil.rmtree(OUT)
    os.makedirs(os.path.join(OUT, 'tiles'))
    os.makedirs(os.path.join(OUT, 'sounds'))
    meta = {}
    for a, b in RANGES:
        for i in range(a, b):
            if i not in T:
                continue
            img = tile_image(T[i], pal)
            img.save(os.path.join(OUT, 'tiles', f'{i}.png'), optimize=True)
            meta[i] = {'w': img.width, 'h': img.height, 'off': tile_offset(T[i][2])}
    with tempfile.TemporaryDirectory() as tmp:
        for s in SOUNDS:
            name = s + '.VOC'
            if name not in files:
                continue
            src = os.path.join(tmp, name)
            open(src, 'wb').write(files[name])
            if shutil.which('ffmpeg'):
                subprocess.run(['ffmpeg', '-loglevel', 'error', '-y', '-i', src, '-ac', '1', '-c:a', 'libvorbis', '-q:a', '4',
                                os.path.join(OUT, 'sounds', s.lower() + '.ogg')], check=True)
            else:
                voc_to_wav(files[name], os.path.join(OUT, 'sounds', s.lower() + '.wav'))
    # level geometry (sectors/walls/sprites) + every tile the maps reference, for the polygon surface renderer
    os.makedirs(os.path.join(OUT, 'maps'), exist_ok=True)
    for mname in MAPS:
        if mname + '.MAP' not in files: continue
        m = read_map(files[mname + '.MAP'])
        need = set()
        for sc in m['sectors']: need.update((sc['fpic'], sc['cpic']))
        for w in m['walls']: need.update((w['pic'], w['opic']))
        for sp in m['sprites']:
            if not sp['cstat'] & 32768: need.add(sp['pic'])
        for i in sorted(need):
            if i in T and str(i) not in meta and i not in meta:
                img = tile_image(T[i], pal)
                img.save(os.path.join(OUT, 'tiles', f'{i}.png'), optimize=True)
                meta[i] = {'w': img.width, 'h': img.height, 'off': tile_offset(T[i][2])}
        for i in need:
            if i in meta and 'avg' not in meta[i]:
                im = Image.open(os.path.join(OUT, 'tiles', f'{i}.png')).convert('RGBA').resize((1, 1), Image.BOX)
                meta[i]['avg'] = list(im.getpixel((0, 0))[:3])
        json.dump(m, open(os.path.join(OUT, 'maps', mname + '.json'), 'w'), separators=(',', ':'))
    if os.path.isdir(ITEMS):
        for item, tile in ITEM_ICONS.items():
            if tile in T:
                icon(tile_image(T[tile], pal)).save(os.path.join(ITEMS, item + '.png'))
    json.dump({'source': 'Duke Nukem 3D shareware v1.3d (3dduke13.zip, md5 ' + SHAREWARE_MD5 + ')',
               'notice': 'Extracted locally from the unmodified shareware episode. (c) 1996 3D Realms. Do not redistribute.',
               'tiles': meta, 'soundExt': 'ogg' if shutil.which('ffmpeg') else 'wav', 'sounds': sorted(s.lower() for s in SOUNDS if s + '.VOC' in files)},
              open(os.path.join(OUT, 'manifest.json'), 'w'))
    open(os.path.join(OUT, 'LICENSE-3DREALMS-SHAREWARE.TXT'), 'wb').write(shr.read('LICENSE.TXT'))
    print(f'duke3d: {len(meta)} sprites, {len(os.listdir(os.path.join(OUT, "sounds")))} sounds -> {OUT}')

if __name__ == '__main__':
    main()
