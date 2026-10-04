"""Read-only access to the Duke Nukem 3D shareware data (unmodified 3dduke13.zip -> DN3DSW13.SHR -> DUKE3D.GRP).
Own code (MIT). Formats per Ken Silverman's public BUILD documentation."""
import io, struct, zipfile, hashlib
from PIL import Image

SHAREWARE_MD5 = '04e4ca70b8a2d59ed56c451c5c1d5d39'

def open_grp(zip_path):
    data = open(zip_path, 'rb').read()
    if hashlib.md5(data).hexdigest() != SHAREWARE_MD5:
        raise SystemExit(f'{zip_path}: not the unmodified 3dduke13.zip (md5 mismatch)')
    outer = zipfile.ZipFile(io.BytesIO(data))
    shr = zipfile.ZipFile(io.BytesIO(outer.read('DN3DSW13.SHR')))
    grp = shr.read('DUKE3D.GRP')
    assert grp[:12] == b'KenSilverman'
    n = struct.unpack_from('<I', grp, 12)[0]
    files = {}
    off = 16 + n * 16
    for i in range(n):
        name = grp[16 + i * 16:28 + i * 16].rstrip(b'\0').decode('ascii')
        size = struct.unpack_from('<I', grp, 28 + i * 16)[0]
        files[name] = grp[off:off + size]
        off += size
    return files, shr

def palette(files):
    p = files['PALETTE.DAT'][:768]
    return [min(255, v * 4 + (v >> 4)) for v in p]

def tiles(files):
    out = {}
    for name in sorted(k for k in files if k.startswith('TILES') and k.endswith('.ART')):
        d = files[name]
        ver, _, start, end = struct.unpack_from('<4i', d, 0)
        cnt = end - start + 1
        sx = struct.unpack_from(f'<{cnt}h', d, 16)
        sy = struct.unpack_from(f'<{cnt}h', d, 16 + cnt * 2)
        anm = struct.unpack_from(f'<{cnt}I', d, 16 + cnt * 4)
        off = 16 + cnt * 8
        for i in range(cnt):
            w, h = sx[i], sy[i]
            if w > 0 and h > 0:
                out[start + i] = (w, h, anm[i], d[off:off + w * h])
                off += w * h
    return out

def fullbright(files):
    """palette indices the Build shade tables never darken (Duke's fullbright neon/lamp/window colours)"""
    d = files['PALETTE.DAT']; pal = palette(files)
    n = struct.unpack_from('<h', d, 768)[0]; lk = d[770:770 + n * 256]
    dark = (n - 2) * 256
    return {i for i in range(255) if lk[dark + i] == i and sum(pal[i * 3:i * 3 + 3]) > 120}

def tile_image(t, pal, glow=None):
    """RGBA image; fullbright pixels get alpha 250 (emissive mask for the renderer), opaque 255, transparent 0"""
    w, h, anm, px = t
    img = Image.new('RGBA', (w, h))
    pp = img.load()
    for x in range(w):
        col = px[x * h:(x + 1) * h]
        for y in range(h):
            c = col[y]
            if c != 255:
                pp[x, y] = (pal[c * 3], pal[c * 3 + 1], pal[c * 3 + 2], 250 if glow and c in glow else 255)
    return img

def tile_offset(anm):
    # picanm: bits 8-15 x offset, 16-23 y offset (signed)
    xo = (anm >> 8) & 0xff; yo = (anm >> 16) & 0xff
    return (xo - 256 if xo > 127 else xo, yo - 256 if yo > 127 else yo)
