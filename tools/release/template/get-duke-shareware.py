#!/usr/bin/env python3
"""REQUIRED for the Duke surface: extract the Duke Nukem 3D shareware levels E1L1-E1L6, tiles, skies and sounds.
Downloads the UNMODIFIED shareware package 3dduke13.zip (v1.3d, (c) 1996 3D Realms) from archive.org - or uses
./3dduke13.zip if you put it here yourself - verifies its md5 and extracts levels/tiles/skies/sounds into www/duke/ on THIS
computer only. Needs Python 3 + Pillow (pip install pillow); ffmpeg is optional (otherwise WAV sounds).
The extracted files must not be redistributed (shareware licence: only the complete unmodified package may be
copied). Without them there are no Duke levels on the surface."""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
os.environ.setdefault('DUKE3D_SHAREWARE_ZIP', os.path.join(HERE, '3dduke13.zip'))
os.environ['DUKE3D_OUT'] = os.path.join(HERE, 'www', 'duke')
os.environ['DUKE3D_ITEMS'] = os.path.join(HERE, '.no-item-patching')
sys.path.insert(0, os.path.join(HERE, 'tools'))
try:
    import PIL  # noqa
except ImportError:
    sys.exit('Pillow missing: run  python3 -m pip install pillow  and try again')
import extract_duke
extract_duke.main()
