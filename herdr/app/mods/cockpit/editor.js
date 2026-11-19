// Open in editor: a folder in the person's editor, on this machine or over SSH for a remote space (VS Code's and
// Cursor's Remote-SSH). The editor is the cockpit config's `editor` (code, cursor, zed, ...), else VS Code.

import { exec, readTextFile, hc, window as win } from "herdr";
import * as hub from "./hub.js";

const APPS = { code: "Visual Studio Code", cursor: "Cursor", zed: "Zed", windsurf: "Windsurf", subl: "Sublime Text" };

/**
 * The config's `editor`, one command: from the resolved copy in the cache (plain JSON), else the file as written when it
 * reads as plain JSON (one with comments has its copy); else VS Code's `code`.
 */
export async function editor() {
  // ADAPTADO para dotfiles: lê config.json na máquina remota (WSL) via `{ on: machine }`.
  const { home, cache, machine } = await hub.install().catch(() => ({}));
  const opt = machine ? { on: machine } : undefined;
  for (const path of [cache && `${cache}/config.json`, home && `${home}/.config/cockpit/config.json`].filter(Boolean)) {
    try {
      const name = JSON.parse((await readTextFile(path, opt)) ?? "null")?.editor;
      if (typeof name === "string" && name.trim() && !name.trim().startsWith("-")) return name.trim();
    } catch {}
  }
  return "code";
}

/** Runs an editor CLI, retrying with `cmd /c` on Windows where `.cmd` wrappers (e.g. `code.cmd`) fail bare exec. */
async function execEditor(name, args) {
  const r = await exec(name, args).catch(() => null);
  if (r?.code === 0 || win()?.platform !== "windows") return r;
  return exec("cmd", ["/c", name, ...args]).catch(() => null);
}

/** The SSH host of a machine `hc machine ls` knows, else its name. */
async function hostOf(machine) {
  try {
    const r = await hc(["machine", "ls", "--json"]);
    const list = JSON.parse(r.stdout);
    const m = (Array.isArray(list) ? list : list.machines ?? []).find((x) => x.name === machine);
    const target = m?.target ?? m?.host ?? m?.ssh ?? machine;
    return String(target).replace(/^ssh:\/\//, "");
  } catch {
    return machine;
  }
}

/** Opens `folder` in the editor; resolves with what to tell the person when it could not. */
export async function openInEditor(folder, machine = null) {
  if (!folder) return "no folder to open";
  const name = await editor();
  if (machine) {
    const uri = `vscode-remote://ssh-remote+${await hostOf(machine)}${folder}`;
    const r = await execEditor(name, ["--folder-uri", uri]);
    return r?.code === 0 ? null : `${name} could not open ${machine}:${folder}`;
  }
  const r = await execEditor(name, [folder]);
  if (r?.code === 0) return null;
  const app = APPS[name] ?? name;
  // An editor whose command isn't on the PATH still opens by its app name on macOS.
  const opened = win()?.platform === "macos" ? await exec("open", ["-a", app, folder]).catch(() => null) : null;
  return opened?.code === 0 ? null : `${app} is not installed (set "editor" in the cockpit config)`;
}

/** Opens a file (with optional 1-based line) in the editor, using Remote-SSH when `machine` is set. */
export async function openFileInEditor(file, { line = null, machine = null } = {}) {
  if (!file) return "no file to open";
  const name = await editor();
  const target = `${file}${line ? `:${line}` : ""}`;
  const args = machine ? ["--remote", `ssh-remote+${await hostOf(machine)}`, "-g", target] : ["-g", target];
  const r = await execEditor(name, args);
  return r?.code === 0 ? null : `${name} could not open ${machine ? `${machine}:` : ""}${target}`;
}

/** The editor's name, for labels: "VS Code", "Cursor", ... */
export async function editorLabel() {
  const name = await editor();
  return name === "code" ? "VS Code" : (APPS[name] ?? name);
}
