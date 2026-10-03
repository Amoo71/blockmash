// BlockMash desktop wrapper: serves ../www with the bundled zero-dependency server and opens it in a window.
// First run needs internet once for `npm install` (downloads Electron, ~100 MB); afterwards fully offline.
const { app, BrowserWindow } = require('electron')
const path = require('path')
process.env.NO_BROWSER = '1'
const port = 8721
app.whenReady().then(async () => {
  process.argv[2] = String(port)
  await import(require('url').pathToFileURL(path.join(__dirname, '..', 'serve.mjs')).href)
  const win = new BrowserWindow({ width: 1280, height: 760, title: 'BlockMash', autoHideMenuBar: true })
  win.loadURL(`http://localhost:${port}/?singleplayer=1`)
})
app.on('window-all-closed', () => app.quit())
