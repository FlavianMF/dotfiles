#!/usr/bin/env node
// Gera o bloco ENTRADA de build-poster.js a partir dos *.stickies.md de uma empresa.
// Uso (da raiz do repo ou de qualquer lugar):
//   node ~/.agents/skills/figjam-pm-canvas/tools/stickies-to-entrada.mjs <Pasta> [--rename-v1] > ~/.agents/skills/figjam-pm-canvas/tools/entradas/<empresa>.js
// Convenções do .stickies.md: título "# Stickies — ... — Pn: <nome curto>", um "### <chave>" por bloco,
// um "- item" por sticky, "§ " = pendente (cinza), "a || b" = variantes, "### date" = linhas do sticky de data.
// Erro (stderr, exit 1): sticky > 6 palavras, chave desconhecida, pôster com > 6 linhas de stickies
// (teto 16:9 com S = 4.1: altura ≈ 1612 + 276·linhas ≤ 5890/1.78). Aviso (stderr): palavra > 9 letras sem
// variante; ela pode quebrar no meio (longWords no build-poster), então dê uma variante "a || b" sem ela.
import { readFileSync, readdirSync } from 'node:fs';
import { join, relative, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const KEYS = ['just', 'obj', 'ben', 'prod', 'req', 'stk', 'eq', 'prem', 'ent', 'restr', 'risk', 'lt', 'cust'];
const MAX_WORDS = 6;
const MAX_LETTERS = 9;

const args = process.argv.slice(2);
const renameV1 = args.includes('--rename-v1');
const folder = args.find((a) => !a.startsWith('--'));
if (!folder) {
  console.error('uso: stickies-to-entrada.mjs <Pasta> [--rename-v1]');
  process.exit(2);
}
// Raiz do repo da empresa: rode a partir dela (os caminhos de <Pasta> e md são relativos a ela).
const ROOT = process.cwd();
const dir = resolve(ROOT, folder);
const errors = [];
const warnings = [];

const norm = (s) => s.trim().replace(/^§\s+/, '§');
const words = (s) => s.replace(/^§/, '').split(/\s+/).filter((w) => /[\p{L}\p{N}]/u.test(w));
const letters = (w) => w.replace(/[^\p{L}]/gu, '').length;

function check(file, key, text, hasVariants) {
  const ws = words(text);
  if (ws.length > MAX_WORDS) errors.push(`${file} [${key}] ${ws.length} palavras: "${text}"`);
  if (!hasVariants) {
    for (const w of ws.flatMap((x) => x.split('-'))) {
      if (letters(w) > MAX_LETTERS) warnings.push(`aviso: ${file} [${key}] palavra longa sem variante: "${w}"`);
    }
  }
}

function parse(file) {
  const src = readFileSync(join(dir, file), 'utf8');
  const head = src.match(/^#\s+.*?—\s*P(\d+):\s*(.+)$/m);
  if (!head) throw new Error(`${file}: título sem "Pn: <nome>"`);
  const blocks = {};
  let key = null;
  for (const line of src.split('\n')) {
    const h3 = line.match(/^###\s+(\S+)/);
    if (h3) {
      key = h3[1];
      if (key !== 'date' && !KEYS.includes(key)) errors.push(`${file}: chave desconhecida "${key}"`);
      blocks[key] = [];
      continue;
    }
    const li = line.match(/^-\s+(.+)$/);
    if (li && key) blocks[key].push(li[1]);
  }
  const md = file.replace(/\.stickies\.md$/, '.md');
  const mdTitle = readFileSync(join(dir, md), 'utf8').match(/^#\s+(.+)$/m)?.[1]?.trim();
  if (!mdTitle) throw new Error(`${md}: sem título "#"`);
  const stickies = {};
  for (const k of KEYS) {
    const items = (blocks[k] || []).map((raw) => {
      const vs = raw.split('||').map(norm).filter(Boolean);
      vs.forEach((v) => check(file, k, v, vs.length > 1));
      return vs.length > 1 ? vs : vs[0];
    });
    if (items.length) stickies[k] = items;
  }
  const dateLines = (blocks.date || []).map((s) => norm(s).replace(/^§/, ''));
  return {
    n: Number(head[1]),
    name: `P${head[1]} · ${head[2].trim()}`,
    title: mdTitle,
    md: relative(ROOT, join(dir, md)),
    stickies,
    date: dateLines.length ? '§' + dateLines.join('\n') : null,
  };
}

const files = readdirSync(dir).filter((f) => /^pm-canvas-empresa-\d+-.+\.stickies\.md$/.test(f));
if (!files.length) {
  console.error(`nenhum *.stickies.md em ${dir}`);
  process.exit(2);
}
const posters = files.map(parse).sort((a, b) => a.n - b.n);
posters.forEach((p, i) => {
  if (p.n !== i + 1) errors.push(`numeração dos pôsteres com buraco: esperado P${i + 1}, achei P${p.n}`);
});
// Estimativa do orçamento de linhas (aviso, não erro): ~6 linhas somando as 4 faixas cabem em 16:9.
const PER_ROW = { ben: 7, restr: 15 };
const rows = (p, k) => Math.max(1, Math.ceil((p.stickies[k]?.length || 0) / (PER_ROW[k] || 3)));
for (const p of posters) {
  const b0 = Math.max(rows(p, 'just'), rows(p, 'prod'));
  const b1 = Math.max(rows(p, 'obj'), rows(p, 'req'));
  const tall = Math.max(rows(p, 'stk'), rows(p, 'prem'), rows(p, 'risk'));
  const b2 = Math.max(rows(p, 'ben'), rows(p, 'eq'), rows(p, 'ent'), rows(p, 'lt'));
  const b3 = Math.max(rows(p, 'restr'), rows(p, 'cust'));
  const total = Math.max(b0 + b1, tall) + b2 + b3;
  if (total > 6) errors.push(`${p.name} ~${total} linhas (faixas ${Math.max(b0 + b1, tall)}+${b2}+${b3}); teto ~6`);
}
if (warnings.length) console.error(warnings.join('\n'));
if (errors.length) {
  console.error(errors.join('\n'));
  process.exit(1);
}

const q = (s) => JSON.stringify(s);
const item = (v) => (Array.isArray(v) ? `[${v.map(q).join(', ')}]` : q(v));
const out = [];
out.push(`// ENTRADA gerada por stickies-to-entrada.mjs a partir de ${folder}/*.stickies.md. Não edite à mão: edite o .stickies.md e gere de novo.`);
out.push('// ===== ENTRADA ==============================================================');
out.push('const S = 4.1;');
out.push('const ASPECT = 1.78;');
out.push('const POSTERS = [');
for (const p of posters) {
  out.push('  {');
  out.push(`    name: ${q(p.name)},`);
  out.push(`    title: ${q(p.title)},`);
  out.push(`    md: ${q(p.md)},`);
  out.push('    stickies: {');
  for (const [k, items] of Object.entries(p.stickies)) out.push(`      ${k}: [${items.map(item).join(', ')}],`);
  out.push('    },');
  out.push(`    date: ${p.date === null ? 'null' : q(p.date)},`);
  out.push('  },');
}
out.push('];');
if (renameV1) {
  out.push('const RENAME = {};');
  out.push("for (const n of figma.currentPage.children) if (n.type === 'SECTION' && !n.name.endsWith('(v1)')) RENAME[n.id] = n.name + ' (v1)';");
} else {
  out.push('const RENAME = {};');
}
out.push('const REMOVE = [];');
out.push('// ============================================================================');
process.stdout.write(out.join('\n') + '\n');
