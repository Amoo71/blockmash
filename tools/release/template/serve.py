#!/usr/bin/env python3
"""BlockMash local static server for systems without Node (Python 3). Usage: python3 serve.py [port]"""
import functools, http.server, os, sys, threading, webbrowser
port = int(sys.argv[1]) if len(sys.argv) > 1 else 8720
root = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'www')
http.server.SimpleHTTPRequestHandler.extensions_map.update({'.js': 'text/javascript', '.mjs': 'text/javascript', '.wasm': 'application/wasm', '.ogg': 'audio/ogg'})
handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=root)
srv = http.server.ThreadingHTTPServer(('127.0.0.1', port), handler)
url = f'http://localhost:{port}/?singleplayer=1'
print(f'BlockMash running at {url}  (Ctrl+C to stop)')
if not os.environ.get('NO_BROWSER'): threading.Timer(1.0, lambda: webbrowser.open(url)).start()
try: srv.serve_forever()
except KeyboardInterrupt: pass
