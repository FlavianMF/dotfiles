#!/usr/bin/env python3
"""Idempotent frontmatter backfill for the second-brain vault.

Guardrails (see docs/PRD.md RQ-11 in the pilot project):
  - Never overwrites a field that already has a value.
  - Never fabricates content or frontmatter for a genuinely empty (0-byte) file
    — those are skipped and reported, not touched.
  - Never silently "fixes" a suspicious existing value (e.g. a `provenance`
    that looks numeric instead of a project name / "manual") — flags it for
    manual review instead.

Usage:
    python3 backfill_frontmatter.py --vault-path docs/second_brain --dry-run
    python3 backfill_frontmatter.py --vault-path docs/second_brain
    python3 backfill_frontmatter.py --vault-path docs/second_brain --report-only
"""
from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from lib import frontmatter  # noqa: E402

EXCLUDE_DIR_PARTS = {".obsidian", ".git"}
MANIFEST_DIR_NAME = "00_META/manifests"

REQUIRED_FIELDS = ("title", "type", "tags", "created", "provenance")
FIELD_ORDER = ("title", "type", "tags", "created", "provenance")

FOLDER_TYPE_MAP = {
    "20_Permanent_Notes": "concept",
    "90_Assets": "template",
    "30_MOCs": "moc",
    "40_Projects": "project",
    "00_Inbox": "inbox",
    "10_Literature_Notes": "literature",
    "00_META": "meta",
}


def iter_notes(vault_root: Path):
    for path in sorted(vault_root.rglob("*.md")):
        rel = path.relative_to(vault_root)
        if any(part in EXCLUDE_DIR_PARTS for part in rel.parts):
            continue
        if str(rel).startswith(MANIFEST_DIR_NAME):
            continue
        yield path, rel


def derive_title(body: str, path: Path) -> str:
    for line in body.splitlines():
        stripped = line.strip()
        if stripped.startswith("# "):
            return stripped[2:].strip()
    return path.stem


def derive_type(rel: Path) -> str:
    top = rel.parts[0] if len(rel.parts) > 1 else None
    if rel.name.startswith("Skill - "):
        return "pattern"
    if top and top in FOLDER_TYPE_MAP:
        return FOLDER_TYPE_MAP[top]
    return "unclassified"


def derive_created(vault_root: Path, rel: Path) -> str:
    try:
        result = subprocess.run(
            ["git", "log", "--follow", "--diff-filter=A", "--format=%aI", "--", str(rel)],
            cwd=vault_root,
            capture_output=True,
            text=True,
            check=True,
        )
    except (subprocess.CalledProcessError, FileNotFoundError):
        return ""
    lines = [line for line in result.stdout.strip().splitlines() if line]
    if not lines:
        return ""
    oldest = lines[-1]
    return oldest.split("T", 1)[0]


def looks_like_provenance(value: str) -> bool:
    if value == "manual":
        return True
    try:
        float(value)
    except ValueError:
        return True
    return False


def process_note(vault_root: Path, path: Path, rel: Path) -> tuple[str, str]:
    """Return (status, detail). status in {skipped-empty, unchanged, updated, flagged}."""
    if path.stat().st_size == 0:
        return "skipped-empty", str(rel)

    data, order, body = frontmatter.read_note(path)
    original_data = dict(data)
    flags = []

    if "provenance" in data and not looks_like_provenance(str(data["provenance"])):
        flags.append(f"provenance={data['provenance']!r} looks non-standard, left untouched")

    missing = [f for f in REQUIRED_FIELDS if f not in data]
    if not missing:
        if flags:
            return "flagged", f"{rel}: " + "; ".join(flags)
        return "unchanged", str(rel)

    if "title" not in data:
        data["title"] = derive_title(body, path)
    if "type" not in data:
        data["type"] = derive_type(rel)
    if "tags" not in data:
        data["tags"] = []
    if "created" not in data:
        data["created"] = derive_created(vault_root, rel)
    if "provenance" not in data:
        data["provenance"] = "manual"

    new_order = [f for f in FIELD_ORDER if f in data] + [k for k in order if k not in FIELD_ORDER]
    if data == original_data:
        return "unchanged", str(rel)

    return "updated", (rel, data, new_order, body)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--vault-path", required=True, type=Path)
    parser.add_argument("--dry-run", action="store_true", help="Report what would change, write nothing.")
    parser.add_argument("--report-only", action="store_true", help="Print only summary counts, write nothing.")
    args = parser.parse_args()

    vault_root = args.vault_path.resolve()
    if not vault_root.is_dir():
        print(f"error: vault path not found: {vault_root}", file=sys.stderr)
        return 2

    write = not (args.dry_run or args.report_only)

    counts = {"skipped-empty": 0, "unchanged": 0, "updated": 0, "flagged": 0}
    updated_details = []
    flagged_details = []
    skipped_details = []

    for path, rel in iter_notes(vault_root):
        status, detail = process_note(vault_root, path, rel)
        counts[status] += 1
        if status == "updated":
            rel_, data, new_order, body = detail
            if write:
                frontmatter.write_note(path, data, new_order, body)
            updated_details.append(str(rel_))
        elif status == "flagged":
            flagged_details.append(detail)
        elif status == "skipped-empty":
            skipped_details.append(detail)

    if not args.report_only:
        for rel in updated_details:
            print(f"{'would update' if not write else 'updated'}: {rel}")
        for detail in flagged_details:
            print(f"FLAGGED (manual review): {detail}")
        for rel in skipped_details:
            print(f"SKIPPED (empty): {rel}")

    print(
        f"\nsummary: {counts['updated']} updated, {counts['unchanged']} unchanged, "
        f"{counts['flagged']} flagged, {counts['skipped-empty']} skipped (empty)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
