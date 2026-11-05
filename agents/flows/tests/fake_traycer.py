"""CLI `traycer` falso para os testes de unidade (sem rede e sem cota).

Dois papéis no mesmo arquivo:

- `FakeTraycer` (lado do teste): cria o estado em disco, devolve o `executable` para o adaptador
  e lê as chamadas registradas.
- `main()` (lado do processo): o script que o adaptador executa. Imita a saída NDJSON do CLI real
  (`{"type":"result","status":"ok","data":{...}}`).

O estado fica num JSON, e o caminho dele vai como argumento (`--state`), porque o adaptador roda
com `env -i` e nenhuma variável de teste chega ao processo. Cada `send` consome um comportamento
da fila `script`: arquivos que o filho escreve, quantos polls ele fica ativo e o que responde.
"""

from __future__ import annotations

import json
import os
import re
import sys
import uuid
from pathlib import Path

THIS_FILE = Path(__file__).resolve()
DEFAULT_BEHAVIOR = {"write": {}, "active_polls": 0, "reply": "feito"}


class FakeTraycer:
    def __init__(self, tmp_path: Path) -> None:
        self.state_path = tmp_path / "fake-traycer-state.json"
        self._save(
            {
                "agents": {},
                "calls": [],
                "script": [],
                "default_behavior": DEFAULT_BEHAVIOR,
                "rate": {"fiveHour": 10, "sevenDay": 20},
                "rate_error": False,
                "rate_available": True,
                "apply_model": {},  # modelo pedido -> modelo aplicado (simula divergência)
                "fail": {},  # comando -> mensagem de erro
                "sends": 0,
            }
        )

    @property
    def executable(self) -> list[str]:
        return [sys.executable, str(THIS_FILE), "--state", str(self.state_path)]

    def _load(self) -> dict:
        return json.loads(self.state_path.read_text(encoding="utf-8"))

    def _save(self, state: dict) -> None:
        self.state_path.write_text(json.dumps(state), encoding="utf-8")

    def update(self, **fields) -> None:
        state = self._load()
        state.update(fields)
        self._save(state)

    def queue(self, *behaviors: dict) -> None:
        """Comportamentos dos próximos `send`, em ordem. Campos: write, active_polls, reply."""
        state = self._load()
        state["script"].extend(behaviors)
        self._save(state)

    @property
    def calls(self) -> list[dict]:
        return self._load()["calls"]

    def commands(self, name: str | None = None) -> list[list[str]]:
        argvs = [c["argv"] for c in self.calls]
        return [a for a in argvs if name is None or a[:2] == ["agent", name]]

    @property
    def agents(self) -> dict:
        return self._load()["agents"]


def _arg(argv: list[str], flag: str) -> str | None:
    prefix = flag + "="
    for i, token in enumerate(argv):
        if token.startswith(prefix):
            return token[len(prefix):]
        if token == flag and i + 1 < len(argv):
            return argv[i + 1]
    return None


def _out(data: dict) -> None:
    print(json.dumps({"type": "result", "status": "ok", "data": data, "timestamp": "2026-01-01T00:00:00Z"}))


def _error(code: str, message: str) -> int:
    print(json.dumps({"type": "result", "status": "error", "error": {"code": code, "message": message}}))
    return 1


def _agent_row(agent_id: str, agent: dict) -> dict:
    return {
        "id": agent_id,
        "parentId": os.environ.get("TRAYCER_AGENT_ID"),
        "active": agent["active_polls"] > 0,
        "archived": agent["archived"],
        "harnessId": agent["harness"],
        "profile": agent["profile"],
        "runConfig": {
            "model": {"kind": "concrete", "slug": agent["model"]},
            "reasoningEffort": agent["effort"],
            "fastMode": False,
        },
    }


def main(argv: list[str]) -> int:
    assert argv[0] == "--state"
    state_path = Path(argv[1])
    args = argv[2:]
    state = json.loads(state_path.read_text(encoding="utf-8"))
    state["calls"].append({"argv": args, "env": dict(os.environ)})
    code = _dispatch(state, args)
    state_path.write_text(json.dumps(state), encoding="utf-8")
    return code


def _dispatch(state: dict, args: list[str]) -> int:
    key = " ".join(args[:2]) if args[0] == "agent" else args[0] + " " + args[1]
    name = args[1] if args[0] == "agent" else args[0]
    if state["fail"].get(name):
        return _error("E_FAKE", state["fail"][name])
    if not os.environ.get("TRAYCER_EPIC_ID") or not os.environ.get("TRAYCER_AGENT_ID"):
        return _error("E_INVALID_ARGUMENT", "traycer: epic id required - set TRAYCER_EPIC_ID.")

    if key == "agent create":
        agent_id = str(uuid.uuid4())
        requested = _arg(args, "--model")
        state["agents"][agent_id] = {
            "harness": _arg(args, "--harness"),
            "model": state["apply_model"].get(requested, requested),
            "effort": _arg(args, "--reasoning-effort"),
            "profile": _arg(args, "--profile"),
            "cwd": _arg(args, "--cwd"),
            "name": _arg(args, "--name"),
            "active_polls": 0,
            "archived": False,
            "messages": [],
            "replies": [],
        }
        _out({"agentId": agent_id, "warnings": []})
        return 0
    if key == "agent send":
        agent = state["agents"].get(_arg(args, "--to"))
        if agent is None:
            return _error("E_AGENT_NOT_FOUND", "traycer: unknown agent")
        behavior = state["script"].pop(0) if state["script"] else state["default_behavior"]
        state["sends"] += 1
        agent["messages"].append(_arg(args, "--message"))
        agent["replies"].append(behavior.get("reply", "feito"))
        agent["active_polls"] = behavior.get("active_polls", 0)
        agent["archived"] = False
        for path, content in behavior.get("write", {}).items():
            target = Path(path)
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(content, encoding="utf-8")
        _out({"responseId": None})
        return 0
    if key == "agent list":
        rows = []
        for agent_id, agent in state["agents"].items():
            rows.append(_agent_row(agent_id, agent))
            if agent["active_polls"] > 0:
                agent["active_polls"] -= 1
        print(json.dumps({"type": "result", "status": "ok", "data": {"agents": rows}}))
        return 0
    if key == "agent transcript":
        agent = state["agents"].get(_arg(args, "--agent-id"))
        if agent is None:
            return _error("E_AGENT_NOT_FOUND", "traycer: agent.getTranscript: cannot read agent")
        parts = []
        for message, reply in zip(agent["messages"], agent["replies"]):
            parts.append(f"<user_message>\n{message}\n</user_message>")
            parts.append(f"<assistant_response>\n[assistant row | provider=claude | model={agent['model']} | turn=t]\n{reply}\n</assistant_response>")
        _out({"transcript": "\n\n".join(parts)})
        return 0
    if key == "agent archive":
        agent = state["agents"].get(_arg(args, "--agent-id"))
        if agent is None:
            return _error("E_AGENT_NOT_FOUND", "traycer: unknown agent")
        agent["archived"] = True
        _out({"updated": True, "outcome": "applied"})
        return 0
    if key == "agent stop":
        agent = state["agents"].get(_arg(args, "--agent-id"))
        if agent is None:
            return _error("E_AGENT_NOT_FOUND", "traycer: unknown agent")
        agent["active_polls"] = 0
        _out({"stoppedAgentIds": [_arg(args, "--agent-id")]})
        return 0
    if key == "agent profile-rate-limits":
        if state["rate_error"]:
            return _error("E_RATE", "traycer: cannot read rate limits")
        if not state["rate_available"]:
            _out({"rateLimits": {"provider": "x", "available": False}})
            return 0
        limits = {"provider": "claude-code", "available": True}
        for field in ("fiveHour", "sevenDay"):
            limits[field] = {"usedPercent": state["rate"][field], "resetsAt": 1, "durationMinutes": 1}
        _out({"rateLimits": limits, "usageUpdatedAt": 1234})
        return 0
    if key == "worktree create":
        branch = _arg(args, "--branch") or _arg(args, "--existing")
        path = str(Path(_arg(args, "--workspace")).parent / ("wt-" + re.sub(r"\W", "-", branch)))
        _out({"entries": [{"path": path, "branch": branch}]})
        return 0
    return _error("E_FAKE", f"unsupported command: {' '.join(args)}")


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
