// The native shell: one window, a menu, and the data file. Everything you see is
// rendered by src/ — this side only touches the disk and the OS.
const { app, BrowserWindow, Menu, ipcMain, dialog, shell, nativeTheme, clipboard } = require('electron');
const fs = require('fs');
const path = require('path');

// %APPDATA%\TimePie\timepie.json on Windows — the counterpart of
// ~/Library/Application Support/TimePie/timepie.json on the Mac.
app.setName('TimePie');
app.setAppUserModelId('com.nikolaikravchenko.timepie');

// TIMEPIE_DATA_DIR lets a test run point somewhere else — on a Mac the default would
// be the real Mac app's file.
const dataDir = process.env.TIMEPIE_DATA_DIR || path.join(app.getPath('appData'), 'TimePie');
const dataFile = path.join(dataDir, 'timepie.json');
// Which friends group you're in, if any — kept apart from your data.
const friendsFile = path.join(dataDir, 'friends.json');

let win;

function createWindow() {
  win = new BrowserWindow({
    title: 'TimePie',
    width: 460,
    height: 620,
    minWidth: 460,
    minHeight: 620,
    useContentSize: true,
    show: false,
    backgroundColor: nativeTheme.shouldUseDarkColors ? '#171717' : '#E2E2E2',
    icon: path.join(__dirname, 'build', 'icon.png'),
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
    },
  });
  win.loadFile(path.join(__dirname, 'src', 'index.html'));
  win.once('ready-to-show', () => win.show());
}

function buildMenu() {
  const send = (channel) => () => win && win.webContents.send(channel);
  const template = [
    {
      label: 'File',
      submenu: [
        { label: 'Export JSON…', accelerator: 'CmdOrCtrl+Shift+E', click: exportJSON },
        { label: 'Show Data File in Folder', click: () => shell.showItemInFolder(dataFile) },
        { type: 'separator' },
        { role: 'quit' },
      ],
    },
    {
      label: 'Edit',
      submenu: [
        // The store keeps its own undo stack; text fields keep theirs (see app.js).
        { label: 'Undo', accelerator: 'CmdOrCtrl+Z', click: send('undo') },
        { type: 'separator' },
        { role: 'cut' },
        { role: 'copy' },
        { role: 'paste' },
        { role: 'selectAll' },
      ],
    },
    {
      label: 'View',
      submenu: [{ role: 'resetZoom' }, { role: 'zoomIn' }, { role: 'zoomOut' }, { type: 'separator' }, { role: 'togglefullscreen' }],
    },
  ];
  if (process.platform === 'darwin') template.unshift({ role: 'appMenu' });
  Menu.setApplicationMenu(Menu.buildFromTemplate(template));
}

// Your history is never trapped. The store file is already this exact format —
// export just puts a copy somewhere you chose.
async function exportJSON() {
  const day = new Date();
  const stamp = `${day.getFullYear()}-${String(day.getMonth() + 1).padStart(2, '0')}-${String(day.getDate()).padStart(2, '0')}`;
  const { canceled, filePath } = await dialog.showSaveDialog(win, {
    defaultPath: `timepie-${stamp}.json`,
    filters: [{ name: 'JSON', extensions: ['json'] }],
  });
  if (canceled || !filePath) return;
  try {
    fs.copyFileSync(dataFile, filePath);
  } catch {
    fs.writeFileSync(filePath, JSON.stringify({ activities: [], entries: [], version: 1 }, null, 2));
  }
}

ipcMain.handle('store:load', () => {
  try {
    return fs.readFileSync(dataFile, 'utf8');
  } catch {
    return null;
  }
});

// Atomic: write beside the file, then rename over it, so a crash mid-write can't
// leave half a file behind.
ipcMain.handle('store:save', (_event, json) => {
  fs.mkdirSync(dataDir, { recursive: true });
  const tmp = dataFile + '.tmp';
  fs.writeFileSync(tmp, json);
  fs.renameSync(tmp, dataFile);
});

ipcMain.handle('friends:load', () => {
  try {
    return fs.readFileSync(friendsFile, 'utf8');
  } catch {
    return null;
  }
});

ipcMain.handle('friends:save', (_event, json) => {
  if (json == null) return fs.rmSync(friendsFile, { force: true });
  fs.mkdirSync(dataDir, { recursive: true });
  fs.writeFileSync(friendsFile + '.tmp', json);
  fs.renameSync(friendsFile + '.tmp', friendsFile);
});

const RELEASES_PAGE = 'https://github.com/kravchenkonikolai05/timepie/releases/latest';
const LATEST_RELEASE = 'https://api.github.com/repos/kravchenkonikolai05/timepie/releases/latest';

// Only ever the leaderboard's own web page, or the latest release.
ipcMain.handle('open:page', (_event, url) => {
  if (url.startsWith('https://timepie-friends.timepie.workers.dev/') || url === RELEASES_PAGE) shell.openExternal(url);
});

/**
 * This build's version and the latest release's, for the reminder to update. Asked from
 * here rather than the page, which may only talk to the friends server. Null on any
 * failure: offline, or GitHub's rate limit, is no reason to bother anyone.
 * TIMEPIE_VERSION stands in for this build's version, for a test run.
 */
/**
 * The release notes' bullets, shortest form first: "- **Live timers.** When someone…" is
 * just "Live timers". At most four, to fit the card.
 */
function highlightsOf(notes) {
  return notes.split(/\r?\n/)
    .map((line) => /^\s*[-*]\s+(.*)$/.exec(line)?.[1])
    .filter(Boolean)
    .map((text) => /^\*\*(.+?)\*\*/.exec(text)?.[1].replace(/[\s.:]+$/, '') ?? text.replace(/\*\*/g, ''))
    .filter((text) => text.trim())
    .slice(0, 4);
}

ipcMain.handle('update:check', async () => {
  try {
    const res = await fetch(LATEST_RELEASE, {
      headers: { Accept: 'application/vnd.github+json' }, signal: AbortSignal.timeout(15000),
    });
    if (!res.ok) return null;
    const { tag_name: tag, body } = await res.json();
    return {
      current: process.env.TIMEPIE_VERSION ?? app.getVersion(),
      latest: String(tag).replace(/^v/i, ''),
      highlights: highlightsOf(String(body ?? '')),
      page: RELEASES_PAGE,
    };
  } catch {
    return null;
  }
});

ipcMain.handle('clipboard:write', (_event, text) => clipboard.writeText(String(text)));

ipcMain.handle('menu:context', (event, items) => {
  return new Promise((resolve) => {
    let chosen = null;
    const menu = Menu.buildFromTemplate(
      items.map((item) =>
        item === '-' ? { type: 'separator' } : { label: item.label, click: () => { chosen = item.id; resolve(chosen); } }
      )
    );
    // On some platforms the click lands just after the menu closes.
    menu.popup({ window: BrowserWindow.fromWebContents(event.sender), callback: () => setTimeout(() => resolve(chosen), 50) });
  });
});

app.whenReady().then(() => {
  buildMenu();
  createWindow();
  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on('window-all-closed', () => app.quit());
