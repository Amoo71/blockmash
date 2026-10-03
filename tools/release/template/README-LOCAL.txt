BlockMash – local build (v0.6, phases 1-6)
==========================================
A browser block game mashup: Duke Nukem 3D city, The Dark Mod medieval/steampunk quarters and
Yorg race tracks built from minable/explodable blocks on top of vanilla-style terrain, villages,
golems and mobs. Based on zardoy/minecraft-web-client (MIT). Not affiliated with Mojang/Microsoft,
3D Realms/Gearbox, The Dark Mod team or Ya2.

LOCAL USE ONLY – DO NOT REDISTRIBUTE THIS ZIP. It contains PureBDcraft textures (BDcraft terms),
The Dark Mod icons/sounds (CC BY-NC-SA 3.0) and Yorg cars (CC BY-SA); see licenses/ and the
in-game credits page (www/credits.html).

Start (fully offline, nothing is installed):
  Windows : double-click start-windows.bat
  macOS   : double-click start-mac.command (first time: right-click > Open)
  Linux   : ./start-linux.sh
Needs Node.js >= 18 or Python 3. The browser opens http://localhost:8720/?singleplayer=1
(port: start-linux.sh 9000 / node serve.mjs 9000). Chrome/Edge/Firefox recommended.

Desktop window (optional): cd electron && npm install && npm start
(npm install downloads Electron once, ~100 MB; then it runs offline.)

Duke Nukem 3D sprites + sounds (optional, not included):
  python3 -m pip install pillow
  python3 get-duke-shareware.py
Downloads the unmodified shareware 3dduke13.zip (or uses ./3dduke13.zip) and extracts it into
www/duke on your computer only. The shareware licence allows copying only the complete unmodified
package, so the extracted files are never shipped. Without them the Duke zone uses fallbacks
(normal mob models, silent weapons, horse-armor icons).

In game:  /mashup tp duke|darkmod|yorg|village   /duke give   /darkmod give   /yorg race 3
          /yorg give (kart key) – or right-click a car in the Yorg pit garage.
