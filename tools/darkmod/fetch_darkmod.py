"""BlockMash phase 4: fetch a small selection of The Dark Mod 2.00 assets (CC BY-NC-SA 3.0) from the official
zipsync server (https://update.thedarkmod.com/zipsync) with HTTP range requests - only the needed members of the
pk4 archives are transferred. Output: assets/darkmod/ (gitignored, generated at install time). Own code, MIT."""
import io, json, os, re, struct, sys, urllib.request, zipfile, zlib
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
BASE = 'https://update.thedarkmod.com/zipsync/release/release200'
CACHE = os.path.join(ROOT, '.cache', 'darkmod')
OUT = os.path.join(ROOT, 'assets', 'darkmod')
ITEMS = os.path.join(ROOT, 'packages', 'free-mc-assets', 'minecraft-assets', 'data', '1.14.4', 'items')
ICON = 'tdm_gui01.pk4||dds/guis/assets/hud/'
SFX = 'tdm_sound_sfx01.pk4||sound/sfx/'
VOX = 'tdm_sound_vocals02.pk4||sound/voices/builders/builder2/tdm_ai_builder2_'
# MC items repurposed as Dark Mod tools/loot (inventory icon replaced, display name in blockmash-en.json)
ICONS = {
  'music_disc_13': 'inventory_icons/loot_icon_coin_stack_gold', 'music_disc_cat': 'inventory_icons/loot_icon_chalice',
  'music_disc_blocks': 'inventory_icons/loot_icon_ring_diamond', 'music_disc_chirp': 'inventory_icons/loot_icon_ruby',
  'music_disc_far': 'inventory_icons/loot_icon_necklace_golden_diamonds', 'music_disc_mall': 'inventory_icons/loot_icon_statue_lion',
  'music_disc_mellohi': 'weapon_icons/blackjack_icon', 'music_disc_stal': 'weapon_icons/broadhead_icon',
  'music_disc_strad': 'weapon_icons/waterarrow_icon', 'music_disc_ward': 'inventory_icons/flashbomb_icon',
  'music_disc_11': 'inventory_icons/lockpick_triangle_icon', 'music_disc_wait': 'inventory_icons/spyglass_icon',
}
SOUNDS = {
  'loot': '../meta/game/frob_loot', 'coins': 'movement/impacts/coins_2', 'bj_hit': 'tools/melee/blackjack_hit_head_01',
  'bj_swing': 'tools/melee/blackjack_swing01', 'bow_fire': 'tools/projectiles/bow_fire01', 'bow_draw': 'tools/projectiles/bow_draw',
  'arrow_flesh': 'tools/projectiles/arrow_broadhead_flesh_01', 'arrow_wood': 'tools/projectiles/arrow_broadhead_wood01',
  'arrow_water': 'tools/projectiles/arrow_water_impact_01', 'flashbomb': 'tools/misc/flashbomb01',
}
VOICES = {'idle': 'idle_01', 'idle2': 'idle_whistle_01', 'huh': 'to_alert1_01', 'suspicious': 'to_alert2_01', 'spotted': 'spotted_combat_01',
          'melee': 'combat_melee_01', 'pain': 'pain_small_01', 'die': 'die_quiet_01', 'ko': 'die_quiet_02', 'blinded': 'blinded_01',
          'lost': 'lost_player_01', 'killed': 'killed_player_01', 'lights': 'notice_lights_01', 'alarm': 'raise_alarm_01'}

def get(url, rng=None, timeout=60):
    req = urllib.request.Request(url, headers={'User-Agent': 'BlockMash-asset-fetch/1.0', **({'Range': f'bytes={rng[0]}-{rng[1] - 1}'} if rng else {})})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read()

def manifest():
    os.makedirs(CACHE, exist_ok=True)
    p = os.path.join(CACHE, 'release200.ini')
    if not os.path.exists(p):
        z = zipfile.ZipFile(io.BytesIO(get(BASE + '/manifest.iniz', timeout=180)))
        open(p, 'wb').write(z.read('data.ini'))
    entries = {}; cur = None
    for line in open(p, encoding='utf-8', errors='replace'):
        line = line.strip()
        m = re.match(r'^\[File (.*)\]$', line)
        if m: cur = m.group(1); entries[cur] = {}; continue
        if cur and '=' in line:
            k, v = line.split('=', 1); entries[cur][k] = v
    return entries

def member(entries, key):
    cp = os.path.join(CACHE, 'm', key.replace('||', '/'))
    if os.path.exists(cp):
        return open(cp, 'rb').read()
    e = entries.get(key)
    if not e:
        raise KeyError(key)
    pk4, _ = key.split('||')
    a, b = map(int, e['byterange'].split('-'))
    raw = get(f'{BASE}/{pk4}', (a, b))
    assert raw[:4] == b'PK\x03\x04', key
    n, x = struct.unpack_from('<HH', raw, 26)
    data = raw[30 + n + x:30 + n + x + int(e['compressedSize'])]
    out = zlib.decompress(data, -15) if e['compressionMethod'] == '8' else data
    os.makedirs(os.path.dirname(cp), exist_ok=True)
    open(cp, 'wb').write(out)
    return out

def dds_png(data, size=None):
    im = Image.open(io.BytesIO(data)).convert('RGBA')
    if size: im = im.resize((size, size), Image.LANCZOS)
    return im

def main():
    if os.environ.get('BLOCKMASH_NO_DARKMOD'):
        return
    try:
        entries = manifest()
    except Exception as e:
        print('darkmod: manifest download failed, Dark Mod items use fallbacks:', e); return
    os.makedirs(os.path.join(OUT, 'icons'), exist_ok=True)
    os.makedirs(os.path.join(OUT, 'sounds'), exist_ok=True)
    got = {'icons': [], 'sounds': [], 'lightgem': 0}
    for item, rel in ICONS.items():
        try:
            im = dds_png(member(entries, ICON + rel + '.dds'))
            im.save(os.path.join(OUT, 'icons', item + '.png'))
            if os.path.isdir(ITEMS):
                im.resize((64, 64), Image.LANCZOS).save(os.path.join(ITEMS, item + '.png'))
            got['icons'].append(item)
        except Exception as e:
            print('darkmod: icon', rel, e)
    for i in range(0, 32, 2):
        try:
            dds_png(member(entries, ICON + f'lightgem/lightgem_{i:05d}.dds')).save(os.path.join(OUT, 'icons', f'lightgem_{i // 2:02d}.png'))
            got['lightgem'] += 1
        except Exception as e:
            print('darkmod: lightgem', i, e)
    for name, rel in list(SOUNDS.items()) + [('vo_' + k, None) for k in VOICES]:
        if rel:
            key = (SFX + rel + '.ogg').replace('sfx/../', '')
        else:
            want = VOX + VOICES[name[3:]].rsplit('_', 1)[0] + '_'
            cands = sorted(k for k in entries if k.startswith(want) and re.match(r'^\d+\.ogg$', k[len(want):]))
            key = cands[0] if cands else VOX + VOICES[name[3:]] + '.ogg'
        try:
            open(os.path.join(OUT, 'sounds', name + '.ogg'), 'wb').write(member(entries, key))
            got['sounds'].append(name)
        except Exception as e:
            print('darkmod: sound', key, e)
    try:
        lic = member(entries, 'tdm_shared_stuff.zip||LICENSE.txt')
        open(os.path.join(OUT, 'LICENSE-TheDarkMod.txt'), 'wb').write(lic)
    except Exception as e:
        print('darkmod: licence', e)
    json.dump({'source': 'The Dark Mod 2.00 (thedarkmod.com), assets CC BY-NC-SA 3.0', **got}, open(os.path.join(OUT, 'manifest.json'), 'w'))
    print(f"darkmod: {len(got['icons'])} icons, {got['lightgem']} light gem frames, {len(got['sounds'])} sounds -> assets/darkmod")

if __name__ == '__main__':
    main()
