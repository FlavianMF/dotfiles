// build-poster.js — cola direto no `code` do use_figma (FigJam, figma.com/board/...).
// Reconstrói N pôsteres PM Canvas no layout do template "PM Canvas — Template
// Residência PNAAT Cariri" e preenche stickies. Edite só a seção ENTRADA.
// Medidas: print CDP do template (1 px de tela = S unidades de canvas). Ver README.md.
// v2: fonte 40 fixa, altura das faixas variável (bloco cheio cresce), teto de proporção.

// ===== ENTRADA ==============================================================
const S = 4.1;        // fator de escala; 4.1 = 3 stickies por linha nas colunas de 232
const ASPECT = 1.78;  // largura/altura mínima do pôster (16:9); acima disso vira overflow
const POSTERS = [
  {
    name: 'P1 · Exemplo',                          // nome da section (navegação)
    title: 'PM Canvas — Empresa 0N — Nome — P1: Exemplo',
    md: 'Pasta/pm-canvas-empresa-0N-exemplo.md',   // aparece no subtítulo
    // stickies por bloco, ≤ 6 palavras cada; prefixo § = sticky cinza. Omitir = bloco vazio.
    // Um item pode ser uma lista de variantes: vale a 1ª sem palavra quebrada nem estouro.
    stickies: {
      just: ['Dor 1', 'Dor 2'],
      eq: ['§Alunos: a preencher'],
    },
    date: '§Visita: a preencher', // sticky no canto direito; null = sem
  },
];
const RENAME = {}; // opcional: { '1:6': 'P1 · Nome (v1)' } renomeia sections antigas na mesma chamada
const REMOVE = []; // opcional: ids de sections a apagar na mesma chamada (remontagem)
// ============================================================================

const h = (hex) => ({ r: parseInt(hex.slice(1,3),16)/255, g: parseInt(hex.slice(3,5),16)/255, b: parseInt(hex.slice(5,7),16)/255 });
const CHAR = h('#1e1e1e');
const G = '§';
const GRAY = '#E6E6E6';
await figma.loadFontAsync({ family: 'Inter', style: 'Bold' });
await figma.loadFontAsync({ family: 'Inter', style: 'Regular' });
await figma.loadFontAsync({ family: 'Inter', style: 'Medium' });

// Cores amostradas do template (fundo/borda do bloco, fundo/borda da tag) + sticky FigJam
const COL = {
  purple: { fill: '#f8f5ff', stroke: '#e3d6ff', tag: '#dcccff', tagStroke: '#9f73ff', sticky: '#D3BDFF' },
  yellow: { fill: '#fffbf0', stroke: '#fff0ca', tag: '#ffecbd', tagStroke: '#ffd366', sticky: '#FFE299' },
  red:    { fill: '#fff5f5', stroke: '#ffcdc8', tag: '#ffc7c2', tagStroke: '#f56c4f', sticky: '#FFB8A8' },
  green:  { fill: '#ebffee', stroke: '#d1f5d6', tag: '#cdf4d3', tagStroke: '#83de8f', sticky: '#B3EFBD' },
  blue:   { fill: '#f5fbff', stroke: '#c8e8ff', tag: '#c2e5ff', tagStroke: '#63bdff', sticky: '#A8DAFF' },
};
// Geometria horizontal em px de tela, relativa ao canto do pôster (template)
const CX = [39, 301, 563, 825, 1087];
// Faixas verticais: 0 = linha de cima, 1 = segunda, '01' = bloco alto (0+1), 2, 3.
// key, rótulo, subtítulo, cor, x, largura, faixa, largura da tag
const BLOCKS = [
  ['just', 'Justificativas', 'Passado, dores, coisas ruins', 'purple', CX[0], 232, 0, 102],
  ['obj', 'Objetivos', 'Finalidade dos esforços — deve ser SMART', 'purple', CX[0], 232, 1, 78],
  ['ben', 'Benefícios', 'Futuro, valor, coisas boas', 'purple', CX[0], 494, 2, 84],
  ['prod', 'Produto', 'Resultado final (produto ou serviço)', 'yellow', CX[1], 232, 0, 67],
  ['req', 'Requisitos', 'Qualidade', 'yellow', CX[1], 232, 1, 84],
  ['stk', 'Stakeholders Externos', 'Afetados ou decisores, não subordinados ao GP', 'red', CX[2], 232, '01', 165],
  ['eq', 'Equipe', 'Quem produz o projeto', 'red', CX[2], 232, 2, 60],
  ['prem', 'Premissas', 'Suposição', 'green', CX[3], 232, '01', 83],
  ['ent', 'Grupos de Entregas', 'Tangível, mensurável, verificável', 'green', CX[3], 232, 2, 148],
  ['restr', 'Restrições', 'Limitante', 'green', CX[0], 1018, 3, 85],
  ['risk', 'Riscos', 'Futuros, incertos, relevantes', 'blue', CX[4], 232, '01', 58],
  ['lt', 'Linha do Tempo', 'Compromisso, estimativa', 'blue', CX[4], 232, 2, 118],
  ['cust', 'Custos', 'Aproximado, desejável, resumido', 'blue', CX[4], 232, 3, 68],
];
const HEADERS = ['POR QUÊ?', 'O QUÊ?', 'QUEM?', 'COMO?', 'QUANDO E QUANTO?'];
const FS = 40;                              // fonte fixa de todo sticky (não encolhe)
let MAX_H = 250;                            // teto de 3 linhas; recalibrado abaixo pela medida real
const SUB_FS = Math.max(7 * S, 40);         // subtítulo do bloco: legível no fit
const Y0 = 146 * S, GAP = 7 * S, BOTTOM = 39 * S;
const DATE_X = (CX[4] + 232 + 20) * S;      // coluna estreita à direita, só para o sticky de data
const POSTER_W = DATE_X + 240 + 39 * S;
const GAP_POSTERS = 1200;
const PAD = 40, SG = 32, TAIL = 24;         // grid de stickies dentro do bloco

function text(parent, chars, size, style, x, y, w) {
  const t = figma.createText();
  t.fontName = { family: 'Inter', style };
  t.characters = chars;
  t.fontSize = size;
  t.fills = [{ type: 'SOLID', color: CHAR }];
  parent.appendChild(t);
  if (w) { t.textAutoResize = 'HEIGHT'; t.resize(w, t.height); }
  t.x = x; t.y = y;
  return t;
}
// Encolhe a fonte até o texto caber em 1 linha (título e linha de registro)
function oneLine(t, min) {
  const one = () => { const c = t.characters; t.characters = 'X'; const hh = t.height; t.characters = c; return hh; };
  while (t.height > one() * 1.2 && t.fontSize > min) t.fontSize = t.fontSize - 2;
  return t;
}
function shape(parent, w, hh, fill, stroke, sw) {
  const s = figma.createShapeWithText();
  s.shapeType = 'ROUNDED_RECTANGLE';
  parent.appendChild(s);
  s.resize(w, hh);
  s.fills = [{ type: 'SOLID', color: h(fill) }];
  s.strokes = [{ type: 'SOLID', color: h(stroke) }];
  try { s.strokeWeight = sw; } catch (e) {}
  return s;
}

const probe = figma.createSticky(); probe.authorVisible = false; // sem nome do autor: no navegador ele soma 16 de altura
const STICKY_FONT = probe.text.fontName;
await figma.loadFontAsync(STICKY_FONT);
// A altura de 3 linhas muda com o ambiente: 244 via MCP, 280 no navegador. Mede aqui e usa como teto.
probe.text.fontSize = 40;
probe.text.characters = 'a\na\na';
MAX_H = probe.height + 6;
probe.remove();

// Palavra que não cabe numa linha do sticky a 40 (quebra no meio): teste empírico,
// 6 linhas da palavra × 6 linhas de "a" — se quebra, o sticky fica mais alto.
const wordCache = {};
function breaks(word) {
  if (!(word in wordCache)) {
    const t = figma.createSticky(); t.authorVisible = false; // sem nome do autor: no navegador ele soma 16 de altura
    t.text.fontSize = FS;
    t.text.characters = Array(6).fill('a').join('\n');
    const h0 = t.height;
    t.text.characters = Array(6).fill(word).join('\n');
    wordCache[word] = t.height > h0;
    t.remove();
  }
  return wordCache[word];
}
const brokenWords = (txt) => txt.split(/\s+/).filter(wd => wd.length > 6 && breaks(wd));

const removed = [];
for (const id of REMOVE) {
  const n = await figma.getNodeByIdAsync(id);
  if (n) { n.remove(); removed.push(id); }
}
const renamed = [];
for (const [id, nm] of Object.entries(RENAME)) {
  const n = await figma.getNodeByIdAsync(id);
  if (n) { n.name = nm; renamed.push(id); }
}

let startX = 0;
for (const n of figma.currentPage.children) startX = Math.max(startX, n.x + n.width + 1000);
const result = [];

for (let i = 0; i < POSTERS.length; i++) {
  const P = POSTERS[i];
  const sec = figma.createSection();
  sec.name = P.name;
  sec.x = startX + i * (POSTER_W + GAP_POSTERS);
  sec.y = 0;
  sec.fills = [{ type: 'SOLID', color: h('#ffffff') }];
  oneLine(text(sec, P.title, 32 * S, 'Bold', 39 * S, 30 * S, POSTER_W - 78 * S), 20 * S);
  oneLine(text(sec, `Project Model Canvas (José Finocchio Jr., 13 blocos, formato oficial) — cobre o negócio da residência. Registro: ${P.md}`, 13.5 * S, 'Regular', 39 * S, 78 * S, POSTER_W - 78 * S), 9 * S);
  HEADERS.forEach((hd, c) => text(sec, hd, 15 * S, 'Bold', CX[c] * S, 116 * S));

  const overflow = [], textOverflow = [], longWords = [], chosen = [], stickyIds = [];
  const blocks = [];
  // 1ª passada: cria bloco, tag, subtítulo e stickies; mede a altura que cada bloco pede
  for (const [key, label, sub, col, x, w, band, tagW] of BLOCKS) {
    const C = COL[col];
    const b = shape(sec, w * S, 100, C.fill, C.stroke, 1 * S);
    b.name = label;
    const tag = shape(sec, tagW * S, 20 * S, C.tag, C.tagStroke, 1 * S);
    tag.name = label + ' (tag)';
    await figma.loadFontAsync(tag.text.fontName);
    tag.text.characters = label;
    tag.text.fontSize = 14 * S;
    tag.text.fills = [{ type: 'SOLID', color: CHAR }];
    { // a tag cresce para o rótulo não sair truncado (o padding interno do shape não escala com S)
      const m = figma.createText(); m.fontName = tag.text.fontName; m.fontSize = 14 * S; m.characters = label;
      tag.resize(Math.max(tagW * S, m.width + 120), 20 * S); m.remove();
    }
    const st_ = text(sec, sub, SUB_FS, 'Regular', 0, 0, (w - 22) * S);
    const head = Math.max(44 * S, 29 * S + st_.height + 16);

    const made = [];
    for (const item of (P.stickies && P.stickies[key]) || []) {
      const variants = Array.isArray(item) ? item : [item];
      const st = figma.createSticky(); st.authorVisible = false; // sem nome do autor: no navegador ele soma 16 de altura
      sec.appendChild(st);
      st.text.fontSize = FS;
      let raw, bad;
      for (raw of variants) {
        st.text.characters = raw.startsWith(G) ? raw.slice(1) : raw;
        bad = brokenWords(st.text.characters);
        if (!bad.length && st.height <= MAX_H) break;
      }
      const gray = raw.startsWith(G);
      const txt = st.text.characters;
      st.fills = [{ type: 'SOLID', color: h(gray ? GRAY : C.sticky) }];
      if (st.height > MAX_H) textOverflow.push({ key, text: txt, height: st.height });
      for (const wd of bad) longWords.push({ key, word: wd });
      if (variants.length > 1) chosen.push({ key, text: txt, variant: variants.indexOf(raw) });
      made.push(st);
      stickyIds.push(st.id);
    }
    const cols = Math.max(1, Math.floor((w * S - 2 * PAD + SG) / (240 + SG)));
    const rows = [];
    for (let k = 0; k < made.length; k += cols) rows.push(made.slice(k, k + cols));
    const gridH = rows.length
      ? rows.reduce((a, r) => a + Math.max(...r.map(s => s.height)), 0) + SG * (rows.length - 1)
      : 240; // bloco vazio ainda reserva 1 linha
    blocks.push({ key, x, w, band, b, tag, sub: st_, head, rows, need: head + gridH + TAIL });
  }

  // Altura das faixas: cada faixa = maior necessidade entre seus blocos; bloco alto divide o excesso
  const need = (bd) => Math.max(0, ...blocks.filter(o => o.band === bd).map(o => o.need));
  let H0 = need(0), H1 = need(1);
  const tall = need('01');
  if (H0 + GAP + H1 < tall) { const d = tall - (H0 + GAP + H1); H0 += d / 2; H1 += d / 2; }
  const H2 = need(2), H3 = need(3);
  const Y1 = Y0 + H0 + GAP, Y2 = Y1 + H1 + GAP, Y3 = Y2 + H2 + GAP;
  const BAND = { 0: [Y0, H0], 1: [Y1, H1], '01': [Y0, H0 + GAP + H1], 2: [Y2, H2], 3: [Y3, H3] };

  // 2ª passada: posiciona
  for (const o of blocks) {
    const [by, bh] = BAND[o.band];
    o.b.resize(o.w * S, bh); o.b.x = o.x * S; o.b.y = by;
    o.tag.x = (o.x + 6) * S; o.tag.y = by + 7 * S;
    o.sub.x = (o.x + 11) * S; o.sub.y = by + 29 * S;
    let yy = by + o.head;
    for (const row of o.rows) {
      let xx = o.x * S + PAD;
      for (const st of row) { st.x = xx; st.y = yy; xx += st.width + SG; }
      yy += Math.max(...row.map(s => s.height)) + SG;
    }
  }
  if (P.date) {
    const gray = P.date.startsWith(G);
    const txt = gray ? P.date.slice(1) : P.date;
    const st = figma.createSticky(); st.authorVisible = false; // sem nome do autor: no navegador ele soma 16 de altura
    sec.appendChild(st);
    st.text.characters = txt;
    st.text.fontSize = FS;
    st.fills = [{ type: 'SOLID', color: h(GRAY) }];
    st.x = DATE_X; st.y = Y0;
    // a data fica sozinha na coluna da direita: pode passar de 3 linhas, só não pode quebrar palavra
    for (const wd of brokenWords(txt)) longWords.push({ key: 'date', word: wd });
    stickyIds.push(st.id);
  }
  const H = Y3 + H3 + BOTTOM;
  sec.resize(POSTER_W, H);
  if (H > POSTER_W / ASPECT) overflow.push({ key: 'poster', height: Math.round(H), limit: Math.round(POSTER_W / ASPECT) });
  result.push({
    sectionId: sec.id, name: P.name, width: Math.round(POSTER_W), height: Math.round(H),
    ratio: +(POSTER_W / H).toFixed(2), bands: [H0, H1, H2, H3].map(Math.round),
    stickyCount: stickyIds.length, overflow, textOverflow, longWords, chosen,
  });
}
return { posters: result, renamed, removed };
