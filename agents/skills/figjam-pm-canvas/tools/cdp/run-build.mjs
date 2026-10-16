// node --experimental-websocket run-build.mjs <fileKey> <entrada.js> [--remove 1:6,1:640] [--script outro.js]
// Roda build-poster.js (ou outro script do use_figma) direto na aba do board, via CDP, sem MCP e sem cota.
// O bloco ENTRADA do script é trocado pelo conteúdo de <entrada.js>. A aba precisa estar aberta e
// carregada (com login), e o global `figma` precisa existir no console. Imprime o retorno em JSON.
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const argv = process.argv.slice(2);
const opt = (name) => { const i = argv.indexOf(name); return i < 0 ? null : argv.splice(i, 2)[1]; };
const removeIds = opt('--remove');
const scriptArg = opt('--script');
const [fileKey, entradaPath] = argv;
if (!fileKey || !entradaPath) {
  console.error('uso: run-build.mjs <fileKey> <entrada.js> [--remove 1:6,1:640] [--script outro.js]');
  process.exit(2);
}
const here = dirname(fileURLToPath(import.meta.url));
const script = readFileSync(scriptArg || join(here, '..', 'build-poster.js'), 'utf8');
const entrada = readFileSync(entradaPath, 'utf8');
const BLOCK = /\/\/ ===== ENTRADA =+\n[\s\S]*?\n\/\/ =+\n/;
if (!BLOCK.test(script)) throw new Error('bloco ENTRADA não encontrado no script');
const ent = entrada.match(BLOCK);
if (!ent) throw new Error('bloco ENTRADA não encontrado na entrada');
// --remove: remontagem; apaga essas sections na mesma chamada (o REMOVE da entrada é ignorado)
let block = ent[0];
if (removeIds) block = block.replace(/^const REMOVE = .*$/m, `const REMOVE = ${JSON.stringify(removeIds.split(','))};`);
const code = script.replace(BLOCK, () => block);

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

// aba em segundo plano é estrangulada pelo Chrome e a montagem leva minutos: traz para a frente
await send('Page.bringToFront');
const check = await send('Runtime.evaluate', { expression: 'typeof figma', returnByValue: true });
if (check.result?.result?.value !== 'object') throw new Error('global figma ausente: espere o board carregar');
const r = await send('Runtime.evaluate', {
  expression: `(async () => {\n${code}\n})()`,
  awaitPromise: true,
  returnByValue: true,
});
ws.close();
if (r.result?.exceptionDetails) {
  console.error(JSON.stringify(r.result.exceptionDetails, null, 1));
  process.exit(1);
}
console.log(JSON.stringify(r.result?.result?.value, null, 1));
