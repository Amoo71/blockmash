# BlockMash

A browser block-game mashup: the real Duke Nukem 3D shareware levels (from your own file), real The Dark Mod building
prefabs and the real Yorg Orlando race track on the surface, vanilla-style caves and ores underneath. Non-commercial.

- Based on [zardoy/minecraft-web-client](https://github.com/zardoy/minecraft-web-client) (MIT) – see `README.upstream.md`.
- Textures: **PureBDcraft 128x** by https://bdcraft.net (not included – put the zip at `vendor/purebdcraft/pack.zip`).
- **Play online (free, non-commercial):** https://amoo71.github.io/blockmash/ (`?singleplayer=1` starts directly; works on
  phones – touch controls, Low graphics by default). The site never contains Duke Nukem 3D data: tap the small
  **Duke3D data…** button (bottom-left on the menu/loading/pause screens) and pick your own shareware `3dduke13.zip`
  (or `DUKE3D.GRP`). It is parsed in the browser (`src/mashup/client/dukedata.ts`, JS port of `tools/duke3d/`), stored
  only in that browser's IndexedDB and never uploaded. Without it the Duke strip is plain terrain.
  Site build: `tools/release/make_pages.sh <dir>` (branch `gh-pages`).
- Asset audit: `ASSETS_AUDIT.md`. Design: `DESIGN.md`. Credits: `assets/credits.html`.

## Build & run
```sh
export COREPACK_HOME=$HOME/.cache/corepack
CI=true npx -y pnpm@9.15.9 install     # generates textures from PureBDcraft
npx -y pnpm@9.15.9 build               # includes the no-Mojang-asset check
node server.js 8720                    # open http://localhost:8720/?singleplayer=1
```

## Local release zip
`bash tools/release/make_release.sh` → `release/BlockMash-local-<version>.zip` (gitignored).
Contains `www/` (prod build), `start-windows.bat`, `start-mac.command`, `start-linux.sh` (Node ≥ 18 or Python 3, no
install, offline), an optional `electron/` wrapper (`npm install && npm start`), `get-duke-shareware.py` and `licenses/`.
**Local use only – do not redistribute** (PureBDcraft terms, The Dark Mod CC BY-NC-SA). Duke Nukem 3D shareware data is
never included; `get-duke-shareware.py` extracts it from the unmodified `3dduke13.zip` on the user's machine.

In-game: `/mashup tp duke|darkmod|yorg|village`, `/duke give`, `/darkmod give`, `/yorg race 3`, `/yorg give`.
Screenshots: `docs/screenshots/phase1` … `phase8`.

## Graphics / atmosphere (phase 8)
Quality **Low** (mobile default) / **Medium** (desktop default) / **Ultra**: press **F7** to cycle or type
`/mashup gfx low|medium|ultra` (saved in localStorage `blockmash.gfx`).
- Sky: the real Duke3D shareware parallax sky (LA skyline tile 89 panorama, laid out like Duke's `setupbackdrop`) around
  the Duke levels, blended into the MC day/night sky (hazy silhouette by day, lit windows at night).
- Duke light: Build sector/wall shade drives brightness; sectors under a parallax sky follow the sun/moon, interiors keep
  their own shade; Build fullbright palette colours (240-254) and negative-shade walls/sprites glow (bloom) and act as
  point lights; sector visibility thickens the fog.
- Dynamic point lights: explosions, muzzle flashes (player and enemies), rockets, Duke neon/signs, MC torches/lanterns/fire.
- Sun shadows (Medium: 1024 map / 40 m, Ultra: 4096 soft / 96 m, Low: none) following the MC sun/moon.
- Distance fog + low height fog, soft-shoulder tone curve (MC colours unchanged, HDR rolls off), bloom (Medium half-res).
- Dark Mod quarter: darker ambient/fog/sky (light gem HUD reads the real light); caves: black fog and dimmed ambient.

