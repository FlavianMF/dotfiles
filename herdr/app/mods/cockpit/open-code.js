// ADAPTADO para dotfiles: helper sem imports de UI para abrir arquivo no painel 'main' a partir de code.js e link.js.
import { exec, run, panes, focused, home, appHome, shared, setShared, window as win } from "herdr";

export const SHOWN = "cockpit.code.panes";

/** Finds the pane beside which a new viewer split should open. */
export function findBesidePane({ terminal, pane, machine } = {}) {
  const all = panes();
  const here = focused()?.tab ?? null;
  const matchTerm = (p) =>
    terminal &&
    (p.terminal === terminal || (machine && p.terminal === `${machine}/${terminal}`) || p.terminal?.endsWith(`/${terminal}`));
  return {
    all,
    here,
    beside:
      (pane && all.find((p) => p.pane === pane)) ??
      (terminal && all.find(matchTerm)) ??
      all.find((p) => p.focused && p.terminal) ??
      all.find((p) => p.tab === here && p.terminal) ??
      all.find((p) => p.tab === here),
  };
}

/** Opens `file` in a right split of the active tab (`main` area), replacing any existing cockpit code pane there. */
export async function splitCodePane({ file, terminal, line, pane, machine, mdMode } = {}) {
  const { all, here, beside } = findBesidePane({ terminal, pane, machine });
  const tab = beside?.tab ?? here;
  const open = tab ? (shared(SHOWN) ?? {})[tab] : null;
  if (open && all.some((p) => p.pane === open)) run("pane.close", { pane: open });
  if (shared("cockpit.view") === "agent") {
    run("layout.select", { stack: "view", child: "main" });
    setShared("cockpit.view", "main");
  }
  const props = {
    app: "code",
    file,
    line: line ?? undefined,
    terminal: beside?.terminal ?? terminal,
    tab,
    ...(machine !== undefined ? { machine } : {}),
    ...(mdMode ? { mdMode } : {}),
  };
  const args = { direction: "right", ...(beside ? { pane: beside.pane } : {}), mod: "cockpit", props };
  const r = await (
    win()?.platform === "windows"
      ? exec("herdr-app.exe", ["do", "pane.split", JSON.stringify(args)])
      : exec("env", [`HERDR_APP_HOME=${appHome()}`, `${home()}/.local/bin/herdr-app`, "do", "pane.split", JSON.stringify(args)])
  ).catch(() => null);
  const made = r?.code === 0 ? JSON.parse(r.stdout || "{}").pane : null;
  if (!made) run("pane.split", args);
  else if (tab) setShared(SHOWN, { ...(shared(SHOWN) ?? {}), [tab]: made });
}
