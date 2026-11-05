"""Relatório por fase de um run: `python -m engine.cli report <run_id> [--json]`.

Lê o JSON de estado e os transcripts dos filhos pelo `Adapter`. Não grava nada e não muda o motor.
Dado que o estado não guarda aparece como `n/d` (campo `None` no JSON):

- cota 5h/7d antes e depois da fase: o motor só compara a cota com o limite e não grava a leitura;
- contexto: depende de o cabeçalho `[assistant row | ...]` do transcript trazer o uso. O cabeçalho é
  lido em busca de campos `chave=valor` cujo nome contém `input`, `cache_read` e `cache_creation`
  (ou `cache_write`); sem eles, `n/d`;
- filhos de tentativas anteriores (repetição ou upgrade): o estado guarda só o último filho do nó.
"""

from __future__ import annotations

import json
import re
from datetime import datetime
from typing import Any

from engine.loader import load_flow
from engine.run_state import StateError
from engine.traycer_cli import AgentInfo, CliError

ND = "n/d"
_WORK_END = ("done", "failed", "awaiting_gate", "aborted", "awaiting_quota")
_FIELD_RE = re.compile(r"([A-Za-z_]+)=(\d+)")


def _seconds(start: str, end: str) -> float:
    return (datetime.fromisoformat(end) - datetime.fromisoformat(start)).total_seconds()


def _duration(ns: dict[str, Any]) -> float | None:
    history = ns.get("history") or []
    starts = [h["t"] for h in history if h["to"] == "running"]
    ends = [h["t"] for h in history if h["to"] in _WORK_END]
    if not starts or not ends or ends[-1] < starts[0]:
        return None
    return _seconds(starts[0], ends[-1])


def _context(header: str) -> int | None:
    """Entrada + cache lido + cache criado de uma resposta; None se o cabeçalho não traz uso."""
    total, found = 0, False
    for key, value in _FIELD_RE.findall(header):
        key = key.lower()
        if "cache_read" in key or "cache_creation" in key or "cache_write" in key or key.endswith("input_tokens") and "output" not in key:
            total += int(value)
            found = True
    return total if found else None


def _child_data(adapter: Any, child_id: str, infos: dict[str, AgentInfo]) -> dict[str, Any]:
    data: dict[str, Any] = {"applied_model": infos[child_id].model if child_id in infos else None}
    try:
        values = [_context(h) for h in adapter.assistant_headers(child_id)]
        prompts = adapter.prompt_count(child_id)
    except CliError:
        return {**data, "context_end": None, "context_peak": None, "interventions": None}
    known = [v for v in values if v is not None]
    data["context_end"] = values[-1] if values and values[-1] is not None else None
    data["context_peak"] = max(known) if known else None
    data["interventions"] = max(prompts - 1, 0)  # a primeira mensagem é o briefing do motor
    return data


def build_report(state: dict[str, Any], adapter: Any) -> dict[str, Any]:
    flow = load_flow(state["flow_file"], slug=state["slug"])
    try:
        infos = {i.agent_id: i for i in adapter.list_agents()}
    except CliError:
        infos = {}
    phases = []
    for node in flow.nodes:
        ns = state["nodes"].get(node.id)
        if ns is None:
            continue
        requested = ns.get("model") or node.agent.model
        row: dict[str, Any] = {
            "node": node.id,
            "requested_model": requested,
            "applied_model": None,
            "diverged": False,
            "duration_s": _duration(ns),
            "context_end": None,
            "context_peak": None,
            "quota": None,
            "interventions": None,
            "result": ns["state"],
            "outputs": [] if ns["state"] == "skipped" else list(_rel_outputs(node.outputs, state["repo"])),
        }
        child_id = ns.get("child_id") or ns.get("last_child_id")
        if child_id:
            row.update(_child_data(adapter, child_id, infos))
            if row["applied_model"] is None and ns.get("divergence"):
                row["applied_model"] = ns["divergence"]["applied"]["model"]
            row["diverged"] = row["applied_model"] is not None and row["applied_model"] != requested
        phases.append(row)
    return {"run_id": state["run_id"], "flow": state.get("flow"), "status": state["status"], "phases": phases}


def _rel_outputs(outputs: tuple[str, ...], repo: str) -> list[str]:
    prefix = repo.rstrip("/") + "/"
    return [o[len(prefix):] if o.startswith(prefix) else o for o in outputs]


def _fmt(value: Any, unit: str = "") -> str:
    return ND if value is None else f"{value}{unit}"


def format_table(report: dict[str, Any]) -> str:
    head = ["fase", "modelo pedido/aplicado", "duração", "ctx fim/pico", "cota 5h/7d", "interv.", "resultado", "saída"]
    rows = [head]
    for p in report["phases"]:
        if p["applied_model"] is None:
            model = f"{p['requested_model']}/{ND}"
        else:
            model = f"{p['requested_model']}/{p['applied_model']}" + (" DIVERGE" if p["diverged"] else "")
        quota = ND if p["quota"] is None else f"{p['quota']['5h']}/{p['quota']['7d']}"
        rows.append(
            [
                p["node"],
                model,
                _fmt(None if p["duration_s"] is None else round(p["duration_s"]), "s"),
                f"{_fmt(p['context_end'])}/{_fmt(p['context_peak'])}",
                quota,
                _fmt(p["interventions"]),
                p["result"],
                ", ".join(p["outputs"]) or "-",
            ]
        )
    widths = [max(len(r[i]) for r in rows) for i in range(len(head))]
    lines = ["  ".join(c.ljust(w) for c, w in zip(r, widths)).rstrip() for r in rows]
    return f"run {report['run_id']} · {report['status']}\n" + "\n".join(lines)


def cmd_report(args: Any, ctx: Any) -> int:
    state = ctx.store.load(args.run)  # StateError("run X not found") vira exit 2 em cli.main
    report = build_report(state, ctx.get_adapter())
    print(json.dumps(report, indent=2, ensure_ascii=False) if args.json else format_table(report))
    return 0
