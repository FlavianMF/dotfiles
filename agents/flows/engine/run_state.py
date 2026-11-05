"""Estado do run em JSON: um arquivo por run, escrita atômica e trava entre processos.

Formato (`version: 1`), tudo texto e número, sem segredo nem ambiente:

    {
      "version": 1, "run_id": "...", "status": "active" | "done" | "aborted",
      "flow_file": "/abs/flow.yaml", "slug": "...", "repo": "/abs/realpath",
      "variables": {"sensitive": false, "diff_lines": null},   # valores fixos do `when`
      "created_at": "...", "updated_at": "...",
      "nodes": {"<id>": {"state": "...", "reason": "", "attempts": 0, "retries_used": 0,
                          "child_id": null, "sent": false, "history": [{"to": "...", ...}], ...}},
      "events": [{"t": "...", "node": "<id>" | null, "msg": "..."}]
    }

`history` só cresce: cada transição de estado vira uma entrada, e os testes leem a trilha dali.
"""

from __future__ import annotations

import contextlib
import fcntl
import json
import os
import re
import tempfile
import threading
from collections.abc import Iterator
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

VERSION = 1

NODE_STATES = (
    "pending",
    "running",
    "awaiting_gate",
    "failed",
    "awaiting_upgrade",
    "awaiting_quota",
    "done",
    "skipped",
    "aborted",
)
TERMINAL_NODE_STATES = frozenset({"done", "skipped", "aborted"})

# Transições permitidas (seção 4 do plano, mais `awaiting_quota`).
TRANSITIONS: dict[str, frozenset[str]] = {
    "pending": frozenset({"skipped", "running", "awaiting_gate", "done", "awaiting_quota", "aborted"}),
    "running": frozenset({"awaiting_gate", "done", "failed", "awaiting_quota", "aborted"}),
    "awaiting_gate": frozenset({"done", "running", "aborted"}),
    "failed": frozenset({"running", "awaiting_upgrade", "awaiting_quota", "aborted"}),
    "awaiting_upgrade": frozenset({"running", "aborted"}),
    "awaiting_quota": frozenset({"running", "aborted"}),
    "done": frozenset(),
    "skipped": frozenset(),
    "aborted": frozenset(),
}

RUN_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$")
MAX_EVENTS = 300
START_LOCK = "start"  # trava interna da criação de run; nenhum run_id é só "start" (tem sufixo)


class StateError(Exception):
    """Estado ausente, ilegível ou com id inválido."""


def iso(epoch: float) -> str:
    return datetime.fromtimestamp(epoch, tz=timezone.utc).isoformat(timespec="seconds")


def new_node_state() -> dict[str, Any]:
    return {
        "state": "pending",
        "reason": "",
        "attempts": 0,  # filhos criados para este nó
        "retries_used": 0,  # repetições gastas desde a última escolha de upgrade
        "child_id": None,
        "sent": False,
        "pending_message": None,
        "snapshot": None,  # assinatura das saídas antes do send: sucesso = mudou
        "replies_before": 0,
        "sent_at": None,
        "model": None,  # modelo escolhido em `choose_upgrade`; None = o do YAML
        "effort": None,
        "divergence": None,
        "when_result": None,
        "history": [],
    }


def transition(node: dict[str, Any], to: str, reason: str, at: float) -> None:
    """Muda o estado do nó e acrescenta a entrada na trilha. Levanta ValueError se a tabela proíbe."""
    current = node["state"]
    if to not in TRANSITIONS.get(current, frozenset()):
        raise ValueError(f"transition {current} -> {to} is not allowed")
    node["state"] = to
    node["reason"] = reason
    node["history"].append({"from": current, "to": to, "reason": reason, "t": iso(at)})


def add_event(state: dict[str, Any], node_id: str | None, msg: str, at: float) -> None:
    events = state["events"]
    events.append({"t": iso(at), "node": node_id, "msg": msg})
    del events[:-MAX_EVENTS]


class RunStore:
    """Diretório de estado: `<run_id>.json` por run."""

    def __init__(self, state_dir: str | os.PathLike[str]) -> None:
        self.dir = Path(state_dir)
        self._threads: dict[str, threading.RLock] = {}
        self._guard = threading.Lock()

    def _ensure_dir(self) -> None:
        """Cria `state_dir` com modo 0o700 e aperta o modo se ele já existia mais aberto."""
        self.dir.mkdir(parents=True, exist_ok=True, mode=0o700)
        if self.dir.stat().st_mode & 0o077:
            os.chmod(self.dir, 0o700)

    def path(self, run_id: str) -> Path:
        if not isinstance(run_id, str) or not RUN_ID_RE.fullmatch(run_id):
            raise StateError(f"invalid run id {run_id!r}")
        return self.dir / f"{run_id}.json"

    def load(self, run_id: str) -> dict[str, Any]:
        path = self.path(run_id)
        try:
            state = json.loads(path.read_text(encoding="utf-8"))
        except FileNotFoundError as exc:
            raise StateError(f"run {run_id} not found") from exc
        except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise StateError(f"run {run_id}: unreadable state file: {exc}") from exc
        if not isinstance(state, dict) or state.get("version") != VERSION or state.get("run_id") != run_id:
            raise StateError(f"run {run_id}: unexpected state format")
        return state

    def save(self, state: dict[str, Any]) -> None:
        """Escreve em arquivo temporário no mesmo diretório e troca por `rename`: ninguém lê meio arquivo."""
        path = self.path(state["run_id"])
        self._ensure_dir()
        fd, tmp_name = tempfile.mkstemp(dir=self.dir, prefix=f".{path.name}.", suffix=".tmp")
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as handle:
                json.dump(state, handle, indent=2, ensure_ascii=False, sort_keys=True)
                handle.write("\n")
                handle.flush()
                os.fsync(handle.fileno())
            os.chmod(tmp_name, 0o600)
            os.replace(tmp_name, path)
        except BaseException:
            with contextlib.suppress(OSError):
                os.unlink(tmp_name)
            raise

    def list_runs(self) -> list[dict[str, Any]]:
        runs = []
        if not self.dir.is_dir():
            return runs
        for path in sorted(self.dir.glob("*.json")):
            try:
                runs.append(self.load(path.stem))
            except StateError:
                continue  # arquivo estranho no diretório: não derruba a checagem de run ativo
        return runs

    @contextlib.contextmanager
    def lock(self, name: str) -> Iterator[None]:
        """Trava exclusiva por nome: `threading.RLock` (mesmo processo) e `flock` (outro processo).

        `name` é `START_LOCK` ou o id de um run que existe: nome inválido ou run inexistente levanta
        `StateError` antes de tocar o disco (nada de `.lock` fora de `state_dir`, nada de `_threads` inflado)."""
        if name != START_LOCK and not self.path(name).is_file():
            raise StateError(f"run {name} not found")
        self._ensure_dir()
        with self._guard:
            thread_lock = self._threads.setdefault(name, threading.RLock())
        with thread_lock:
            fd = os.open(self.dir / f".{name}.lock", os.O_CREAT | os.O_RDWR, 0o600)
            try:
                fcntl.flock(fd, fcntl.LOCK_EX)
                try:
                    yield
                finally:
                    fcntl.flock(fd, fcntl.LOCK_UN)
            finally:
                os.close(fd)
