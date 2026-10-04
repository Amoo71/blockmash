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
if [ -d "$OUT/duke" ] || grep -rqi "3D Realms. Do not redistribute" "$OUT"; then echo "Duke data in pages output" >&2; exit 1; fi
python3 tools/free-assets/verify_no_mojang.py "$OUT"
find "$OUT" -type f -size +95M | grep . && { echo "file over GitHub limit" >&2; exit 1; } || true
du -sh "$OUT"
