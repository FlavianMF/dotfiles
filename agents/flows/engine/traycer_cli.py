"""Adaptador do CLI `traycer`: toda chamada ao CLI passa por aqui.

    adapter = Adapter.from_environ(os.environ)           # executável `traycer`
    child = adapter.create_child(harness="claude", model="haiku", effort="low",
                                 profile="ambient", cwd="/repo")
    adapter.send(child.agent_id, "prompt completo")
    adapter.wait_turn_end(child.agent_id, timeout=900, interval=5)
    adapter.last_message(child.agent_id)
    adapter.archive(child.agent_id)

Regras:

- O CLI roda com o ambiente de `env -i`: só `HOME`, `PATH`, `TRAYCER_EPIC_ID` e `TRAYCER_AGENT_ID`.
  `subprocess` recebe `env=` com exatamente essas quatro variáveis, então nada do ambiente do
  servidor passa. `TRAYCER_AGENT_ID` é o agente base do Task (o pai dos filhos).
- O executável e o ambiente chegam por injeção; os testes usam um CLI falso.
- O adaptador nunca espera por `responseId`. `send` não pede resposta, e o fim do turno sai de
  `agent list` (campo `active`). Quem decide o sucesso da fase é o motor, pela saída em disco.
- Valores de opção vão na forma `--opção=valor`: uma mensagem que começa com `---` (frontmatter
  de prompt) seria lida como opção na forma `--message valor`.
- `traycer monitor` não funciona em ambiente limpo e não é usado.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import time
from collections.abc import Callable, Mapping, Sequence
from dataclasses import dataclass
from typing import Any

ENV_KEYS = ("HOME", "PATH", "TRAYCER_EPIC_ID", "TRAYCER_AGENT_ID")

_ASSISTANT_RE = re.compile(r"<assistant_response>\n(.*?)\n?</assistant_response>", re.DOTALL)
_ROW_HEADER_RE = re.compile(r"^\[assistant row \|[^\n]*\]\n?")


class CliError(Exception):
    """O CLI falhou (código de saída, `status: error`, timeout ou saída ilegível)."""

    def __init__(self, message: str, code: str = "E_CLI") -> None:
        self.code = code
        super().__init__(message)


class AgentNotFound(CliError):
    """O agente não está em `agent list` (nunca existiu ou o Task não o enxerga)."""


class TurnTimeout(CliError):
    """O agente continuou ativo depois do tempo limite."""

    def __init__(self, message: str) -> None:
        super().__init__(message, code="E_TURN_TIMEOUT")


@dataclass(frozen=True)
class AgentInfo:
    agent_id: str
    active: bool
    archived: bool
    harness: str | None
    model: str | None
    effort: str | None
    profile: str | None


@dataclass(frozen=True)
class Child:
    agent_id: str
    requested_model: str
    requested_effort: str
    applied_model: str | None
    applied_effort: str | None
    warnings: tuple[str, ...] = ()

    @property
    def diverged(self) -> bool:
        """O Traycer aplicou outro modelo ou esforço (ex.: pedi gemini-4-argon, veio gemini-3.8-flash)."""
        return self.applied_model != self.requested_model or self.applied_effort != self.requested_effort


def _used_percents(node: Any) -> list[float]:
    """Todos os `usedPercent` do bloco de limites: janelas de 5h e 7d (claude) ou grupos (antigravity)."""
    found: list[float] = []
    if isinstance(node, dict):
        for key, value in node.items():
            if key == "usedPercent" and isinstance(value, (int, float)) and not isinstance(value, bool):
                found.append(float(value))
            else:
                found.extend(_used_percents(value))
    elif isinstance(node, list):
        for item in node:
            found.extend(_used_percents(item))
    return found


@dataclass(frozen=True)
class RateLimits:
    five_hour: float | None
    seven_day: float | None
    used_percent: float | None  # maior janela (5h, 7 dias ou grupos); None se o provedor não informa
    updated_at: int | None  # `usageUpdatedAt` do CLI (ms): a leitura pode vir de cache


class Adapter:
    def __init__(
        self,
        *,
        executable: str | Sequence[str] = "traycer",
        env: Mapping[str, str],
        command_timeout: float = 60.0,
        sleep: Callable[[float], None] = time.sleep,
        clock: Callable[[], float] = time.monotonic,
    ) -> None:
        if set(env) != set(ENV_KEYS) or not all(isinstance(env[k], str) and env[k] for k in ENV_KEYS):
            raise ValueError(f"env must have exactly these non-empty variables: {', '.join(ENV_KEYS)}")
        self._executable = [executable] if isinstance(executable, str) else list(executable)
        self._env = {key: env[key] for key in ENV_KEYS}
        self._command_timeout = command_timeout
        self._sleep = sleep
        self._clock = clock

    @classmethod
    def from_environ(
        cls, environ: Mapping[str, str] | None = None, *, executable: str | Sequence[str] = "traycer", **kwargs: Any
    ) -> Adapter:
        """Copia só as quatro variáveis de `environ` (padrão: `os.environ`)."""
        source = os.environ if environ is None else environ
        missing = [k for k in ENV_KEYS if not source.get(k)]
        if missing:
            raise ValueError(f"missing environment variables: {', '.join(missing)}")
        return cls(executable=executable, env={k: source[k] for k in ENV_KEYS}, **kwargs)

    # --- chamada ao CLI -------------------------------------------------------------------

    def _call(self, *args: str) -> dict[str, Any]:
        argv = [*self._executable, *args, "--json"]
        try:
            proc = subprocess.run(  # noqa: S603 (argv fixo, sem shell)
                argv,
                env=self._env,
                stdin=subprocess.DEVNULL,
                capture_output=True,
                text=True,
                timeout=self._command_timeout,
                check=False,
            )
        except subprocess.TimeoutExpired as exc:
            raise CliError(f"traycer {' '.join(args[:2])}: no answer in {self._command_timeout}s", "E_CLI_TIMEOUT") from exc
        except OSError as exc:
            raise CliError(f"cannot run {self._executable[0]}: {exc.strerror or exc}", "E_CLI_MISSING") from exc
        result = self._parse(proc.stdout)
        if result is None:
            detail = (proc.stderr or proc.stdout).strip()[:300]
            raise CliError(f"traycer {' '.join(args[:2])}: exit {proc.returncode} without a result ({detail})")
        if result.get("status") != "ok":
            error = result.get("error") or {}
            code = error.get("code", "E_CLI")
            message = error.get("message", "unknown error")
            exc_type = AgentNotFound if code == "E_AGENT_NOT_FOUND" else CliError
            raise exc_type(message, code)
        if proc.returncode != 0:
            raise CliError(f"traycer {' '.join(args[:2])}: exit {proc.returncode}")
        data = result.get("data")
        return data if isinstance(data, dict) else {}

    @staticmethod
    def _parse(stdout: str) -> dict[str, Any] | None:
        """O CLI emite NDJSON; o evento `result` é o último que importa."""
        for line in reversed(stdout.splitlines()):
            line = line.strip()
            if not line.startswith("{"):
                continue
            try:
                event = json.loads(line)
            except json.JSONDecodeError:
                continue
            if isinstance(event, dict) and event.get("type") == "result":
                return event
        return None

    # --- operações ------------------------------------------------------------------------

    def create_worktree(self, *, workspace: str, branch: str, source_branch: str | None = None) -> str:
        """`traycer worktree create`: devolve o caminho do worktree novo para usar como `cwd` do filho."""
        args = ["worktree", "create", f"--workspace={workspace}", f"--branch={branch}"]
        if source_branch:
            args.append(f"--source-branch={source_branch}")
        data = self._call(*args)
        entries = data.get("entries")
        path = data.get("path") or (entries[0].get("path") if isinstance(entries, list) and entries else None)
        if not isinstance(path, str) or not path:
            raise CliError("worktree create: the answer has no path")
        return path

    def create_child(
        self,
        *,
        harness: str,
        model: str,
        effort: str,
        profile: str,
        cwd: str,
        name: str | None = None,
    ) -> Child:
        args = [
            "agent",
            "create",
            "--surface=gui",
            f"--harness={harness}",
            f"--model={model}",
            f"--reasoning-effort={effort}",
            f"--profile={profile}",
            f"--cwd={cwd}",
        ]
        if name:
            args.append(f"--name={name}")
        data = self._call(*args)
        agent_id = data.get("agentId")
        if not isinstance(agent_id, str) or not agent_id:
            raise CliError("agent create: the answer has no agentId")
        warnings = tuple(str(w) for w in data.get("warnings") or ())
        info = self.poll_status(agent_id)  # runConfig aplicado: pode diferir do pedido
        return Child(agent_id, model, effort, info.model, info.effort, warnings)

    def send(self, agent_id: str, message: str) -> None:
        """Entrega o prompt sem pedir resposta: nenhum `responseId` nasce."""
        self._call("agent", "send", f"--to={agent_id}", f"--message={message}")

    def list_agents(self) -> list[AgentInfo]:
        data = self._call("agent", "list")
        rows = data.get("agents")
        if not isinstance(rows, list):
            raise CliError("agent list: the answer has no agents")
        infos = []
        for row in rows:
            if not isinstance(row, dict) or not isinstance(row.get("id"), str) or not row["id"]:
                raise CliError(f"agent list: malformed agent row: {str(row)[:120]}")
            config = row.get("runConfig")
            config = config if isinstance(config, dict) else {}
            model = config.get("model")
            model = model.get("slug") if isinstance(model, dict) else model
            effort = config.get("reasoningEffort")
            infos.append(
                AgentInfo(
                    agent_id=row["id"],
                    active=bool(row.get("active")),
                    archived=bool(row.get("archived")),
                    harness=row.get("harnessId"),
                    model=model if isinstance(model, str) else None,
                    effort=effort if isinstance(effort, str) else None,
                    profile=row.get("profile"),
                )
            )
        return infos

    def poll_status(self, agent_id: str) -> AgentInfo:
        for info in self.list_agents():
            if info.agent_id == agent_id:
                return info
        raise AgentNotFound(f"agent {agent_id} is not in this Task", "E_AGENT_NOT_FOUND")

    def wait_turn_end(
        self,
        agent_id: str,
        *,
        timeout: float,
        interval: float,
        settle: int = 2,
        replies_before: int | None = None,
    ) -> None:
        """Espera o agente ficar inativo em `settle` polls seguidos. Levanta `TurnTimeout` depois de `timeout` s.

        Logo após o `send` o agente pode aparecer inativo até o host marcá-lo ativo. Com
        `replies_before` (valor de `reply_count` antes do `send`), o turno só acaba quando também
        há uma resposta nova no transcript, o que fecha essa corrida."""
        deadline = self._clock() + timeout
        idle = 0
        while True:
            info = self.poll_status(agent_id)
            idle = idle + 1 if (not info.active or info.archived) else 0
            if idle >= settle and (replies_before is None or self.reply_count(agent_id) > replies_before):
                return
            if self._clock() >= deadline:
                raise TurnTimeout(f"agent {agent_id} still active after {timeout:g}s")
            self._sleep(interval)

    def _assistant_blocks(self, agent_id: str) -> list[str]:
        transcript = self._call("agent", "transcript", f"--agent-id={agent_id}").get("transcript")
        if not isinstance(transcript, str):
            raise CliError("agent transcript: the answer has no transcript")
        return _ASSISTANT_RE.findall(transcript)

    def reply_count(self, agent_id: str) -> int:
        """Quantas respostas do assistente o transcript tem: cresce a cada turno concluído."""
        return len(self._assistant_blocks(agent_id))

    def last_message(self, agent_id: str) -> str:
        """Texto da última resposta do agente, sem o cabeçalho `[assistant row | ...]`. Vazio se não houver."""
        blocks = self._assistant_blocks(agent_id)
        if not blocks:
            return ""
        return _ROW_HEADER_RE.sub("", blocks[-1]).strip()

    def stop(self, agent_id: str) -> None:
        self._call("agent", "stop", f"--agent-id={agent_id}")

    def archive(self, agent_id: str) -> None:
        self._call("agent", "archive", f"--agent-id={agent_id}")

    def rate_limits(self, harness: str, profile: str) -> RateLimits:
        data = self._call("agent", "profile-rate-limits", harness, f"--profile={profile}")
        limits = data.get("rateLimits")
        updated = data.get("usageUpdatedAt")
        updated_at = updated if isinstance(updated, int) else None
        if not isinstance(limits, dict) or limits.get("available") is False:
            return RateLimits(None, None, None, updated_at)

        def window(name: str) -> float | None:
            percents = _used_percents(limits.get(name))
            return percents[0] if percents else None

        percents = _used_percents(limits)
        return RateLimits(window("fiveHour"), window("sevenDay"), max(percents) if percents else None, updated_at)

    def rate_limit_used_percent(self, harness: str, profile: str) -> float | None:
        """Maior `usedPercent` entre as janelas do perfil (5h e 7 dias). None se o provedor não informa."""
        return self.rate_limits(harness, profile).used_percent
