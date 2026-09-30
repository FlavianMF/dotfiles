#!/usr/bin/env python3
"""Renderiza ~/.codex/config.toml a partir de codex/config.base.toml.

O Codex reescreve o próprio config.toml (ex.: ao confiar num projeto grava
[projects."/caminho"]), então o arquivo não pode ser symlink. Este script mescla:
a base versionada vence em cada chave folha; chaves que só existem no arquivo da
máquina são preservadas.

Uso:
  render_config.py BASE TARGET            escreve TARGET (só se mudou)
  render_config.py BASE TARGET --dry-run  imprime o resultado sem escrever
  render_config.py BASE TARGET --drift    lista diferenças máquina x base; exit 1 se a base
                                          não estiver aplicada (chaves só da máquina são informativas)
"""
import argparse
import json
import re
import sys
import tomllib
from pathlib import Path

BARE_KEY = re.compile(r"^[A-Za-z0-9_-]+$")


def merge(machine: dict, base: dict) -> dict:
    out = dict(machine)
    for key, value in base.items():
        if isinstance(value, dict) and isinstance(out.get(key), dict):
            out[key] = merge(out[key], value)
        else:
            out[key] = value
    return out


def fmt_key(key: str) -> str:
    return key if BARE_KEY.match(key) else json.dumps(key)


def fmt_value(value) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return repr(value)
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, list):
        return "[" + ", ".join(fmt_value(v) for v in value) + "]"
    if isinstance(value, dict):
        inner = ", ".join(f"{fmt_key(k)} = {fmt_value(v)}" for k, v in value.items())
        return "{ " + inner + " }" if inner else "{}"
    raise TypeError(f"tipo TOML não suportado: {type(value).__name__}")


def is_table_array(value) -> bool:
    return isinstance(value, list) and bool(value) and all(isinstance(v, dict) for v in value)


def dump(data: dict, prefix: tuple = ()) -> list[str]:
    lines: list[str] = []
    scalars = {k: v for k, v in data.items() if not isinstance(v, dict) and not is_table_array(v)}
    tables = {k: v for k, v in data.items() if isinstance(v, dict)}
    arrays = {k: v for k, v in data.items() if is_table_array(v)}

    if prefix and (scalars or not (tables or arrays)):
        lines.append("[" + ".".join(fmt_key(p) for p in prefix) + "]")
    for key, value in scalars.items():
        lines.append(f"{fmt_key(key)} = {fmt_value(value)}")
    if scalars or (prefix and not (tables or arrays)):
        lines.append("")
    for key, value in tables.items():
        lines.extend(dump(value, prefix + (key,)))
    for key, items in arrays.items():
        header = ".".join(fmt_key(p) for p in prefix + (key,))
        for item in items:
            lines.append(f"[[{header}]]")
            for k, v in item.items():
                lines.append(f"{fmt_key(k)} = {fmt_value(v)}")
            lines.append("")
    return lines


def flatten(data: dict, prefix: str = "") -> dict:
    flat = {}
    for key, value in data.items():
        path = f"{prefix}.{fmt_key(key)}" if prefix else fmt_key(key)
        if isinstance(value, dict) and value:
            flat.update(flatten(value, path))
        else:
            flat[path] = value
    return flat


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("base", type=Path)
    parser.add_argument("target", type=Path)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--dry-run", action="store_true")
    mode.add_argument("--drift", action="store_true")
    args = parser.parse_args()

    base = tomllib.loads(args.base.read_text())
    machine = tomllib.loads(args.target.read_text()) if args.target.exists() else {}

    if args.drift:
        if not args.target.exists():
            print(f"{args.target} não existe (rode ./install.sh com o componente codex).")
            return 1
        fb, fm = flatten(base), flatten(machine)
        drift = False
        for key in sorted(fm.keys() - fb.keys()):
            print(f"+ só na máquina : {key} = {fmt_value(fm[key])}")
        for key in sorted(fb.keys() - fm.keys()):
            print(f"- falta na máquina: {key} = {fmt_value(fb[key])}")
            drift = True
        for key in sorted(fb.keys() & fm.keys()):
            if fb[key] != fm[key]:
                print(f"~ diferente     : {key}: máquina={fmt_value(fm[key])} base={fmt_value(fb[key])}")
                drift = True
        if not drift:
            print("Sem drift: a base está aplicada (linhas + são chaves só desta máquina).")
        return 1 if drift else 0

    header = (
        "# Gerado por ~/dotfiles/install.sh a partir de codex/config.base.toml.\n"
        "# Edite a base no dotfiles; chaves só desta máquina (ex.: [projects.*]) são preservadas.\n\n"
    )
    rendered = header + "\n".join(dump(merge(machine, base))).rstrip() + "\n"
    tomllib.loads(rendered)  # garante que a saída é TOML válido

    if args.dry_run:
        sys.stdout.write(rendered)
        return 0

    args.target.parent.mkdir(parents=True, exist_ok=True)
    # O install.sh já copia o arquivo anterior para ~/.dotfiles-backup/<ts>/.
    if args.target.exists() and args.target.read_text() == rendered:
        return 0
    args.target.write_text(rendered)
    return 0


if __name__ == "__main__":
    sys.exit(main())
