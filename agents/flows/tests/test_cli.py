"""Testes do `engine.cli` (T7) com o CLI falso do T3: sem rede e sem cota."""

import json

import pytest
import yaml

from engine import cli
from engine.runner import Runner
from engine.traycer_cli import Adapter
from tests.conftest import ECC_DEV, make_node
from tests.fake_traycer import FakeTraycer

ENV = {"HOME": "/home/x", "PATH": "/usr/bin:/bin", "TRAYCER_EPIC_ID": "epic-1", "TRAYCER_AGENT_ID": "base-1"}


class Clock:
    def __init__(self):
        self.now = 1_000_000.0

    def time(self):
        return self.now

    def sleep(self, seconds):
        self.now += seconds


class CliEnv:
    """Repo, fluxo e CLI falso ligados ao `cli.main`. Cada chamada de `main` é um processo novo."""

    def __init__(self, tmp_path, capsys):
        self.tmp_path = tmp_path
        self.capsys = capsys
        self.repo = tmp_path / "repo"
        self.repo.mkdir()
        self.fake = FakeTraycer(tmp_path)
        self.clock = Clock()
        self.state_dir = tmp_path / "state"
        self.adapter = Adapter(executable=self.fake.executable, env=ENV, sleep=self.clock.sleep, clock=self.clock.time)
        self.flow_path = None

    def flow(self, *nodes):
        data = {"name": "demo", "run_inputs": [], "nodes": list(nodes)}
        self.flow_path = self.tmp_path / "flow.yaml"
        self.flow_path.write_text(yaml.safe_dump(data, sort_keys=False), encoding="utf-8")
        for node in nodes:
            prompt = self.tmp_path / node["prompt"]
            prompt.parent.mkdir(parents=True, exist_ok=True)
            prompt.write_text(f"Fase {node['id']} do ${{slug}}. Entrada: {{{{input}}}}.\n", encoding="utf-8")
        return self.flow_path

    def node(self, node_id, inputs=(), **overrides):
        agent = {"harness": "claude", "profile": "p-fit", "model": "sonnet", "effort": "medium", "skills": []}
        agent.update(overrides.pop("agent", {}))
        return make_node(node_id, inputs, [f"out/{node_id}.md"], agent=agent, **overrides)

    def done(self, name):
        return {"write": {str(self.repo / "out" / f"{name}.md"): "conteudo\n"}}

    def factory(self, adapter, state_dir):
        return Runner(
            adapter,
            state_dir=state_dir,
            variables_provider=lambda repo: {"diff_lines": 0},
            now=self.clock.time,
            sleep=self.clock.sleep,
        )

    def main(self, *argv, with_adapter=True):
        code = cli.main(
            [*argv, "--repo", str(self.repo), "--state-dir", str(self.state_dir)],
            adapter=self.adapter if with_adapter else None,
            runner_factory=self.factory,
        )
        out = self.capsys.readouterr()
        return code, out.out, out.err


@pytest.fixture
def cenv(tmp_path, capsys):
    return CliEnv(tmp_path, capsys)


def test_slugify_makes_a_kebab_case_slug():
    assert cli.slugify("Adicionar login com Google!") == "adicionar-login-com-google"
    assert cli.slugify("Ação rápida") == "acao-rapida"
    assert cli.slugify("x" * 100) == "x" * 40
    assert cli.slugify("???") == ""


def test_run_starts_the_flow_and_prints_the_initial_phase_states(cenv):
    code, out, _ = cenv.main("run", "ecc-dev", "--input", "Adicionar login")
    assert code == 0
    assert "fluxo ecc-dev · slug adicionar-login · active" in out
    for node in ("prd", "plan", "implement", "review", "commit"):
        assert node in out
    assert "waiting for output file" in out  # prd é manual: espera o arquivo do usuário
    assert cenv.fake.commands() == []  # nenhum filho nasceu: o prd é manual


def test_run_accepts_a_flow_path_and_spawns_the_auto_node(cenv):
    cenv.flow(cenv.node("a"), cenv.node("b", ["out/a.md"], gate="human"))
    cenv.fake.queue(cenv.done("a"), cenv.done("b"))
    code, out, _ = cenv.main("run", str(cenv.flow_path), "--slug", "feat-x")
    assert code == 0
    assert "b            awaiting_gate" in out
    assert "espera você: b (awaiting_gate)" in out
    assert len(cenv.fake.agents) == 2


def test_run_json_prints_the_run_state(cenv):
    code, out, _ = cenv.main("run", "ecc-dev", "--input", "Ideia", "--json")
    state = json.loads(out)
    assert code == 0 and state["slug"] == "ideia" and state["nodes"]["prd"]["state"] == "pending"


def test_run_without_input_or_slug_is_a_usage_error(cenv):
    code, _, err = cenv.main("run", "ecc-dev")
    assert code == 2 and "--input" in err


def test_run_with_an_unknown_flow_lists_the_known_ones(cenv):
    code, _, err = cenv.main("run", "nao-existe", "--input", "x")
    assert code == 2 and "ecc-dev" in err


def test_run_rejects_a_flow_name_that_escapes_the_flows_directory(cenv):
    code, _, err = cenv.main("run", "../flows/ecc-dev", "--input", "x")
    assert code == 2 and "not found" in err


def test_second_run_in_the_same_repo_is_refused(cenv):
    assert cenv.main("run", "ecc-dev", "--input", "um")[0] == 0
    code, _, err = cenv.main("run", "ecc-dev", "--input", "dois")
    assert code == 2 and "already has an active run" in err


def test_status_advances_the_run_and_finds_the_active_run_of_the_repo(cenv):
    cenv.flow(cenv.node("a", agent={"profile": "p-fit"}), cenv.node("b", ["out/a.md"]))
    cenv.fake.update(rate={"fiveHour": 95, "sevenDay": 20})  # a cota segura o nó a
    code, out, _ = cenv.main("run", str(cenv.flow_path), "--slug", "feat-x")
    assert "a            awaiting_quota" in out
    cenv.fake.update(rate={"fiveHour": 10, "sevenDay": 20})
    cenv.fake.queue(cenv.done("a"), cenv.done("b"))
    code, out, _ = cenv.main("status")
    assert code == 0
    assert "a            done" in out and "b            done" in out and "· done" in out
    assert "motor: finished" in out


def test_status_no_advance_only_reads(cenv):
    cenv.main("run", "ecc-dev", "--input", "Ideia")
    calls = len(cenv.fake.calls)
    code, out, _ = cenv.main("status", "--no-advance")
    assert code == 0 and "motor:" not in out
    assert len(cenv.fake.calls) == calls


def test_status_without_a_run_is_a_usage_error(cenv):
    code, _, err = cenv.main("status")
    assert code == 2 and "no active run" in err


def test_status_with_an_unknown_run_id_is_a_usage_error(cenv):
    cenv.main("run", "ecc-dev", "--input", "Ideia")
    code, _, err = cenv.main("status", "--run", "nao-existe")
    assert code == 2 and "not found" in err


def test_approve_releases_the_human_gate_and_advances(cenv):
    cenv.flow(cenv.node("a", gate="human"), cenv.node("b", ["out/a.md"]))
    cenv.fake.queue(cenv.done("a"), cenv.done("b"))
    _, out, _ = cenv.main("run", str(cenv.flow_path), "--slug", "feat-x")
    assert "a            awaiting_gate" in out
    code, out, _ = cenv.main("approve", "a")
    assert code == 0
    assert "a            done" in out and "b            done" in out


def test_approve_a_node_that_is_not_waiting_is_a_usage_error(cenv):
    cenv.main("run", "ecc-dev", "--input", "Ideia")
    code, _, err = cenv.main("approve", "plan")
    assert code == 2 and "not awaiting_gate" in err


def test_approve_an_unknown_node_is_a_usage_error(cenv):
    cenv.main("run", "ecc-dev", "--input", "Ideia")
    code, _, err = cenv.main("approve", "xyz")
    assert code == 2 and "no node 'xyz'" in err


def test_phase_sends_the_rendered_prompt_with_the_given_input(cenv):
    code, out, _ = cenv.main("phase", "plan", "--input", ".claude/PRPs/prds/minha-feature.prd.md", "--slug", "minha-feature")
    assert code == 0
    assert "phase plan: child" in out and ".claude/PRPs/plans/minha-feature.plan.md" in out
    (send,) = cenv.fake.commands("send")
    message = next(t for t in send if t.startswith("--message="))
    assert ".claude/PRPs/prds/minha-feature.prd.md" in message and "{{input}}" not in message
    assert "${slug}" not in message and "minha-feature.plan.md" in message
    (child,) = cenv.fake.agents.values()
    assert (child["harness"], child["model"], child["effort"]) == ("claude", "sonnet", "medium")
    assert not child["archived"]  # sem --wait o filho segue vivo para o usuário abrir


def test_phase_defaults_input_to_the_node_inputs_and_the_slug_to_the_active_run(cenv):
    cenv.main("run", "ecc-dev", "--input", "Minha Ideia")
    code, _, _ = cenv.main("phase", "plan")
    assert code == 0
    (send,) = cenv.fake.commands("send")
    message = next(t for t in send if t.startswith("--message="))
    assert ".claude/PRPs/prds/minha-ideia.prd.md" in message


def test_phase_does_not_create_a_run_or_touch_the_state(cenv):
    cenv.main("phase", "plan", "--slug", "feat-x")
    assert not cenv.state_dir.exists() or not list(cenv.state_dir.glob("*.json"))


def test_phase_wait_reports_the_outputs_and_archives_the_child(cenv):
    cenv.fake.queue(cenv.done("a"))
    cenv.flow(cenv.node("a"))
    code, out, _ = cenv.main("phase", "a", "--flow", str(cenv.flow_path), "--slug", "feat-x", "--wait")
    assert code == 0 and "ok      out/a.md" in out
    (child,) = cenv.fake.agents.values()
    assert child["archived"]


def test_phase_wait_reports_a_missing_output(cenv):
    cenv.flow(cenv.node("a"))
    code, out, _ = cenv.main("phase", "a", "--flow", str(cenv.flow_path), "--slug", "feat-x", "--wait")
    assert code == 0 and "missing out/a.md" in out


def test_phase_refuses_when_the_quota_is_over_the_limit(cenv):
    cenv.fake.update(rate={"fiveHour": 95, "sevenDay": 20})
    code, _, err = cenv.main("phase", "plan", "--slug", "feat-x")
    assert code == 1 and "quota at 95%" in err
    assert cenv.fake.commands("create") == []


def test_phase_refuses_a_manual_node(cenv):
    code, _, err = cenv.main("phase", "prd", "--slug", "feat-x")
    assert code == 2 and "manual" in err
    assert cenv.fake.calls == []


def test_phase_with_an_unknown_node_lists_the_nodes(cenv):
    code, _, err = cenv.main("phase", "xyz", "--slug", "feat-x")
    assert code == 2 and "Nodes: prd, plan" in err


def test_phase_without_a_slug_source_is_a_usage_error(cenv):
    code, _, err = cenv.main("phase", "plan")
    assert code == 2 and "--slug" in err


def test_phase_reports_a_cli_failure_with_exit_1(cenv):
    cenv.fake.update(fail={"create": "boom"})
    code, _, err = cenv.main("phase", "plan", "--slug", "feat-x")
    assert code == 1 and "boom" in err


def test_phase_archives_the_child_when_the_send_fails(cenv):
    cenv.fake.update(fail={"send": "boom"})
    code, _, err = cenv.main("phase", "plan", "--slug", "feat-x")
    assert code == 1 and "boom" in err
    (child,) = cenv.fake.agents.values()
    assert child["archived"]


def test_phase_stops_then_archives_the_child_when_the_wait_fails_mid_turn(cenv):
    cenv.fake.queue({"active_polls": 50})
    cenv.fake.update(fail_after_send={"list": "boom"})  # o poll do `--wait` falha com o turno em curso
    cenv.flow(cenv.node("a"))
    code, _, err = cenv.main("phase", "a", "--flow", str(cenv.flow_path), "--slug", "feat-x", "--wait")
    assert code == 1 and "boom" in err
    assert [c[:2] for c in cenv.fake.commands() if c[1] in ("stop", "archive")] == [["agent", "stop"], ["agent", "archive"]]
    (child,) = cenv.fake.agents.values()
    assert child["archived"]


def test_phase_archives_the_child_when_the_wait_times_out(cenv, monkeypatch):
    monkeypatch.setattr(cli, "PHASE_TIMEOUT", 20.0)
    cenv.fake.queue({"active_polls": 1000})
    cenv.flow(cenv.node("a"))
    code, _, err = cenv.main("phase", "a", "--flow", str(cenv.flow_path), "--slug", "feat-x", "--wait")
    assert code == 1 and "still active" in err
    (child,) = cenv.fake.agents.values()
    assert child["archived"]


def test_phase_warns_and_keeps_the_original_error_when_stop_and_archive_fail(cenv):
    cenv.fake.update(fail={"send": "boom", "archive": "no-archive", "stop": "no-stop"})
    code, _, err = cenv.main("phase", "plan", "--slug", "feat-x")
    assert code == 1 and "error: boom" in err
    assert "warning: could not stop child" in err and "no-stop" in err
    assert "warning: could not archive child" in err and "no-archive" in err


def test_phase_wait_warns_when_the_archive_fails_after_success(cenv):
    cenv.fake.queue(cenv.done("a"))
    cenv.fake.update(fail={"archive": "no-archive"})
    cenv.flow(cenv.node("a"))
    code, out, err = cenv.main("phase", "a", "--flow", str(cenv.flow_path), "--slug", "feat-x", "--wait")
    assert code == 0 and "ok      out/a.md" in out
    assert "warning: could not archive child" in err and "no-archive" in err


def test_without_the_traycer_environment_the_command_fails_with_exit_2(cenv, monkeypatch):
    for key in ("TRAYCER_EPIC_ID", "TRAYCER_AGENT_ID"):
        monkeypatch.delenv(key, raising=False)
    code, _, err = cenv.main("run", "ecc-dev", "--input", "x", with_adapter=False)
    assert code == 2 and "TRAYCER_EPIC_ID" in err


def test_default_state_dir_follows_the_environment(monkeypatch, tmp_path):
    monkeypatch.setenv("FLOWS_STATE_DIR", str(tmp_path / "s"))
    assert cli.default_state_dir() == tmp_path / "s"


def test_the_shipped_flow_file_resolves_by_name():
    assert cli.resolve_flow("ecc-dev") == ECC_DEV
