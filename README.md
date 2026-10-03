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
