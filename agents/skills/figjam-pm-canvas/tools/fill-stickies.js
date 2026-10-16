// fill-stickies.js — cola direto no `code` do use_figma (FigJam).
// Preenche stickies num pôster PM Canvas JÁ montado por build-poster.js (v2).
// Blocos são achados pelo nome do ShapeWithText dentro da section (rótulo exato).
// Não apaga stickies existentes: novos entram abaixo dos que já estão no bloco.
// Não cresce o bloco: se não couber, acusa `overflow`; para crescer, remonte com build-poster.js.

// ===== ENTRADA ==============================================================
const SECTION_ID = '3:128';
// ≤ 6 palavras por sticky; prefixo § = sticky cinza "a preencher"
const STICKIES = {
  just: ['Dor 1', 'Dor 2'],
  // obj, ben, prod, req, stk, eq, prem, ent, restr, risk, lt, cust
};
const DATE = '§Visita: a preencher'; // sticky à direita de Riscos; null = sem
const S = 4.1; // mesmo fator do build-poster.js
// ============================================================================

const h = (hex) => ({ r: parseInt(hex.slice(1,3),16)/255, g: parseInt(hex.slice(3,5),16)/255, b: parseInt(hex.slice(5,7),16)/255 });
const G = '§', GRAY = '#E6E6E6';
const LABEL = {
  just: 'Justificativas', obj: 'Objetivos', ben: 'Benefícios', prod: 'Produto',
  req: 'Requisitos', stk: 'Stakeholders Externos', eq: 'Equipe', prem: 'Premissas',
  ent: 'Grupos de Entregas', restr: 'Restrições', risk: 'Riscos', lt: 'Linha do Tempo', cust: 'Custos',
};
const STICKY_COLOR = {
  just: '#D3BDFF', obj: '#D3BDFF', ben: '#D3BDFF', prod: '#FFE299', req: '#FFE299',
  stk: '#FFB8A8', eq: '#FFB8A8', prem: '#B3EFBD', ent: '#B3EFBD', restr: '#B3EFBD',
  risk: '#A8DAFF', lt: '#A8DAFF', cust: '#A8DAFF',
};
const FS = 40, PAD = 40, SG = 32, TAIL = 24; // a 40 cabem 3 linhas
let MAX_H = 250; // teto de 3 linhas; recalibrado abaixo pela medida real

const sec = await figma.getNodeByIdAsync(SECTION_ID);
if (!sec || sec.type !== 'SECTION') throw new Error('section não encontrada: ' + SECTION_ID);
const shapes = sec.children.filter(n => n.type === 'SHAPE_WITH_TEXT');
const inside = (n, b) => n.x >= b.x && n.x < b.x + b.width && n.y >= b.y && n.y < b.y + b.height;

const probe = figma.createSticky(); probe.authorVisible = false; // sem nome do autor: no navegador ele soma 16 de altura
await figma.loadFontAsync(probe.text.fontName);
// A altura de 3 linhas muda com o ambiente: 244 via MCP, 280 no navegador. Mede aqui e usa como teto.
probe.text.fontSize = 40;
probe.text.characters = 'a\na\na';
MAX_H = probe.height + 6;
probe.remove();

const created = [], overflow = [], textOverflow = [], missing = [];
for (const [key, items] of Object.entries(STICKIES)) {
  const b = shapes.find(s => s.name === LABEL[key]);
  if (!b) { missing.push(key); continue; }
  // topo da grade = logo abaixo do subtítulo do bloco
  const sub = sec.children.filter(n => n.type === 'TEXT' && inside(n, b)).sort((a, c) => c.y - a.y)[0];
  const top = sub ? sub.y + sub.height + 16 : b.y + 44 * S;
  const existing = sec.children.filter(n => n.type === 'STICKY' && inside(n, b));
  const made = [];
  for (const raw of items) {
    const gray = raw.startsWith(G);
    const st = figma.createSticky(); st.authorVisible = false; // sem nome do autor: no navegador ele soma 16 de altura
    sec.appendChild(st);
    st.text.characters = gray ? raw.slice(1) : raw;
    st.text.fontSize = FS;
    st.fills = [{ type: 'SOLID', color: h(gray ? GRAY : STICKY_COLOR[key]) }];
    if (st.height > MAX_H) textOverflow.push({ key, text: st.text.characters, height: st.height });
    made.push(st);
    created.push(st.id);
  }
  const all = existing.sort((a, c) => a.y - c.y || a.x - c.x).concat(made);
  const cols = Math.max(1, Math.floor((b.width - 2 * PAD + SG) / (240 + SG)));
  let y = top, idx = 0;
  while (idx < all.length) {
    const row = all.slice(idx, idx + cols);
    let x = b.x + PAD;
    for (const st of row) { st.x = x; st.y = y; x += st.width + SG; }
    y += Math.max(...row.map(s => s.height)) + SG;
    idx += cols;
  }
  if (y - SG > b.y + b.height - TAIL) overflow.push({ key, bottom: y - SG, limit: b.y + b.height - TAIL });
}
if (DATE) {
  const risk = shapes.find(s => s.name === LABEL.risk);
  const gray = DATE.startsWith(G);
  const st = figma.createSticky(); st.authorVisible = false; // sem nome do autor: no navegador ele soma 16 de altura
  sec.appendChild(st);
  st.text.characters = gray ? DATE.slice(1) : DATE;
  st.text.fontSize = FS;
  st.fills = [{ type: 'SOLID', color: h(GRAY) }];
  st.x = risk ? risk.x + risk.width + 20 * S : sec.width - 240 - 39 * S;
  st.y = risk ? risk.y : 146 * S;
  if (st.height > MAX_H) textOverflow.push({ key: 'date', text: st.text.characters, height: st.height });
  created.push(st.id);
}
return { createdNodeIds: created, count: created.length, overflow, textOverflow, missing };
