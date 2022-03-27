import { create } from 'domain';
import { app, BrowserWindow } from 'electron';
import path from 'path';

const isDev = true;

function createWindow() {
    const window = new BrowserWindow({
        width: 800,
        height: 600,
        webPreferences: {
            nodeIntegration: true,
        }
    });

    if (isDev) {
        window.loadURL('http://localhost:3000');
        window.webContents.openDevTools();
    }
    else {
        window.loadFile(`file://${path.join(__dirname, '..', 'dist', 'index.html')}`);
    }
}

app.whenReady().then(createWindow);

app.on('window-all-closed', () => {
    if (process.platform !== 'darwin') {
        app.quit();
    }
});

app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) {
        createWindow();
    }
});