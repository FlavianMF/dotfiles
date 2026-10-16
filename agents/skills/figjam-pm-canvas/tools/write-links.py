#!/usr/bin/env python3
"""Grava os links do board nos .md de uma empresa (passo 5 da skill).

Uso, da raiz do repo:
  python3 ~/.agents/skills/figjam-pm-canvas/tools/write-links.py <entrada.js> <retorno.json> <fileKey> "<Nome do board>"

<retorno.json> é a saída do run-build.mjs (ou do use_figma). Os pôsteres do retorno estão na mesma
ordem do POSTERS da entrada, que diz o .md de cada um. O índice da empresa (o .md sem sufixo) recebe
o link do board inteiro. O campo trocado é a linha "**Board FigJam desta empresa (rascunho):**" e,
se houver, a linha seguinte de continuação "[índice](...)".
"""
import json
import re
import sys
from pathlib import Path
from urllib.parse import quote

FIELD = '**Board FigJam desta empresa (rascunho):**'


def set_field(path: Path, value: str) -> None:
    lines = path.read_text(encoding='utf-8').split('\n')
    for i, line in enumerate(lines):
        if line.startswith(FIELD):
            end = i + 1
            if end < len(lines) and lines[end].startswith('[índice]('):
                end += 1
            lines[i:end] = [f'{FIELD} {value}']
            path.write_text('\n'.join(lines), encoding='utf-8')
            return
    raise SystemExit(f'campo não encontrado em {path}')


def main() -> None:
    entrada, retorno, file_key, board_name = sys.argv[1:5]
    mds = re.findall(r'^\s*md:\s*"([^"]+)"', Path(entrada).read_text(encoding='utf-8'), re.M)
    posters = json.loads(Path(retorno).read_text(encoding='utf-8'))['posters']
    if len(mds) != len(posters):
        raise SystemExit(f'{len(mds)} pôsteres na entrada, {len(posters)} no retorno')
    for p in posters:
        if p['overflow'] or p['textOverflow'] or p['longWords']:
            raise SystemExit(f"{p['name']} ainda tem overflow/textOverflow/longWords; remonte antes")
    base = f'https://www.figma.com/board/{file_key}/{quote(board_name.replace(" ", "-"), safe="-")}'
    for i, (md, p) in enumerate(zip(mds, posters), 1):
        set_field(Path(md), f"[P{i} no board]({base}?node-id={p['sectionId'].replace(':', '-')})")
        print(f"{md} -> {p['sectionId']}")
    folder = Path(mds[0]).parent
    num = re.match(r'pm-canvas-empresa-(\d+)-', Path(mds[0]).name).group(1)
    index = folder / f'pm-canvas-empresa-{num}.md'
    n = len(posters)
    set_field(index, f'[{board_name}]({base}) ({n} pôsteres P1–P{n})')
    print(f'{index} -> board')


if __name__ == '__main__':
    main()
