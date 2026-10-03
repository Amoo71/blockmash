#!/usr/bin/env python3
"""BlockMash UI assets: regenerates every client-bundled image/font/sound that upstream
shipped as Mojang-derived files. Run after build_free_assets.py and gen-textures.
Outputs into assets/ (committed only where the source license allows; see ASSETS_AUDIT.md)."""
import json, os, shutil, subprocess
from PIL import Image, ImageDraw, ImageFont, ImageEnhance
import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
FREE = os.path.join(ROOT, 'packages', 'free-mc-assets', 'minecraft-assets', 'data', '1.14.4')
BDC = os.path.join(ROOT, '.cache', 'purebdcraft', 'assets', 'minecraft', 'textures')
PUB = os.path.join(ROOT, 'prismarine-viewer', 'public')
ASSETS = os.path.join(ROOT, 'assets')
CACHE = os.path.join(ROOT, '.cache')
FONT = os.path.join(ASSETS, 'fonts', 'PixelifySans.ttf')
KENNEY = os.path.join(CACHE, 'kenney')

def font(sz):
    f = ImageFont.truetype(FONT, sz)
    try: f.set_variation_by_name('Bold')
    except Exception: pass
    return f

# ------------------------------------------------------------------ invsprite (iso block icons)
def find_coeffs(dst, src):
    m = []
    for (x, y), (X, Y) in zip(dst, src):
        m.append([x, y, 1, 0, 0, 0, -X * x, -X * y])
        m.append([0, 0, 0, x, y, 1, -Y * x, -Y * y])
    A = np.array(m, dtype=float); B = np.array(src, dtype=float).reshape(8)
    return np.linalg.solve(A, B).tolist()

def face_img(atlas, tex, n):
    W, H = atlas.size
    x, y, w, h = tex['u'] * W, tex['v'] * H, tex['su'] * W, tex['sv'] * H
    x0, x1 = sorted((x, x + w)); y0, y1 = sorted((y, y + h))
    return atlas.crop((int(round(x0)), int(round(y0)), int(round(x1)), int(round(y1)))).resize((n, n), Image.LANCZOS)

GRASS = (124, 189, 107); FOLIAGE = (72, 181, 24)
def tint(im, color):
    a = np.asarray(im).astype(float)
    a[:, :, :3] *= np.array(color) / 255.0
    return Image.fromarray(a.clip(0, 255).astype(np.uint8), 'RGBA')

def iso_icon(atlas, faces, S=32):
    out = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    n = 64
    h = S / 2; q = S / 4
    quads = {
        'up': [(0, q), (h, 0), (S, q), (h, h)],
        'left': [(0, q), (h, h), (h, S), (0, S - q)],
        'right': [(h, h), (S, q), (S, S - q), (h, S)],
    }
    shade = {'up': 1.0, 'left': 0.8, 'right': 0.62}
    for side in ('left', 'right', 'up'):
        f = faces.get(side)
        if not f: continue
        im = face_img(atlas, f['texture'], n)
        if 'tintindex' in f: im = tint(im, f.get('_tint', GRASS))
        im = ImageEnhance.Brightness(im).enhance(shade[side])
        src = [(0, 0), (n, 0), (n, n), (0, n)]
        if side == 'up':
            src = [(0, n), (0, 0), (n, 0), (n, n)]
        coeffs = find_coeffs(quads[side], src)
        layer = im.transform((S, S), Image.PERSPECTIVE, coeffs, Image.BILINEAR)
        out.alpha_composite(layer)
    return out

def build_invsprite():
    sprite = json.load(open(os.path.join(ROOT, 'src', 'invsprite.json')))
    states = json.load(open(os.path.join(PUB, 'blocksStates', '1.14.4.json')))
    atlas = Image.open(os.path.join(PUB, 'textures', '1.14.4.png')).convert('RGBA')
    W = max(v['x'] for v in sprite.values()) + 32
    H = max(v['y'] for v in sprite.values()) + 32
    sheet = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    stats = {'iso': 0, 'item': 0, 'empty': 0}
    for name, pos in sprite.items():
        icon = None
        st = states.get(name)
        model = None
        if st and st.get('variants'):
            v = list(st['variants'].values())[0]
            model = (v[0] if isinstance(v, list) else v).get('model')
        elif st and st.get('multipart'):
            a = st['multipart'][0]['apply']
            model = (a[0] if isinstance(a, list) else a).get('model')
        item_p = os.path.join(FREE, 'items', name + '.png')
        if os.path.exists(item_p) and (not model or len(model.get('elements', [])) != 1):
            icon = Image.open(item_p).convert('RGBA').resize((32, 32), Image.LANCZOS); stats['item'] += 1
        elif model and model.get('elements'):
            el = model['elements'][0]
            fc = el['faces']
            faces = {'up': fc.get('up'), 'left': fc.get('south') or fc.get('west'), 'right': fc.get('east') or fc.get('north')}
            for k in faces:
                if faces[k] and 'leaves' in name: faces[k] = {**faces[k], '_tint': FOLIAGE}
            if any(faces.values()):
                icon = iso_icon(atlas, {k: v for k, v in faces.items() if v}); stats['iso'] += 1
        if icon is None:
            stats['empty'] += 1; continue
        sheet.paste(icon, (pos['x'], pos['y']))
    sheet.save(os.path.join(ASSETS, 'invsprite.png'), optimize=True)
    print('invsprite', stats)

# ------------------------------------------------------------------ chest GUIs 9xN
def build_generic():
    g = Image.open(os.path.join(FREE, 'gui', 'container', 'generic_54.png')).convert('RGBA')
    for rows in range(1, 6):
        out = Image.new('RGBA', (256, 256), (0, 0, 0, 0))
        top = g.crop((0, 0, 176, 17 + rows * 18))
        out.paste(top, (0, 0))
        out.paste(g.crop((0, 125, 176, 222)), (0, 17 + rows * 18))
        out.save(os.path.join(ASSETS, f'generic_9{rows}.png'))

# ------------------------------------------------------------------ menu/hud bits
def build_gui_png():
    """mobile pause/chat buttons (used at 202,66 and 202,84, 14x14) - own drawing (CC0)"""
    im = Image.new('RGBA', (256, 256), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    for (x, y) in [(202, 66), (202, 84)]:
        d.rectangle((x, y, x + 13, y + 13), fill=(30, 22, 14, 220), outline=(196, 160, 96, 255))
    d.rectangle((206, 69, 207, 76), fill=(240, 230, 210, 255)); d.rectangle((210, 69, 211, 76), fill=(240, 230, 210, 255))
    d.rounded_rectangle((205, 87, 213, 93), 2, fill=(240, 230, 210, 255)); d.polygon([(206, 93), (209, 93), (206, 96)], fill=(240, 230, 210, 255))
    im.save(os.path.join(ASSETS, 'extra-textures', 'gui.png'))

def outlined(d, xy, text, f, fill, outline=(20, 12, 6, 255), w=2):
    x, y = xy
    for dx in range(-w, w + 1):
        for dy in range(-w, w + 1):
            if dx or dy: d.text((x + dx, y + dy), text, font=f, fill=outline)
    d.text((x, y), text, font=f, fill=fill)

def build_logo():
    """BlockMash title: own lettering filled with the PureBDcraft cobblestone/planks textures."""
    W, H = 620, 120
    f = font(96)
    mask = Image.new('L', (W, H), 0)
    ImageDraw.Draw(mask).text((W // 2, H // 2), 'BLOCKMASH', font=f, anchor='mm', fill=255)
    fill = Image.new('RGBA', (W, H))
    stone = Image.open(os.path.join(FREE, 'blocks', 'cobblestone.png')).convert('RGBA').resize((60, 60), Image.LANCZOS)
    for x in range(0, W, 60):
        for y in range(0, H, 60): fill.paste(stone, (x, y))
    out = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    m = np.asarray(mask)
    shadow = Image.fromarray(np.where(m > 0, 255, 0).astype(np.uint8))
    from PIL import ImageFilter
    edge = shadow.filter(ImageFilter.MaxFilter(9))
    out.paste((25, 16, 8, 255), (0, 0), edge)
    out.paste(fill, (0, 0), mask)
    hl = Image.new('RGBA', (W, H), (255, 255, 255, 0))
    top = np.zeros((H, W), np.uint8); top[: H // 2] = 50
    out.alpha_composite(Image.composite(Image.new('RGBA', (W, H), (255, 240, 200, 255)), hl, Image.fromarray((top * (m > 0)).astype(np.uint8))))
    os.makedirs(os.path.join(ASSETS, 'extra-textures'), exist_ok=True)
    out.save(os.path.join(ASSETS, 'extra-textures', 'logo.png'))
    # "MASHUP EDITION" ribbon (128x16 sheet, 88x14 visible like upstream edition.png)
    ed = Image.new('RGBA', (600, 80), (0, 0, 0, 0))
    dd = ImageDraw.Draw(ed)
    outlined(dd, (10, 10), 'MASHUP EDITION', font(44), (255, 214, 64, 255), w=3)
    ed = ed.crop(ed.getbbox())
    ed = ed.resize((min(252, round(ed.width * 30 / ed.height)), 30), Image.LANCZOS)
    e2 = Image.new('RGBA', (256, 32), (0, 0, 0, 0)); e2.paste(ed, ((256 - ed.width) // 2, 1))
    e2.save(os.path.join(ASSETS, 'extra-textures', 'edition.png'))

def build_panorama():
    for i in range(6):
        src = os.path.join(BDC, 'gui', 'title', 'background', f'panorama_{i}.png')
        dst = os.path.join(ASSETS, 'extra-textures', 'background', f'panorama_{i}.png')
        Image.open(src).convert('RGB').save(dst, optimize=True)

# ------------------------------------------------------------------ sounds
def build_click():
    src = os.path.join(KENNEY, 'kenney_interface-sounds', 'Audio', 'click_002.ogg')
    if not os.path.exists(src):
        import glob
        src = glob.glob(os.path.join(KENNEY, '**', 'click_002.ogg'), recursive=True)[0]
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', src, '-ac', '1', '-b:a', '64k', os.path.join(ASSETS, 'button_click.mp3')], check=True)

def build_world_preview():
    """default world icon: iso grass block from our invsprite, on a dark tile (own composition)"""
    sprite = json.load(open(os.path.join(ROOT, 'src', 'invsprite.json')))
    inv = Image.open(os.path.join(ASSETS, 'invsprite.png'))
    p = sprite['grass_block']
    icon = inv.crop((p['x'], p['y'], p['x'] + 32, p['y'] + 32)).resize((96, 96), Image.NEAREST)
    out = Image.new('RGBA', (128, 128), (24, 18, 12, 255))
    out.alpha_composite(icon, (16, 16))
    out.save(os.path.join(ASSETS, 'world_preview.png'))

if __name__ == '__main__':
    build_invsprite()
    build_world_preview()
    build_generic()
    build_gui_png()
    build_logo()
    build_panorama()
    build_click()
    print('ui assets done')
