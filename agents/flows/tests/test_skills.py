"""Contrato das skills `/flow` e `/phase` (T7): invocação só explícita, tamanho e link no install.sh."""

import os
import re
import shlex
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
def test_install_links_the_skill_for_claude_code_only(name):
    """Codex e OpenCode leem ~/.agents/skills e podem ignorar `disable-model-invocation`: não entram lá."""
    install = (REPO / "install.sh").read_text(encoding="utf-8")
    assert f'link_claude_skill {name} "$REPO_DIR/agents/skills/{name}"' in install
    assert f"link_shared_skill {name}" not in install
    assert f'"$HOME/.claude/skills/{name}"' in install  # backup list
    assert f"remove_stale_shared_link {name}" in install  # um install anterior deixou o link em ~/.agents/skills


def _install_function(name):
    text = (REPO / "install.sh").read_text(encoding="utf-8")
    match = re.search(rf"^{name}\(\) \{{\n.*?^\}}\n", text, re.S | re.M)
    assert match, f"{name} not found in install.sh"
    return match.group(0)


def test_remove_stale_shared_link_removes_only_links_into_a_dotfiles_skill_dir(tmp_path):
    home = tmp_path / "home"
    skills = home / ".agents" / "skills"
    skills.mkdir(parents=True)
    (skills / "flow").symlink_to(REPO / "agents" / "skills" / "flow")  # deste checkout
    (skills / "phase").symlink_to("/outro/checkout/dotfiles/agents/skills/phase")  # de outro checkout (nem existe)
    (skills / "foreign").symlink_to("/elsewhere/foreign")  # link alheio
    (skills / "other").symlink_to("/outro/checkout/dotfiles/agents/skills/another")  # outra skill: alvo não termina em /agents/skills/other
    (skills / "realdir").mkdir()
    (skills / "realdir" / "keep.txt").write_text("x", encoding="utf-8")
    script = "as_user() { \"$@\"; }\n" + _install_function("remove_stale_shared_link")
    script += "\nfor n in flow phase foreign other realdir; do remove_stale_shared_link \"$n\"; done"
    proc = subprocess.run(["bash", "-c", script], env={"HOME": str(home), "PATH": "/usr/bin:/bin"}, capture_output=True, text=True, check=False)
    assert proc.returncode == 0, proc.stderr
    assert sorted(p.name for p in skills.iterdir()) == ["foreign", "other", "realdir"]
    assert (skills / "realdir" / "keep.txt").exists()


def test_skills_readme_documents_the_claude_only_install():
    readme = (REPO / "agents" / "skills" / "README.md").read_text(encoding="utf-8")
    assert "disable-model-invocation" in readme and "Codex" in readme and "OpenCode" in readme


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


def _resolve_snippet(name):
    """As linhas `FLOWS_DIR=...` da skill, que o agente roda antes de chamar o motor."""
    text = (REPO / "agents" / "skills" / name / "SKILL.md").read_text(encoding="utf-8")
    lines = [line for line in text.splitlines() if line.startswith(("SKILL_DIR=", "FLOWS_DIR="))]
    assert [l.split("=")[0] for l in lines] == ["SKILL_DIR", "FLOWS_DIR"], f"{name}: snippet missing"
    return "\n".join(lines)


def _run_snippet(name, skill_dir, extra_env=None):
    script = re.sub(r"^SKILL_DIR=.*$", lambda _: f"SKILL_DIR={shlex.quote(str(skill_dir))}", _resolve_snippet(name), count=1, flags=re.M)
    script += '\nPYTHONPATH="$FLOWS_DIR" python3 -m engine.cli --help >/dev/null && echo "$FLOWS_DIR"'
    env = {"PATH": "/usr/bin:/bin", "HOME": "/nonexistent", **(extra_env or {})}
    return subprocess.run(["bash", "-c", script], env=env, capture_output=True, text=True, check=False)


@pytest.mark.parametrize("name", SKILLS)
def test_skill_finds_the_engine_from_its_own_location_through_a_symlink(name, tmp_path):
    """Instalada como link em ~/.claude/skills, a skill acha `agents/flows` sem depender de $HOME/dotfiles."""
    link = tmp_path / ".claude" / "skills" / name
    link.parent.mkdir(parents=True)
    link.symlink_to(REPO / "agents" / "skills" / name)
    proc = _run_snippet(name, link)
    assert proc.returncode == 0, proc.stderr
    assert os.path.realpath(proc.stdout.strip()) == str(FLOWS_DIR)


@pytest.mark.parametrize("name", SKILLS)
def test_skill_dir_with_a_space_in_the_path_still_resolves(name, tmp_path):
    link = tmp_path / "my skills" / name
    link.parent.mkdir(parents=True)
    link.symlink_to(REPO / "agents" / "skills" / name)
    proc = _run_snippet(name, link)
    assert proc.returncode == 0, proc.stderr
    assert os.path.realpath(proc.stdout.strip()) == str(FLOWS_DIR)


@pytest.mark.parametrize("name", SKILLS)
def test_empty_skill_dir_fails_instead_of_guessing_a_path(name):
    proc = _run_snippet(name, "")
    assert proc.returncode != 0
    assert "defina SKILL_DIR" in proc.stderr
    assert proc.stdout.strip() == ""  # não segue com um caminho chutado


@pytest.mark.parametrize("name", SKILLS)
def test_flows_dir_env_overrides_the_resolved_path(name, tmp_path):
    proc = _run_snippet(name, tmp_path / "nowhere", {"FLOWS_DIR": str(FLOWS_DIR)})
    assert proc.returncode == 0, proc.stderr
    assert proc.stdout.strip() == str(FLOWS_DIR)


@pytest.mark.parametrize("name", SKILLS)
def test_skill_does_not_pin_the_dotfiles_path(name):
    _, text = _frontmatter(name)
    assert "$HOME/dotfiles" not in text and "~/dotfiles" not in text
