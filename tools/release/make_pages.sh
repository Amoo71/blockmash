#!/bin/bash
# Public static site for GitHub Pages: the staged release www (no Duke3D data, PureBDcraft item icons),
# plus licenses/ and a flag that skips the on-disk ./duke probe (Duke data only via the in-browser loader).
# Usage: tools/release/make_pages.sh <out-dir>
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT=${1:-release/pages}
STAGE_ONLY=1 bash tools/release/make_release.sh
mkdir -p "$OUT"
find "$OUT" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
cp -r release/stage/BlockMash/www/. "$OUT/"
cp -r release/stage/BlockMash/licenses "$OUT/licenses"
touch "$OUT/.nojekyll"
python3 - "$OUT/index.html" <<'PY'
import sys
p = sys.argv[1]; s = open(p, encoding='utf-8').read()
tag = '<script>window.blockmashNoDukeOnDisk=1</script>'
if tag not in s: s = s.replace('<head>', '<head>' + tag, 1)
open(p, 'w', encoding='utf-8').write(s)
PY
# Duke Nukem 3D shareware v1.3D: the complete, unmodified 3dduke13.zip (byte-identical to archive.org/details/3dduke13),
# redistributed free of charge as its LICENSE.TXT allows for free WWW sites. Never any extracted files.
DUKE_SHA=c67efd179022bc6d9bde54f404c707cbcbdc15423c20be72e277bc2bdddf3d0e
mkdir -p "$OUT/duke-shareware"
cp vendor/duke3d/3dduke13.zip "$OUT/duke-shareware/3dduke13.zip"
echo "$DUKE_SHA  $OUT/duke-shareware/3dduke13.zip" | sha256sum -c --quiet - || { echo "3dduke13.zip is not the original shareware package" >&2; exit 1; }
cat > "$OUT/duke-shareware/README.txt" <<'TXT'
Duke Nukem 3D Shareware v1.3D - the complete, unmodified original package (3dduke13.zip).
sha256 c67efd179022bc6d9bde54f404c707cbcbdc15423c20be72e277bc2bdddf3d0e (identical to https://archive.org/download/3dduke13/3dduke13.zip)
Redistributed free of charge as permitted by the LICENSE.TXT inside the package (free WWW sites may make the
complete, unmodified shareware available for download). BlockMash unpacks it in your browser only.
Duke Nukem 3D (c) 3D Realms Entertainment. Duke Nukem is a trademark of Gearbox Software / 3D Realms.
BlockMash is not affiliated with or endorsed by 3D Realms or Gearbox.
TXT
if [ -d "$OUT/duke" ] || grep -rqi "3D Realms. Do not redistribute" "$OUT"; then echo "Duke data in pages output" >&2; exit 1; fi
python3 tools/free-assets/verify_no_mojang.py "$OUT"
find "$OUT" -type f -size +95M | grep . && { echo "file over GitHub limit" >&2; exit 1; } || true
du -sh "$OUT"
