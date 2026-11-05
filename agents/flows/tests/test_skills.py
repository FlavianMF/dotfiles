"""Contrato das skills `/flow` e `/phase` (T7): invocação só explícita, tamanho e link no install.sh."""

import re
import subprocess
import sys
from pathlib import Path

import pytest
import yaml

from tests.conftest import FLOWS_DIR

REPO = FLOWS_DIR.parent.parent
SKILLS = ("flow", "phase")


def _frontmatter(name):
    text = (REPO / "agents" / "skills" / name / "SKILL.md").read_text(encoding="utf-8")
    match = re.match(r"^---\n(.*?)\n---\n", text, re.S)
    assert match, f"{name}: no frontmatter"
    return yaml.safe_load(match.group(1)), text


@pytest.mark.parametrize("name", SKILLS)
def test_skill_is_only_invoked_explicitly(name):
    meta, _ = _frontmatter(name)
    assert meta["name"] == name
    assert meta["disable-model-invocation"] is True
    assert meta["description"]


@pytest.mark.parametrize("name", SKILLS)
def test_skill_has_at_most_40_lines_and_does_not_repeat_the_yaml(name):
    _, text = _frontmatter(name)
    assert len(text.splitlines()) <= 40
    flow_yaml = (FLOWS_DIR / "flows" / "ecc-dev.yaml").read_text(encoding="utf-8")
    for token in re.findall(r"model: ([\w.-]+)", flow_yaml):
        assert f"model: {token}" not in text


@pytest.mark.parametrize("name", SKILLS)
def test_install_links_the_skill_for_the_three_harnesses(name):
    install = (REPO / "install.sh").read_text(encoding="utf-8")
    assert f'link_shared_skill {name} "$REPO_DIR/agents/skills/{name}"' in install
    assert f'"$HOME/.claude/skills/{name}"' in install  # backup list
    assert f'"$HOME/.agents/skills/{name}"' in install


def test_the_command_in_the_skills_runs_from_any_directory(tmp_path):
    """`PYTHONPATH=agents/flows python3 -m engine.cli` funciona fora do diretório do motor."""
    proc = subprocess.run(
        [sys.executable, "-m", "engine.cli", "--help"],
        cwd=tmp_path,
        env={"PYTHONPATH": str(FLOWS_DIR), "PATH": "/usr/bin:/bin"},
        capture_output=True,
        text=True,
        check=False,
    )
    assert proc.returncode == 0 and "run,status,approve,phase" in proc.stdout
