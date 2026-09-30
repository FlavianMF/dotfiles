#!/usr/bin/env python3
"""Converte agents no formato do Claude Code para o formato do OpenCode.

O frontmatter do Claude (`tools: Read, Grep`, `model: sonnet`, `name`, `color`) não é
válido no OpenCode: `tools` lá é um mapa (deprecado), `model` é `provider/model` e campos
desconhecidos são repassados ao provider. Este script mantém só `description`, marca o
agent como `mode: subagent` e traduz o escopo de ferramentas para `permission`:
sem Write/Edit -> edit: deny; sem Bash -> bash: deny. O corpo é copiado como está.

Uso: render_agents.py SRC_DIR DST_DIR [--prefix ecc-] [--dry-run]
Escreve só arquivos que mudaram; imprime o que escreveu. Exit 0.
"""
import argparse
import json
import re
import sys
from pathlib import Path

FRONTMATTER = re.compile(r"\A---\n(.*?)\n---\n", re.S)


def parse_frontmatter(text: str) -> tuple[dict, str]:
    m = FRONTMATTER.match(text)
    if not m:
        raise ValueError("sem frontmatter")
    fields = {}
    for line in m.group(1).splitlines():
        key, sep, value = line.partition(":")
        if not sep or line.startswith(" "):
            raise ValueError(f"frontmatter fora do formato chave: valor simples: {line!r}")
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] == '"':
            value = json.loads(value)
        fields[key.strip()] = value
    return fields, text[m.end():]


def convert(text: str) -> str:
    fields, body = parse_frontmatter(text)
    if "description" not in fields:
        raise ValueError("sem description")
    tools = {t.strip() for t in fields.get("tools", "").split(",") if t.strip()}
    lines = ["---", "description: " + json.dumps(fields["description"], ensure_ascii=False), "mode: subagent"]
    perms = []
    if tools and not tools & {"Write", "Edit", "MultiEdit"}:
        perms.append("  edit: deny")
    if tools and "Bash" not in tools:
        perms.append("  bash: deny")
    if perms:
        lines += ["permission:"] + perms
    lines.append("---")
    return "\n".join(lines) + "\n" + body


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("src", type=Path)
    ap.add_argument("dst", type=Path)
    ap.add_argument("--prefix", default="")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    for src in sorted(args.src.glob("*.md")):
        out = convert(src.read_text())
        dst = args.dst / f"{args.prefix}{src.name}"
        if dst.is_file() and not dst.is_symlink() and dst.read_text() == out:
            continue
        print(f"{'[dry-run] ' if args.dry_run else ''}write {dst}")
        if not args.dry_run:
            args.dst.mkdir(parents=True, exist_ok=True)
            if dst.is_symlink():
                dst.unlink()
            dst.write_text(out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
