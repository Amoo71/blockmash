#!/usr/bin/env python3
"""Fetch CC0 terrain textures (Poly Haven, https://polyhaven.com, CC0 1.0) for the smooth surface terrain.
Output: assets/surface/*.jpg (512 px, gitignored). Safe to skip: the terrain then uses vertex colours only."""
import io, json, os, sys, time, urllib.request
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, 'assets', 'surface')
TEX = {'grass': 'aerial_grass_rock', 'rock': 'rocky_terrain_02', 'sand': 'aerial_beach_01', 'snow': 'snow_02', 'dirt': 'brown_mud_leaves_01'}
URL = 'https://dl.polyhaven.org/file/ph-assets/Textures/jpg/1k/{0}/{0}_diff_1k.jpg'

def main():
    try:
        from PIL import Image
    except ImportError:
        print('[surface] Pillow missing - skipping'); return 0
    os.makedirs(OUT, exist_ok=True)
    man = {'source': 'Poly Haven (polyhaven.com), CC0 1.0', 'textures': {}}
    for key, name in TEX.items():
        dst = os.path.join(OUT, key + '.jpg')
        if not os.path.exists(dst):
            for i in range(4):
                try:
                    data = urllib.request.urlopen(urllib.request.Request(URL.format(name), headers={'User-Agent': 'BlockMash/1.0'}), timeout=60).read(); break
                except Exception as e:
                    if i == 3: print('[surface] failed', name, e); data = None
                    time.sleep(2)
            if not data: continue
            im = Image.open(io.BytesIO(data)).convert('RGB').resize((512, 512), Image.LANCZOS)
            im.save(dst, quality=85)
        man['textures'][key] = name
    json.dump(man, open(os.path.join(OUT, 'manifest.json'), 'w'), indent=1)
    print('[surface] CC0 textures:', ', '.join(man['textures']))
    return 0

if __name__ == '__main__':
    sys.exit(main())
