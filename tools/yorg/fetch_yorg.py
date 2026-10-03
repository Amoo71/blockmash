#!/usr/bin/env python3
"""Fetch Yorg (Ya2, https://www.ya2.it) car models, textures and sounds for BlockMash's kart race track.

Yorg code is GPLv3; Ya2's art assets are CC BY-SA (4.0 per itch.io), some sounds are CC from OpenGameArt
(see LICENSES-Yorg.txt that is written next to the data). Panda3D .egg models are converted to a compact
JSON triangle mesh (Z-up -> Y-up); textures are scaled down. Output: assets/yorg/ (gitignored, fetched at
install time; safe to skip - the game then falls back to a simple box kart).
"""
import io, json, os, re, sys, time, urllib.request
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, 'assets', 'yorg')
CACHE = os.path.join(ROOT, '.cache', 'yorg')
ITEMS = os.path.join(ROOT, 'packages', 'free-mc-assets', 'minecraft-assets', 'data', '1.14.4', 'items')
REV = os.environ.get('YORG_REV', 'master')
RAW = f'https://raw.githubusercontent.com/cflavio/yorg/{REV}/'
CARS = ['kronos', 'themis', 'diones', 'iapeto', 'iperion', 'phoibe', 'rea', 'teia']
SFX = ['engine', 'brake', 'crash', 'crash_high_speed', 'lap', 'countdown', 'turbo', 'hit', 'landing']


def get(path):
    cp = os.path.join(CACHE, path)
    if os.path.exists(cp):
        return open(cp, 'rb').read()
    for i in range(5):
        try:
            with urllib.request.urlopen(RAW + path, timeout=60) as r:
                data = r.read()
            os.makedirs(os.path.dirname(cp), exist_ok=True)
            open(cp, 'wb').write(data)
            return data
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return None
            time.sleep(2 * (i + 1))
        except Exception:
            time.sleep(2 * (i + 1))
    raise RuntimeError('download failed: ' + path)


VERT = re.compile(r'<Vertex>\s*(\d+)\s*\{\s*([-\d.e+]+)\s+([-\d.e+]+)\s+([-\d.e+]+)(.*?)\n\s{4}\}', re.S)
UV = re.compile(r'<UV>\s*\{\s*([-\d.e+]+)\s+([-\d.e+]+)')
NRM = re.compile(r'<Normal>\s*\{\s*([-\d.e+]+)\s+([-\d.e+]+)\s+([-\d.e+]+)')
POLY = re.compile(r'<Polygon>\s*\{(.*?)<VertexRef>\s*\{([\d\s]+)<Ref>', re.S)


def egg_mesh(text):
    verts = {}
    for m in VERT.finditer(text):
        rest = m.group(5)
        uv = UV.search(rest); n = NRM.search(rest)
        x, y, z = float(m.group(2)), float(m.group(3)), float(m.group(4))
        verts[int(m.group(1))] = ((x, z, -y), (float(uv.group(1)), float(uv.group(2))) if uv else (0, 0),
                                  (float(n.group(1)), float(n.group(3)), -float(n.group(2))) if n else (0, 1, 0))
    keys = sorted(verts); remap = {k: i for i, k in enumerate(keys)}
    pos, uvs, nrm, idx = [], [], [], []
    for k in keys:
        p, t, n = verts[k]
        pos += [round(c, 4) for c in p]; uvs += [round(c, 4) for c in t]; nrm += [round(c, 3) for c in n]
    for m in POLY.finditer(text):
        refs = [remap[int(v)] for v in m.group(2).split() if int(v) in remap]
        for i in range(1, len(refs) - 1):
            idx += [refs[0], refs[i], refs[i + 1]]
    return {'pos': pos, 'uv': uvs, 'nrm': nrm, 'idx': idx}


def wheel_slots(text):
    out = []
    for m in re.finditer(r'<Group>\s*EmptyWheel[^{]*\{\s*<Transform>\s*\{\s*<Matrix4>\s*\{([^}]*)\}', text):
        v = [float(x) for x in m.group(1).split()]
        x, y, z = v[12], v[13], v[14]
        out.append([round(x, 4), round(z, 4), round(-y, 4)])
    return out


def main():
    try:
        from PIL import Image
    except ImportError:
        print('[yorg] Pillow missing - skipping'); return 0
    os.makedirs(os.path.join(OUT, 'sounds'), exist_ok=True)
    manifest = {'source': RAW, 'cars': {}, 'sounds': []}
    try:
        for car in CARS:
            base = f'assets/cars/{car}/'
            d = os.path.join(OUT, 'cars', car); os.makedirs(d, exist_ok=True)
            body = egg_mesh(get(base + 'models/car.egg').decode('utf8', 'replace'))
            wf = get(base + 'models/wheel.egg') or get(base + 'models/wheelfront.egg')
            wr = get(base + 'models/wheelrear.egg') or wf
            wheel = egg_mesh(wf.decode('utf8', 'replace')); wheel_r = egg_mesh(wr.decode('utf8', 'replace'))
            slots = wheel_slots(get(base + 'models/capsule.egg').decode('utf8', 'replace'))
            phys = json.loads(get(base + 'phys.json'))
            json.dump({'body': body, 'wheel': wheel, 'wheelRear': wheel_r, 'slots': slots}, open(os.path.join(d, 'mesh.json'), 'w'), separators=(',', ':'))
            for name, out in (('TEXCar.jpg', 'car.jpg'), ('TEXWheel.jpg', 'wheel.jpg')):
                im = Image.open(io.BytesIO(get(base + 'models/tex/' + name))).convert('RGB')
                im.thumbnail((512, 512)); im.save(os.path.join(d, out), quality=85)
            sel = Image.open(io.BytesIO(get(base + 'images/car_sel.png'))).convert('RGBA')
            sel.thumbnail((256, 256)); sel.save(os.path.join(d, 'sel.png'))
            manifest['cars'][car] = {'maxSpeed': phys.get('max_speed'), 'acc': phys.get('engine_acc_frc'), 'mass': phys.get('mass'),
                                     'steering': phys.get('steering'), 'color': phys.get('color'), 'tris': len(body['idx']) // 3}
            print(f'[yorg] {car}: {len(body["idx"]) // 3} tris, wheels {len(slots)}')
        for s in SFX:
            data = get(f'assets/sfx/{s}.ogg')
            if data: open(os.path.join(OUT, 'sounds', s + '.ogg'), 'wb').write(data); manifest['sounds'].append(s)
        lic = (get('license.txt') or b'').decode() + '\n\n' + (get('licenses/licenses.txt') or b'').decode()
        open(os.path.join(OUT, 'LICENSES-Yorg.txt'), 'w').write(
            'Yorg (c) Ya2 - https://www.ya2.it - https://github.com/cflavio/yorg\n'
            'Car models/textures: CC BY-SA (Ya2). Converted to JSON meshes / resized by BlockMash tools/yorg/fetch_yorg.py;\n'
            'the converted files remain under CC BY-SA.\n\n' + lic)
        if os.path.isdir(ITEMS):
            im = Image.open(os.path.join(OUT, 'cars', 'kronos', 'sel.png')).convert('RGBA')
            bb = im.getbbox(); im = im.crop(bb) if bb else im
            side = max(im.size); sq = Image.new('RGBA', (side, side)); sq.paste(im, ((side - im.size[0]) // 2, (side - im.size[1]) // 2))
            sq.resize((64, 64), Image.LANCZOS).save(os.path.join(ITEMS, 'knowledge_book.png'))
        json.dump(manifest, open(os.path.join(OUT, 'manifest.json'), 'w'), indent=1)
    except Exception as e:
        print('[yorg] could not fetch Yorg assets (%s) - karts fall back to simple boxes' % e)
        return 0
    return 0


if __name__ == '__main__':
    sys.exit(main())
