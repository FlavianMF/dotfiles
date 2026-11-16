import { shared } from "herdr";
import { modRoot, runSh, runWsl } from "./sh.js";
import { KEY_BINDINGS, codexBinding, sessionReadResult } from "../lib/session-binding.js";

const SPEND_HELPER_DEADLINE_MS = 15 * 1000;
const SESSION_HELPER_DEADLINE_MS = 15 * 1000;
const SESSION_MODE_BY_APP = { "claude-code": "claude", codex: "codex", opencode: "opencode", pi: "pi" };
const NO_SESSION = { session: null, choices: null, manual: false };

const helperPath = (helper) => `${modRoot()}/${helper}`;
const folderName = (cwd) => (cwd ?? "").split("/").pop();

export function runProviderHelper(p) {
  const args = [helperPath(p.helper)];
  return p.kind === "spend" ? runSh(args, { timeout: SPEND_HELPER_DEADLINE_MS }) : runSh(args);
}

function bindingFor(app, terminal, pid) {
  if (app !== "codex") return null;
  return codexBinding(shared(KEY_BINDINGS), terminal, pid, shared("patchbay.chat.bindings"), shared("patchbay.sessions")?.boot);
}

export async function readTerminalSession(terminal) {
  try {
    // "wsl/t12" -> "t12": o hc do WSL não prefixa a máquina. Terminal do Windows não tem sessão.
    if (!terminal.startsWith("wsl/")) return NO_SESSION;
    const info = JSON.parse((await runWsl("hc", ["get", terminal.slice(4)])).stdout);
    const app = SESSION_MODE_BY_APP[info.status?.app];
    const pid = info.foreground?.pid;
    if (!app || !pid) return NO_SESSION;
    const binding = bindingFor(app, terminal, pid);
    const args = [helperPath("helpers/session.sh"), app, String(pid)];
    if (binding) args.push(binding.id, binding.identity);
    const result = await runSh(args, { timeout: SESSION_HELPER_DEADLINE_MS });
    return sessionReadResult(result, app, binding, pid, folderName(info.cwd));
  } catch {
    return NO_SESSION;
  }
}
