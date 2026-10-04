// Copied from /workspace/vcmc/src/voxel/voxelize.js (same author, mesh-to-voxel approach from its DESIGN.md).
// Triangle-mesh -> voxel conversion, used to turn GTA map geometry (preferably
// the COL collision mesh, which is simpler and closed-ish) into minable blocks.
// Surface voxelisation uses the separating-axis triangle/box overlap test
// (Akenine-Möller 2001), then optional per-column interior fill.

function sub(a, b) { return [a[0] - b[0], a[1] - b[1], a[2] - b[2]]; }
function cross(a, b) { return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]; }
function dot(a, b) { return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]; }

/** Does triangle (v0,v1,v2) overlap the box centred at c with half-size h? */
export function triBoxOverlap(c, h, t0, t1, t2) {
  const v0 = sub(t0, c), v1 = sub(t1, c), v2 = sub(t2, c);
  const e = [sub(v1, v0), sub(v2, v1), sub(v0, v2)];
  // 9 edge cross-product axes
  for (let i = 0; i < 3; i++) for (let k = 0; k < 3; k++) {
    const axis = [0, 0, 0]; axis[k] = 1;
    const a = cross(axis, e[i]);
    if (!a[0] && !a[1] && !a[2]) continue;
    const p0 = dot(v0, a), p1 = dot(v1, a), p2 = dot(v2, a);
    const r = h * (Math.abs(a[0]) + Math.abs(a[1]) + Math.abs(a[2]));
    if (Math.min(p0, p1, p2) > r || Math.max(p0, p1, p2) < -r) return false;
  }
  // box face normals
  for (let k = 0; k < 3; k++) if (Math.min(v0[k], v1[k], v2[k]) > h || Math.max(v0[k], v1[k], v2[k]) < -h) return false;
  // triangle plane
  const n = cross(e[0], e[1]);
  const d = dot(n, v0), r = h * (Math.abs(n[0]) + Math.abs(n[1]) + Math.abs(n[2]));
  return Math.abs(d) <= r;
}

/**
 * Voxelise triangles into integer cells of size `size`.
 * @param positions Float32Array xyz (already in voxel-world space, Y-up)
 * @param indices Uint32Array triangle indices
 * @returns Set of "x,y,z" keys
 */
export function voxelizeTriangles(positions, indices, size = 1, out = new Set()) {
  const h = size / 2 - 1e-4; // shrink slightly: geometry touching a cell border does not claim the neighbour
  for (let t = 0; t < indices.length; t += 3) {
    const a = [positions[indices[t] * 3], positions[indices[t] * 3 + 1], positions[indices[t] * 3 + 2]];
    const b = [positions[indices[t + 1] * 3], positions[indices[t + 1] * 3 + 1], positions[indices[t + 1] * 3 + 2]];
    const c = [positions[indices[t + 2] * 3], positions[indices[t + 2] * 3 + 1], positions[indices[t + 2] * 3 + 2]];
    const lo = [0, 1, 2].map((k) => Math.floor(Math.min(a[k], b[k], c[k]) / size - 1e-6));
    const hi = [0, 1, 2].map((k) => Math.floor(Math.max(a[k], b[k], c[k]) / size + 1e-6));
    for (let x = lo[0]; x <= hi[0]; x++) for (let y = lo[1]; y <= hi[1]; y++) for (let z = lo[2]; z <= hi[2]; z++) {
      const k = `${x},${y},${z}`;
      if (out.has(k)) continue;
      if (triBoxOverlap([(x + 0.5) * size, (y + 0.5) * size, (z + 0.5) * size], h, a, b, c)) out.add(k);
    }
  }
  return out;
}

/** Fill interiors column-wise (Y): between the lowest and highest surface voxel of
 *  each (x,z) column that is enclosed. Good for solid-ish buildings; open
 *  structures should skip this (see DESIGN.md). */
export function fillColumns(set) {
  const cols = new Map();
  for (const k of set) { const [x, y, z] = k.split(',').map(Number); const ck = `${x},${z}`; const c = cols.get(ck); if (!c) cols.set(ck, [y, y]); else { c[0] = Math.min(c[0], y); c[1] = Math.max(c[1], y); } }
  for (const [ck, [y0, y1]] of cols) { const [x, z] = ck.split(',').map(Number); for (let y = y0; y <= y1; y++) set.add(`${x},${y},${z}`); }
  return set;
}
