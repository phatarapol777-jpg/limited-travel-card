// Starts the real server on a free port with a throw-away data dir (backup off) and gives tests a small HTTP client.
const { spawn } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');
const net = require('net');

function freePort() {
  return new Promise((resolve, reject) => {
    const srv = net.createServer();
    srv.listen(0, () => {
      const { port } = srv.address();
      srv.close(() => resolve(port));
    });
    srv.on('error', reject);
  });
}

async function startServer(extraEnv = {}) {
  const port = await freePort();
  const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'tc-srv-'));
  const child = spawn(process.execPath, [path.join(__dirname, '..', 'src', 'server.js')], {
    env: { ...process.env, PORT: String(port), DATA_DIR: dataDir, BACKUP: 'off', KIOSK_SECRET: 'test-secret', ...extraEnv },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  let log = '';
  child.stdout.on('data', (d) => { log += d; });
  child.stderr.on('data', (d) => { log += d; });
  const base = `http://localhost:${port}/api`;
  for (let i = 0; i < 100; i++) {
    try {
      if ((await fetch(`${base}/health`)).ok) break;
    } catch { /* not up yet */ }
    await new Promise((r) => setTimeout(r, 100));
    if (i === 99) throw new Error(`server did not start:\n${log}`);
  }
  const call = async (method, p, body, token) => {
    const res = await fetch(base + p, {
      method,
      headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    let json = null;
    try { json = await res.json(); } catch { /* binary or empty */ }
    return { status: res.status, body: json, res };
  };
  const descriptor = () => Array.from({ length: 128 }, () => Math.random());
  let n = 0;
  const register = async (name) => {
    const username = `${name}${Date.now()}${n++}`;
    const r = await call('POST', '/auth/register', { username, password: 'secret123', first_name: name, last_name: 'T', email: `${username}@x.com`, face_descriptor: descriptor() });
    if (r.status !== 201) throw new Error(`register failed: ${JSON.stringify(r.body)}`);
    return { username, token: r.body.token, id: r.body.user.user_id };
  };
  const admin = async () => {
    const r = await call('POST', '/auth/login', { username: 'admin', password: 'admin1234' });
    return { token: r.body.token, id: r.body.user.user_id };
  };
  const Database = require('better-sqlite3');
  const sql = () => new Database(path.join(dataDir, 'app.db'));
  const stop = () => { child.kill(); };
  return { call, register, admin, sql, stop, base, dataDir, descriptor };
}

// A tiny valid JPEG (header bytes are what the server checks) as a data URL.
const TINY_JPEG = `data:image/jpeg;base64,${Buffer.concat([Buffer.from([0xff, 0xd8, 0xff, 0xe0]), Buffer.alloc(64, 1), Buffer.from([0xff, 0xd9])]).toString('base64')}`;

module.exports = { startServer, TINY_JPEG };
