// node --experimental-websocket measure.mjs <fileKey> <arquivo.stickies.md>...
// Mede na aba do board (via CDP, sem MCP) cada sticky dos .stickies.md, a fonte 40, e lista os que
// passam de 3 linhas ou quebram palavra no meio. Usa a mesma regra do build-poster.js, cria stickies
// temporários e apaga em seguida. Para cada item com variantes "a || b", mostra qual entraria.
import { readFileSync } from 'node:fs';

const [fileKey, ...files] = process.argv.slice(2);
if (!fileKey || !files.length) {
  console.error('uso: measure.mjs <fileKey> <arquivo.stickies.md>...');
  process.exit(2);
}
const items = [];
for (const f of files) {
  let key = null;
  const date = [];
  for (const line of readFileSync(f, 'utf8').split('\n')) {
    const h = line.match(/^###\s+(\S+)/);
    if (h) { key = h[1]; continue; }
    const li = line.match(/^-\s+(.+)$/);
    if (li && key === 'date') date.push(li[1].trim().replace(/^§\s*/, ''));
    else if (li && key) {
      items.push({ file: f.split('/').pop(), key, variants: li[1].split('||').map((s) => s.trim().replace(/^§\s*/, '')) });
    }
  }
  // o sticky de data junta as linhas do ### date com \n, como o stickies-to-entrada.mjs
  if (date.length) items.push({ file: f.split('/').pop(), key: 'date', variants: [date.join('\n')] });
}

const expr = `(async () => {
  const items = ${JSON.stringify(items)};
  const st = figma.createSticky(); st.authorVisible = false;
  await figma.loadFontAsync(st.text.fontName);
  st.text.fontSize = 40;
  st.text.characters = 'a\\na\\na';
  const MAX_H = st.height + 6;
  const cache = {};
  const breaks = (w) => {
    if (!(w in cache)) {
      st.text.characters = Array(6).fill('a').join('\\n'); const h0 = st.height;
      st.text.characters = Array(6).fill(w).join('\\n'); cache[w] = st.height > h0;
    }
    return cache[w];
  };
  const bad = [];
  for (const it of items) {
    let ok = null, last = null;
    for (const v of it.variants) {
      const words = v.split(/\\s+/).filter((w) => w.length > 6 && breaks(w));
      st.text.characters = v;
      last = { text: v, height: st.height, broken: words };
      if (!words.length && (it.key === 'date' || st.height <= MAX_H)) { ok = v; break; } // data pode crescer
    }
    if (!ok) bad.push({ file: it.file, key: it.key, ...last });
    else if (ok !== it.variants[0]) bad.push({ file: it.file, key: it.key, chosen: ok, note: 'variante' });
  }
  st.remove();
  return { maxH: MAX_H, total: items.length, bad };
})()`;

const tabs = await (await fetch('http://127.0.0.1:9222/json')).json();
const tab = tabs.find((t) => t.type === 'page' && t.url.includes(fileKey));
if (!tab) throw new Error('aba do board não encontrada: ' + fileKey);
const ws = new WebSocket(tab.webSocketDebuggerUrl);
await new Promise((r) => ws.addEventListener('open', r));
let id = 0;
const pending = {};
ws.addEventListener('message', (e) => {
  const m = JSON.parse(e.data);
  if (pending[m.id]) { pending[m.id](m); delete pending[m.id]; }
});
const send = (method, params = {}) => new Promise((r) => { const i = ++id; pending[i] = r; ws.send(JSON.stringify({ id: i, method, params })); });
await send('Page.bringToFront'); // aba em segundo plano roda estrangulada
const r = await send('Runtime.evaluate', { expression: expr, awaitPromise: true, returnByValue: true });
ws.close();
if (r.result?.exceptionDetails) {
  console.error(JSON.stringify(r.result.exceptionDetails, null, 1));
  process.exit(1);
}
const out = r.result.result.value;
console.log(`maxH ${out.maxH}, ${out.total} stickies, ${out.bad.filter((b) => !b.note).length} problemas`);
for (const b of out.bad) console.log(JSON.stringify(b));
