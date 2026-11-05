"""Testes do motor (T4) com o CLI falso do T3: sem rede e sem cota."""

import json
import os
import subprocess
import sys

import pytest

from engine.run_state import RunStore, StateError
from engine.runner import RepoBusy, RunError, Runner, Step, git_variables
from engine.schema import FlowError
from engine.traycer_cli import Adapter
from tests.conftest import make_node
from tests.fake_traycer import FakeTraycer

ENV = {"HOME": "/home/x", "PATH": "/usr/bin:/bin", "TRAYCER_EPIC_ID": "epic-1", "TRAYCER_AGENT_ID": "base-1"}
PROFILE = "p-fit"


class Clock:
    def __init__(self):
        self.now = 1_000_000.0

    def time(self):
        return self.now

    def sleep(self, seconds):
        self.now += seconds


class Env:
    """Repo, fluxo, CLI falso e motor ligados. `restart()` simula o reinício do servidor."""

    def __init__(self, tmp_path):
        self.tmp_path = tmp_path
        self.repo = tmp_path / "repo"
        self.repo.mkdir()
        self.fake = FakeTraycer(tmp_path)
        self.clock = Clock()
        self.variables = {"diff_lines": 10}
        self.provider_calls = 0
        self.flow_path = None
        self.runner = self.new_runner()

    def new_runner(self, **kwargs):
        adapter = Adapter(executable=self.fake.executable, env=ENV, sleep=self.clock.sleep, clock=self.clock.time)

        def provider(repo):
            self.provider_calls += 1
            return dict(self.variables)

        options = {
            "state_dir": self.tmp_path / "state",
            "variables_provider": provider,
            "turn_timeout": 600,
            "poll_interval": 60,
            "now": self.clock.time,
            "sleep": self.clock.sleep,
        }
        options.update(kwargs)
        return Runner(adapter, **options)

    def restart(self, **kwargs):
        self.runner = self.new_runner(**kwargs)
        return self.runner

    def node(self, node_id, inputs=(), outputs=None, **overrides):
        outputs = [f"out/{node_id}.md"] if outputs is None else outputs
        agent = {"harness": "claude", "profile": PROFILE, "model": "sonnet", "effort": "medium", "skills": []}
        agent.update(overrides.pop("agent", {}))
        return make_node(node_id, inputs, outputs, agent=agent, **overrides)

    def flow(self, *nodes, run_inputs=()):
        import yaml

        data = {"name": "demo", "run_inputs": list(run_inputs), "nodes": list(nodes)}
        self.flow_path = self.tmp_path / "flow.yaml"
        self.flow_path.write_text(yaml.safe_dump(data, sort_keys=False), encoding="utf-8")
        for node in nodes:
            prompt = self.tmp_path / node["prompt"]
            prompt.parent.mkdir(parents=True, exist_ok=True)
            prompt.write_text(f"Fase {node['id']} do ${{slug}}. Entrada: {{{{input}}}}.\n", encoding="utf-8")
        return self.flow_path

    def start(self, **kwargs):
        return self.runner.start_run(self.flow_path, slug="feat-x", repo=self.repo, **kwargs)

    def out(self, name, content="conteudo\n"):
        """Comportamento do filho: escreve o arquivo de saída `out/<name>.md`."""
        return {str(self.repo / "out" / f"{name}.md"): content}

    def done(self, *names, **extra):
        write = {}
        for name in names:
            write.update(self.out(name))
        return {"write": write, **extra}

    def drive(self, run_id, limit=200):
        return self.runner.drive(run_id, max_steps=limit)

    def states(self, run_id):
        return {k: v["state"] for k, v in self.runner.status(run_id)["nodes"].items()}

    def history(self, run_id, node_id):
        return [h["to"] for h in self.runner.status(run_id)["nodes"][node_id]["history"]]


@pytest.fixture
def env(tmp_path):
    return Env(tmp_path)


# --- caminho feliz ---------------------------------------------------------------------------


def test_happy_path_runs_two_nodes_and_stops_at_the_human_gate(env):
    env.flow(env.node("a"), env.node("b", ["out/a.md"], gate="human"))
    env.fake.queue(env.done("a"), env.done("b"))
    run_id = env.start()
    assert env.drive(run_id) is Step.BLOCKED
    assert env.states(run_id) == {"a": "done", "b": "awaiting_gate"}
    assert env.history(run_id, "a") == ["running", "done"]
    env.runner.approve_gate(run_id, "b")
    assert env.drive(run_id) is Step.FINISHED
    status = env.runner.status(run_id)
    assert status["status"] == "done"
    assert env.states(run_id) == {"a": "done", "b": "done"}
    # um filho por fase, arquivados ao terminar
    agents = env.fake.agents
    assert len(agents) == 2 and all(a["archived"] for a in agents.values())


def test_child_message_has_the_rendered_prompt_and_a_context_pack_of_at_most_30_lines(env):
    env.flow(env.node("a"), env.node("b", ["out/a.md"]))
    env.fake.queue(env.done("a"), env.done("b"))
    env.drive(env.start())
    first, second = (a["messages"][0] for a in env.fake.agents.values())
    assert "Fase a do feat-x. Entrada: (nenhuma)." in first
    assert "Fase b do feat-x. Entrada: out/a.md." in second
    assert str(env.repo) in second
    pack = second.split("## Pacote de contexto", 1)[1].splitlines()
    assert 3 <= len(pack) <= 30
    text = "\n".join(pack)
    for heading in ("Decisão", "Estado", "Próximo passo"):
        assert heading in text
    assert "a: done" in text and "out/b.md" in text


def test_context_pack_stays_within_30_lines_for_a_long_flow(env):
    nodes = [env.node("n0")]
    for i in range(1, 18):
        nodes.append(env.node(f"n{i}", [f"out/n{i - 1}.md"]))
    env.flow(*nodes)
    env.fake.queue(*[env.done(f"n{i}") for i in range(18)])
    env.drive(env.start(), limit=500)
    for agent in env.fake.agents.values():
        message = agent["messages"][0]
        assert len(message.split("## Pacote de contexto", 1)[1].splitlines()) <= 30


def test_children_get_the_node_agent_options_and_the_repo_as_cwd(env):
    env.flow(env.node("a", agent={"model": "haiku", "effort": "low"}))
    env.fake.queue(env.done("a"))
    env.drive(env.start())
    (argv,) = env.fake.commands("create")
    assert {"--model=haiku", "--reasoning-effort=low", f"--profile={PROFILE}", f"--cwd={env.repo.resolve()}"} <= set(argv)


def test_applied_model_that_differs_from_the_requested_one_is_recorded(env):
    env.flow(env.node("a", agent={"model": "gemini-4-argon"}))
    env.fake.update(apply_model={"gemini-4-argon": "gemini-3.8-flash"})
    env.fake.queue(env.done("a"))
    run_id = env.start()
    env.drive(run_id)
    node = env.runner.status(run_id)["nodes"]["a"]
    assert node["divergence"] == {
        "requested": {"model": "gemini-4-argon", "effort": "medium"},
        "applied": {"model": "gemini-3.8-flash", "effort": "medium"},
    }
    assert any("gemini-3.8-flash" in e["msg"] for e in env.runner.status(run_id)["events"])


# --- parada humana e nó manual ---------------------------------------------------------------


def test_manual_node_creates_no_child_and_waits_for_the_file_and_the_approval(env):
    env.flow(
        env.node("prd", mode="manual", gate="human"),
        env.node("plan", ["out/prd.md"]),
    )
    env.fake.queue(env.done("plan"))
    run_id = env.start()
    assert env.drive(run_id) is Step.BLOCKED
    assert env.states(run_id) == {"prd": "pending", "plan": "pending"}
    assert env.fake.commands("create") == []
    # aprovação antes do arquivo é recusada e não muda nada
    with pytest.raises(RunError):
        env.runner.approve_gate(run_id, "prd")
    assert env.states(run_id)["prd"] == "pending"
    # o arquivo aparece: o nó espera a aprovação
    (env.repo / "out").mkdir()
    (env.repo / "out" / "prd.md").write_text("prd\n")
    assert env.drive(run_id) is Step.BLOCKED
    assert env.states(run_id) == {"prd": "awaiting_gate", "plan": "pending"}
    assert env.fake.commands("create") == []
    env.runner.approve_gate(run_id, "prd")
    assert env.drive(run_id) is Step.FINISHED
    assert env.states(run_id) == {"prd": "done", "plan": "done"}
    assert len(env.fake.commands("create")) == 1  # só o plan


def test_manual_node_without_gate_is_done_as_soon_as_the_file_exists(env):
    env.flow(env.node("prd", mode="manual"))
    run_id = env.start()
    env.drive(run_id)
    (env.repo / "out").mkdir()
    (env.repo / "out" / "prd.md").write_text("prd\n")
    assert env.drive(run_id) is Step.FINISHED
    assert env.states(run_id) == {"prd": "done"}


def test_manual_node_accepts_a_file_that_existed_before_the_run(env):
    (env.repo / "out").mkdir()
    (env.repo / "out" / "prd.md").write_text("prd\n")
    env.flow(env.node("prd", mode="manual", gate="human"))
    run_id = env.start()
    env.drive(run_id)
    assert env.states(run_id) == {"prd": "awaiting_gate"}


def test_manual_node_does_not_read_the_quota(env):
    env.fake.update(rate={"fiveHour": 99, "sevenDay": 99})
    env.flow(env.node("prd", mode="manual"))
    run_id = env.start()
    (env.repo / "out").mkdir()
    (env.repo / "out" / "prd.md").write_text("prd\n")
    env.drive(run_id)
    assert env.fake.commands("profile-rate-limits") == []
    assert env.states(run_id) == {"prd": "done"}


def test_request_adjustment_sends_the_note_to_the_same_child_and_returns_to_the_gate(env):
    env.flow(env.node("a", gate="human"))
    env.fake.queue(env.done("a"), {"write": env.out("a", "versão 2\n"), "reply": "ajustado"})
    run_id = env.start()
    env.drive(run_id)
    assert env.states(run_id) == {"a": "awaiting_gate"}
    env.runner.request_adjustment(run_id, "a", "troque o título")
    assert env.states(run_id) == {"a": "running"}
    env.drive(run_id)
    assert env.states(run_id) == {"a": "awaiting_gate"}
    (agent,) = env.fake.agents.values()
    assert len(env.fake.commands("create")) == 1
    assert "troque o título" in agent["messages"][1]
    assert env.history(run_id, "a") == ["running", "awaiting_gate", "running", "awaiting_gate"]


def test_adjustment_that_rewrites_nothing_fails_instead_of_passing_on_the_stale_file(env):
    env.flow(env.node("a", gate="human", on_fail={"retry": 0, "then": "abort"}))
    env.fake.queue(env.done("a"), {"write": {}})
    run_id = env.start()
    env.drive(run_id)
    env.runner.request_adjustment(run_id, "a", "mude")
    env.drive(run_id)
    assert env.states(run_id) == {"a": "aborted"}


def test_reject_gate_aborts_the_node_and_its_dependents(env):
    env.flow(env.node("a", gate="human"), env.node("b", ["out/a.md"]))
    env.fake.queue(env.done("a"))
    run_id = env.start()
    env.drive(run_id)
    env.runner.reject_gate(run_id, "a")
    assert env.drive(run_id) is Step.FINISHED
    assert env.states(run_id) == {"a": "aborted", "b": "aborted"}
    assert env.runner.status(run_id)["status"] == "aborted"


def test_gate_actions_need_the_node_in_the_right_state(env):
    env.flow(env.node("a"))
    run_id = env.start()
    for call in (
        lambda: env.runner.approve_gate(run_id, "a"),
        lambda: env.runner.reject_gate(run_id, "a"),
        lambda: env.runner.request_adjustment(run_id, "a", "x"),
        lambda: env.runner.choose_upgrade(run_id, "a", model="opus"),
        lambda: env.runner.approve_gate(run_id, "zzz"),
    ):
        with pytest.raises(RunError):
            call()


# --- falha, repetição e awaiting_upgrade -----------------------------------------------------


def test_child_that_ends_without_the_output_fails_and_is_retried_once(env):
    env.flow(env.node("a", on_fail={"retry": 1, "then": "ask_before_upgrade"}))
    env.fake.queue({"write": {}}, env.done("a"))
    run_id = env.start()
    assert env.drive(run_id) is Step.FINISHED
    assert env.history(run_id, "a") == ["running", "failed", "running", "done"]
    assert len(env.fake.commands("create")) == 2  # filho novo por tentativa
    first, second = env.fake.agents.values()
    assert first["archived"] and second["archived"]
    assert env.runner.status(run_id)["nodes"]["a"]["attempts"] == 2


def test_second_failure_goes_to_awaiting_upgrade_and_never_raises_the_model_alone(env):
    env.flow(env.node("a", on_fail={"retry": 1, "then": "ask_before_upgrade"}))
    env.fake.queue({"write": {}}, {"write": {}})
    run_id = env.start()
    assert env.drive(run_id) is Step.BLOCKED
    assert env.history(run_id, "a") == ["running", "failed", "running", "failed", "awaiting_upgrade"]
    assert len(env.fake.commands("create")) == 2
    assert {c.split("=", 1)[1] for argv in env.fake.commands("create") for c in argv if c.startswith("--model=")} == {"sonnet"}
    # nada acontece sozinho enquanto o humano não escolhe
    assert env.drive(run_id) is Step.BLOCKED
    assert len(env.fake.commands("create")) == 2


def test_choose_upgrade_restarts_the_node_with_the_chosen_model(env):
    env.flow(env.node("a", on_fail={"retry": 0, "then": "ask_before_upgrade"}), env.node("b", ["out/a.md"]))
    env.fake.queue({"write": {}}, env.done("a"), env.done("b"))
    run_id = env.start()
    env.drive(run_id)
    assert env.states(run_id) == {"a": "awaiting_upgrade", "b": "pending"}
    env.runner.choose_upgrade(run_id, "a", model="opus", effort="high")
    assert env.states(run_id)["a"] == "running"
    assert env.drive(run_id) is Step.FINISHED
    upgraded = env.fake.commands("create")[1]
    assert "--model=opus" in upgraded and "--reasoning-effort=high" in upgraded
    assert env.runner.status(run_id)["nodes"]["a"]["model"] == "opus"
    assert env.history(run_id, "a") == ["running", "failed", "awaiting_upgrade", "running", "done"]


def test_upgrade_gets_a_fresh_retry_budget(env):
    env.flow(env.node("a", on_fail={"retry": 1, "then": "ask_before_upgrade"}))
    env.fake.queue({"write": {}}, {"write": {}}, {"write": {}}, env.done("a"))
    run_id = env.start()
    env.drive(run_id)
    env.runner.choose_upgrade(run_id, "a", model="opus")
    env.drive(run_id)  # falha de novo no modelo novo, repete uma vez e dá certo
    assert env.states(run_id) == {"a": "done"}
    assert len(env.fake.commands("create")) == 4


def test_on_fail_abort_aborts_the_node_and_everything_after_it(env):
    env.flow(
        env.node("a", on_fail={"retry": 0, "then": "abort"}),
        env.node("b", ["out/a.md"]),
        env.node("c", after=["a"]),
    )
    env.fake.queue({"write": {}})
    run_id = env.start()
    assert env.drive(run_id) is Step.FINISHED
    assert env.states(run_id) == {"a": "aborted", "b": "aborted", "c": "aborted"}
    assert env.runner.status(run_id)["status"] == "aborted"
    assert env.history(run_id, "a") == ["running", "failed", "aborted"]


def test_retry_count_comes_from_the_node(env):
    env.flow(env.node("a", on_fail={"retry": 2, "then": "abort"}))
    env.fake.queue({"write": {}}, {"write": {}}, {"write": {}})
    run_id = env.start()
    env.drive(run_id)
    assert len(env.fake.commands("create")) == 3
    assert env.states(run_id) == {"a": "aborted"}


def test_a_stale_output_from_before_the_attempt_does_not_count_as_success(env):
    (env.repo / "out").mkdir()
    (env.repo / "out" / "a.md").write_text("velho\n")
    env.flow(env.node("a", on_fail={"retry": 0, "then": "abort"}))
    env.fake.queue({"write": {}})
    run_id = env.start()
    env.drive(run_id)
    assert env.states(run_id) == {"a": "aborted"}


def test_a_stale_output_is_replaced_by_a_real_rewrite(env):
    (env.repo / "out").mkdir()
    (env.repo / "out" / "a.md").write_text("velho\n")
    env.flow(env.node("a"))
    env.fake.queue(env.done("a"))
    run_id = env.start()
    env.drive(run_id)
    assert env.states(run_id) == {"a": "done"}


def test_all_outputs_must_be_written(env):
    env.flow(env.node("a", outputs=["out/a.md", "out/a2.md"], on_fail={"retry": 0, "then": "abort"}))
    env.fake.queue(env.done("a"))
    run_id = env.start()
    env.drive(run_id)
    assert env.states(run_id) == {"a": "aborted"}


def test_child_that_never_finishes_is_stopped_archived_and_failed(env):
    env.flow(env.node("a", on_fail={"retry": 0, "then": "ask_before_upgrade"}))
    env.fake.queue({"active_polls": 10_000})
    run_id = env.start()
    assert env.drive(run_id) is Step.BLOCKED
    assert env.states(run_id) == {"a": "awaiting_upgrade"}
    assert len(env.fake.commands("stop")) == 1
    (agent,) = env.fake.agents.values()
    assert agent["archived"]
    assert "timeout" in env.runner.status(run_id)["nodes"]["a"]["reason"].lower()


def test_idle_child_without_a_new_reply_is_not_finished_before_the_timeout(env):
    """Corrida logo após o send: ocioso, sem resposta nova e sem saída = o turno ainda não começou."""
    env.flow(env.node("a", on_fail={"retry": 0, "then": "ask_before_upgrade"}))
    env.fake.queue({"write": {}, "reply": None, "active_polls": 0})
    run_id = env.start()
    env.runner.step(run_id)  # cria o filho e envia
    for _ in range(5):
        assert env.runner.step(run_id) is Step.WAITING
    assert env.states(run_id) == {"a": "running"}
    assert env.drive(run_id) is Step.BLOCKED  # só o timeout encerra
    assert "timeout" in env.runner.status(run_id)["nodes"]["a"]["reason"].lower()


def test_cli_error_when_creating_the_child_counts_as_a_failed_attempt(env):
    env.flow(env.node("a", on_fail={"retry": 0, "then": "ask_before_upgrade"}))
    env.fake.update(fail={"create": "sem vaga"})
    run_id = env.start()
    env.drive(run_id)
    assert env.states(run_id) == {"a": "awaiting_upgrade"}
    assert "sem vaga" in env.runner.status(run_id)["nodes"]["a"]["reason"]


# --- cota ------------------------------------------------------------------------------------


@pytest.mark.parametrize(
    ("rate", "creates"),
    [
        ({"fiveHour": 81, "sevenDay": 10}, 0),
        ({"fiveHour": 10, "sevenDay": 81}, 0),
        ({"fiveHour": 80, "sevenDay": 80}, 1),
        ({"fiveHour": 10, "sevenDay": 20}, 1),
    ],
)
def test_quota_above_80_percent_stops_before_creating_the_child(env, rate, creates):
    env.fake.update(rate=rate)
    env.flow(env.node("a"))
    env.fake.queue(env.done("a"))
    run_id = env.start()
    env.drive(run_id)
    assert len(env.fake.commands("create")) == creates
    if creates == 0:
        assert env.states(run_id) == {"a": "awaiting_quota"}
        assert "81" in env.runner.status(run_id)["nodes"]["a"]["reason"]
        assert env.runner.status(run_id)["status"] == "active"
    else:
        assert env.states(run_id) == {"a": "done"}


def test_quota_is_read_from_the_nodes_own_harness_and_profile(env):
    env.flow(env.node("a", agent={"harness": "antigravity", "profile": "ambient", "model": "m"}))
    env.fake.queue(env.done("a"))
    env.drive(env.start())
    argvs = env.fake.commands("profile-rate-limits")
    assert argvs and all("antigravity" in argv and "--profile=ambient" in argv for argv in argvs)


def test_run_resumes_from_awaiting_quota_when_the_quota_drops(env):
    env.fake.update(rate={"fiveHour": 95, "sevenDay": 10})
    env.flow(env.node("a"))
    env.fake.queue(env.done("a"))
    run_id = env.start()
    assert env.drive(run_id) is Step.BLOCKED
    env.fake.update(rate={"fiveHour": 20, "sevenDay": 10})
    assert env.drive(run_id) is Step.FINISHED
    assert env.states(run_id) == {"a": "done"}
    assert env.history(run_id, "a") == ["awaiting_quota", "running", "done"]


def test_quota_is_read_before_every_child_including_retries(env):
    env.flow(env.node("a", on_fail={"retry": 1, "then": "abort"}))
    env.fake.queue({"write": {}}, env.done("a"))
    run_id = env.start()
    env.drive(run_id)
    assert len(env.fake.commands("create")) == 2
    assert len(env.fake.commands("profile-rate-limits")) == 2 + 2  # antes de cada filho e depois de cada fim de turno


def test_node_state_records_the_quota_before_and_after_the_child(env):
    env.flow(env.node("a"))
    env.fake.queue(env.done("a"))
    run_id = env.start()
    env.fake.update(rate={"fiveHour": 36, "sevenDay": 61})
    env.drive(run_id, limit=1)  # cria o filho e envia: lê a cota antes
    env.fake.update(rate={"fiveHour": 47, "sevenDay": 63})
    env.drive(run_id)
    ns = env.runner.status(run_id)["nodes"]["a"]
    assert ns["quota_before"] == {"five_hour": 36, "seven_day": 61, "updated_at": 1234}
    assert ns["quota_after"] == {"five_hour": 47, "seven_day": 63, "updated_at": 1234}


def test_approving_a_gate_reads_the_quota_again_so_post_approval_work_is_counted(env):
    env.flow(env.node("a", gate="human"))
    env.fake.queue(env.done("a"))
    run_id = env.start()
    env.fake.update(rate={"fiveHour": 30, "sevenDay": 50})
    env.drive(run_id)  # chega à parada
    assert env.runner.status(run_id)["nodes"]["a"]["quota_after"]["five_hour"] == 30
    env.fake.update(rate={"fiveHour": 44, "sevenDay": 52})  # o filho trabalhou depois da aprovação
    env.runner.approve_gate(run_id, "a")
    ns = env.runner.status(run_id)["nodes"]["a"]
    assert ns["quota_after"] == {"five_hour": 44, "seven_day": 52, "updated_at": 1234}


def test_quota_after_that_cannot_be_read_stays_empty_and_does_not_fail_the_node(env):
    env.flow(env.node("a"))
    env.fake.queue(env.done("a"))
    run_id = env.start()
    env.drive(run_id, limit=1)
    env.fake.update(fail={"profile-rate-limits": "sem rede"})
    env.drive(run_id)
    assert env.states(run_id) == {"a": "done"}
    ns = env.runner.status(run_id)["nodes"]["a"]
    assert ns["quota_before"]["five_hour"] == 10
    assert ns["quota_after"] is None


def test_node_state_keeps_the_title_of_the_child_session(env):
    env.flow(env.node("a", gate="human"))
    env.fake.queue(env.done("a"))
    run_id = env.start()
    env.drive(run_id)
    ns = env.runner.status(run_id)["nodes"]["a"]
    (argv,) = env.fake.commands("create")
    title = next(a.split("=", 1)[1] for a in argv if a.startswith("--name="))
    assert ns["child_name"] == title
    assert title.startswith("demo:a (")


def test_quota_that_cannot_be_read_stops_the_run_instead_of_spending(env):
    env.fake.update(fail={"profile-rate-limits": "sem rede"})
    env.flow(env.node("a"))
    run_id = env.start()
    env.drive(run_id)
    assert env.states(run_id) == {"a": "awaiting_quota"}
    assert env.fake.commands("create") == []
    assert "sem rede" in env.runner.status(run_id)["nodes"]["a"]["reason"]


RAW_CLI_ERROR = (
    "[48213:1105/174523.123:ERROR:gpu_process_host.cc(991)] GPU process (pid 48213) exited unexpectedly\n"
    "[48213:1105/174523.124:ERROR:ozone_platform_x11.cc(257)] second line " + "x" * 400
)


def test_node_reason_has_one_short_line_without_pids_when_the_cli_fails(env):
    env.fake.update(fail={"profile-rate-limits": RAW_CLI_ERROR})
    env.flow(env.node("a"))
    run_id = env.start()
    env.drive(run_id)
    reason = env.runner.status(run_id)["nodes"]["a"]["reason"]
    assert env.states(run_id) == {"a": "awaiting_quota"}
    assert "\n" not in reason
    assert "48213" not in reason and "pid" not in reason.lower()
    assert len(reason) <= 200
    assert "GPU process" in reason  # a causa continua legível


def test_provider_without_quota_information_does_not_block(env):
    env.fake.update(rate_available=False)
    env.flow(env.node("a"))
    env.fake.queue(env.done("a"))
    run_id = env.start()
    env.drive(run_id)
    assert env.states(run_id) == {"a": "done"}


def test_quota_threshold_is_configurable(env):
    env.fake.update(rate={"fiveHour": 50, "sevenDay": 10})
    env.restart(quota_threshold=40)
    env.flow(env.node("a"))
    run_id = env.start()
    env.drive(run_id)
    assert env.states(run_id) == {"a": "awaiting_quota"}


# --- when ------------------------------------------------------------------------------------


def review_flow(env):
    env.flow(
        env.node("impl"),
        env.node("review", ["out/impl.md"], when="diff_lines > 150 or sensitive", gate="human"),
        env.node("commit", ["out/impl.md"], after=["review"]),
    )


def test_when_false_skips_the_node_and_the_dependents_go_on(env):
    review_flow(env)
    env.variables = {"diff_lines": 10}
    env.fake.queue(env.done("impl"), env.done("commit"))
    run_id = env.start()
    assert env.drive(run_id) is Step.FINISHED
    assert env.states(run_id) == {"impl": "done", "review": "skipped", "commit": "done"}
    assert len(env.fake.commands("create")) == 2  # sem filho para o review


def test_when_true_runs_the_node_and_the_after_waits_for_its_gate(env):
    review_flow(env)
    env.variables = {"diff_lines": 400}
    env.fake.queue(env.done("impl"), env.done("review"), env.done("commit"))
    run_id = env.start()
    assert env.drive(run_id) is Step.BLOCKED
    assert env.states(run_id) == {"impl": "done", "review": "awaiting_gate", "commit": "pending"}
    env.runner.approve_gate(run_id, "review")
    assert env.drive(run_id) is Step.FINISHED
    assert env.states(run_id)["commit"] == "done"


def test_sensitive_flag_given_at_start_turns_the_when_on(env):
    review_flow(env)
    env.variables = {"diff_lines": 1}
    env.fake.queue(env.done("impl"), env.done("review"))
    run_id = env.start(sensitive=True)
    env.drive(run_id)
    assert env.states(run_id)["review"] == "awaiting_gate"


def test_when_is_evaluated_lazily_when_the_node_is_reached(env):
    review_flow(env)
    env.fake.queue(env.done("impl"), env.done("commit"))
    run_id = env.start()
    assert env.provider_calls == 0
    env.runner.step(run_id)  # impl começa
    assert env.provider_calls == 0
    env.drive(run_id)
    assert env.provider_calls == 1  # uma vez, depois do impl; o resultado fica guardado


def test_diff_lines_given_at_start_overrides_the_provider(env):
    review_flow(env)
    env.fake.queue(env.done("impl"), env.done("review"))
    run_id = env.start(diff_lines=999)
    env.drive(run_id)
    assert env.states(run_id)["review"] == "awaiting_gate"


def test_when_that_cannot_be_evaluated_aborts_the_node_cleanly(env):
    review_flow(env)
    env.variables = {}  # `diff_lines` ausente
    env.fake.queue(env.done("impl"))
    run_id = env.start()
    assert env.drive(run_id) in (Step.FINISHED, Step.BLOCKED)  # não levanta
    assert env.states(run_id)["review"] == "aborted"
    assert "diff_lines" in env.runner.status(run_id)["nodes"]["review"]["reason"]


def test_default_provider_counts_changed_lines_with_git_and_ignores_prp_files(tmp_path):
    repo = tmp_path / "r"
    repo.mkdir()
    git = lambda *a: subprocess.run(["git", "-C", str(repo), *a], check=True, capture_output=True)  # noqa: E731
    git("init", "-q")
    git("config", "user.email", "t@t")
    git("config", "user.name", "t")
    (repo / "code.py").write_text("a\nb\nc\n")
    (repo / ".claude" / "PRPs").mkdir(parents=True)
    (repo / ".claude" / "PRPs" / "x.md").write_text("1\n")
    git("add", "-A")
    git("commit", "-qm", "init")
    (repo / "code.py").write_text("a\nB\nc\nd\n")  # +2 -1
    (repo / ".claude" / "PRPs" / "x.md").write_text("1\n2\n3\n4\n5\n")
    assert git_variables(repo) == {"diff_lines": 3}


def _repo_with_commit(tmp_path):
    repo = tmp_path / "repo"
    repo.mkdir()
    git = lambda *a: subprocess.run(["git", "-C", str(repo), *a], check=True, capture_output=True)  # noqa: E731
    git("init", "-q")
    git("config", "user.email", "t@t")
    git("config", "user.name", "t")
    (repo / "code.py").write_text("a\nb\nc\n")
    git("add", "-A")
    git("commit", "-qm", "init")
    return repo


def test_git_variables_counts_new_untracked_files(tmp_path):
    repo = _repo_with_commit(tmp_path)
    (repo / "code.py").write_text("a\nB\nc\n")  # +1 -1
    (repo / "new.py").write_text("1\n2\n3\n4\n")  # arquivo novo, 4 linhas
    (repo / "pkg").mkdir()
    (repo / "pkg" / "deep.sh").write_text("x\ny")  # sem newline final conta como 2 linhas
    assert git_variables(repo) == {"diff_lines": 2 + 4 + 2}


def test_git_variables_ignores_untracked_flow_artifacts_binaries_and_ignored_files(tmp_path):
    repo = _repo_with_commit(tmp_path)
    (repo / ".gitignore").write_text("build/\n")
    (repo / "build").mkdir()
    (repo / "build" / "out.txt").write_text("1\n2\n3\n")
    (repo / ".claude" / "PRPs").mkdir(parents=True)
    (repo / ".claude" / "PRPs" / "plan.md").write_text("1\n2\n3\n4\n5\n")
    (repo / "blob.bin").write_bytes(b"\x00\x01\x02\n\x00")
    assert git_variables(repo) == {"diff_lines": 1}  # só o `.gitignore` novo


# --- retomada --------------------------------------------------------------------------------


def test_restart_in_the_middle_of_a_running_node_polls_the_same_child(env):
    env.flow(env.node("a"), env.node("b", ["out/a.md"]))
    env.fake.queue({"active_polls": 5, "write": env.out("a")}, env.done("b"))
    run_id = env.start()
    env.runner.step(run_id)
    env.runner.step(run_id)
    child_id = env.runner.status(run_id)["nodes"]["a"]["child_id"]
    assert env.states(run_id)["a"] == "running"
    # reinício: motor e adaptador novos, o mesmo diretório de estado
    env.restart()
    assert env.drive(run_id) is Step.FINISHED
    assert env.runner.status(run_id)["nodes"]["a"]["last_child_id"] == child_id
    assert len(env.fake.commands("create")) == 2  # a e b; nada recriado
    assert env.states(run_id) == {"a": "done", "b": "done"}


def test_restart_after_the_child_finished_while_the_server_was_down(env):
    env.flow(env.node("a"))
    env.fake.queue({"active_polls": 3, "write": env.out("a")})
    run_id = env.start()
    env.runner.step(run_id)
    env.restart()
    assert env.drive(run_id) is Step.FINISHED
    assert len(env.fake.commands("create")) == 1


def test_restart_between_create_and_send_resends_without_recreating_the_child(env):
    env.flow(env.node("a"))
    env.fake.queue(env.done("a"))
    run_id = env.start()
    env.runner.step(run_id)
    # simula a queda antes de gravar `sent`: o estado volta para "ainda não enviado"
    path = env.tmp_path / "state" / f"{run_id}.json"
    state = json.loads(path.read_text())
    node = state["nodes"]["a"]
    node["sent"] = False
    path.write_text(json.dumps(state))
    env.restart()
    env.drive(run_id)
    assert env.states(run_id) == {"a": "done"}
    assert len(env.fake.commands("create")) == 1


def test_restart_keeps_waiting_states(env):
    env.flow(env.node("a", gate="human"))
    env.fake.queue(env.done("a"))
    run_id = env.start()
    env.drive(run_id)
    env.restart()
    assert env.drive(run_id) is Step.BLOCKED
    env.runner.approve_gate(run_id, "a")
    assert env.drive(run_id) is Step.FINISHED


def test_child_that_vanished_while_running_fails_the_attempt(env):
    env.flow(env.node("a", on_fail={"retry": 0, "then": "ask_before_upgrade"}))
    env.fake.queue({"active_polls": 30})
    run_id = env.start()
    env.runner.step(run_id)
    fake_state = json.loads(env.fake.state_path.read_text())
    fake_state["agents"].clear()
    env.fake.state_path.write_text(json.dumps(fake_state))
    env.drive(run_id)
    assert env.states(run_id) == {"a": "awaiting_upgrade"}


# --- segundo run, estado e segurança ---------------------------------------------------------


def test_second_run_on_the_same_repo_is_refused(env):
    env.flow(env.node("a", gate="human"))
    env.fake.queue(env.done("a"))
    first = env.start()
    env.drive(first)
    with pytest.raises(RepoBusy):
        env.start()
    # o mesmo repo por outro caminho (symlink) também conta
    link = env.tmp_path / "link"
    link.symlink_to(env.repo)
    with pytest.raises(RepoBusy):
        env.runner.start_run(env.flow_path, slug="other", repo=link)
    # retomar o próprio run não é um segundo run
    assert env.drive(first) is Step.BLOCKED
    # sem criar estado extra
    assert len(list((env.tmp_path / "state").glob("*.json"))) == 1


def test_a_finished_run_frees_the_repo(env):
    env.flow(env.node("a"))
    env.fake.queue(env.done("a"), env.done("a"))
    first = env.start()
    env.drive(first)
    assert env.runner.status(first)["status"] == "done"
    second = env.start()
    assert second != first


def test_abort_run_frees_the_repo_and_archives_running_children(env):
    env.flow(env.node("a"))
    env.fake.queue({"active_polls": 100})
    run_id = env.start()
    env.runner.step(run_id)
    env.runner.abort_run(run_id)
    assert env.runner.status(run_id)["status"] == "aborted"
    assert env.states(run_id) == {"a": "aborted"}
    (agent,) = env.fake.agents.values()
    assert agent["archived"] and len(env.fake.commands("stop")) == 1
    env.start()  # o repo ficou livre


def test_a_different_repo_can_run_at_the_same_time(env):
    env.flow(env.node("a", gate="human"))
    env.fake.queue(env.done("a"))
    env.drive(env.start())
    other = env.tmp_path / "other"
    other.mkdir()
    env.runner.start_run(env.flow_path, slug="feat-y", repo=other)


def test_start_run_rejects_an_invalid_flow_or_repo(env, tmp_path):
    env.flow(env.node("a"))
    with pytest.raises(FlowError):
        env.runner.start_run(env.flow_path, slug="bad slug!", repo=env.repo)
    with pytest.raises(RunError):
        env.runner.start_run(env.flow_path, slug="ok", repo=tmp_path / "missing")
    assert not list((tmp_path / "state").glob("*.json"))


def test_state_file_is_atomic_json_without_leftovers(env):
    env.flow(env.node("a", gate="human"))
    env.fake.queue(env.done("a"))
    run_id = env.start()
    env.drive(run_id)
    files = sorted(p.name for p in (env.tmp_path / "state").iterdir() if p.suffix != ".lock")
    assert files == [f"{run_id}.json"]
    state = json.loads((env.tmp_path / "state" / f"{run_id}.json").read_text())
    assert state["version"] == 1 and state["run_id"] == run_id
    assert os.stat(env.tmp_path / "state" / f"{run_id}.json").st_mode & 0o077 == 0


def test_failed_write_keeps_the_previous_state_intact(tmp_path, monkeypatch):
    store = RunStore(tmp_path)
    store.save({"version": 1, "run_id": "r1", "status": "active", "nodes": {}})
    before = (tmp_path / "r1.json").read_text()

    def boom(src, dst):
        raise OSError("disco cheio")

    monkeypatch.setattr("engine.run_state.os.replace", boom)
    with pytest.raises(OSError):
        store.save({"version": 1, "run_id": "r1", "status": "done", "nodes": {}})
    monkeypatch.undo()
    assert (tmp_path / "r1.json").read_text() == before
    assert [p.name for p in tmp_path.iterdir() if p.suffix == ".tmp"] == []


def test_corrupt_state_raises_state_error(tmp_path):
    store = RunStore(tmp_path)
    (tmp_path / "r1.json").write_text("{nao é json")
    with pytest.raises(StateError):
        store.load("r1")
    with pytest.raises(StateError):
        store.load("naoexiste")


@pytest.mark.parametrize("run_id", ["../etc/passwd", "a/b", "", ".hidden", "x" * 200])
def test_run_id_cannot_escape_the_state_dir(env, run_id):
    with pytest.raises((StateError, RunError)):
        env.runner.status(run_id)


def test_state_has_no_environment_or_secret_values(env):
    env.flow(env.node("a"))
    env.fake.queue(env.done("a"))
    run_id = env.start()
    env.drive(run_id)
    text = (env.tmp_path / "state" / f"{run_id}.json").read_text()
    for value in ENV.values():
        assert value not in text


def test_review_is_always_cold_even_if_the_node_asks_for_fork(env):
    env.flow(env.node("impl"), env.node("review", ["out/impl.md"], context="fork"))
    env.fake.queue(env.done("impl"), env.done("review"))
    run_id = env.start()
    env.drive(run_id)
    assert not [c for c in env.fake.calls if c["argv"][:2] == ["agent", "fork"]]
    impl, review = env.fake.agents.values()
    assert "Fase impl" not in review["messages"][0]  # nada do transcript da fase anterior
    assert any("fork" in e["msg"] for e in env.runner.status(run_id)["events"])
    assert env.states(run_id) == {"impl": "done", "review": "done"}


def test_status_returns_a_copy_and_lists_the_waiting_nodes(env):
    env.flow(env.node("a", gate="human"))
    env.fake.queue(env.done("a"))
    run_id = env.start()
    env.drive(run_id)
    status = env.runner.status(run_id)
    assert status["waiting"] == [{"node": "a", "state": "awaiting_gate"}]
    status["nodes"]["a"]["state"] = "done"
    assert env.states(run_id) == {"a": "awaiting_gate"}


def test_importing_the_module_needs_no_traycer_binary():
    code = "import engine.runner, engine.run_state"
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    subprocess.run([sys.executable, "-c", code], check=True, cwd=root, env={"PATH": "/nonexistent", "PYTHONPATH": root})
