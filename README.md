# BlockMash

A browser block-game mashup: Minecraft-style survival with Duke Nukem 3D-style cities, Dark Mod-style medieval
quarters and Yorg race tracks on the surface, vanilla-style caves and ores underneath. Non-commercial.

- Based on [zardoy/minecraft-web-client](https://github.com/zardoy/minecraft-web-client) (MIT) – see `README.upstream.md`.
- Textures: **PureBDcraft 128x** by https://bdcraft.net (not included – put the zip at `vendor/purebdcraft/pack.zip`).
- Asset audit: `ASSETS_AUDIT.md`. Design: `DESIGN.md`. Credits: `assets/credits.html`.

## Build & run
```sh
export COREPACK_HOME=$HOME/.cache/corepack
CI=true npx -y pnpm@9.15.9 install     # generates textures from PureBDcraft
npx -y pnpm@9.15.9 build               # includes the no-Mojang-asset check
node server.js 8720                    # open http://localhost:8720/?singleplayer=1
```

## Local release zip (phase 6)
`bash tools/release/make_release.sh` → `release/BlockMash-local-0.6.0.zip` (~24.8 MB, gitignored).
Contains `www/` (prod build), `start-windows.bat`, `start-mac.command`, `start-linux.sh` (Node ≥ 18 or Python 3, no
install, offline), an optional `electron/` wrapper (`npm install && npm start`), `get-duke-shareware.py` and `licenses/`.
**Local use only – do not redistribute** (PureBDcraft terms, The Dark Mod CC BY-NC-SA). Duke Nukem 3D shareware data is
never included; `get-duke-shareware.py` extracts it from the unmodified `3dduke13.zip` on the user's machine.

In-game: `/mashup tp duke|darkmod|yorg|village`, `/duke give`, `/darkmod give`, `/yorg race 3`, `/yorg give`.
Screenshots: `docs/screenshots/phase1` … `phase6`.
