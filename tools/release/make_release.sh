#!/bin/bash
# Build the LOCAL-ONLY release zip: release/BlockMash-local-<ver>.zip
# - www = production build without source maps / unused mc-data versions
# - Duke3D-derived data is NOT included (shareware licence): no www/duke, and the item atlas is rebuilt with
#   the PureBDcraft horse-armor icons instead of the extracted Duke sprites (get-duke-shareware.py adds them locally)
set -euo pipefail
cd "$(dirname "$0")/../.."
export COREPACK_HOME=${COREPACK_HOME:-$HOME/.cache/corepack}
PNPM="npx -y pnpm@9.15.9"
VER=${VER:-0.7.1}
STAGE=release/stage/BlockMash
ITEMS=packages/free-mc-assets/minecraft-assets/data/1.14.4/items
BDC=.cache/purebdcraft/assets/minecraft/textures/item
DUKE_ITEMS="iron_horse_armor golden_horse_armor diamond_horse_armor leather_horse_armor firework_star nautilus_shell heart_of_the_sea nether_star"
BACKUP=$(mktemp -d)
for n in $DUKE_ITEMS; do cp "$ITEMS/$n.png" "$BACKUP/"; done
restore () { for n in $DUKE_ITEMS; do cp "$BACKUP/$n.png" "$ITEMS/"; done; $PNPM gen-textures >/dev/null 2>&1; node esbuild.mjs --minify --prod >/dev/null 2>&1; node scripts/build.js copyFiles >/dev/null 2>&1; }
trap restore EXIT
python3 - "$ITEMS" "$BDC" $DUKE_ITEMS <<'PY'
import sys, os, math
from PIL import Image, ImageDraw
items, bdc, names = sys.argv[1], sys.argv[2], sys.argv[3:]
for n in names:
    src = os.path.join(bdc, n + '.png')
    if os.path.exists(src):
        Image.open(src).convert('RGBA').resize((64, 64), Image.NEAREST).save(os.path.join(items, n + '.png'))
    else:  # own simple star icon
        im = Image.new('RGBA', (64, 64)); d = ImageDraw.Draw(im)
        pts = [(32 + 28 * math.cos(math.pi / 2 + i * math.pi / 5) * (1 if i % 2 == 0 else .45), 32 - 28 * math.sin(math.pi / 2 + i * math.pi / 5) * (1 if i % 2 == 0 else .45)) for i in range(10)]
        d.polygon(pts, fill=(235, 240, 250, 255), outline=(60, 60, 80, 255)); im.save(os.path.join(items, n + '.png'))
PY
$PNPM gen-textures >/dev/null 2>&1
node scripts/build.js copyFiles >/dev/null 2>&1
node esbuild.mjs --minify --prod >/dev/null 2>&1
rm -rf release/stage && mkdir -p "$STAGE"
cp -r tools/release/template/. "$STAGE/"
sed -i "s/__VER__/$VER/" "$STAGE/README-LOCAL.txt"
cp -r dist "$STAGE/www"
( cd "$STAGE/www" && find . -name '*.map' -delete && rm -rf meta.json duke && cd mc-data && ls | grep -v '^1\.14\.js$' | xargs -r rm -f )
mkdir -p "$STAGE/tools" "$STAGE/licenses"
cp tools/duke3d/dukegrp.py tools/duke3d/extract_duke.py tools/duke3d/buildmap.py "$STAGE/tools/"
cp LICENSE "$STAGE/licenses/LICENSE-BlockMash-MIT.txt"; cp ASSETS_AUDIT.md "$STAGE/licenses/"
[ -f dist/darkmod/LICENSE-TheDarkMod.txt ] && cp dist/darkmod/LICENSE-TheDarkMod.txt "$STAGE/licenses/"
[ -f dist/yorg/LICENSES-Yorg.txt ] && cp dist/yorg/LICENSES-Yorg.txt "$STAGE/licenses/" && printf '\nRace track: www/yorg/tracks/* (track.egg, collision.egg, props, textures of the Yorg track) converted to\nmesh.bin/mesh.json/ground.bin by BlockMash tools/yorg/fetch_track.py (own .egg parser); CC BY-SA, Ya2.\n' >> "$STAGE/licenses/LICENSES-Yorg.txt"
[ -f "$STAGE/licenses/LICENSE-TheDarkMod.txt" ] && printf '\n\nBlockMash note: www/darkmod/prefabs = The Dark Mod building prefabs (tdm_prefabs01.pk4: house_01-10,\ntower_round_brick, tower_octagonal_blocks) and their textures, converted to polygons by tools/darkmod/fetch_prefabs.py.\nCC BY-NC-SA 3.0, The Dark Mod team - non-commercial use only.\n' >> "$STAGE/licenses/LICENSE-TheDarkMod.txt"
chmod +x "$STAGE"/start-linux.sh "$STAGE"/start-mac.command "$STAGE"/serve.py "$STAGE"/get-duke-shareware.py
# shrink a few oversized images for the zip (entity textures stay untouched: their UVs depend on the size)
python3 - "$STAGE/www" <<'PY'
import glob, os, sys
from PIL import Image
w = sys.argv[1]
def shrink(f, maxw):
    im = Image.open(f)
    if im.width > maxw:
        im = im.resize((maxw, round(im.height * maxw / im.width)), Image.LANCZOS)
    im.save(f, optimize=True)
for f in glob.glob(os.path.join(w, 'extra-textures', 'background', '*.png')): shrink(f, 512)
shrink(os.path.join(w, 'extra-textures', 'loading.png'), 1050)
shrink(os.path.join(w, 'favicon.png'), 128)
PY
if grep -rqi "3D Realms. Do not redistribute" "$STAGE/www"; then echo "Duke data leaked into stage" >&2; exit 1; fi
OUT=release/BlockMash-local-$VER.zip; rm -f "$OUT"
python3 - "$OUT" <<'PY'
import os, sys, zipfile, stat
out = sys.argv[1]
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    for dp, dn, fn in os.walk('release/stage/BlockMash'):
        for f in sorted(fn):
            p = os.path.join(dp, f); arc = os.path.relpath(p, 'release/stage')
            zi = zipfile.ZipInfo.from_file(p, arc); zi.compress_type = zipfile.ZIP_DEFLATED
            if os.access(p, os.X_OK): zi.external_attr = (0o100755 << 16)
            with open(p, 'rb') as fh: z.writestr(zi, fh.read(), compresslevel=9)
PY
ls -la "$OUT"
