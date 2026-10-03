#!/bin/sh
# BlockMash – start locally (Linux). Needs Node.js >= 18 or Python 3.
cd "$(dirname "$0")"
if command -v node >/dev/null 2>&1; then exec node serve.mjs "$@"; fi
if command -v python3 >/dev/null 2>&1; then exec python3 serve.py "$@"; fi
echo "Please install Node.js (https://nodejs.org) or Python 3." >&2; exit 1
