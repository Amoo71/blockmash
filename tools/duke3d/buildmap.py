"""Build-engine MAP (v7) reader for the Duke Nukem 3D shareware maps (local extraction only)."""
import struct

SECTOR = struct.Struct('<hhiihhhhbBBBhhbBBBBBhhh')
WALL = struct.Struct('<iihhhhhhbBBBBBhhh')
SPRITE = struct.Struct('<iiihhbBBBBBbbhhhhhhhhhh')


def read_map(data):
    ver, px, py, pz, ang, cursect = struct.unpack_from('<iiiihh', data, 0)
    o = 20
    (ns,) = struct.unpack_from('<H', data, o); o += 2
    sectors = []
    for _ in range(ns):
        v = SECTOR.unpack_from(data, o); o += SECTOR.size
        sectors.append(dict(wallptr=v[0], wallnum=v[1], cz=v[2], fz=v[3], cstat=v[4], fstat=v[5], cpic=v[6], cheinum=v[7],
                            cshade=v[8], cpal=v[9], cxpan=v[10], cypan=v[11], fpic=v[12], fheinum=v[13], fshade=v[14], fpal=v[15],
                            fxpan=v[16], fypan=v[17], vis=v[18], lotag=v[20], hitag=v[21]))
    (nw,) = struct.unpack_from('<H', data, o); o += 2
    walls = []
    for _ in range(nw):
        v = WALL.unpack_from(data, o); o += WALL.size
        walls.append(dict(x=v[0], y=v[1], p2=v[2], nw=v[3], ns=v[4], cstat=v[5], pic=v[6], opic=v[7], shade=v[8], pal=v[9],
                          xr=v[10], yr=v[11], xp=v[12], yp=v[13], lotag=v[14], hitag=v[15]))
    (nsp,) = struct.unpack_from('<H', data, o); o += 2
    sprites = []
    for _ in range(nsp):
        v = SPRITE.unpack_from(data, o); o += SPRITE.size
        sprites.append(dict(x=v[0], y=v[1], z=v[2], cstat=v[3], pic=v[4], shade=v[5], pal=v[6], clip=v[7], xr=v[9], yr=v[10],
                            xo=v[11], yo=v[12], sect=v[13], stat=v[14], ang=v[15], lotag=v[20], hitag=v[21]))
    return dict(version=ver, start=dict(x=px, y=py, z=pz, ang=ang, sect=cursect), sectors=sectors, walls=walls, sprites=sprites)
