// node --experimental-websocket input.mjs <match> click x y | dblclick x y | type "text" | key Enter|Escape | selectall
const [match, cmd, a, b] = process.argv.slice(2);
const tabs = await (await fetch('http://127.0.0.1:9222/json')).json();
const tab = tabs.find(t => t.type === 'page' && t.url.includes(match));
const ws = new WebSocket(tab.webSocketDebuggerUrl);
await new Promise(r => ws.addEventListener('open', r));
let id = 0; const pending = {};
ws.addEventListener('message', e => { const m = JSON.parse(e.data); if (pending[m.id]) { pending[m.id](m); delete pending[m.id]; } });
const send = (method, params = {}) => new Promise(r => { const i = ++id; pending[i] = r; ws.send(JSON.stringify({ id: i, method, params })); });
await send('Page.bringToFront');
const click = async (x, y, n) => { for (const type of ['mousePressed', 'mouseReleased']) await send('Input.dispatchMouseEvent', { type, x, y, button: 'left', clickCount: n }); };
if (cmd === 'click') await click(+a, +b, 1);
if (cmd === 'dblclick') { await click(+a, +b, 1); await click(+a, +b, 2); }
if (cmd === 'type') await send('Input.insertText', { text: a });
if (cmd === 'key') { const codes = { Enter: 13, Escape: 27 }; for (const type of ['rawKeyDown', 'keyUp']) await send('Input.dispatchKeyEvent', { type, key: a, code: a, windowsVirtualKeyCode: codes[a] }); }
if (cmd === 'selectall') { for (const type of ['rawKeyDown', 'keyUp']) await send('Input.dispatchKeyEvent', { type, key: 'a', code: 'KeyA', modifiers: 2, windowsVirtualKeyCode: 65 }); }
console.log('ok'); ws.close();
