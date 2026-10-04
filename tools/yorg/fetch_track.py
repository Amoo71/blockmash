#!/usr/bin/env python3
"""BlockMash: fetch real Yorg race tracks (Ya2, CC BY-SA) and convert them for the polygon surface.
Per track -> assets/yorg/tracks/<name>/:
  mesh.bin   float32 [x y z u v] vertices + uint32 indices, Y-up, track-local metres (Panda Z-up converted)
  mesh.json  texture groups, bbox, waypoint loop (AI racing line), start grid, goal
  ground.bin heightfield (1 m cells over the bbox): float32 surface height (road/offroad) + uint8 kind
  tex/*.jpg  textures (resized)
Track geometry: track.egg (minus skydome) + every prop instanced by its Empty* placeholders. Collision:
collision.egg Road*/Offroad* surfaces and Wall* meshes. Own code, MIT; the converted data stays CC BY-SA."""
import io, json, math, os, struct, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from egg import Egg, IDENT, mat_mul
from fetch_yorg import get, OUT

TRACKS = os.environ.get('YORG_TRACKS', 'orlando').split(',')
MAXTEX = 512


def load_egg(path):
    data = get(path)
    return Egg(data.decode('utf8', 'replace')) if data else None


def convert(name):
    from PIL import Image
    base = f'assets/tracks/{name}/models/'
    trk = load_egg(base + 'track.egg'); col = load_egg(base + 'collision.egg')
    if not trk or not col: print('[yorg] track missing', name); return None
    d = os.path.join(OUT, 'tracks', name); os.makedirs(os.path.join(d, 'tex'), exist_ok=True)
    # ---- collision first: bbox of the drivable area
    surf = []; walls = []
    for path, m, nd in col.groups():
        nm = path[-1]
        if nm.startswith('Road') or nm.startswith('Offroad'):
            surf += [(1 if nm.startswith('Road') else 2, tri) for _, tri in col.polys(nd, IDENT)]
        elif nm.startswith('Wall'):
            walls += [tri for _, tri in col.polys(nd, IDENT)]
    road = [p for k, t in surf if k == 1 for p, _ in t]
    bx0, bx1 = math.floor(min(p[0] for p in road)) - 24, math.ceil(max(p[0] for p in road)) + 24
    by0, by1 = math.floor(min(p[1] for p in road)) - 24, math.ceil(max(p[1] for p in road)) + 24
    VIS = 60
    inside = lambda p: bx0 - VIS <= p[0] <= bx1 + VIS and by0 - VIS <= p[1] <= by1 + VIS
    # ---- visual geometry: model 0 = static track meshes, then one model per prop with its instance matrices
    C = lambda p: (p[0], p[2], -p[1])
    models = []  # {name, groups: {tex: (V, I)}, inst: [16 floats column-major, Y-up]}

    def new_model(name):
        md = {'name': name, 'groups': {}, 'inst': []}; models.append(md); return md

    def add(md, texfile, tri):
        if texfile not in md['groups']: md['groups'][texfile] = ([], [])
        V, I = md['groups'][texfile]; b = len(V) // 5
        for p, (u, v) in tri: x, y, z = C(p); V += [x, y, z, u, 1 - v]
        I += [b, b + 1, b + 2]

    def texfile_of(egg, tref):
        # (base texture, optional modulating repeat texture + its uv scale) - Yorg tracks use TEX* x TEXREP*
        if isinstance(tref, tuple):
            b = egg.textures.get(tref[0]); r = egg.textures.get(tref[1]); sc = egg.tex_scale.get(tref[1], (1, 1))
            return (b, r, sc) if r else b
        return egg.textures.get(tref)
    static = new_model('track'); static['inst'].append([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1])
    for path, m, nd in trk.groups():
        if path[-1].startswith('OBJSkydome'): continue
        for tex, tri in trk.polys(nd, IDENT):
            if all(inside(p) for p, _ in tri): add(static, texfile_of(trk, tex), tri)
    def ymat(m):  # Panda row-vector Z-up matrix -> three.js column-major Y-up matrix  (C * M^T * C^-1)
        R = [[m[c * 4 + r] for c in range(4)] for r in range(4)]  # column-vector form
        P = [[1, 0, 0, 0], [0, 0, 1, 0], [0, -1, 0, 0], [0, 0, 0, 1]]; Pi = [[1, 0, 0, 0], [0, 0, -1, 0], [0, 1, 0, 0], [0, 0, 0, 1]]
        mul = lambda A, B: [[sum(A[i][k] * B[k][j] for k in range(4)) for j in range(4)] for i in range(4)]
        T = mul(mul(P, R), Pi)
        return [round(T[r][c], 5) for c in range(4) for r in range(4)]
    byname = {}
    for path, m, nd in trk.groups():
        nm = path[-1]
        if not nm.startswith('Empty') or not inside((m[12], m[13], m[14])): continue
        model = nm[5:].split('.')[0]
        if model not in byname:
            pe = load_egg(base + model + '.egg')
            if not pe: byname[model] = None; print('[yorg]   no model', model); continue
            md = new_model(model)
            for p2, m2, nd2 in pe.groups():
                for tex, tri in pe.polys(nd2, IDENT): add(md, texfile_of(pe, tex), tri)
            byname[model] = md
        if byname[model]: byname[model]['inst'].append(ymat(m))
    # ---- textures
    keys = {k for md in models for k in md['groups'] if k}
    texlist = sorted({k for k in keys if isinstance(k, str)} | {k[0] for k in keys if isinstance(k, tuple) and k[0]} | {k[1] for k in keys if isinstance(k, tuple)})
    texmap = {}
    for i, f in enumerate(texlist):
        data = get(base + f)
        out = f't{i}.jpg'
        if data:
            try:
                im = Image.open(io.BytesIO(data)).convert('RGB'); im.thumbnail((MAXTEX, MAXTEX)); im.save(os.path.join(d, 'tex', out), quality=82)
            except Exception: out = None
        else: out = None
        texmap[f] = out
    # ---- write mesh: per model a vertex range + texture groups (index ranges), instances
    allV = []; allI = []; mout = []; tris = 0
    for md in models:
        if not md['groups'] or not md['inst']: continue
        v0 = len(allV) // 5; gl = []
        for f in sorted(md['groups'], key=lambda k: (k is None, str(k))):
            V, I = md['groups'][f]; b0 = len(allV) // 5
            if isinstance(f, tuple): gl.append({'tex': texmap.get(f[0]), 'rep': texmap.get(f[1]), 'rs': list(f[2]), 'start': len(allI), 'count': len(I)})
            else: gl.append({'tex': texmap.get(f), 'start': len(allI), 'count': len(I)})
            allI += [i + b0 - v0 for i in I]; allV += V
        mout.append({'name': md['name'], 'v0': v0, 'nv': len(allV) // 5 - v0, 'groups': gl, 'inst': md['inst']})
        tris += sum(g['count'] for g in gl) // 3 * len(md['inst'])
    open(os.path.join(d, 'mesh.bin'), 'wb').write(struct.pack(f'<{len(allV)}f', *allV) + struct.pack(f'<{len(allI)}I', *allI))
    # ---- heightfield (track-local Y-up: x, z_world = -y_panda)
    NX = bx1 - bx0; NZ = by1 - by0
    H = [-999.0] * (NX * NZ); K = bytearray(NX * NZ)

    def raster(tri, fn):
        (a, _), (b, _), (c, _) = tri
        x0 = max(bx0, math.floor(min(a[0], b[0], c[0]))); x1 = min(bx1 - 1, math.ceil(max(a[0], b[0], c[0])))
        y0 = max(by0, math.floor(min(a[1], b[1], c[1]))); y1 = min(by1 - 1, math.ceil(max(a[1], b[1], c[1])))
        den = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
        if abs(den) < 1e-9: return
        for x in range(x0, x1 + 1):
            for y in range(y0, y1 + 1):
                px, py = x + 0.5, y + 0.5
                l1 = ((b[1] - c[1]) * (px - c[0]) + (c[0] - b[0]) * (py - c[1])) / den
                l2 = ((c[1] - a[1]) * (px - c[0]) + (a[0] - c[0]) * (py - c[1])) / den
                l3 = 1 - l1 - l2
                if l1 >= -0.02 and l2 >= -0.02 and l3 >= -0.02:
                    fn((x - bx0) * NZ + (y - by0), l1 * a[2] + l2 * b[2] + l3 * c[2])
    for kind, tri in surf:
        def f(i, z, kind=kind):
            if z > H[i]: H[i] = z; K[i] = kind if (K[i] != 1 or kind == 1) else K[i]
            elif kind == 1 and abs(z - H[i]) < 0.3: K[i] = 1
        raster(tri, f)
    for tri in walls:
        zt = max(p[2] for p, _ in tri)
        def fw(i, z, zt=zt):
            if H[i] > -999 and zt > H[i] + 0.7: K[i] = 3
        # walls are vertical: rasterise their edges instead of the (degenerate) area
        for (p, _), (q, _) in ((tri[0], tri[1]), (tri[1], tri[2]), (tri[2], tri[0])):
            n = max(1, int(math.hypot(q[0] - p[0], q[1] - p[1]) * 2))
            for s in range(n + 1):
                x = p[0] + (q[0] - p[0]) * s / n; y = p[1] + (q[1] - p[1]) * s / n
                if bx0 <= x < bx1 and by0 <= y < by1: fw((int(math.floor(x)) - bx0) * NZ + (int(math.floor(y)) - by0), 0)
    open(os.path.join(d, 'ground.bin'), 'wb').write(struct.pack(f'<{NX * NZ}f', *H) + bytes(K))
    # ---- racing line: waypoint loop via the 'prev' tags, starting near the grid
    wps = {}
    for path, m, nd in col.groups():
        nm = path[-1]
        if nm.startswith('Waypoint') and nm != 'Waypoints':
            prev = []
            for c in nd[3]:
                if c[0] == '<Tag>' and c[1] == 'prev': prev = [int(x) for x in ' '.join(c[2]).replace('"', ' ').replace(',', ' ').split() if x.isdigit()]
            wps[int(nm[8:].split('.')[0])] = {'p': (m[12], m[13], m[14]), 'prev': prev}
    starts = sorted(((int(p[-1][5:].split('.')[0]), (m[12], m[13], m[14])) for p, m, nd in col.groups() if p[-1].startswith('Start') and p[-1] != 'Starts'))
    nxt = {}
    for k, w in wps.items():
        for pv in w['prev']: nxt.setdefault(pv, []).append(k)
    s0 = starts[0][1] if starts else (0, 0, 0)
    first = min(wps, key=lambda k: (wps[k]['p'][0] - s0[0]) ** 2 + (wps[k]['p'][1] - s0[1]) ** 2)
    loop = [first]; cur = first
    for _ in range(len(wps) + 2):
        n = nxt.get(cur)
        if not n: break
        cur = n[0]
        if cur in loop: loop = loop[loop.index(cur):]; break
        loop.append(cur)
    # orient the loop so that the start grid faces forward (grid order 1..8 goes backwards along the line)
    yl = lambda p: [round(p[0], 2), round(p[2], 2), round(-p[1], 2)]
    meta = {'name': name, 'bbox': [bx0, -by1, bx1, -by0], 'grid': {'x0': bx0, 'y0': by0, 'nx': NX, 'nz': NZ},
            'models': mout, 'verts': len(allV) // 5, 'indices': len(allI), 'tris': tris, 'path': [yl(wps[k]['p']) for k in loop],
            'starts': [yl(p) for _, p in starts], 'track': json.loads(get(f'assets/tracks/{name}/track.json') or b'{}')}
    json.dump(meta, open(os.path.join(d, 'mesh.json'), 'w'), separators=(',', ':'))
    print(f'[yorg] track {name}: {meta["tris"]} tris drawn ({len(allI) // 3} unique), {len(mout)} models, {len(texlist)} textures, path {len(loop)}/{len(wps)} waypoints, ground {NX}x{NZ}')
    return meta


def main():
    try:
        import PIL  # noqa
    except ImportError:
        return 0
    done = []
    for t in TRACKS:
        try:
            if convert(t): done.append(t)
        except Exception as e:
            print('[yorg] track', t, 'failed:', e)
    man = os.path.join(OUT, 'manifest.json')
    if os.path.exists(man):
        m = json.load(open(man)); m['tracks'] = done; json.dump(m, open(man, 'w'), indent=1)
    return 0


if __name__ == '__main__':
    sys.exit(main())
