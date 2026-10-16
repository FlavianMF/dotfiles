// node --experimental-websocket shot2.mjs out.png urlMatch [dsf]
const [out, match, dsf='2'] = process.argv.slice(2);
const tabs = await (await fetch('http://127.0.0.1:9222/json')).json();
const tab = tabs.find(t => t.type === 'page' && t.url.includes(match));
const ws = new WebSocket(tab.webSocketDebuggerUrl);
await new Promise(r => ws.addEventListener('open', r));
let id = 0; const pending = {};
ws.addEventListener('message', e => { const m = JSON.parse(e.data); if (pending[m.id]) { pending[m.id](m); delete pending[m.id]; } });
const send = (method, params = {}) => new Promise(r => { const i = ++id; pending[i] = r; ws.send(JSON.stringify({ id: i, method, params })); });
await send('Page.bringToFront');
const res = await send('Page.captureScreenshot', { format: 'png', captureBeyondViewport: false, clip: { x: 0, y: 0, width: 1800, height: 1013, scale: Number(dsf) } });
(await import('node:fs')).writeFileSync(out, Buffer.from(res.result.data, 'base64'));
console.log('saved', out); ws.close();
