#!/usr/bin/env python3
"""BlockMash free asset builder.

Builds packages/free-mc-assets/minecraft-assets/data/1.14.4 (a drop-in for the
`minecraft-assets` npm layout) WITHOUT copying a single Mojang image.

Sources, in priority order:
  1. PureBDcraft 128x (vendor/purebdcraft/pack.zip) - BDcraft.net terms, non-commercial + credit
  2. Pixel Perfection CE (.cache/ppce)              - CC BY-SA 4.0
  3. own procedural placeholders                    - CC0 (BlockMash)

The vanilla `minecraft-assets` package (installed as `mc-assets-reference`) is used
ONLY as a reference: list of file names, image dimensions, sprite coordinates and the
block model/blockstate JSON tables. No vanilla pixels are written to the output;
tools/free-assets/verify_no_mojang.py checks this by hashing.
"""
import hashlib, json, os, shutil, sys, zipfile, glob, random
from PIL import Image
import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
REF = os.path.join(ROOT, 'node_modules', 'mc-assets-reference', 'minecraft-assets', 'data')
CACHE = os.path.join(ROOT, '.cache')
BDC_ZIP = os.environ.get('BDCRAFT_ZIP', os.path.join(ROOT, 'vendor', 'purebdcraft', 'pack.zip'))
BDC_DIR = os.path.join(CACHE, 'purebdcraft')
BDC = os.path.join(BDC_DIR, 'assets', 'minecraft', 'textures')
PPC = os.path.join(CACHE, 'ppce', 'assets', 'minecraft', 'textures')
PKG = os.path.join(ROOT, 'packages', 'free-mc-assets')
OUTDATA = os.path.join(PKG, 'minecraft-assets', 'data')
VER = '1.14.4'
OUT = os.path.join(OUTDATA, VER)
# version folder names that source code imports from (all alias the free folder)
ALIAS_VERSIONS = ['1.8.8', '1.9', '1.10', '1.11.2', '1.12', '1.13', '1.13.2', '1.15.2', '1.16.1', '1.16.4', '1.17.1', '1.18.1', '1.19.1', '1.20.2']
TILE = int(os.environ.get('BLOCK_TILE', '128'))  # atlas tile (128 = native PureBDcraft, atlas 4096px; 64 = low-memory build)
ITEM_TILE = int(os.environ.get('ITEM_TILE', '64'))
ENTITY_MAX_SCALE = int(os.environ.get('ENTITY_SCALE', '4'))  # entity textures: max x4 of vanilla size

report = {'bdcraft': [], 'ppce': [], 'composite': [], 'placeholder': [], 'skipped': [], 'rejected_identical_to_mojang': []}
_REFHASH = None
def is_mojang(im):
    """True if the image pixels are identical to any vanilla texture (some PPCE files are)."""
    global _REFHASH
    if _REFHASH is None:
        import importlib.util
        spec = importlib.util.spec_from_file_location('verify', os.path.join(os.path.dirname(__file__), 'verify_no_mojang.py'))
        mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
        _REFHASH = mod.reference()
    a = im.convert('RGBA')
    return ('px:' + hashlib.md5(a.tobytes() + bytes(str(a.size), 'ascii')).hexdigest()) in _REFHASH

def ensure_sources():
    if not os.path.isdir(BDC):
        if not os.path.exists(BDC_ZIP):
            sys.exit(f'PureBDcraft zip not found at {BDC_ZIP}. Download PureBDcraft 128x from https://bdcraft.net and put it there (or set BDCRAFT_ZIP).')
        os.makedirs(BDC_DIR, exist_ok=True)
        zipfile.ZipFile(BDC_ZIP).extractall(BDC_DIR)
    if not os.path.isdir(PPC):
        import tarfile, urllib.request, io
        url = 'https://github.com/Athemis/PixelPerfectionCE/archive/refs/heads/master.tar.gz'
        print('downloading Pixel Perfection CE', url)
        data = urllib.request.urlopen(url).read()
        os.makedirs(os.path.join(CACHE, 'ppce'), exist_ok=True)
        with tarfile.open(fileobj=io.BytesIO(data)) as t:
            for m in t.getmembers():
                parts = m.name.split('/', 1)
                if len(parts) < 2 or not parts[1]: continue
                m.name = parts[1]
                t.extract(m, os.path.join(CACHE, 'ppce'))
    if not os.path.isdir(REF):
        sys.exit('reference package mc-assets-reference missing, run pnpm install')

DIRMAP = {'blocks': 'block', 'items': 'item'}

# 1.14/1.16 name -> modern (26.x) name in PureBDcraft
RENAMES = {
    'blocks/grass.png': 'block/short_grass.png',
    'blocks/grass_path_top.png': 'block/dirt_path_top.png',
    'blocks/grass_path_side.png': 'block/dirt_path_side.png',
    'entity/steve.png': 'entity/player/wide/steve.png',
    'entity/alex.png': 'entity/player/slim/alex.png',
    'entity/sign.png': 'entity/signs/oak.png',
}
for c in ['all_black', 'black', 'british_shorthair', 'calico', 'jellie', 'persian', 'ragdoll', 'red', 'siamese', 'tabby', 'white']:
    RENAMES[f'entity/cat/{c}.png'] = f'entity/cat/cat_{c}.png'

def src_path(base, rel, renamed=False):
    top, rest = rel.split('/', 1)
    if renamed and rel in RENAMES:
        return os.path.join(base, RENAMES[rel])
    return os.path.join(base, DIRMAP.get(top, top), rest)

def ref_size(rel_versions, rel):
    for v in rel_versions + ['1.13.2', '1.19.1']:
        p = os.path.join(REF, v, rel)
        if os.path.exists(p):
            with Image.open(p) as im:
                return im.size
    return None

def first_frame(im, w):
    """animated strips: keep full strip (atlas only samples the first frame)."""
    return im

def resize_to(im, size):
    if im.size == tuple(size): return im
    if im.width >= size[0]:
        f = im.width // size[0]
        if f >= 1 and im.width == size[0] * f and im.height == size[1] * f:
            return im.reduce(f)
        return im.resize(size, Image.LANCZOS)
    return im.resize(size, Image.NEAREST)

def scale_to_width(im, w):
    if im.width == w: return im
    h = round(im.height * w / im.width)
    return resize_to(im, (w, h))

def placeholder(size, rel):
    """Own procedural texture (CC0): deterministic noisy tile from the name hash."""
    h = hashlib.md5(rel.encode()).digest()
    base = np.array([h[0], h[1], h[2]], dtype=np.int16)
    rng = np.random.default_rng(int.from_bytes(h[:4], 'little'))
    w, hh = size
    arr = np.clip(base[None, None, :] + rng.integers(-25, 25, (hh, w, 1)), 0, 255).astype(np.uint8)
    a = np.full((hh, w, 1), 255, np.uint8)
    return Image.fromarray(np.concatenate([arr, a], 2), 'RGBA')

def target_size(rel, im_size, refsz):
    top = rel.split('/')[0]
    w, h = im_size
    if top == 'blocks':
        return (TILE, round(h * TILE / w))
    if top == 'items':
        return (ITEM_TILE, round(h * ITEM_TILE / w))
    if top in ('gui', 'font', 'map', 'misc', 'environment', 'effect', 'mob_effect') and refsz:
        return refsz
    if top in ('entity', 'painting', 'particle', 'colormap', 'models') and refsz:
        sc = min(ENTITY_MAX_SCALE, max(1, w // refsz[0])) if w >= refsz[0] else 1
        if top == 'colormap': sc = 1
        return (refsz[0] * sc, refsz[1] * sc)
    return im_size

def aspect_ok(a, b):
    return a and b and abs(a[0] / a[1] - b[0] / b[1]) < 1e-6

def entity_variants(rel):
    """26.x renamed most entity textures: entity/bat.png -> entity/bat/bat.png,
    entity/panda/lazy_panda.png -> entity/panda/panda_lazy.png, ..."""
    parts = rel[:-4].split('/')
    out = []
    if len(parts) == 2:
        n = parts[1]
        out += [f'entity/{n}/{n}', f'entity/{n.split("_")[0]}/{n}']
    elif len(parts) >= 3:
        d, f = parts[-2], parts[-1]
        pre = '/'.join(parts[:-1])
        bits = f.split('_')
        if len(bits) >= 2:
            out.append(f'{pre}/{bits[-1]}_{"_".join(bits[:-1])}')      # aggressive_panda -> panda_aggressive
            out.append(f'{pre}/{bits[1]}_{bits[0]}' + ('_' + '_'.join(bits[2:]) if len(bits) > 2 else ''))  # snow_fox_sleep -> fox_snow_sleep
        out.append(f'{pre}/{d}_{f}')
    return [o + '.png' for o in out]

def pick(rel, refsz):
    """returns (Image, source-tag) or (None, None)"""
    top = rel.split('/')[0]
    if top == 'entity' and rel not in RENAMES and not os.path.exists(src_path(BDC, rel)):
        for cand in entity_variants(rel):
            p = os.path.join(BDC, cand)
            if os.path.exists(p):
                im = Image.open(p).convert('RGBA')
                if refsz and aspect_ok(im.size, refsz) and not is_mojang(im):
                    return im, 'bdcraft (renamed ' + cand + ')'
    # 1. PureBDcraft
    for renamed in (False, True):
        if renamed and rel not in RENAMES: continue
        p = src_path(BDC, rel, renamed)
        if os.path.exists(p):
            im = Image.open(p).convert('RGBA')
            if top in ('entity', 'gui', 'models', 'map') and refsz and not aspect_ok(im.size, refsz):
                # layout changed between 1.16 and 26.x -> not usable
                report['skipped'].append(f'{rel}: PureBDcraft layout differs ({im.size} vs {refsz})')
                continue
            if top in ('blocks', 'items') and refsz and im.width / im.height != refsz[0] / refsz[1] and im.height % im.width != 0:
                report['skipped'].append(f'{rel}: PureBDcraft aspect differs')
                continue
            if is_mojang(im):
                report['rejected_identical_to_mojang'].append('bdcraft:' + rel); continue
            return im, 'bdcraft' + (' (renamed ' + RENAMES[rel] + ')' if renamed else '')
    # 2. Pixel Perfection CE
    p = src_path(PPC, rel)
    if os.path.exists(p):
        im = Image.open(p).convert('RGBA')
        if refsz and not aspect_ok(im.size, refsz) and top not in ('blocks', 'items'):
            report['skipped'].append(f'{rel}: PPCE layout differs')
        elif is_mojang(im):
            report['rejected_identical_to_mojang'].append('ppce:' + rel)
        else:
            return im, 'ppce'
    return None, None

def save(im, rel):
    out = os.path.join(OUT, rel)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    im.save(out, compress_level=6)

# ---------------------------------------------------------------- sprites -> legacy sheets
_sheet_cache = {}
def find_exact(sheet, sprite):
    S = sheet if isinstance(sheet, np.ndarray) else np.asarray(sheet.convert('RGBA')).astype(np.int16)
    P = np.asarray(sprite.convert('RGBA')).astype(np.int16)
    ph, pw = P.shape[:2]
    H, W = S.shape[:2]
    if ph > H or pw > W: return None
    mask = P[:, :, 3] > 0
    if mask.sum() < 4: return None
    oy, ox = np.argwhere(mask)[0]
    cand = np.argwhere((S[oy:H - ph + 1 + oy, ox:W - pw + 1 + ox] == P[oy, ox]).all(-1))
    out = []
    for y, x in cand:
        reg = S[y:y + ph, x:x + pw]
        if ((reg[:, :, 3] > 0) == mask).all() and (np.abs(reg - P).sum(-1)[mask] == 0).all():
            out.append((int(x), int(y)))
    return out or None

SPRITE_SHEETS = {
    'gui/icons.png': ['hud', 'hud/heart', 'icon'],
    'gui/widgets.png': ['hud', 'widget'],
    'gui/bars.png': ['boss_bar'],
}
def composite_sheet(rel, refsz):
    """Rebuild a legacy GUI sheet: base = BDcraft (if layout ok) or PPCE, then paste BDcraft
    sprites at coordinates located with the vanilla 1.20.2 sprite <-> 1.17.1 sheet reference."""
    ref_sheet_p = os.path.join(REF, '1.17.1', rel)
    if not os.path.exists(ref_sheet_p):
        ref_sheet_p = os.path.join(REF, VER, rel)
    ref_sheet = np.asarray(Image.open(ref_sheet_p).convert('RGBA')).astype(np.int16)
    taken = set()
    base, tag = pick(rel, refsz)
    if base is not None:
        base = resize_to(base, refsz)
    else:
        base = Image.new('RGBA', refsz, (0, 0, 0, 0))
        tag = 'empty'
    ppce_p = src_path(PPC, rel)
    ppce = resize_to(Image.open(ppce_p).convert('RGBA'), refsz) if os.path.exists(ppce_p) else None
    if ppce is not None and is_mojang(ppce): ppce = None
    sprite_root = os.path.join(REF, '1.20.2', 'gui', 'sprites')
    dirs = SPRITE_SHEETS.get(rel)
    if dirs is None and rel.startswith('gui/container/'):
        name = rel.split('/')[-1][:-4]
        dirs = [f'container/{name}', 'container/slot']
    if not dirs: dirs = []
    pasted = []
    for d in dirs:
        for sp in sorted(glob.glob(os.path.join(sprite_root, d, '*.png'))):
            relsp = os.path.relpath(sp, sprite_root)
            spr = Image.open(sp).convert('RGBA')
            if spr.height > spr.width * 1.5 and spr.height % spr.width == 0:
                continue  # animated
            locs = find_exact(ref_sheet, spr)
            if not locs: continue
            bdc = os.path.join(BDC, 'gui', 'sprites', relsp)
            for (x, y) in locs[:4]:
                box = (x, y, x + spr.width, y + spr.height)
                if box in taken: continue
                taken.add(box)
                if os.path.exists(bdc):
                    b = Image.open(bdc).convert('RGBA')
                    if not aspect_ok(b.size, spr.size): continue
                    b = resize_to(b, spr.size)
                    base.paste(Image.new('RGBA', spr.size, (0, 0, 0, 0)), box)
                    base.paste(b, box)
                    pasted.append(relsp)
                elif tag.startswith('bdcraft') and ppce is not None:
                    region = base.crop(box)
                    if np.asarray(region)[:, :, 3].max() == 0:
                        base.paste(ppce.crop(box), box)
    report['composite'].append(f'{rel}: base={tag}, +{len(set(pasted))} PureBDcraft sprites')
    return base

# ---------------------------------------------------------------- main texture pass
def collect_reference():
    rels = set()
    def walk(v, sub):
        d = os.path.join(REF, v, sub)
        for root, _, fs in os.walk(d):
            for f in fs:
                if f.endswith('.png') or f.endswith('.mcmeta'):
                    rels.add(os.path.relpath(os.path.join(root, f), os.path.join(REF, v)))
    for sub in ['blocks', 'items', 'entity', 'gui', 'environment', 'misc', 'particle', 'painting', 'mob_effect', 'map', 'colormap', 'models', 'effect']:
        walk(VER, sub)
    walk('1.16.4', 'entity')
    walk('1.17.1', 'gui')
    walk('1.20.2', 'mob_effect')
    walk('1.19.1', 'entity/chest')
    walk('1.20.2', 'entity/player')
    # never needed by the client (and contain Mojang branding / unused)
    rels = {r for r in rels if not r.startswith('gui/title/') and '/presets/' not in r and not r.startswith('gui/sprites/')
            and not r.startswith('gui/advancements') and not r.startswith('gui/realms') and r != 'gui/demo_background.png'}
    rels.add('font/ascii.png')
    rels.add('entity/sign.png')  # 1.13 name used by prismarine-viewer sign models
    return sorted(rels)

def ref_versions_for(rel):
    return ['1.17.1', VER, '1.16.4', '1.20.2'] if rel.startswith('gui/') else [VER, '1.16.4', '1.17.1', '1.20.2']

def build_textures():
    rels = collect_reference()
    for rel in rels:
        if rel.endswith('.mcmeta'):
            # animation metadata: take the one of the texture source we used
            png = rel[:-7]
            for base in (BDC, PPC):
                p = src_path(base, png) + '.mcmeta'
                if os.path.exists(p) and os.path.exists(os.path.join(OUT, png)):
                    os.makedirs(os.path.dirname(os.path.join(OUT, rel)), exist_ok=True)
                    shutil.copy(p, os.path.join(OUT, rel)); break
            continue
        refsz = ref_size(ref_versions_for(rel), rel)
        if rel in SPRITE_SHEETS or (rel.startswith('gui/container/') and os.path.exists(os.path.join(REF, '1.20.2', 'gui', 'sprites', 'container', rel.split('/')[-1][:-4]))):
            im = composite_sheet(rel, refsz)
            save(im, rel)
            continue
        im, tag = pick(rel, refsz)
        if im is None:
            if rel.split('/')[0] in ('blocks', 'items', 'mob_effect', 'entity', 'models'):
                size = refsz or (16, 16)
                im = placeholder(size, rel)
                tag = 'placeholder'
            else:
                report['skipped'].append(f'{rel}: no free source, not shipped')
                continue
        im = resize_to(im, target_size(rel, im.size, refsz))
        save(im, rel)
        report['ppce' if tag == 'ppce' else 'placeholder' if tag == 'placeholder' else 'bdcraft'].append(rel)

def copy_bdc_extra_block_textures():
    d = os.path.join(BDC, 'block', '_bdc')
    n = 0
    for root, _, fs in os.walk(d):
        for f in fs:
            if not f.endswith('.png'): continue
            rel = 'blocks/' + os.path.relpath(os.path.join(root, f), os.path.join(BDC, 'block'))
            im = Image.open(os.path.join(root, f)).convert('RGBA')
            save(resize_to(im, (TILE, round(im.height * TILE / im.width))), rel)
            n += 1
    report['composite'].append(f'blocks/_bdc: {n} extra PureBDcraft variant textures')

def build_json():
    for name in ['blocks_textures.json', 'items_textures.json', 'blocks_states.json', 'blocks_models.json']:
        shutil.copy(os.path.join(REF, VER, name), os.path.join(OUT, name))
    with open(os.path.join(OUT, 'texture_content.json'), 'w') as f:
        f.write('[]')
    # Merge PureBDcraft block models where the model name exists in 1.14.4 and every
    # referenced parent/texture can be resolved, so the pack's own 3D shapes are used.
    models = json.load(open(os.path.join(OUT, 'blocks_models.json')))
    bdm_dir = os.path.join(BDC_DIR, 'assets', 'minecraft', 'models', 'block')
    merged = 0
    for k in list(models.keys()):
        p = os.path.join(bdm_dir, k + '.json')
        if not os.path.exists(p): continue
        try:
            m = json.load(open(p))
        except Exception:
            continue
        if not texture_refs_ok(m, bdm_dir, models):
            continue
        models[k] = strip_ns(m)
        merged += 1
    # parents only present in the pack (e.g. block/_bdc/...)
    for root, _, fs in os.walk(os.path.join(bdm_dir, '_bdc')):
        for f in fs:
            if f.endswith('.json'):
                key = os.path.relpath(os.path.join(root, f), bdm_dir)[:-5]
                try: models[key] = strip_ns(json.load(open(os.path.join(root, f))))
                except Exception: pass
    # revert PureBDcraft models whose parent chain does not resolve in the merged table
    vanilla = json.load(open(os.path.join(REF, VER, 'blocks_models.json')))
    def chain_ok(k, depth=0):
        m = models.get(k)
        if m is None or depth > 20: return False
        par = m.get('parent')
        if not par or par.startswith('builtin'): return True
        return chain_ok(par.replace('minecraft:', '').replace('block/', '', 1), depth + 1)
    reverted = 0
    for _ in range(3):
        for k in list(models):
            if not chain_ok(k):
                if k in vanilla: models[k] = vanilla[k]
                else: del models[k]
                reverted += 1
    report['composite'].append(f'blocks_models.json: {reverted} PureBDcraft models reverted (unresolvable parents)')
    # PureBDcraft blockstates (random variants etc.) when the variant keys match 1.14.4 exactly
    states = json.load(open(os.path.join(OUT, 'blocks_states.json')))
    bds_dir = os.path.join(BDC_DIR, 'assets', 'minecraft', 'blockstates')
    st_merged = 0
    for k, vs in states.items():
        p = os.path.join(bds_dir, k + '.json')
        if not vs or 'variants' not in vs or not os.path.exists(p): continue
        try: b = strip_ns(json.load(open(p)))
        except Exception: continue
        if 'variants' not in b or set(b['variants']) != set(vs['variants']): continue
        refs = []
        for v in b['variants'].values():
            refs += [x['model'] for x in (v if isinstance(v, list) else [v])]
        if all(r.replace('block/', '', 1) in models for r in refs):
            states[k] = b; st_merged += 1
    json.dump(states, open(os.path.join(OUT, 'blocks_states.json'), 'w'))
    json.dump(models, open(os.path.join(OUT, 'blocks_models.json'), 'w'))
    report['composite'].append(f'blocks_states.json: {st_merged} blockstates taken from PureBDcraft')
    report['composite'].append(f'blocks_models.json: {merged} models taken from PureBDcraft, rest are 1.14.4 geometry tables')

def strip_ns(m):
    s = json.dumps(m).replace('"minecraft:block/', '"block/').replace('"minecraft:item/', '"item/')
    return json.loads(s)

def texture_refs_ok(m, bdm_dir, models):
    for v in (m.get('textures') or {}).values():
        if not isinstance(v, str): return False
        if v.startswith('#'): continue
        name = v.replace('minecraft:', '')
        if not name.startswith('block/'): return False
        if not os.path.exists(os.path.join(OUT, 'blocks', name[6:] + '.png')): return False
    par = m.get('parent')
    if par:
        par = par.replace('minecraft:', '').replace('block/', '')
        if par not in models and not os.path.exists(os.path.join(bdm_dir, par + '.json')) and not par.startswith('builtin'):
            return False
    return True

# entity textures for prismarine-viewer's OBJ models (upstream shipped them as base64 vanilla PNGs).
# Only the vanilla *dimensions* are kept as reference so we can verify the UV layout matches.
EXT_SIZES = {'allay': (32, 32), 'axolotl': (64, 64), 'blaze': (64, 32), 'boat': (128, 64), 'camel': (128, 128), 'cat': (64, 32), 'chicken': (64, 32), 'cod': (32, 32), 'creeper': (64, 32), 'dolphin': (64, 64), 'ender_dragon': (256, 256), 'enderman': (64, 32), 'endermite': (64, 32), 'fox': (48, 32), 'frog': (48, 48), 'ghast': (64, 32), 'goat': (64, 64), 'guardian': (64, 64), 'horse': (64, 64), 'llama': (128, 64), 'minecart': (64, 32), 'parrot': (32, 32), 'piglin': (64, 64), 'pillager': (64, 64), 'rabbit': (64, 32), 'sheep': (64, 32), 'shulker': (64, 64), 'sniffer': (192, 192), 'spider': (64, 32), 'tadpole': (16, 16), 'turtle': (128, 64), 'vex': (32, 32), 'villager': (64, 64), 'warden': (128, 128), 'witch': (64, 128), 'wolf': (64, 32), 'zombie': (64, 64), 'zombie_villager': (64, 64)}
EXT_HINTS = {'boat': ['boat/oak'], 'cat': ['cat/cat_tabby', 'cat/tabby'], 'cod': ['fish/cod'], 'ender_dragon': ['enderdragon/dragon'], 'fox': ['fox/fox'], 'frog': ['frog/temperate_frog', 'frog/frog_temperate'], 'axolotl': ['axolotl/axolotl_lucy'], 'horse': ['horse/horse_brown'], 'llama': ['llama/creamy', 'llama/llama_creamy'], 'parrot': ['parrot/parrot_red_blue'], 'pillager': ['illager/pillager'], 'vex': ['illager/vex'], 'rabbit': ['rabbit/brown', 'rabbit/rabbit_brown'], 'turtle': ['turtle/big_sea_turtle'], 'zombie_villager': ['zombie_villager/zombie_villager'], 'villager': ['villager/villager'], 'shulker': ['shulker/shulker'], 'sheep': ['sheep/sheep'], 'creeper': ['creeper/creeper'], 'enderman': ['enderman/enderman'], 'ghast': ['ghast/ghast'], 'spider': ['spider/spider'], 'wolf': ['wolf/wolf'], 'zombie': ['zombie/zombie'], 'piglin': ['piglin/piglin'], 'goat': ['goat/goat'], 'camel': ['camel/camel'], 'sniffer': ['sniffer/sniffer'], 'warden': ['warden/warden'], 'tadpole': ['tadpole/tadpole'], 'allay': ['allay/allay'], 'guardian': ['guardian']}
EXT_PREFER_PPCE = {'chicken'}  # 26.x model/texture layout changed

def build_external_entity_textures():
    out = {}
    for key, size in EXT_SIZES.items():
        cands = EXT_HINTS.get(key, []) + [key, f'{key}/{key}']
        bases = [('ppce', PPC), ('bdcraft', BDC)] if key in EXT_PREFER_PPCE else [('bdcraft', BDC), ('ppce', PPC)]
        chosen = None
        for tag, base in bases:
            for c in cands:
                p = os.path.join(base, 'entity', c + '.png')
                if os.path.exists(p):
                    im = Image.open(p).convert('RGBA')
                    if aspect_ok(im.size, size) and im.width % size[0] == 0 and not is_mojang(im):
                        chosen = (tag, im); break
            if chosen: break
        rel = f'entity/_ext/{key}.png'
        if chosen:
            tag, im = chosen
            sc = min(ENTITY_MAX_SCALE, im.width // size[0])
            save(resize_to(im, (size[0] * sc, size[1] * sc)), rel)
            report[tag].append(rel)
        else:
            save(placeholder(size, rel), rel)
            report['placeholder'].append(rel)
        out[key] = f'textures/1.16.4/{rel}'
    with open(os.path.join(ROOT, 'prismarine-viewer', 'viewer', 'lib', 'entity', 'externalTextures.json'), 'w') as f:
        json.dump(out, f, indent=1)

def aliases():
    for v in ALIAS_VERSIONS:
        p = os.path.join(OUTDATA, v)
        if os.path.islink(p) or os.path.exists(p):
            if os.path.islink(p): os.unlink(p)
            else: shutil.rmtree(p)
        os.symlink(VER, p)

def main():
    ensure_sources()
    if os.path.exists(OUTDATA): shutil.rmtree(OUTDATA)
    os.makedirs(OUT)
    build_textures()
    copy_bdc_extra_block_textures()
    build_external_entity_textures()
    build_json()
    aliases()
    with open(os.path.join(PKG, 'build-report.json'), 'w') as f:
        json.dump(report, f, indent=1)
    print({k: len(v) for k, v in report.items()})

if __name__ == '__main__':
    main()
