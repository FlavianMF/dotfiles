"""Motor falso para os testes do servidor (T5): mesma API pública do `Runner`, estado em memória.

Copia as mensagens de erro do motor real (`RunError`, `StateError`) para os testes cobrirem o
mapeamento de erros do servidor sem subir o CLI do Traycer.
"""

import copy
import itertools

from engine.loader import load_flow
from engine.run_state import StateError, new_node_state, transition
from engine.runner import RunError

NOW = 1_000_000.0


class FakeRunner:
    def __init__(self):
        self.runs = {}
        self.driven = []  # run_id de cada chamada a `drive`
        self.raise_on = {}  # método -> exceção levantada na próxima chamada
        self._ids = itertools.count(1)

    def _maybe_raise(self, method):
        exc = self.raise_on.pop(method, None)
        if exc is not None:
            raise exc

    def start_run(self, flow_path, *, slug, repo, sensitive=False, diff_lines=None):
        self._maybe_raise("start_run")
        flow = load_flow(flow_path, slug=slug)
        run_id = f"{slug}-{next(self._ids):08d}"
        self.runs[run_id] = {
            "version": 1,
            "run_id": run_id,
            "status": "active",
            "flow": flow.name,
            "flow_file": str(flow.source),
            "slug": slug,
            "repo": str(repo),
            "variables": {"sensitive": sensitive, "diff_lines": diff_lines},
            "nodes": {node.id: new_node_state() for node in flow.nodes},
            "events": [{"t": "2026-01-01T00:00:00+00:00", "node": None, "msg": "run created"}],
        }
        return run_id

    def drive(self, run_id):
        """Primeiro nó pendente vai para `awaiting_gate`: o fluxo para esperando o humano."""
        self._maybe_raise("drive")
        self.driven.append(run_id)
        for ns in self._state(run_id)["nodes"].values():
            if ns["state"] == "pending":
                transition(ns, "awaiting_gate", "waiting for a human", NOW)
                break

    def status(self, run_id):
        self._maybe_raise("status")
        state = copy.deepcopy(self._state(run_id))
        state["waiting"] = [
            {"node": node_id, "state": ns["state"]}
            for node_id, ns in state["nodes"].items()
            if ns["state"] in ("awaiting_gate", "awaiting_upgrade", "awaiting_quota")
        ]
        return state

    def approve_gate(self, run_id, node_id):
        self._maybe_raise("approve_gate")
        ns = self._node(run_id, node_id)
        if ns["state"] != "awaiting_gate":
            raise RunError(f"node '{node_id}' is {ns['state']}, not awaiting_gate: nothing to approve")
        transition(ns, "done", "approved by a human", NOW)

    def choose_upgrade(self, run_id, node_id, *, model, effort=None):
        self._maybe_raise("choose_upgrade")
        ns = self._node(run_id, node_id)
        if ns["state"] != "awaiting_upgrade":
            raise RunError(f"node '{node_id}' is {ns['state']}, not awaiting_upgrade")
        ns.update(model=model, effort=effort)
        transition(ns, "running", f"upgrade chosen: {model}", NOW)

    # --- ajuda dos testes -----------------------------------------------------------------

    def force(self, run_id, node_id, state, reason=""):
        """Põe o nó direto em `state` (sem validar a transição)."""
        ns = self._node(run_id, node_id)
        ns["state"] = state
        ns["reason"] = reason

    def _state(self, run_id):
        try:
            return self.runs[run_id]
        except KeyError:
            raise StateError(f"run {run_id} not found") from None

    def _node(self, run_id, node_id):
        nodes = self._state(run_id)["nodes"]
        if node_id not in nodes:
            raise RunError(f"unknown node '{node_id}'")
        return nodes[node_id]
