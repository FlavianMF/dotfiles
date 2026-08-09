"""Minimal stdlib-only YAML-frontmatter parser/serializer for the vault's notes.

The vault's frontmatter is always flat: `key: value` or `key: [a, b, c]`,
never nested. A hand-rolled ~30-line parser is enough and easier to audit
than pulling in PyYAML (which install.sh never guarantees is present).
"""
from __future__ import annotations

from pathlib import Path
from typing import Any


def split_frontmatter(text: str) -> tuple[list[str] | None, str]:
    """Return (frontmatter_lines, body). frontmatter_lines is None if text has no frontmatter block."""
    if not (text.startswith("---\n") or text.startswith("---\r\n")):
        return None, text
    lines = text.splitlines(keepends=True)
    end_idx = None
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            end_idx = i
            break
    if end_idx is None:
        return None, text
    fm_lines = lines[1:end_idx]
    body = "".join(lines[end_idx + 1 :])
    return fm_lines, body


def parse_frontmatter(fm_lines: list[str]) -> tuple[dict[str, Any], list[str]]:
    """Return (data, key_order) parsed from raw frontmatter lines."""
    data: dict[str, Any] = {}
    order: list[str] = []
    for raw_line in fm_lines:
        line = raw_line.rstrip("\n").rstrip("\r")
        if not line.strip() or ":" not in line:
            continue
        key, _, value = line.partition(":")
        key = key.strip()
        value = value.strip()
        if value.startswith("[") and value.endswith("]"):
            inner = value[1:-1].strip()
            data[key] = [item.strip() for item in inner.split(",")] if inner else []
        else:
            data[key] = value
        order.append(key)
    return data, order


def serialize_frontmatter(data: dict[str, Any], order: list[str]) -> str:
    lines = ["---"]
    for key in order:
        value = data[key]
        if isinstance(value, list):
            lines.append(f"{key}: [{', '.join(value)}]")
        else:
            lines.append(f"{key}: {value}")
    lines.append("---")
    return "\n".join(lines) + "\n"


def read_note(path: Path) -> tuple[dict[str, Any], list[str], str]:
    """Return (frontmatter_data, key_order, body). Empty dict/list if no frontmatter present."""
    text = path.read_text(encoding="utf-8")
    fm_lines, body = split_frontmatter(text)
    if fm_lines is None:
        return {}, [], text
    data, order = parse_frontmatter(fm_lines)
    return data, order, body


def write_note(path: Path, data: dict[str, Any], order: list[str], body: str) -> None:
    fm_text = serialize_frontmatter(data, order)
    if body and not body.startswith("\n"):
        body = "\n" + body
    path.write_text(fm_text + body, encoding="utf-8")


def has_frontmatter(text: str) -> bool:
    fm_lines, _ = split_frontmatter(text)
    return fm_lines is not None
