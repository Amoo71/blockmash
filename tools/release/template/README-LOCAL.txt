BlockMash – local build (v__VER__)
==================================
A browser block game mashup. The SURFACE is real polygon geometry from the mashed games: the six
Duke Nukem 3D shareware levels E1L1–E1L6 at original scale side by side, plus real Yorg race-track
and car models and The Dark Mod content. UNDER and between them is the normal blocky world: caves,
ores, villages, golems, mobs, crafting. Mining or explosions cut holes into the level geometry and
reveal the blocks underneath. Based on zardoy/minecraft-web-client (MIT). Not affiliated with
Mojang/Microsoft, 3D Realms/Gearbox, The Dark Mod team or Ya2.

LOCAL USE ONLY – DO NOT REDISTRIBUTE THIS ZIP. It contains PureBDcraft textures (BDcraft terms),
The Dark Mod assets (CC BY-NC-SA 3.0) and Yorg assets (CC BY-SA); see licenses/ and the in-game
credits page (www/credits.html).

1) REQUIRED for the Duke surface – extract the Duke Nukem 3D shareware data (not included):
     python3 -m pip install pillow
     python3 get-duke-shareware.py
   Downloads the unmodified shareware 3dduke13.zip (or uses ./3dduke13.zip placed next to this
   file), checks its md5 and extracts levels, tiles, skies and sounds into www/duke on your
   computer only. The shareware licence allows copying only the complete unmodified package, so
   the extracted files are never shipped. Without this step there are NO Duke levels: the surface
   is then plain Minecraft-style terrain (the rest of the game works).

2) Start (fully offline, nothing is installed):
     Windows : double-click start-windows.bat
     macOS   : double-click start-mac.command (first time: right-click > Open)
     Linux   : ./start-linux.sh
   Needs Node.js >= 18 or Python 3. The browser opens http://localhost:8720/?singleplayer=1
   (other port: ./start-linux.sh 9000). Chrome/Edge/Firefox recommended.
   Desktop window (optional): cd electron && npm install && npm start

In game:
  /mashup tp duke 1 … 6     teleport to Duke level E1L1 … E1L6
  /mashup tp darkmod|yorg|village
  /duke give   /darkmod give   /yorg race 3   /yorg give (kart key)
  Graphics quality: F7 cycles Low / Medium / Ultra, or /mashup gfx low|medium|ultra
  (mobile defaults to Low; Ultra = soft sun shadows, full-res bloom, more dynamic lights)
