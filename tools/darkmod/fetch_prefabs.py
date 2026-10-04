#!/usr/bin/env python3
"""BlockMash: converts real The Dark Mod building prefabs (tdm_prefabs01.pk4, CC BY-NC-SA 3.0) into
polygon meshes for the Dark Mod quarter. Only the needed pk4 members are downloaded (HTTP range requests
via fetch_darkmod.member). Doom 3 brushDef3 brushes are clipped into convex polygons, patchDef2/3
bezier patches are tessellated, materials are resolved through the TDM .mtr declarations to their
diffuse DDS images. Collision is voxelised from the brush solids at block resolution.
Output: assets/darkmod/prefabs/{mesh.bin, mesh.json, tex/*.jpg}"""
import io, json, math, os, re, struct, sys
sys.path.insert(0, os.path.dirname(__file__))
import fetch_darkmod as F
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
OUT = os.path.join(ROOT, 'assets', 'darkmod', 'prefabs')
PFX = 'tdm_prefabs01.pk4||prefabs/architecture/buildings, facades/'
PREFABS = [f'house_{i:02d}' for i in range(1, 11)] + ['towers/tower_round_brick', 'towers/tower_octagonal_blocks']
S = 1 / 40.0  # Doom units -> blocks (TDM: 1 unit ~ 2.5 cm, doors 96-112 units ~ 2.4-2.8 m)
SKIP = re.compile(r'^textures/(common|editor)/|visportal|caulk|nodraw|clip|trigger|shadow', re.I)

def tokens(s):
    return re.findall(r'"[^"]*"|\(|\)|\{|\}|[^\s(){}"]+', re.sub(r'//[^\n]*', '', s))

def parse_map(text):
    t = tokens(text); i = 0; ents = []
    if t[0] == 'Version': i = 2
    def num():
        nonlocal i; v = float(t[i]); i += 1; return v
    def expect(x):
        nonlocal i; assert t[i] == x, (t[i], x, i); i += 1
    while i < len(t):
        expect('{'); kv = {}; prims = []
        while t[i] != '}':
            if t[i].startswith('"'):
                kv[t[i][1:-1]] = t[i + 1][1:-1]; i += 2; continue
            expect('{'); kind = t[i]; i += 1; expect('{')
            if kind == 'brushDef3':
                faces = []
                while t[i] != '}':
                    expect('('); pl = [num() for _ in range(4)]; expect(')')
                    expect('('); expect('('); m0 = [num() for _ in range(3)]; expect(')'); expect('('); m1 = [num() for _ in range(3)]; expect(')'); expect(')')
                    mat = t[i][1:-1]; i += 1; i += 3
                    faces.append((pl, m0, m1, mat))
                expect('}'); prims.append(('brush', faces))
            elif kind in ('patchDef2', 'patchDef3'):
                mat = t[i][1:-1]; i += 1
                expect('('); hdr = []
                while t[i] != ')': hdr.append(num())
                expect(')'); w, h = int(hdr[0]), int(hdr[1]); expect('(')
                grid = []
                for _ in range(w):
                    expect('('); row = []
                    for _ in range(h):
                        expect('('); row.append([num() for _ in range(5)]); expect(')')
                    expect(')'); grid.append(row)
                expect(')'); expect('}'); prims.append(('patch', (mat, grid, kind == 'patchDef3', hdr)))
            else:
                depth = 1
                while depth: depth += {'{': 1, '}': -1}.get(t[i], 0); i += 1
                i -= 1
            expect('}')
        expect('}'); ents.append((kv, prims))
    return ents

def sub(a, b): return [a[0] - b[0], a[1] - b[1], a[2] - b[2]]
def dot(a, b): return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
def cross(a, b): return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]
def norm(a):
    l = math.sqrt(dot(a, a)) or 1; return [a[0] / l, a[1] / l, a[2] / l]

def axis_base(n):
    n = [0 if abs(c) < 1e-6 else c for c in n]
    ry = -math.atan2(n[2], math.sqrt(n[0] ** 2 + n[1] ** 2)); rz = math.atan2(n[1], n[0])
    return [-math.sin(rz), math.cos(rz), 0], [-math.sin(ry) * math.cos(rz), -math.sin(ry) * math.sin(rz), -math.cos(ry)]

def brush_polys(faces):
    out = []
    for fi, (pl, m0, m1, mat) in enumerate(faces):
        n = pl[:3]; d = pl[3]
        p0 = [-d * n[0], -d * n[1], -d * n[2]]
        a = [1, 0, 0] if abs(n[0]) < 0.9 else [0, 1, 0]
        u = norm(cross(n, a)); v = cross(n, u); B = 65536
        poly = [[p0[k] + (u[k] * sx + v[k] * sy) * B for k in range(3)] for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
        for fj, (q, *_r) in enumerate(faces):
            if fj == fi or not poly: continue
            qn = q[:3]; qd = q[3]; np_ = []
            for k in range(len(poly)):
                A = poly[k]; Bp = poly[(k + 1) % len(poly)]
                da = dot(qn, A) + qd; db = dot(qn, Bp) + qd
                if da <= 0.01: np_.append(A)
                if (da > 0.01) != (db > 0.01):
                    tt = da / (da - db); np_.append([A[c] + (Bp[c] - A[c]) * tt for c in range(3)])
            poly = np_
        if len(poly) >= 3: out.append((poly, n, m0, m1, mat))
    return out

def bez(grid, sub_n=6):
    W = len(grid); H = len(grid[0]); tris = []
    def q(a, b, c, t): return [(1 - t) ** 2 * a[k] + 2 * (1 - t) * t * b[k] + t * t * c[k] for k in range(5)]
    for i in range(0, W - 2, 2):
        for j in range(0, H - 2, 2):
            pts = [[None] * (sub_n + 1) for _ in range(sub_n + 1)]
            for a in range(sub_n + 1):
                cols = [q(grid[i][j + k], grid[i + 1][j + k], grid[i + 2][j + k], a / sub_n) for k in range(3)]
                for b in range(sub_n + 1): pts[a][b] = q(cols[0], cols[1], cols[2], b / sub_n)
            for a in range(sub_n):
                for b in range(sub_n):
                    p00, p10, p01, p11 = pts[a][b], pts[a + 1][b], pts[a][b + 1], pts[a + 1][b + 1]
                    tris += [(p00, p10, p11), (p00, p11, p01)]
    return tris

class Mats:
    def __init__(self, entries):
        self.e = entries; self.decl = {}; self.dds = {k.split('||')[1][4:-4].lower(): k for k in entries if '||dds/' in k}
        for k in entries:
            if k.endswith('.mtr') and k.startswith('tdm_'):
                try: txt = F.member(entries, k).decode('latin1')
                except Exception: continue
                for m in re.finditer(r'(?m)^\s*([\w/\.-]+)\s*\n?\s*\{', txt):
                    name = m.group(1).lower(); depth = 0; j = m.end() - 1
                    while j < len(txt):
                        depth += {'{': 1, '}': -1}.get(txt[j], 0); j += 1
                        if depth == 0: break
                    self.decl.setdefault(name, txt[m.end():j])
    def image(self, mat):
        m = mat.lower(); body = self.decl.get(m, '')
        cands = []
        for r in (r'diffusemap\s+([^\s}]+)', r'blend\s+diffusemap[^}]*?map\s+([^\s}]+)', r'\bmap\s+([^\s}]+)', r'qer_editorimage\s+([^\s}]+)'):
            cands += re.findall(r, body, re.I)
        cands.append(m)
        for c in cands:
            c = re.sub(r'\.(tga|dds|jpg|png)$', '', c.strip('"').lower())
            if c.startswith('_'): continue
            for k in (c, c + '_d', c + '_ed'):
                if k in self.dds: return self.dds[k]
        return None
    def glow(self, mat):
        body = self.decl.get(mat.lower(), '')
        return bool(re.search(r'blend\s+add|_lit|selflit|brightlit|barelylit', mat + body, re.I)) and 'window' in mat.lower()

def main():
    entries = F.manifest(); M = Mats(entries)
    os.makedirs(os.path.join(OUT, 'tex'), exist_ok=True)
    V = []; I = []; prefabs = []; texdone = {}
    for name in PREFABS:
        try: ents = parse_map(F.member(entries, PFX + name + '.pfb').decode('latin1'))
        except Exception as ex: print('darkmod prefab', name, ex); continue
        bymat = {}; solids = []
        for kv, prims in ents:
            o = [float(x) for x in kv.get('origin', '0 0 0').split()]
            rot = [float(x) for x in kv.get('rotation', '1 0 0 0 1 0 0 0 1').split()]
            local = kv.get('classname') != 'worldspawn'
            def X(p):
                if not local: return p
                r = rot; x, y, z = p
                return [o[0] + r[0] * x + r[3] * y + r[6] * z, o[1] + r[1] * x + r[4] * y + r[7] * z, o[2] + r[2] * x + r[5] * y + r[8] * z]
            for kind, data in prims:
                if kind == 'brush':
                    polys = brush_polys(data)
                    if not polys: continue
                    if not all(re.search(r'visportal|trigger|aasobstacle', f[3], re.I) for f in data):
                        solids.append([X(p) for poly in polys for p in poly[0]])
                    for poly, n, m0, m1, mat in polys:
                        if SKIP.search(mat): continue
                        S_, T_ = axis_base(n)
                        pts = [(X(p), (m0[0] * dot(p, S_) + m0[1] * dot(p, T_) + m0[2], m1[0] * dot(p, S_) + m1[1] * dot(p, T_) + m1[2])) for p in poly]
                        tl = bymat.setdefault(mat, [])
                        for k in range(1, len(pts) - 1): tl.append((pts[0], pts[k], pts[k + 1]))
                else:
                    mat, grid, _, _ = data
                    if SKIP.search(mat): continue
                    tl = bymat.setdefault(mat, [])
                    for a, b, c in bez(grid): tl.append(tuple((X(p[:3]), (p[3], p[4])) for p in (a, b, c)))
        allp = [p for tl in bymat.values() for tri in tl for p, _ in tri]
        if not allp: continue
        lo = [min(p[k] for p in allp) for k in range(3)]; hi = [max(p[k] for p in allp) for k in range(3)]
        # Doom (x, y, z-up) -> blocks (X = x, Y = z, Z = -y), origin at the footprint corner / lowest point
        def W(p): return [(p[0] - lo[0]) * S, (p[2] - lo[2]) * S, (hi[1] - p[1]) * S]
        size = [(hi[0] - lo[0]) * S, (hi[2] - lo[2]) * S, (hi[1] - lo[1]) * S]
        v0 = len(V) // 5; groups = []
        for mat, tl in sorted(bymat.items()):
            key = M.image(mat)
            if not key: print('darkmod prefab', name, 'no image for', mat); continue
            tex = re.sub(r'[^a-z0-9_]+', '_', key.split('||')[1][4:-4].replace('textures/darkmod/', '').lower()) + '.jpg'
            if tex not in texdone:
                try:
                    im = Image.open(io.BytesIO(F.member(entries, key))).convert('RGBA')
                    sz = min(512, max(im.size))
                    im.convert('RGB').resize((sz, sz), Image.LANCZOS).save(os.path.join(OUT, 'tex', tex), quality=85)
                    texdone[tex] = True
                except Exception as ex: print('darkmod prefab tex', key, ex); texdone[tex] = False
            if not texdone[tex]: continue
            start = len(I)
            for tri in tl:
                base = len(V) // 5 - v0
                for p, uv in tri: V.extend(W(p) + [uv[0], uv[1]])
                I.extend([v0 + base, v0 + base + 1, v0 + base + 2])  # clipped polygons wind CCW around the outward normal
            groups.append({'tex': tex, 'start': start, 'count': len(I) - start, 'glow': M.glow(mat), 'mat': mat})
        # collision voxels: cells overlapped (by > 0.25 block) by a solid brush
        cols = {}
        for pts in solids:
            wp = [W(p) for p in pts]
            a = [min(p[k] for p in wp) for k in range(3)]; b = [max(p[k] for p in wp) for k in range(3)]
            for x in range(math.floor(a[0] + 0.25), math.ceil(b[0] - 0.25)):
                for z in range(math.floor(a[2] + 0.25), math.ceil(b[2] - 0.25)):
                    y0 = math.floor(a[1] + 0.25); y1 = math.ceil(b[1] - 0.25)
                    if y1 > y0: cols.setdefault(f'{x},{z}', []).append([y0, y1])
        for k, rs in cols.items():
            rs.sort(); m = []
            for r in rs:
                if m and r[0] <= m[-1][1]: m[-1][1] = max(m[-1][1], r[1])
                else: m.append(r)
            cols[k] = m
        prefabs.append({'name': name.split('/')[-1], 'v0': v0, 'nv': len(V) // 5 - v0, 'groups': groups, 'size': [round(c, 3) for c in size], 'cols': cols, 'tris': sum(g['count'] for g in groups) // 3})
        print('darkmod prefab', name, 'size %.1f x %.1f x %.1f blocks' % tuple(size), prefabs[-1]['tris'], 'tris')
    open(os.path.join(OUT, 'mesh.bin'), 'wb').write(struct.pack(f'<{len(V)}f', *V) + struct.pack(f'<{len(I)}I', *I))
    json.dump({'scale': S, 'verts': len(V) // 5, 'indices': len(I), 'prefabs': prefabs, 'source': 'The Dark Mod 2.x tdm_prefabs01.pk4 (CC BY-NC-SA 3.0)'}, open(os.path.join(OUT, 'mesh.json'), 'w'))

if __name__ == '__main__':
    if not os.environ.get('BLOCKMASH_NO_DARKMOD'): main()
