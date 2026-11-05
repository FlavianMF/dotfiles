import pytest

from engine.traycer_cli import Adapter, AgentNotFound, CliError, TurnTimeout
from tests.fake_traycer import FakeTraycer

ENV = {"HOME": "/home/x", "PATH": "/usr/bin:/bin", "TRAYCER_EPIC_ID": "epic-1", "TRAYCER_AGENT_ID": "base-1"}


class Clock:
    """Relógio falso: sleep avança o tempo, então os timeouts não esperam de verdade."""

    def __init__(self):
        self.now = 0.0
        self.sleeps = []

    def time(self):
        return self.now

    def sleep(self, seconds):
        self.sleeps.append(seconds)
        self.now += seconds


@pytest.fixture
def fake(tmp_path):
    return FakeTraycer(tmp_path)


@pytest.fixture
def clock():
    return Clock()


@pytest.fixture
def adapter(fake, clock):
    return Adapter(executable=fake.executable, env=ENV, sleep=clock.sleep, clock=clock.time)


def create(adapter, **overrides):
    args = {"harness": "claude", "model": "haiku", "effort": "low", "profile": "p1", "cwd": "/tmp/work"}
    args.update(overrides)
    return adapter.create_child(**args)


def test_create_child_passes_every_option_to_the_cli(adapter, fake):
    child = create(adapter, name="fase plan")
    argv = fake.commands("create")[0]
    assert argv[:2] == ["agent", "create"]
    for flag, value in (
        ("--surface", "gui"),
        ("--harness", "claude"),
        ("--model", "haiku"),
        ("--reasoning-effort", "low"),
        ("--profile", "p1"),
        ("--cwd", "/tmp/work"),
        ("--name", "fase plan"),
    ):
        assert f"{flag}={value}" in argv
    assert "--json" in argv
    assert child.agent_id in fake.agents


def test_create_child_reports_applied_run_config(adapter):
    child = create(adapter)
    assert (child.requested_model, child.applied_model) == ("haiku", "haiku")
    assert (child.requested_effort, child.applied_effort) == ("low", "low")
    assert child.diverged is False


def test_create_child_flags_a_model_the_traycer_did_not_apply(adapter, fake):
    fake.update(apply_model={"gemini-4-argon": "gemini-3.8-flash"})
    child = create(adapter, harness="antigravity", model="gemini-4-argon")
    assert child.requested_model == "gemini-4-argon"
    assert child.applied_model == "gemini-3.8-flash"
    assert child.diverged is True


def test_create_worktree_then_child_in_the_new_worktree(adapter, fake, tmp_path):
    source = tmp_path / "repo"
    path = adapter.create_worktree(workspace=str(source), branch="feat/x", source_branch="main")
    argv = fake.commands()[-1]
    assert argv[0] == "worktree" and argv[1] == "create"
    assert f"--workspace={source}" in argv and "--branch=feat/x" in argv and "--source-branch=main" in argv
    child = create(adapter, cwd=path)
    assert fake.agents[child.agent_id]["cwd"] == path


def test_send_passes_message_as_single_argument_even_with_dashes(adapter, fake):
    child = create(adapter)
    text = "---\nfrontmatter: x\n---\nfaça isso --flag"
    adapter.send(child.agent_id, text)
    argv = fake.commands("send")[0]
    assert f"--message={text}" in argv
    assert f"--to={child.agent_id}" in argv
    assert "--expect-reply" not in argv
    assert fake.agents[child.agent_id]["messages"] == [text]


def test_send_to_unknown_agent_raises(adapter):
    with pytest.raises(CliError) as exc:
        adapter.send("nope", "oi")
    assert exc.value.code == "E_AGENT_NOT_FOUND"


def test_poll_status_reads_agent_list(adapter, fake):
    child = create(adapter)
    fake.queue({"active_polls": 2})
    adapter.send(child.agent_id, "go")
    assert adapter.poll_status(child.agent_id).active is True
    assert adapter.poll_status(child.agent_id).active is True
    info = adapter.poll_status(child.agent_id)
    assert info.active is False and info.archived is False and info.model == "haiku"


def test_poll_status_unknown_agent_raises_agent_not_found(adapter):
    with pytest.raises(AgentNotFound):
        adapter.poll_status("nope")


def test_wait_turn_end_returns_after_agent_goes_idle(adapter, fake, clock):
    child = create(adapter)
    fake.queue({"active_polls": 3})
    adapter.send(child.agent_id, "go")
    adapter.wait_turn_end(child.agent_id, timeout=100, interval=5)
    assert adapter.poll_status(child.agent_id).active is False
    assert clock.sleeps and all(s == 5 for s in clock.sleeps)


def test_wait_turn_end_needs_consecutive_idle_polls(adapter, fake, clock):
    """Logo após o send o agente pode aparecer inativo por um instante: um poll ocioso não basta."""
    child = create(adapter)
    adapter.send(child.agent_id, "go")  # active_polls=0: ocioso desde o início
    before = len(fake.commands("list"))
    adapter.wait_turn_end(child.agent_id, timeout=100, interval=2, settle=2)
    assert len(fake.commands("list")) - before == 2


def test_wait_turn_end_with_replies_before_waits_for_a_new_reply(adapter, fake, clock):
    """Idle sem resposta nova = o host ainda não marcou o agente ativo: não conta como fim do turno."""
    child = create(adapter)
    before = adapter.reply_count(child.agent_id)
    assert before == 0
    with pytest.raises(TurnTimeout):  # nenhum send: nunca há resposta nova
        adapter.wait_turn_end(child.agent_id, timeout=20, interval=5, replies_before=before)
    fake.queue({"active_polls": 2})
    adapter.send(child.agent_id, "go")
    adapter.wait_turn_end(child.agent_id, timeout=60, interval=5, replies_before=before)
    assert adapter.reply_count(child.agent_id) == 1


def test_wait_turn_end_times_out_when_the_agent_never_finishes(adapter, fake, clock):
    child = create(adapter)
    fake.queue({"active_polls": 10_000})
    adapter.send(child.agent_id, "go")
    with pytest.raises(TurnTimeout):
        adapter.wait_turn_end(child.agent_id, timeout=30, interval=10)
    assert clock.now >= 30


def test_wait_turn_end_does_not_need_a_response_channel(adapter, fake):
    """O filho termina o turno sem responseId nem canal de resposta: o adaptador não trava."""
    child = create(adapter)
    fake.queue({"active_polls": 1, "reply": ""})
    adapter.send(child.agent_id, "go")
    adapter.wait_turn_end(child.agent_id, timeout=60, interval=1)
    assert adapter.last_message(child.agent_id) == ""
    assert all("--expect-reply" not in c and "--response-id" not in " ".join(c) for c in fake.commands())


def test_last_message_returns_the_last_assistant_reply_without_the_row_header(adapter, fake):
    child = create(adapter)
    fake.queue({"reply": "primeira"}, {"reply": "segunda\ncom duas linhas"})
    adapter.send(child.agent_id, "um")
    adapter.send(child.agent_id, "dois")
    assert adapter.last_message(child.agent_id) == "segunda\ncom duas linhas"


def test_last_message_is_empty_before_any_reply(adapter):
    child = create(adapter)
    assert adapter.last_message(child.agent_id) == ""


def test_archive_marks_the_agent_archived(adapter, fake):
    child = create(adapter)
    adapter.archive(child.agent_id)
    assert fake.agents[child.agent_id]["archived"] is True
    assert f"--agent-id={child.agent_id}" in fake.commands("archive")[0]


def test_stop_halts_the_turn(adapter, fake):
    child = create(adapter)
    fake.queue({"active_polls": 50})
    adapter.send(child.agent_id, "go")
    adapter.stop(child.agent_id)
    assert adapter.poll_status(child.agent_id).active is False


def test_rate_limit_is_the_larger_of_the_windows(adapter, fake):
    fake.update(rate={"fiveHour": 28, "sevenDay": 43})
    assert adapter.rate_limit_used_percent("claude", "p1") == 43
    fake.update(rate={"fiveHour": 91.5, "sevenDay": 20})
    assert adapter.rate_limit_used_percent("claude", "p1") == 91.5
    argv = fake.commands("profile-rate-limits")[0]
    assert "claude" in argv and "--profile=p1" in argv


def test_rate_limits_split_windows_and_report_update_time(adapter, fake):
    fake.update(rate={"fiveHour": 28, "sevenDay": 43})
    limits = adapter.rate_limits("claude", "p1")
    assert (limits.five_hour, limits.seven_day, limits.used_percent, limits.updated_at) == (28, 43, 43, 1234)


def test_rate_limit_is_none_when_the_provider_reports_none(adapter, fake):
    fake.update(rate_available=False)
    assert adapter.rate_limit_used_percent("claude", "ambient") is None


def test_rate_limit_reads_grouped_windows(adapter, fake, monkeypatch):
    groups = {
        "rateLimits": {
            "available": True,
            "groups": [
                {"windows": [{"usedPercent": 6.3}]},
                {"windows": [{"usedPercent": 62.4}, {"usedPercent": 31.2}]},
            ],
        }
    }
    monkeypatch.setattr(adapter, "_call", lambda *a, **k: groups)
    assert adapter.rate_limit_used_percent("antigravity", "ambient") == 62.4


def test_cli_error_carries_code_and_message(adapter, fake):
    fake.update(fail={"profile-rate-limits": "boom"})
    with pytest.raises(CliError) as exc:
        adapter.rate_limit_used_percent("claude", "p1")
    assert exc.value.code == "E_FAKE" and "boom" in str(exc.value)


def test_every_call_runs_with_exactly_the_four_env_vars(adapter, fake):
    child = create(adapter)
    adapter.send(child.agent_id, "go")
    adapter.poll_status(child.agent_id)
    adapter.last_message(child.agent_id)
    adapter.rate_limit_used_percent("claude", "p1")
    adapter.archive(child.agent_id)
    calls = fake.calls
    assert len(calls) >= 6
    for call in calls:
        # o sistema pode injetar LC_CTYPE/PWD no processo; as 4 variáveis do adaptador têm de estar lá
        # e nenhuma outra do ambiente do servidor pode passar.
        assert {k: call["env"].get(k) for k in ENV} == ENV
        leaked = set(call["env"]) - set(ENV)
        assert leaked <= {"LC_CTYPE", "PWD", "SHLVL", "_", "OLDPWD", "LANG", "LC_ALL"}, leaked


def test_subprocess_receives_exactly_the_four_variables(fake, monkeypatch):
    seen = {}

    def fake_run(argv, **kwargs):
        seen.update(kwargs)

        class Proc:
            returncode = 0
            stderr = ""
            stdout = '{"type":"result","status":"ok","data":{"agents":[]}}'

        return Proc()

    monkeypatch.setattr("engine.traycer_cli.subprocess.run", fake_run)
    Adapter(executable="traycer", env=ENV).list_agents()
    assert seen["env"] == ENV
    assert seen["stdin"] is not None


def test_server_environment_does_not_leak_into_the_cli(adapter, fake, monkeypatch):
    monkeypatch.setenv("SECRET_TOKEN", "hunter2")
    monkeypatch.setenv("ANTHROPIC_API_KEY", "x")
    create(adapter)
    assert "SECRET_TOKEN" not in fake.calls[0]["env"]
    assert "ANTHROPIC_API_KEY" not in fake.calls[0]["env"]


@pytest.mark.parametrize(
    "env",
    [
        {"HOME": "/h", "PATH": "/p", "TRAYCER_EPIC_ID": "e"},
        {**ENV, "EXTRA": "1"},
        {**ENV, "TRAYCER_AGENT_ID": ""},
    ],
)
def test_adapter_rejects_an_env_that_is_not_exactly_the_four_variables(fake, env):
    with pytest.raises(ValueError):
        Adapter(executable=fake.executable, env=env)


def test_from_environ_picks_only_the_four_variables(fake, monkeypatch):
    environ = {**ENV, "SECRET_TOKEN": "hunter2"}
    adapter = Adapter.from_environ(environ, executable=fake.executable)
    create(adapter)
    assert "SECRET_TOKEN" not in fake.calls[0]["env"]


def test_missing_executable_raises_cli_error():
    adapter = Adapter(executable=["/nonexistent/traycer"], env=ENV)
    with pytest.raises(CliError):
        adapter.poll_status("x")
