"""Minimal Panda3D .egg parser (own code, MIT): groups with transforms, vertex pools, polygons with textures.
Returns world-space triangles (Panda Z-up converted to Y-up: (x, y, z) -> (x, z, -y))."""
import re

TOK = re.compile(r'<[^>]+>|\{|\}|"[^"]*"|[^\s{}<>"]+')


def parse(text):
    toks = TOK.findall(text); i = 0; n = len(toks)

    def node():
        nonlocal i
        # <Kind> [name] { ... }
        kind = toks[i]; i += 1
        name = None
        if toks[i] != '{':
            name = toks[i]; i += 1
            while toks[i] != '{': name += ' ' + toks[i]; i += 1
        i += 1  # {
        kids = []; vals = []
        while toks[i] != '}':
            if toks[i].startswith('<'): kids.append(node())
            else: vals.append(toks[i]); i += 1
        i += 1
        return (kind, name, vals, kids)
    out = []
    while i < n:
        if toks[i].startswith('<'): out.append(node())
        else: i += 1
    return out


def mat_mul(a, b):  # row-vector convention (Panda): p' = p * M
    return [sum(a[r * 4 + k] * b[k * 4 + c] for k in range(4)) for r in range(4) for c in range(4)]


IDENT = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]


def xf(p, m):
    x, y, z = p
    return (x * m[0] + y * m[4] + z * m[8] + m[12], x * m[1] + y * m[5] + z * m[9] + m[13], x * m[2] + y * m[6] + z * m[10] + m[14])


class Egg:
    def __init__(self, text):
        self.tree = parse(text)
        self.textures = {}; self.pools = {}; self.tex_scale = {}
        for k in self.tree: self._collect(k)

    def _collect(self, nd):
        kind, name, vals, kids = nd
        if kind == '<Texture>':
            self.textures[name] = vals[0].strip('"') if vals else None
            for c in kids:
                if c[0] == '<Transform>':
                    for t in c[3]:
                        if t[0] == '<Scale>' and len(t[2]) >= 2: self.tex_scale[name] = (float(t[2][0]), float(t[2][1]))
        elif kind == '<VertexPool>':
            pool = {}
            for v in kids:
                if v[0] != '<Vertex>': continue
                p = tuple(float(x) for x in v[2][:3]); uv = (0.0, 0.0); got = False
                for c in v[3]:
                    if c[0] == '<UV>' and not got and (c[1] is None or not got):
                        if len(c[2]) >= 2: uv = (float(c[2][0]), float(c[2][1])); got = c[1] is None
                pool[int(v[1])] = (p, uv)
            self.pools[name] = pool
        for c in kids: self._collect(c)

    def groups(self):
        """yield (path_names, matrix, group_node) for every <Group> (matrix = accumulated world transform)"""
        def walk(nds, m, path):
            for nd in nds:
                if nd[0] not in ('<Group>', '<Instance>'): continue
                lm = m
                for c in nd[3]:
                    if c[0] == '<Transform>':
                        for t in c[3]:
                            if t[0] == '<Matrix4>': lm = mat_mul([float(x) for x in t[2]], m)
                yield path + [nd[1] or ''], lm, nd
                yield from walk(nd[3], lm, path + [nd[1] or ''])
        yield from walk(self.tree, IDENT, [])

    def polys(self, nd, m):
        """triangles of the polygons directly inside group nd: (texname, [(p, uv) x3]) with p transformed by m.
        Vertex pools are in world space already in eggs exported by YABEE unless <DCS>; we apply m only for instances."""
        for c in nd[3]:
            if c[0] != '<Polygon>': continue
            tex = None; refs = None; pool = None; texs = []
            for d in c[3]:
                if d[0] == '<TRef>': texs.append(d[2][0])
                if d[0] == '<VertexRef>':
                    refs = [int(x) for x in d[2]]
                    for r in d[3]:
                        if r[0] == '<Ref>': pool = r[2][0]
            if refs is None or pool not in self.pools: continue
            tex = tuple(texs) if len(texs) > 1 else (texs[0] if texs else None)
            P = self.pools[pool]; vs = [P[r] for r in refs if r in P]
            vs = [(xf(p, m), uv) for p, uv in vs]
            for k in range(1, len(vs) - 1):
                yield tex, [vs[0], vs[k], vs[k + 1]]


def yup(p):
    return (p[0], p[2], -p[1])
