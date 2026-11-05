"""Achados da revisão a frio (commit 7c91766): um teste por achado, escrito antes da correção."""

import json
import os
import subprocess
from pathlib import Path

import pytest

from engine.run_state import RunStore, StateError
from engine.runner import RunError, Runner, Step
from tests.test_runner import Env


@pytest.fixture
def env(tmp_path):
    return Env(tmp_path)


# 1. `_fail` tentava failed -> failed quando a repetição falha ao criar o filho ----------------


def test_create_failing_on_every_retry_reaches_awaiting_upgrade(env):
    env.flow(env.node("a", on_fail={"retry": 2, "then": "ask_before_upgrade"}))
    env.fake.update(fail={"create": "sem vaga"})
    run_id = env.start()
    assert env.drive(run_id) is Step.BLOCKED
    node = env.runner.status(run_id)["nodes"]["a"]
    assert node["state"] == "awaiting_upgrade"
    assert node["attempts"] == 3
    assert env.history(run_id, "a") == ["running", "failed", "running", "failed", "running", "failed", "awaiting_upgrade"]


def test_unreadable_prompt_on_a_retry_also_ends_in_awaiting_upgrade(env):
    env.flow(env.node("a", on_fail={"retry": 1, "then": "ask_before_upgrade"}))
    env.fake.queue({"write": {}})
    run_id = env.start()
    env.runner.step(run_id)  # 1ª tentativa roda e termina sem saída
    prompt = env.tmp_path / "prompts" / "a.md"
    prompt.chmod(0)  # a repetição não consegue ler o prompt
    try:
        assert env.drive(run_id) is Step.BLOCKED
    finally:
        prompt.chmod(0o644)
    assert env.states(run_id) == {"a": "awaiting_upgrade"}
    assert env.history(run_id, "a") == ["running", "failed", "running", "failed", "awaiting_upgrade"]


# 2. abort_run não pode depender do YAML --------------------------------------------------------


@pytest.mark.parametrize("damage", ["remove", "change_nodes", "invalid"])
def test_abort_run_works_when_the_flow_file_is_gone_or_changed(env, damage):
    env.flow(env.node("a"), env.node("b", ["out/a.md"]))
    env.fake.queue({"active_polls": 100})
    run_id = env.start()
    env.runner.step(run_id)
    if damage == "remove":
        env.flow_path.unlink()
    elif damage == "change_nodes":
        env.flow(env.node("zzz"))
    else:
        env.flow_path.write_text("nodes: [")
    env.runner.abort_run(run_id)
    status = env.runner.status(run_id)
    assert status["status"] == "aborted"
    assert env.states(run_id) == {"a": "aborted", "b": "aborted"}
    (agent,) = env.fake.agents.values()
    assert agent["archived"] and len(env.fake.commands("stop")) == 1
    env.flow(env.node("a"))
    env.start()  # o repo ficou livre


# 3. `_refresh_manual` ignorava predecessores e `when` -------------------------------------------


def test_approve_gate_refuses_a_manual_node_whose_predecessor_is_still_running(env):
    env.flow(env.node("a", gate="human"), env.node("prd", ["out/a.md"], mode="manual", gate="human"))
    env.fake.queue({"active_polls": 100})  # `a` fica rodando
    run_id = env.start()
    env.runner.step(run_id)
    (env.repo / "out").mkdir()
    (env.repo / "out" / "prd.md").write_text("arquivo velho\n")  # saída de um run anterior
    with pytest.raises(RunError):
        env.runner.approve_gate(run_id, "prd")
    assert env.states(run_id) == {"a": "running", "prd": "pending"}


def test_approve_gate_refuses_a_manual_node_whose_when_was_not_evaluated(env):
    env.flow(env.node("prd", mode="manual", gate="human", when="sensitive"))
    run_id = env.start()  # nenhum step: o `when` ainda não foi avaliado
    (env.repo / "out").mkdir()
    (env.repo / "out" / "prd.md").write_text("arquivo velho\n")
    with pytest.raises(RunError):
        env.runner.approve_gate(run_id, "prd")
    assert env.states(run_id) == {"prd": "pending"}


def test_approve_gate_refuses_a_manual_node_that_the_when_skips(env):
    env.flow(env.node("prd", mode="manual", gate="human", when="sensitive"))
    run_id = env.start(sensitive=False)
    (env.repo / "out").mkdir()
    (env.repo / "out" / "prd.md").write_text("arquivo velho\n")
    env.drive(run_id)
    assert env.states(run_id) == {"prd": "skipped"}
    with pytest.raises(RunError):
        env.runner.approve_gate(run_id, "prd")


def test_approve_gate_still_refreshes_a_ready_manual_node(env):
    env.flow(env.node("prd", mode="manual", gate="human", when="sensitive"))
    run_id = env.start(sensitive=True)
    env.drive(run_id)  # `when` avaliado, arquivo ainda não existe
    (env.repo / "out").mkdir()
    (env.repo / "out" / "prd.md").write_text("prd\n")
    env.runner.approve_gate(run_id, "prd")  # o arquivo apareceu entre dois steps
    assert env.states(run_id) == {"prd": "done"}


# 4. `lock(name)` sem validar o nome ------------------------------------------------------------

BAD_IDS = ["./../../x", "../x", "a/b", "", ".hidden", "x" * 200]


@pytest.mark.parametrize("bad", BAD_IDS)
def test_every_public_method_rejects_a_bad_run_id_without_touching_the_disk(env, bad):
    calls = [
        lambda: env.runner.step(bad),
        lambda: env.runner.drive(bad),
        lambda: env.runner.status(bad),
        lambda: env.runner.approve_gate(bad, "a"),
        lambda: env.runner.reject_gate(bad, "a"),
        lambda: env.runner.request_adjustment(bad, "a", "x"),
        lambda: env.runner.choose_upgrade(bad, "a", model="opus"),
        lambda: env.runner.abort_run(bad),
    ]
    for call in calls:
        with pytest.raises(StateError):
            call()
    assert not list(env.tmp_path.rglob("*.lock"))
    assert env.runner.store._threads == {}


def test_unknown_but_valid_run_id_does_not_create_lock_files(env):
    with pytest.raises(StateError):
        env.runner.step("run-does-not-exist")
    assert not list(env.tmp_path.rglob("*.lock"))
    assert env.runner.store._threads == {}


def test_the_internal_start_lock_still_works(env):
    env.flow(env.node("a", gate="human"))
    env.start()
    assert (env.tmp_path / "state" / ".start.lock").exists()


# 5. git_variables roda git com ambiente mínimo e sem o fsmonitor do repo -------------------------


def _git(repo, *args):
    subprocess.run(["git", "-C", str(repo), *args], check=True, capture_output=True)


def test_git_variables_does_not_run_the_repo_fsmonitor_hook(tmp_path):
    from engine.runner import git_variables

    repo = tmp_path / "r"
    repo.mkdir()
    _git(repo, "init", "-q")
    _git(repo, "config", "user.email", "t@t")
    _git(repo, "config", "user.name", "t")
    (repo / "code.py").write_text("a\n")
    _git(repo, "add", "-A")
    _git(repo, "commit", "-qm", "init")
    sentinel = tmp_path / "sentinel"
    hook = tmp_path / "hook.sh"
    hook.write_text(f"#!/bin/sh\ntouch {sentinel}\nprintf '\\0'\n")
    hook.chmod(0o755)
    _git(repo, "config", "core.fsmonitor", str(hook))
    # controle: o git puro roda o hook, então o teste prova alguma coisa
    subprocess.run(["git", "-C", str(repo), "status", "-s"], check=True, capture_output=True)
    assert sentinel.exists(), "controle: este git não rodou o fsmonitor"
    sentinel.unlink()
    (repo / "code.py").write_text("a\nb\n")
    assert git_variables(repo) == {"diff_lines": 1}
    assert not sentinel.exists()


def test_git_variables_passes_a_minimal_environment_to_git(tmp_path, monkeypatch):
    from engine import runner

    monkeypatch.setenv("SECRET_TOKEN", "hunter2")
    monkeypatch.setenv("GIT_DIR", "/elsewhere")
    seen = {}

    def fake_run(argv, **kwargs):
        seen.update(argv=argv, **kwargs)

        class Proc:
            returncode = 0
            stdout = "3\t1\tf.py\n"
            stderr = ""

        return Proc()

    monkeypatch.setattr(runner.subprocess, "run", fake_run)
    assert runner.git_variables(tmp_path) == {"diff_lines": 4}
    assert set(seen["env"]) <= {"HOME", "PATH", "LANG", "GIT_CONFIG_NOSYSTEM"}
    assert {"HOME", "PATH", "LANG"} <= set(seen["env"])
    assert seen["env"]["GIT_CONFIG_NOSYSTEM"] == "1"
    assert "SECRET_TOKEN" not in seen["env"] and "GIT_DIR" not in seen["env"]
    assert ["-c", "core.fsmonitor=false"] == seen["argv"][1:3]


# 8. state_dir com modo 0o700 ---------------------------------------------------------------------


def _mode(path):
    return path.stat().st_mode & 0o777


def test_state_dir_is_created_private(env):
    env.flow(env.node("a", gate="human"))
    env.start()
    assert _mode(env.tmp_path / "state") == 0o700


def test_state_dir_created_with_parents_is_private(tmp_path):
    store = RunStore(tmp_path / "x" / "y" / "state")
    store.save({"version": 1, "run_id": "r1", "status": "active", "nodes": {}})
    assert _mode(tmp_path / "x" / "y" / "state") == 0o700


def test_existing_open_state_dir_is_tightened(tmp_path):
    state = tmp_path / "state"
    state.mkdir(mode=0o755)
    state.chmod(0o755)
    store = RunStore(state)
    store.save({"version": 1, "run_id": "r1", "status": "active", "nodes": {}})
    assert _mode(state) == 0o700
    state.chmod(0o755)
    with store.lock("start"):
        pass
    assert _mode(state) == 0o700


# 9. o runner confere o prompt antes de ler (symlink trocado depois da validação) -------------------


def test_runner_refuses_a_prompt_that_became_a_symlink_to_outside(env):
    env.flow(env.node("a"))
    run_id = env.start()
    flow = env.runner._flow(env.runner.store.load(run_id))
    state = env.runner.store.load(run_id)
    secret = env.tmp_path / "secret.txt"
    secret.write_text("segredo\n")
    prompt = env.tmp_path / "prompts" / "a.md"
    prompt.unlink()
    prompt.symlink_to(secret)  # trocado depois da validação do fluxo
    with pytest.raises(OSError):
        env.runner._message(state, flow, flow.nodes[0], state["nodes"]["a"])


def test_symlinked_prompt_swapped_in_after_start_never_reaches_the_child(env):
    env.flow(env.node("a", on_fail={"retry": 0, "then": "abort"}))
    run_id = env.start()
    secret = env.tmp_path / "secret.txt"
    secret.write_text("segredo\n")
    prompt = env.tmp_path / "prompts" / "a.md"
    prompt.unlink()
    prompt.symlink_to(secret)
    from engine.schema import FlowError

    with pytest.raises(FlowError):  # o fluxo é validado de novo a cada step
        env.runner.step(run_id)
    assert env.fake.commands("create") == []


# 10. flock sem prazo -> prazo configurável e erro tipado -------------------------------------------


def _hold_flock(env, run_id):
    import fcntl

    fd = os.open(env.tmp_path / "state" / f".{run_id}.lock", os.O_CREAT | os.O_RDWR, 0o600)
    fcntl.flock(fd, fcntl.LOCK_EX)
    return fd


def test_lock_held_by_another_process_times_out_with_a_typed_error(env):
    import time

    from engine.run_state import LockTimeout

    env.flow(env.node("a", gate="human"))
    run_id = env.start()
    env.restart(lock_timeout=0.3)
    fd = _hold_flock(env, run_id)  # outro "processo" (outro fd) segura a trava
    try:
        started = time.monotonic()
        for call in (
            lambda: env.runner.step(run_id),
            lambda: env.runner.approve_gate(run_id, "a"),
            lambda: env.runner.abort_run(run_id),
        ):
            with pytest.raises(LockTimeout) as exc:
                call()
            assert "lock timeout" in str(exc.value) and run_id in str(exc.value)
            assert isinstance(exc.value, StateError)
        assert time.monotonic() - started < 5
    finally:
        os.close(fd)
    env.runner.step(run_id)  # solta a trava: volta a funcionar


def test_lock_held_by_another_thread_times_out(env):
    import threading
    import time

    from engine.run_state import LockTimeout

    env.flow(env.node("a", gate="human"))
    run_id = env.start()
    env.restart(lock_timeout=0.3)
    inside, release = threading.Event(), threading.Event()

    def holder():
        with env.runner.store.lock(run_id):
            inside.set()
            release.wait(10)

    thread = threading.Thread(target=holder)
    thread.start()
    assert inside.wait(5)
    try:
        started = time.monotonic()
        with pytest.raises(LockTimeout):
            env.runner.step(run_id)
        assert time.monotonic() - started < 5
    finally:
        release.set()
        thread.join()


def test_lock_timeout_is_configurable_and_defaults_to_30_seconds(env):
    assert env.runner.store.lock_timeout == 30.0
    assert env.new_runner(lock_timeout=2.5).store.lock_timeout == 2.5


def test_lock_timeout_is_exported_by_the_runner_module():
    from engine import runner

    assert issubclass(runner.LockTimeout, runner.StateError)


# 11. trava presa durante chamadas ao CLI: erro tipado para o T5 e comportamento documentado --------


def test_drive_propagates_the_typed_lock_error_to_the_caller(env):
    from engine.runner import LockTimeout

    env.flow(env.node("a", gate="human"))
    run_id = env.start()
    env.restart(lock_timeout=0.2)
    fd = _hold_flock(env, run_id)
    try:
        with pytest.raises(LockTimeout):
            env.runner.drive(run_id)
        with pytest.raises(LockTimeout):
            env.runner.request_adjustment(run_id, "a", "x")
        with pytest.raises(LockTimeout):
            env.runner.reject_gate(run_id, "a")
        with pytest.raises(LockTimeout):
            env.runner.choose_upgrade(run_id, "a", model="opus")
    finally:
        os.close(fd)


def test_status_does_not_wait_for_the_lock(env):
    """`status` só lê o JSON (escrita atômica): um passo lento no CLI não trava a tela do T5."""
    import time

    env.flow(env.node("a", gate="human"))
    run_id = env.start()
    env.restart(lock_timeout=30)
    fd = _hold_flock(env, run_id)
    try:
        started = time.monotonic()
        assert env.runner.status(run_id)["run_id"] == run_id
        assert time.monotonic() - started < 2
    finally:
        os.close(fd)


def test_runner_docstring_documents_the_lock_held_during_cli_calls():
    doc = Runner.__doc__ or ""
    assert "60 s" in doc and "LockTimeout" in doc and "status" in doc
