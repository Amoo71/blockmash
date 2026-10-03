#!/usr/bin/env python3
"""Fails if any file in dist/ (or the free assets package) is byte- or pixel-identical to a
Mojang asset. Reference set: the vanilla minecraft-assets package (mc-assets-reference),
upstream's Mojang-derived client files (from the import commit) and minecraft-data's en_us table."""
import hashlib, io, json, os, subprocess, sys, base64
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
REF = os.path.join(ROOT, 'node_modules', 'mc-assets-reference', 'minecraft-assets', 'data')
TARGETS = sys.argv[1:] or [os.path.join(ROOT, 'dist')]
CACHE = os.path.join(ROOT, '.cache', 'mojang-hashes.json')
IMPORT_COMMIT_FILES = ['assets/mojangles.ttf', 'assets/minecraftia.woff', 'assets/invsprite.png', 'assets/generic_91.png',
  'assets/generic_92.png', 'assets/generic_93.png', 'assets/generic_94.png', 'assets/generic_95.png', 'assets/button_click.mp3',
  'assets/extra-textures/gui.png', 'assets/extra-textures/edition.png', 'assets/storybook-bg.jpg'] + [f'assets/extra-textures/background/panorama_{i}.png' for i in range(6)]

def pix_hash(data):
    try:
        im = Image.open(io.BytesIO(data)); im.load()
        if im.width * im.height < 16: return None   # 1-4 px images (blank/solid) are not meaningful
        a = im.convert('RGBA')
        if a.getextrema()[3] == (0, 0): return None   # fully transparent
        return 'px:' + hashlib.md5(a.tobytes() + bytes(str(a.size), 'ascii')).hexdigest()
    except Exception:
        return None

def hashes_of(data):
    out = {'b:' + hashlib.md5(data).hexdigest()}
    p = pix_hash(data)
    if p: out.add(p)
    return out

def reference():
    if os.path.exists(CACHE):
        return set(json.load(open(CACHE)))
    ref = set()
    for root, _, fs in os.walk(REF):
        for f in fs:
            if f.endswith(('.png', '.ttf', '.ogg', '.mp3')):
                ref |= hashes_of(open(os.path.join(root, f), 'rb').read())
    # hashes of the Mojang-derived files upstream bundled (fonts, invsprite, GUI sheets, panorama,
    # base64 entity textures); the files themselves were removed from this repository
    ref |= set(json.load(open(os.path.join(os.path.dirname(__file__), 'upstream-removed-hashes.json'))))
    os.makedirs(os.path.dirname(CACHE), exist_ok=True)
    json.dump(sorted(ref), open(CACHE, 'w'))
    return ref

def main():
    ref = reference()
    lang = json.load(open(os.path.join(ROOT, 'node_modules', 'minecraft-data', 'minecraft-data', 'data', 'pc', '1.14', 'language.json'))) if os.path.exists(os.path.join(ROOT, 'node_modules', 'minecraft-data', 'minecraft-data', 'data', 'pc', '1.14', 'language.json')) else {}
    probe = [v for k, v in lang.items() if k.startswith(('menu.', 'options.', 'advancements.')) and len(v) > 25][:200]
    bad, checked = [], 0
    for t in TARGETS:
        for root, _, fs in os.walk(t, followlinks=False):
            for f in fs:
                p = os.path.join(root, f)
                if os.path.islink(p): continue
                data = open(p, 'rb').read()
                checked += 1
                if hashes_of(data) & ref:
                    bad.append(os.path.relpath(p, ROOT))
                if f.endswith(('.js', '.json')) and probe:
                    txt = data.decode('utf8', 'ignore')
                    hits = sum(1 for s in probe if json.dumps(s)[1:-1] in txt)
                    if hits > 20: bad.append(os.path.relpath(p, ROOT) + f' (contains {hits} Mojang en_us strings)')
    print(f'verify_no_mojang: checked {checked} files against {len(ref)} reference hashes')
    if bad:
        print('MOJANG ASSETS FOUND:'); [print('  ' + b) for b in bad]
        sys.exit(1)
    print('OK: no Mojang asset found')

if __name__ == '__main__':
    main()
