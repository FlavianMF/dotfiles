// The cockpit mod's terminal link handler (Herdr 0.1.17): a Cmd-click on a web link in a terminal opens in the person's
// browser, Herdr's own way, unless `links.open` is "side": then in the side browser beside that terminal.
// ADAPTADO para dotfiles: Ctrl+click em arquivos Markdown (.md/.markdown/.mdx) abre no painel 'main' via cockpit code.

import { appHome, exec } from "herdr";
import { installOf, readConfig, optionOf } from "./config.js";
import { splitCodePane } from "./open-code.js";

const MD_FILE = /\.(md|markdown|mdx)$/i;
const LINE_SUFFIX = /(?::(\d+)(?::\d+)?|#L(\d+)(?:-L?\d+)?)\s*$/i;
const RESOLVE_SH = [
  'p="$1"; cwd="$2"',
  'case "$p" in',
  '  "~"|"~/"*) p="$HOME${p#\\~}" ;;',
  '  /*) ;;',
  '  *) [ -n "$cwd" ] && p="$cwd/$p" || exit 1 ;;',
  "esac",
  '[ -f "$p" ] || exit 1',
  'if command -v realpath >/dev/null 2>&1; then realpath -e "$p"; else readlink -f "$p" 2>/dev/null || printf "%s\\n" "$p"; fi',
].join("\n");

/** Extracts raw path and optional 1-based line number from a clicked file link. */
function parseFileTarget(link) {
  let raw = String(link?.raw ?? "").trim();
  const suffix = LINE_SUFFIX.exec(raw);
  const parsedLine = suffix ? Number(suffix[1] ?? suffix[2]) : null;
  if (suffix) raw = raw.slice(0, suffix.index);
  if (/^file:\/\//i.test(raw)) {
    raw = raw.replace(/^file:\/\/(?:localhost)?/i, "");
    try {
      raw = decodeURIComponent(raw);
    } catch {}
  }
  return { raw, line: link?.line ?? parsedLine ?? null };
}

/** Resolves a clicked Markdown path on `source.machine` (or locally) and returns `{ file, machine, line }` or null. */
async function resolveMarkdownLink(click) {
  const { raw, line } = parseFileTarget(click.link);
  const machine = click.source?.machine ?? null;
  if (!machine && click.link?.path) {
    if (!MD_FILE.test(click.link.path)) return null;
    return { file: click.link.path, machine: null, line };
  }
  if (!raw || !MD_FILE.test(raw)) return null;
  if (machine) {
    const r = await exec("sh", ["-c", RESOLVE_SH, "resolve", raw, click.source?.cwd ?? ""], { on: machine }).catch(() => null);
    const resolved = r?.code === 0 ? r.stdout.trim() : "";
    if (!resolved || !MD_FILE.test(resolved)) return null;
    return { file: resolved, machine, line };
  }
  return null;
}

/** What a click asks of cockpit: "side" for the side browser beside its terminal, else null to leave it to Herdr. */
export function routeOf(click, config, install) {
  if (click?.link?.kind !== "url" || !/^https?:\/\//i.test(click.link.url ?? "")) return null;
  if (!install?.bin || install.machine || click.source?.machine || !click.source?.terminal) return null;
  return optionOf(config, "links.open", "browser") === "side" ? "side" : null;
}

/** `cockpit browse <url>` for the clicked terminal, on the install's HOME and driving this window. */
export function browseArgs(click, install, home = appHome()) {
  const vars = Object.entries(install.env ?? {}).map(([k, v]) => `${k}=${v}`);
  return [`HOME=${install.home}`, `HERDR_APP_HOME=${home}`, "COCKPIT_FRONTEND=app", `HC_TERMINAL_ID=${click.source.terminal}`, ...vars, install.bin, "browse", click.link.url];
}

export async function handleLink(click) {
  if (click?.link?.kind === "file") {
    const target = await resolveMarkdownLink(click);
    if (!target) return "pass";
    await splitCodePane({
      file: target.file,
      terminal: click.source?.terminal,
      pane: click.source?.pane,
      line: target.line,
      machine: target.machine,
      mdMode: "preview",
    });
    return "handled";
  }
  const install = await installOf();
  if (routeOf(click, await readConfig(install), install) !== "side") return "pass";
  const r = await exec("env", browseArgs(click, install), { timeout: 25_000 }).catch(() => null);
  return r?.code === 0 ? "handled" : "pass";
}
