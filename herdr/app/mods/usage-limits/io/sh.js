import { appHome, exec } from "herdr";
import { MOD } from "../lib/mod.js";

// ADAPTADO para agentes no WSL: o app roda no Windows, mas claude, codex e hc vivem no WSL.
// Tudo passa por wsl.exe + wsl-run.sh (carrega o PATH de login).
// Origem: nozikov/herdr-usage-limits@ca22615. Mudou io/sh.js, io/helpers.js e ui/bar.js.
// Também: ui/bar.js alinha a barra à esquerda (justify_start, painel em bottom_left).
// "C:\\Users\\User" -> "/mnt/c/Users/User"
const wslPath = (p) => p.replace(/^([A-Za-z]):[\\/]/, (_m, d) => `/mnt/${d.toLowerCase()}/`).replace(/\\/g, "/");

export const modRoot = () => `${wslPath(appHome())}/mods/${MOD}`;

// Roda `cmd args...` no WSL.
export const runWsl = (cmd, args, opts) => {
  const argv = ["-e", "bash", `${modRoot()}/wsl-run.sh`, cmd, ...args];
  return opts ? exec("wsl.exe", argv, opts) : exec("wsl.exe", argv);
};

// Roda um script sh do mod no WSL.
export const runSh = (args, opts) => runWsl("sh", args, opts);
