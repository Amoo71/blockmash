// BlockMash local static server (Node >= 18, no dependencies). Usage: node serve.mjs [port]
import http from 'node:http'
import fs from 'node:fs'
import path from 'node:path'
import { exec } from 'node:child_process'
import { fileURLToPath } from 'node:url'
const root = path.join(path.dirname(fileURLToPath(import.meta.url)), 'www')
const port = Number(process.argv[2] || process.env.PORT || 8720)
const types = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.mjs': 'text/javascript', '.css': 'text/css', '.json': 'application/json', '.png': 'image/png', '.jpg': 'image/jpeg', '.ogg': 'audio/ogg', '.wav': 'audio/wav', '.mp3': 'audio/mpeg', '.ttf': 'font/ttf', '.woff2': 'font/woff2', '.txt': 'text/plain; charset=utf-8', '.svg': 'image/svg+xml' }
const server = http.createServer((req, res) => {
  let p = decodeURIComponent(new URL(req.url, 'http://x').pathname)
  if (p.endsWith('/')) p += 'index.html'
  const f = path.normalize(path.join(root, p))
  if (!f.startsWith(root)) { res.writeHead(403); return res.end() }
  fs.stat(f, (err, st) => {
    if (err || !st.isFile()) { res.writeHead(404); return res.end('not found') }
    res.writeHead(200, { 'Content-Type': types[path.extname(f).toLowerCase()] || 'application/octet-stream', 'Content-Length': st.size, 'Cache-Control': 'no-cache' })
    fs.createReadStream(f).pipe(res)
  })
})
server.listen(port, '127.0.0.1', () => {
  const url = `http://localhost:${port}/?singleplayer=1`
  console.log(`BlockMash running at ${url}  (Ctrl+C to stop)`)
  if (!process.env.NO_BROWSER) {
    const cmd = process.platform === 'win32' ? `start "" "${url}"` : process.platform === 'darwin' ? `open "${url}"` : `xdg-open "${url}"`
    exec(cmd, () => {})
  }
})
export default server
