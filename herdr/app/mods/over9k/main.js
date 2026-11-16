// Over9k: the sidebar's spaces, terminals and agents in one list (help and
// options: over9k-options). Workspace spaces: stable colored avatars, worktrees under their checkout,
// grouped by computer (This computer always has its heading). After a space's name, the repo
// its first terminal is in now, only where unusual: branch, ahead/behind. Agent state lives in the agents list, not here. Click to
// switch, right-click for its menu, drag to reorder.
// Projects are git repos in the projects folder (Options › Folders) and folders with a CLAUDE.md,
// AGENTS.md or .claude folder, plus ones pinned from the right-click menu, less hidden ones; with no open space they stay listed in a folded "Not open" section.
// Every terminal and agent lists under the project or space its live folder is
// in (any other folder gets a row of its own; ~ itself is the home space), so
// there's no separate Agents section. Rows show the GitHub link, uncommitted
// files, unpushed/unpulled commits and open PRs, each one clickable.

import { View, div, image, svg } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { spaces, machines, panes, agents, terminals, setAgentOrder, run, openOverlay, exec, hc, home, appHome, readTextFile, theme, shared, setShared, watchFolder, window, layout, notify, focused, nextCommand } from "herdr";
import { plan, plural } from "./close-plan.js";
import { codexTitle, agentTask, isCodex, sentenceCase } from "./agent-name.js";

// Python 3 runs as "python3", else "python" (as on Windows): found once.
let PY = null;
const python = (args) => (PY ??= exec("python3", ["-c", "1"]).then((r) => (r?.code === 0 ? "python3" : "python"), () => "python"))
  .then((p) => exec(p, args));

// Closing asks first (over9k-close says how many terminals and agents end)
// when a whole space would go or an agent that's still working would end, else
// happens at once, as Herdr does.
function closeAsk(picked) {
  const p = plan(picked);
  if (!p.spaces && !p.working) for (const c of p.commands) run(c.name, c.args);
  else openOverlay({ mod: "over9k-close", kind: "dialog", width: 380, height: 150, props: picked });
}

// Whether a mod shows anywhere in this layout.
function hasMod(node, mod) {
  return Boolean(node) && (node.content?.mod === mod || (node.children ?? []).some((c) => hasMod(c, mod)));
}
function find(node, id) {
  if (node?.id === id) return node;
  for (const child of node?.children ?? []) {
    const found = find(child, id);
    if (found) return found;
  }
  return null;
}

// The sidebar's rail goes by its width, not a flag: dragging its edge narrows it too.
// Every call into Herdr waits for its main thread (a frame when terminals are
// busy), so a render reads each thing once: the home folder is kept here, and
// render keeps spaces, panes, agents and shared colors in this.frame.

// A worktree row's branch icon lines up with the terminal icons; its own
// terminals go in by the icon and gap, under its name.
const TREE = 22;

let HOME = null;
const homeDir = () => (HOME ??= home());
// A path as it's shown on hover: home as ~.
const tilde = (path) => { const p = (path ?? "").replace(/\/+$/, ""); return p === homeDir() ? "~" : p.startsWith(homeDir() + "/") ? `~${p.slice(homeDir().length)}` : p; };
const narrow = () => (find(layout(), "sidebar")?.size?.px ?? Infinity) < 160;

// Where a space is: the folder it was made for, not where its terminals went
// (they list under the project they're in now, see `assign`), so its row keeps
// its project's git. `ps` is unused, kept so callers match the shipped mod.
function place(s, _ps) {
  return s.folder;
}
// A space's name in the list: its own when someone named it, else its folder's
// (Herdr would call it after wherever its first terminal went).
const title = (s) => (s.named || s.machine ? s.name : !s.folder || s.folder.replace(/\/+$/, "") === homeDir() ? "~" : base(s.folder));
const rowHeight = ({ tree }) => (tree ? 28 : 30);
const where = (s, ps) => JSON.stringify([s.machine ?? null, place(s, ps)]);
const base = (path) => path.replace(/\/+$/, "").split("/").pop();
// Changes made outside Herdr (an editor's save, a commit in another app): looked
// for this often, in repos the list shows, while the window is in front.
const FALLBACK = 60000;
// How often each GitHub repo is fetched (so ↓ is current) and its pull requests
// counted. Git never asks for a password here: it fails instead.
const REMOTE = 300000;
const QUIET = ["GIT_TERMINAL_PROMPT=0", "GIT_SSH_COMMAND=ssh -o BatchMode=yes"];
// Folders in a code folder that are never offered as projects (by name; unpin
// or hide one from its right-click menu instead), and how often new ones are looked for.
const SKIP = new Set();
const RESCAN = 30000;
// Project folders: a git repo in a code folder (the arguments), or anywhere up
// to two levels under home a folder set up for an agent (CLAUDE.md,
// CLAUDE.local.md, AGENTS.md, a .claude folder). Git alone elsewhere is usually
// installed software. Hidden folders under home and node_modules aren't looked in.
const MARKED = `{ for d in "$@"; do case "$d" in "~") d=$HOME ;; "~/"*) d="$HOME/\${d#"~/"}" ;; esac
    find "$d" -mindepth 2 -maxdepth 2 -name .git 2>/dev/null; done
  find "$HOME" -maxdepth 3 \\( -path "$HOME/.*" -o -name node_modules \\) -prune -o \\
    \\( -name CLAUDE.md -o -name CLAUDE.local.md -o -name AGENTS.md -o \\( -name .claude -type d \\) \\) -print 2>/dev/null
} | sed 's#/[^/]*$##' | sort -u`;
// A computer's two places (set in over9k-options): Chats, where conversations
// about no project start (home unless set), and Projects, where every git repo
// is a project and hand-offs (handoff.sh) make new ones. Unset, Projects is the
// folder that computer's CLAUDE.md/AGENTS.md name on a line about projects (a
// `~/…` in backticks; over9k's own rule left out), else home. Prints it as typed.
const PROJECTS_FROM_RULES = `for f in "$HOME/.claude/CLAUDE.md" "$HOME/.codex/AGENTS.md" "$HOME/.pi/agent/AGENTS.md"; do
  [ -f "$f" ] && sed '/<!-- over9k:handoff -->/,/<!-- \\/over9k:handoff -->/d' "$f"
done | grep -i 'project' | grep -oE '\`~/[^\` ]+\`' | tr -d '\`' | sed 's#/*$##' | while read -r d; do
  [ -d "$HOME/\${d#"~/"}" ] && { printf '%s' "$d"; break; }
done`;

// Widths of the right-hand columns: new tab, fold chevron (px).
const FOLD = 16;
const ADD = 22;
// Shift, Cmd/Meta or Ctrl + click picks rows; right-click a picked one to close or unpin them.
const multi = (e) => Boolean(e?.modifiers && (e.modifiers.shift || e.modifiers.platform || e.modifiers.control));
const inside = (cwd, dir) => cwd === dir || cwd?.startsWith(dir + "/");

const isPi = (a) => a.app === "pi" || a.program?.key === "pi";
// Possibly Antigravity: agy-info.py, which only answers for terminals agy runs in,
// is asked about any agent that isn't Claude Code, Codex or Pi.
const isAgy = (a) => !isClaude(a) && !isPi(a) && !/codex/i.test(`${a.app ?? ""} ${a.program?.key ?? ""}`);
const isClaude = (a) => a.app === "claude-code" || a.program?.key === "claude";
// Pi's footer: "↑5.5k ↓72 8.6%/66k (auto)  …  qwen3.8-27b • medium" (tokens in and
// out once it has replied, then context used, model, thinking).
function piFooter(text) {
  for (const line of (text ?? "").split("\n").reverse()) {
    const m = /(?:^|\s)(\d+(?:\.\d+)?)%\/\S+.*?\s(\S+)(?: \u2022 (\S+))?\s*$/.exec(line);
    if (m) return { context: Number(m[1]), model: m[2], effort: m[3] ?? null };
  }
  return null;
}

// Running remote connections (ssh, mosh, tailscale ssh, et) with the Herdr
// terminal they were started in: one line each, terminal, the folder it runs
// in, then the command's words, tab-separated (Linux's /proc).
const SSH_PROCS = `for p in $(pgrep -x 'ssh|mosh|mosh-client|tailscale|et'); do
  t=$(tr '\\0' '\\n' < /proc/$p/environ 2>/dev/null | sed -n 's/^HC_TERMINAL_ID=//p')
  [ -n "$t" ] && printf '%s\\t%s\\t%s\\n' "$t" "$(readlink /proc/$p/cwd)" "$(tr '\\0' '\\t' < /proc/$p/cmdline)"
done`;
// The destination in a connection's words, and how: the first word that isn't
// an option (or an option's value); tailscale only counts as "tailscale ssh".
function sshDestination(args) {
  const prog = (args[0] ?? "").split("/").pop();
  const how = prog === "tailscale" ? (args[1] === "ssh" ? "tailscale" : null) : prog.startsWith("mosh") ? "mosh" : prog;
  if (!how) return null;
  const takes = new Set("BbcDEeFIiJLlmOoPpQRSWw".split(""));
  for (let i = how === "tailscale" ? 2 : 1; i < args.length; i++) {
    const a = args[i];
    if (!a) continue;
    if (a.startsWith("-")) { if (how === "ssh" && a.length === 2 && takes.has(a[1])) i++; continue; }
    return { dest: a, how };
  }
  return null;
}

// 42000 tokens is "42k"; 1500000 is "1.5M".
function tokensK(n) {
  return n >= 1e6 ? `${(n / 1e6).toFixed(1).replace(/\.0$/, "")}M` : n >= 1000 ? `${Math.round(n / 1000)}k` : String(n);
}
// A duration in seconds as "40s", "3m", "1h 5m".
function span(sec) {
  sec = Math.max(0, Math.round(sec));
  return sec < 60 ? `${sec}s` : sec < 3600 ? `${Math.round(sec / 60)}m` : sec < 86400 ? `${Math.floor(sec / 3600)}h ${Math.round((sec % 3600) / 60)}m`
    : `${Math.floor(sec / 86400)}d ${Math.round((sec % 86400) / 3600)}h`;
}
// Times written out in words ("every 2 hours at :13") in short units: s, m, h, d,
// w, mo, y ("every 2h at :13"); "every hour" is "every 1h".
const UNITS = [["seconds?|secs?", "s"], ["minutes?|mins?", "m"], ["hours?|hrs?", "h"], ["days?", "d"], ["weeks?", "w"], ["months?", "mo"], ["years?", "y"]];
function short(text) {
  return UNITS.reduce((out, [words, u]) => out
    .replace(new RegExp(`(\\d+)\\s*(?:${words})\\b`, "gi"), `$1${u}`)
    .replace(new RegExp(`\\bevery\\s+(?:${words})\\b`, "gi"), (m) => `${m.split(/\s+/)[0]} 1${u}`), text);
}

// A terminal's program is an agent (Herdr names any program there, "sleep" too).
function isAgentProgram(name) {
  return /^(claude|codex|pi|opencode|gemini|aider|amp|cursor)/.test(name ?? "");
}

// A program's icon (an agent's: Claude, Codex, Pi), else a shell's.
function progIcon(prog, t, size) {
  return prog?.icon ? (prog.tint ? svg(prog.icon).size(size).flex_none().text_color(t.foreground) : image(prog.icon).w(size).h(size).flex_none())
    : svg("icons/shell.svg").size(size).flex_none().text_color(t.foreground);
}

// An effort as rows show it: "medium" is "med".
const effortName = (e) => (e === "medium" ? "med" : e || null);
// A Claude model id as people say it: "claude-haiku-5-5" is "Haiku 5.5".
function modelName(id) {
  const m = /^claude-([a-z]+)-(\d+)-(\d+)/.exec(id ?? "");
  return m ? `${m[1][0].toUpperCase()}${m[1].slice(1)} ${m[2]}.${m[3]}` : id ?? "";
}


// Each link (something working in another space, or on another computer over
// ssh) gets a colour of its own, the same at both ends (linkColor, linkChip):
// the avatars' (MARK) first, blue leading, then six more at the same strength.
const LINK_COLORS = ["#5b8def", "#e3814f", "#3fae6a", "#d9649a", "#8b7cf6", "#22a99a",
  "#d4a72c", "#e05a5a", "#3ba7d9", "#8cb83a", "#c26bd6", "#b08a5a"];
// `icon`: BOT for an agent run in a terminal of its own (Herdr's: Codex, Pi,
// Claude), SUB (a smaller, round robot) for a Claude Code subagent, CPU for a
// process (a server, a build).
const BOT = "mods/over9k/bot.svg", SUB = "mods/over9k/subagent.svg", CPU = "mods/over9k/cpu.svg";
// A Claude Code session's scheduled prompt (CronCreate, /loop).
const CLOCK = "mods/over9k/clock.svg";
// A chip linking what an agent started with the space it works in: "out" on its
// row under the agent (its icon, then an arrow), "in" on its row in that space
// (an arrow, then its icon). Hovering either row lights up the other
// (view.hoverLink, set by the row: lit). `to` (an ssh's computer): the server
// icon its heading has after the arrow; hovering lights its row under there.
function linkChip(t, id, { dir, icon, color, to = null }) {
  return h_flex().id(id).flex_none().h(16).px(4).gap(3).items_center().rounded(4).bg(color + "26").text_size(10.5).text_color(color)
    .when(dir === "in", (el) => el.child(div().flex_none().child("\u2192")))
    .child(svg(icon).size(icon === SUB ? 13 : 10).flex_none()) // the round subagent robot is drawn smaller
    .when(dir === "out", (el) => el.child(div().flex_none().child("\u2192")))
    .when(Boolean(to), (el) => el.child(svg("mods/workspace-chrome/server.svg").size(10).flex_none()));
}

// A row lit up while its other end is hovered (a row with a link chip there).
const lit = (el, link) => (link ? el.bg(link.color + "26") : el);

// The filter at the top of the list (filterBar): All, or Agents (every agent,
// no plain terminals), with what an empty list says. Agents lists them by state
// (SECTIONS, as Herdr's own Priority view), one section under another, every
// computer's together, each naming its space (and computer); or by space, as the
// full list without the rest.
const FILTERS = [
  { id: "agents", label: "Agents", color: null, has: () => true, empty: "No agents running." },
];
const SECTIONS = [
  { status: "blocked", label: "Needs you" },
  { status: "done", label: "Done" },
  { status: "working", label: "Working" },
  { status: "idle", label: "Idle" },
];

// The panel stack's block for a sub-row clicked open (showInPanel).
const PANEL_VIEW = "sub-view";

// Details in a row, close: "Opus 5.5·high·35%" (a dot between each, a pixel of room around it).
const dotted = (parts) => parts.flatMap((el, n) => (n ? [div().px(1).child("\u00b7"), el] : [el]));

// Agent rows' layout and what they show, until over9k-options says otherwise
// (shared "sidebar.options"; the same defaults as there).
const OPTIONS = { keepUpToDate: false, layout: "expanded", model: true, effort: true, context: true, since: true, cache: true, github: true, dirty: true, sync: true, prs: true, stars: true, issues: true,
  subModel: true, subEffort: true, subContext: true, subTime: true };

// Model families with a logo of their own, a badge on the agent's icon.
const FAMILY = [{ match: /qwen/i, icon: "mods/over9k/qwen.svg", color: "#6f69f7" }];
function badge(el, fam, bg) {
  if (!fam) return el;
  return div().relative().flex_none().child(el)
    .child(div().absolute().right(-4).bottom(-4).size(10).rounded(5).bg(bg).flex().items_center().justify_center()
      .child(svg(fam.icon).size(8).text_color(fam.color)));
}
// An agent's name: its tab's name when someone named it, else its session's
// title (agent-name.js), else the program. Tab numbers and addresses aren't names.
// Herdr knows some agents only by app (Antigravity: no program): named after it.
const APP_NAMES = { antigravity: "Antigravity" };
const appName = (a) => a?.program?.name || APP_NAMES[a?.app] || null;
function agentName(a, tab, cwd) {
  if (tab && tab.name !== a.program?.name && !/^(\d+|t[0-9a-z]+)$/.test(tab.name)) return tab.name;
  return agentTask(a, cwd) || appName(a) || a.address;
}

// What a stored color name looks like on an avatar (the same in every mod
// that draws space avatars): one strong color per hue, light and dark alike.
const MARK = { ansi6: "#22a99a", ansi3: "#e3814f", ansi4: "#5b8def", ansi5: "#8b7cf6", ansi2: "#3fae6a", ansi1: "#d9649a" };
// Each project's color, from its folder's name, so it's the same open or not
// (and in the picker, which reads space.colors). Home has none.
const project = (s) => (s.folder === homeDir() ? null : base(s.folder));
function hue(name) {
  if (!name) return null;
  let h = 0;
  for (const c of name) h = (h * 31 + c.codePointAt(0)) >>> 0;
  const keys = Object.keys(MARK);
  return keys[h % keys.length];
}

// A space speaks up only when something in it needs you.
export function glyph(status) {
  return status === "blocked" || status === "done" ? "●" : "·";
}

export function tone(t, status) {
  return t[status] ?? t.unknown;
}

export default class Spaces extends View {
  init(_props, cx) {
    this.git = {}; // where() -> { name, branch, ahead, behind, repo, linked }, null: not a repo
    this.checked = {}; // where() -> when it was last looked at
    this.unsure = new Set(); // where()s git couldn't answer for (a machine away)
    this.pending = new Set(); // where()s to look at next
    this.busy = {}; // pane -> an agent working or a program in front of its shell
    this.ready = {}; // machine -> its layout was readable at the last look
    this.at = {}; // space -> its where() at the last look
    this.watching = new Set(); // local repos' git folders
    // Spaces made while this runs wait (at most a moment) for their git, so a
    // worktree appears under its repo instead of jumping there.
    this.shown = new Set(spaces().map((s) => s.id));
    this.born = {};
    this.pressed = null;
    this.over = null;
    this.machines = [];
    this.folded = new Set(JSON.parse(localStorage.getItem("machines.folded") ?? "[]"));
    this.refreshMachines(cx);
    cx.timer.every(15000, cx => this.refreshMachines(cx));
    this.recent = shared("over9k.recentAgents") ?? [];
    cx.timer.every(500, () => this.trackRecent());
    this.projects = []; // shown projects: Claude's folders + pinned - hidden (see render)
    this.auto = []; // ~/Code git repos and folders with a CLAUDE.md, AGENTS.md or .claude
    this.tops = new Map(); // a terminal's folder -> its repo's top (else itself)
    // A shell's last command: the last prompt line ("❯ make") on its screen,
    // kept once seen (a clear wipes the screen). Shared as terminals.last for
    // the tab bar (over9k-tabs).
    this.lastCmd = {};
    cx.timer.every(4000, (cx) => this.readCommands(cx));
    // Spaces whose agents are folded away, and whether the not-open projects show.
    this.agentsFolded = new Set(JSON.parse(localStorage.getItem("agents.folded") ?? "[]"));
    this.closedOpen = localStorage.getItem("projects.closedOpen") === "true";
    this.scanProjects(cx);
    // Other computers' Projects and Chats (over9k-options, per computer) and
    // the projects found there, by machine name; looked for over SSH, less often.
    try { this.remote = JSON.parse(localStorage.getItem("remote.projects") ?? "{}"); } catch { this.remote = {}; }
    // What was found on each, for the menus' Pin/Unpin (over9k-menu, over9k-new-menu).
    const autoOn = Object.fromEntries(Object.entries(this.remote).map(([m, f]) => [m, f.dirs ?? []]));
    if (JSON.stringify(autoOn) !== JSON.stringify(shared("projects.autoOn") ?? {})) setShared("projects.autoOn", autoOn);
    this.closedOpenOn = JSON.parse(localStorage.getItem("projects.closedOpenOn") ?? "{}");
    // Model, effort and context per agent, one file per Herdr terminal here:
    // claude-info.py writes Claude Code's (from its own session and conversation
    // files; no status line), Antigravity's status line its own (optional).
    this.info = {};
    this.infoDir = `${homeDir()}/.cache/over9k/agents`;
    // Pi's info, from its footer on screen; models other than an agent's own
    // (Pi's model list: name and server), and the effort each local server runs at.
    this.piInfo = {};
    this.models = {};
    this.serverEffort = {};
    this.serversUp = {}; // port -> pid of a local model server running
    this.hoverServer = null; // the server chip under the pointer: it reads "Stop …"
    // When each agent last stopped working (ms), seen here for any agent;
    // Claude Code's status line also says when it last replied (lastAt).
    try { this.lastWork = JSON.parse(localStorage.getItem("agents.lastWork") ?? "{}"); } catch { this.lastWork = {}; }
    this.wasWorking = {};
    // Agents whose sub-agents are shown (folded by default).
    try { this.subsOpen = new Set(JSON.parse(localStorage.getItem("agents.subsOpen") ?? "[]")); } catch { this.subsOpen = new Set(); }
    // The filter at the top (filterBar): null shows everything, else only agents
    // in that state (FILTERS) and the spaces they're in.
    try { this.filter = localStorage.getItem("agents.filter") || null; } catch { this.filter = null; }
    if (!FILTERS.some((f) => f.id === this.filter)) this.filter = null; // an older one (Needs you, Working…)
    // Agents, by state (sections) or by space.
    try { this.agentsBy = localStorage.getItem("agents.by") === "space" ? "space" : "state"; } catch { this.agentsBy = "state"; }
    // A close of picked sub-rows already done before a reload isn't done again.
    this.closedAt = shared("over9k.closeSubs")?.at ?? null;
    cx.timer.every(60000, (cx) => cx.notify()); // the "3m"s move on
    this.loadInfo(cx);
    this.prs = {}; // "owner/repo" -> { open, review }: open pull requests, those asking you
    this.write = {}; // "owner/repo" -> you can push there (yours, or your team's)
    this.repoInfo = {}; // "owner/repo" -> { stars, issues }: its stars and open issues on GitHub
    this.me = null; // your GitHub login
    this.armed = null; // ↑ clicked once: { repo, until }; a second click pushes
    this.sel = new Set(); // Ctrl+clicked rows: "s:<space>", "p:<pane>", "d:<project folder>"
    // Keys bound to this mod (keys.json): ctrl-shift-w is "over9k.close-tab".
    cx.spawn(async (cx) => {
      for (;;) {
        const c = await nextCommand();
        if (c === "close-tab") { const f = focused(); if (f?.tab) closeAsk({ tabs: [f.tab] }); }
        // Cmd+Tab for agents (over9k-switcher), most recent first.
        if (c === "switcher") { this.trackRecent(); openOverlay({ mod: "over9k-switcher", kind: "dialog", width: 460, height: Math.min(520, 12 + 35 * Math.max(1, agents().length)) }); }
        if (c === "close-pane") { const f = focused(); if (f?.pane) closeAsk({ panes: [f.pane] }); }
        cx.notify();
      }
    });
    cx.timer.after(5000, (cx) => this.refreshRemote(cx));
    cx.timer.every(REMOTE, (cx) => this.refreshRemote(cx));
    cx.timer.every(5000, (cx) => this.loadInfo(cx));
    // Looked for at start and when the folders change (loadInfo); again every
    // RESCAN only with over9k-options' "Keep sidebar up to date" on.
    cx.timer.every(RESCAN, cx => { if (this.frame?.options.keepUpToDate) this.scanProjects(cx); });
    cx.timer.after(8000, cx => this.scanRemote(cx));
    // `git status` walks the whole tree, on another machine a process there:
    // only when its answer could have changed (see `due`).
    cx.timer.every(250, (cx) => this.checkNew(cx));
  }

  checkNew(cx) {
    const now = Date.now();
    const sp = spaces();
    for (const s of sp) if (!this.shown.has(s.id)) this.born[s.id] ??= now;
    const due = this.due(now, sp, panes());
    if (due.size) this.refreshGit(due, cx);
    this.resolveTops(cx);
    if (sp.some((s) => !this.shown.has(s.id))) cx.notify();
  }

  // Closed projects are only looked at while "Not open" is unfolded (each look
  // is four git processes, and there can be a dozen of them).
  // Places whose git could have changed: new ones (a new space, a cd), where a
  // command or an agent's turn just ended (a checkout, a commit, edits), those on
  // a machine that is back, and repos in view whose fallback is due.
  due(now, sp, ps) {
    // Moved there: what it knew of that place may be old.
    const at = {};
    for (const s of sp) at[s.id] = where(s, ps);
    // Other computers' Not open projects too, while that section is open.
    const remote = Object.entries(this.remote ?? {}).filter(([m]) => this.closedOpenOn?.[m] && this.machines.some((x) => x.name === m && x.state === "connected"))
      .flatMap(([m, f]) => (f.dirs ?? []).filter((d) => !sp.some((s) => s.machine === m && inside((s.folder ?? "").replace(/\/+$/, ""), d))).map((d) => JSON.stringify([m, d])));
    const keys = new Set([...Object.values(at).filter((k) => JSON.parse(k)[1]), ...(this.closedOpen ? this.spaceless(sp) : []).map((d) => JSON.stringify([null, d])), ...(this.loose ?? []).map((d) => JSON.stringify([null, d])), ...remote]);
    const due = new Set([...keys].filter((k) => !(k in this.git)));
    for (const [id, k] of Object.entries(at)) if (this.at[id] && this.at[id] !== k && keys.has(k)) due.add(k);
    this.at = at;
    const spaceOf = {};
    for (const s of sp) for (const t of s.tabs ?? []) spaceOf[t.id] = s;
    const busy = {};
    for (const p of ps) {
      if (!p.terminal || !spaceOf[p.tab]) continue;
      busy[p.pane] = p.status === "working" || !(p.program?.shell || p.program?.agent);
      if (this.busy[p.pane] && !busy[p.pane]) this.sameRepo(at[spaceOf[p.tab].id], keys).forEach((k) => due.add(k));
    }
    this.busy = busy;
    for (const m of machines()) {
      const ready = m.layout === "ready";
      if (ready && this.ready[m.name] === false) for (const k of keys) if (JSON.parse(k)[0] === m.name) due.add(k);
      this.ready[m.name] = ready;
    }
    if (window().active) {
      for (const k of keys) {
        const asks = this.git[k] || this.unsure.has(k);
        if (asks && !this.folded.has(JSON.parse(k)[0]) && now - (this.checked[k] ?? 0) > FALLBACK) due.add(k);
      }
    }
    return due;
  }

  // `key` and the other places in its repo (a commit there moves their ahead/behind).
  sameRepo(key, keys) {
    const repo = this.git[key]?.repo;
    return [key, ...(repo ? [...keys].filter((k) => this.git[k]?.repo === repo) : [])];
  }

  // Agents here that are SSH'd into another computer: each ssh started inside
  // an agent's terminal (it carries HC_TERMINAL_ID; Herdr's own connections
  // don't), its destination matched to a computer Herdr knows (name, ssh host
  // or address, or the same IP: an ssh to 192.168.1.20 is to the laptop there),
  // else the host as typed. Kept a minute after it ends, so a command at a time
  // doesn't flicker.
  async findSsh() {
    const r = await exec("sh", ["-c", SSH_PROCS]).catch(() => null);
    const now = Date.now(), seen = {};
    // Addresses, looked up at most every 5 minutes: each computer's, and each
    // destination that names none of them.
    const addrs = async (name) => {
      const c = (this.ipCache ??= {})[name];
      if (c && now - c.at < 300000) return c.ips;
      const g = await exec("getent", ["ahostsv4", name]).catch(() => null);
      const ips = [...new Set((g?.stdout ?? "").split("\n").map((l) => l.split(/\s+/)[0]).filter(Boolean))];
      this.ipCache[name] = { ips, at: now };
      return ips;
    };
    for (const line of (r?.stdout ?? "").split("\n").filter(Boolean)) {
      const [t, cwd, ...args] = line.split("\t");
      const found = sshDestination(args);
      if (!t || !found) continue;
      const { dest, how } = found;
      const host = dest.replace(/^.*@/, "").toLowerCase();
      let m = this.machines.find((x) => [x.name, x.host, x.target, x.target?.replace(/\.local$/i, "")].some((v) => v && v.toLowerCase() === host));
      if (!m) {
        const mine = await addrs(host);
        for (const x of this.machines) if (!m && x.target && (await addrs(x.target)).some((ip) => mine.includes(ip))) m = x;
      }
      // Folders the remote command names ("cd ~/Code/retake && …"): where it works there.
      const rest = args.slice(args.indexOf(dest) + 1).join(" ");
      const paths = [...rest.matchAll(/(?:^|[\s;&|'"=(])((?:~|\/)[^\s;&|'"()]*)/g)].map((x) => x[1].replace(/\/+$/, "") || "/");
      // Started by one of a Claude agent's subagents in a worktree of its own
      // (.claude/worktrees/agent-<id>, its id in subagents.sh): that one's, else
      // the agent's (a subagent without a worktree can't be told apart).
      const sub = /\/\.claude\/worktrees\/(agent-[0-9a-z]+)(\/|$)/.exec(cwd ?? "")?.[1] ?? null;
      // The agent's own (`self`: to, how, cmd, paths) and each subagent's (subs).
      // A command naming no folder (an scp, an sftp) keeps the last one named.
      const to = m?.name ?? dest.replace(/^.*@/, ""), named = paths.length ? paths : null;
      const e = (seen[t] ??= { self: false, subs: [], at: now });
      if (sub) {
        const x = e.subs.find((y) => y.id === sub);
        if (!x) e.subs.push({ id: sub, to, paths: named ?? [] }); else if (named) x.paths = named;
        if (!e.self) e.to ??= to;
      } else {
        Object.assign(e, { self: true, to, how, cmd: args.filter(Boolean).join(" ") });
        if (named) e.paths = named;
      }
    }
    for (const [t, e] of Object.entries(seen)) e.paths ??= this.sshTo?.[t]?.paths ?? [];
    this.sshSeen = now; // the scan whose entries are connected right now
    const was = JSON.stringify(Object.keys(this.sshTo ?? {}));
    this.sshTo = Object.fromEntries(Object.entries({ ...(this.sshTo ?? {}), ...seen }).filter(([, v]) => now - v.at < 60000));
    return JSON.stringify(Object.keys(this.sshTo)) !== was || Object.keys(seen).length > 0; // redraw
  }

  // Over9k's helpers in ~/.local/share/over9k: handoff.sh and resume.sh (the
  // hand-off rule points there), locations.json (Chats and Projects),
  // spaces.json (open spaces by folder, for handoff.sh where no Herdr window
  // runs) and servers.json (this computer's). Written only on change. This
  // computer always gets them; another only while its Automatic hand off is on
  // (over9k-options), which also puts the rule into its CLAUDE.md/AGENTS.md;
  // turned off, the rule and the helpers go again.
  async syncHelpers() {
    const mods = `${appHome()}/mods`;
    this.helperFiles ??= {
      "handoff.sh": await readTextFile(`${mods}/over9k/handoff.sh`).catch(() => null),
      "resume.sh": await readTextFile(`${mods}/over9k-new-menu/resume.sh`).catch(() => null),
    };
    this.synced ??= {};
    const wanted = shared("sidebar.options")?.computers ?? {};
    const connected = this.machines.filter((m) => m.state === "connected" && this.remote[m.name]).map((m) => m.name);
    this.ruleOn ??= {};
    for (const m of connected) {
      const on = Boolean(wanted[m]?.handoffRule);
      if (!on && this.ruleOn[m]) {
        await exec("sh", ["-c", 'sh "$HOME/.local/share/over9k/handoff.sh" --rule off; rm -rf "$HOME/.local/share/over9k"'], { on: m }).catch(() => null);
        for (const k of Object.keys(this.synced)) if (k.startsWith(`${m}/`)) delete this.synced[k];
      }
      if (!on) this.ruleOn[m] = false;
    }
    const up = [null, ...connected.filter((m) => wanted[m]?.handoffRule)];
    for (const m of up) {
      const loc = m ? { chats: this.remote[m].chats, projects: this.remote[m].projects } : shared("over9k.locations") ?? {};
      const open = Object.fromEntries(this.frame?.sp.filter((s) => (s.machine ?? null) === m && s.folder)
        .map((s) => [s.folder.replace(/\/+$/, ""), m ? s.id.replace(`${m}/`, "") : s.id]) ?? []);
      const files = { ...this.helperFiles, "locations.json": JSON.stringify(loc), "spaces.json": JSON.stringify(open) };
      // This computer's model servers come along for resume.sh.
      if (!m) files["servers.json"] = await readTextFile(`${mods}/over9k-new-menu/servers.json`).catch(() => null);
      for (const [name, text] of Object.entries(files)) {
        const key = `${m ?? ""}/${name}`;
        if (text == null || this.synced[key] === text) continue;
        const r = await exec("sh", ["-c", 'mkdir -p "$HOME/.local/share/over9k" && printf %s "$2" > "$HOME/.local/share/over9k/$1"', "sh", name, text], m ? { on: m } : {}).catch(() => null);
        if (r?.code === 0) this.synced[key] = text;
      }
      // Folders handed off to (handoff.sh lists them in "pin"): pinned, as the
      // menus' Pin does, so they stay listed.
      const p = await exec("sh", ["-c", 'f="$HOME/.local/share/over9k/pin"; [ -s "$f" ] || exit 0; mv "$f" "$f.$$" && cat "$f.$$" && rm -f "$f.$$"'], m ? { on: m } : {}).catch(() => null);
      const handed = (p?.stdout ?? "").split("\n").map((d) => d.trim().replace(/\/+$/, "")).filter(Boolean);
      if (handed.length) this.pinHanded(handed, m);
      // Another computer's rule, once its helpers are there (written again when its folders change).
      const sig = m && JSON.stringify(loc);
      if (m && this.ruleOn[m] !== sig) {
        const r = await exec("sh", ["-c", 'sh "$HOME/.local/share/over9k/handoff.sh" --rule on'], { on: m }).catch(() => null);
        if (r?.code === 0) this.ruleOn[m] = sig;
      }
    }
  }

  // Under another computer: this computer's agents SSH'd into it (findSsh),
  // marked as working from here; a click goes to the agent.
  // `dir`: only those working in that folder there (a space's), else (null)
  // those whose folder matches none of its spaces. Only while connected.
  sshRows(m, t, dir = null) {
    const home = this.remote[m]?.home ?? "";
    const full = (d) => d.replace(/^~(?=\/|$)/, home);
    // Its spaces' folders and its pinned projects' (open or not: busy lifts one).
    const folders = [...this.frame.sp.filter((s) => s.machine === m && s.folder).map((s) => s.folder.replace(/\/+$/, "")), ...this.listedOn(m)];
    // The most specific of those its paths are in (home only for home itself).
    const where = (e) => {
      const hits = (e.paths ?? []).map(full).flatMap((x) => folders.filter((f) => (f === home ? x === f : inside(x, f))));
      return hits.sort((a, b) => b.length - a.length)[0] ?? null;
    };
    // Terminals ssh'd in from here themselves: with a pane (an agent, a shell) or
    // without (something an agent started). Their subagents' get rows of their own.
    const fresh = (address) => { const e = address && this.sshTo?.[address]; return e && e.self && e.to === m && e.at === this.sshSeen && where(e) === dir; };
    const subs = Object.entries(this.subSsh ?? {}).filter(([k, v]) => {
      const [addr, id] = k.split("|");
      return v.to === m && where(v) === dir && this.subs?.[addr]?.some((x) => x.id === id && !x.done);
    });
    const panes = this.frame.ps.filter((p) => fresh(p.terminal));
    const kids = (this.frame.terms ?? []).filter((k) => k.state === "live" && !this.frame.ps.some((p) => p.terminal === k.address) && fresh(k.address));
    // Where it works there, as its command names it ("cd /tmp/my-app && …"),
    // after its name: from home with ~, under its space's folder from there
    // (nothing when it's the space's own).
    const folderOf = (paths) => {
      const f = full(paths?.[0] ?? "");
      if (!f || f === dir) return null;
      return dir && inside(f, dir) ? f.slice(dir.length + 1) : home && (f === home || inside(f, home)) ? `~${f.slice(home.length)}` : f;
    };
    // One row each, marked with a link chip in its link's colour ("→" then a
    // server); hovering it lights up its row here (and the other way round).
    const linkRow = (address, icon, name, click, kind = BOT, paths = this.sshTo?.[address]?.paths) => {
      const c = this.linkColor(address), folder = folderOf(paths);
      // Lit while its other end is hovered, or the agent it belongs to (its row).
      const on = this.hoverLink?.visitor === address || this.hoverLink?.parent === address.split("|")[0];
      return lit(h_flex().id(`via-${address}`), on && { color: c })
        .h(26).flex_none().pl(4).pr(8).gap(8).items_center().rounded(7).hover((s) => s.bg(t.hover))
        .on_hover((on, cx) => { if (on) this.hoverLink = { color: c, source: address }; else if (this.hoverLink?.source === address) this.hoverLink = null; cx.notify(); })
        .when(Boolean(click), (el) => el.on_click(click))
        .child(h_flex().flex_none().gap(4).items_center().child(div().w(16).flex_none()).child(icon))
        .child(h_flex().flex_1().min_w(0).gap(6).items_center()
          .child(div().min_w(0).truncate().text_size(12.5).text_color(t.muted).child(name))
          .when(Boolean(folder), (el) => el.child(div().flex_shrink(0).max_w(170).truncate().text_size(11).text_color(t.dim).child(folder))))
        .child(linkChip(t, `via-chip-${address}`, { dir: "in", icon: kind, color: c }));
    };
    return [
      ...panes.map((p) => {
        const a = this.frame.byPane.get(p.pane);
        const space = this.frame.sp.find((s) => (s.tabs ?? []).some((x) => x.id === p.tab));
        const tab = space?.tabs.find((x) => x.id === p.tab);
        const prog = (a ?? p).program;
        const icon = prog?.icon ? (prog.tint ? svg(prog.icon).size(14).flex_none().text_color(t.foreground) : image(prog.icon).w(14).h(14).flex_none()) : svg("icons/shell.svg").size(14).flex_none().text_color(t.foreground);
        const name = a ? agentName(a, tab, p.cwd) : this.termName(p, tab, "");
        return linkRow(p.terminal, icon, name,
          () => { if (space && !space.active) run("space.select", { id: space.id }); run("pane.focus", { pane: p.pane }); }, a ? BOT : CPU);
      }),
      ...kids.map((k) => {
        const agent = Boolean(k.program?.agent || isAgentProgram(k.agent) || this.frame.ag.some((x) => x.address === k.address));
        return linkRow(k.address, agent ? progIcon(k.program, t, 14) : svg(CPU).size(14).flex_none().text_color(t.foreground), this.nameOf(k.address),
          (_e, cx) => this.showSub(k.address, false, this.nameOf(k.address)), agent ? BOT : CPU);
      }),
      // A subagent by its task; a click shows its transcript, as its row there does.
      ...subs.map(([k, v]) => {
        const [addr, id] = k.split("|"), x = this.subs[addr].find((y) => y.id === id);
        // Its agent's logo (Claude), as its row there has; the chip says it's a subagent.
        const prog = this.frame.ag.find((y) => y.address === addr)?.program;
        return linkRow(k, prog ? progIcon(prog, t, 14) : svg(SUB).size(14).flex_none().text_color(t.foreground), x.desc || "Subagent",
          (e, cx) => this.viewSubagent(addr, id, cx, x.desc || "Subagent", e), SUB, v.paths);
      }),
    ];
  }

  // A computer that has just connected again (or whose folders changed in
  // over9k-options) has its projects looked for again (scanRemote).
  refreshMachines(cx) {
    cx.spawn(async cx => {
      const before = new Set(this.machines.filter((m) => m.state === "connected").map((m) => m.name));
      try { const r = await hc(["machine", "ls", "--json"]); if (r.code === 0) this.machines = (JSON.parse(r.stdout).machines ?? []).filter((m) => !m.temporary); } catch {}
      const back = this.machines.filter((m) => m.state === "connected" && !before.has(m.name)).map((m) => m.name);
      if (back.length && this.remoteSeen) this.scanRemote(cx, back);
      this.remoteSeen = true;
      this.scanRemote(cx); // only where the folders changed or nothing is known yet
      cx.notify();
    });
  }

  // Every 5 s, one at a time: a run that outlasts the next tick (a big
  // transcript to read) isn't joined by another; one stuck a minute is given up on.
  loadInfo(cx) {
    if (this.infoBusy && Date.now() - this.infoBusy < 60000) return;
    const run = this.infoBusy = Date.now();
    cx.spawn(async (cx) => {
      try {
        const info = {};
        // Herdr's own subagents (hc run, no pane) aren't in agents(): their terminals too.
        const listed = agents();
        // (A terminal says what it runs by its program: "agent" isn't there.)
        const kids = terminals().filter((k) => (k.program?.agent || isAgentProgram(k.agent)) && k.state === "live" && !listed.some((a) => a.address === k.address));
        // Claude Code's and Antigravity's, on each computer that runs one: claude-info.py
        // and agy-info.py there, from each one's own files.
        this.ciScript ??= await readTextFile(`${appHome()}/mods/over9k/claude-info.py`).catch(() => null);
        this.aiScript ??= await readTextFile(`${appHome()}/mods/over9k/agy-info.py`).catch(() => null);
        const ci = {}, ai = {};
        for (const a of [...listed, ...kids]) {
          const [script, into] = isClaude(a) ? [this.ciScript, ci] : isAgy(a) ? [this.aiScript, ai] : [null, null];
          if (!script) continue;
          const [m] = a.address.includes("/") ? a.address.split("/") : [null];
          const key = m ?? "";
          if (key in into || (m && !this.machines.some((x) => x.name === m && x.state === "connected"))) continue;
          const r = await (m ? exec("python3", ["-c", script], { on: m }) : python(["-c", script])).catch(() => null);
          try { into[key] = JSON.parse(r?.stdout || "{}"); } catch { into[key] = {}; }
        }
        for (const a of [...listed, ...kids]) {
          const [m, t] = a.address.includes("/") ? a.address.split("/") : [null, a.address];
          if (m && !(this.remote[m]?.home && this.machines.some((x) => x.name === m && x.state === "connected"))) continue;
          try {
            const found = ci[m ?? ""]?.[t];
            const agy = ai[m ?? ""]?.[t];
            // Antigravity: what its status line saved, if it's on, adds the context
            // (agy's files don't have it readably); the rest from agy-info.py wins.
            const text = found ? null : m ? await readTextFile(`${this.remote[m].home}/.cache/over9k/agents/${t}.json`, { on: m }).catch(() => null)
              : await readTextFile(`${this.infoDir}/${a.address}.json`).catch(() => null);
            let saved = null;
            try { saved = text ? JSON.parse(text) : null; } catch {}
            const merged = agy ? { ...agy, context: saved?.context ?? null, out: saved?.out, lastAt: agy.lastAt ?? saved?.lastAt ?? null } : saved;
            if (found || merged) {
              const i = found ?? merged;
              // Past the prompt cache's expiry (cacheUntil, seconds): the next message re-reads everything.
              i.cold = i.cacheUntil != null && Date.now() / 1000 > i.cacheUntil;
              info[a.address] = i;
            }
          } catch {}
        }
        await this.syncHelpers();
        const ssh = await this.findSsh();
        // Claude Code's subagents, per agent: from its transcript's folder (subagents.sh).
        this.subScript ??= await readTextFile(`${appHome()}/mods/over9k/subagents.sh`).catch(() => null);
        const subs = {};
        for (const [addr, i] of Object.entries(info)) {
          if (!i.transcript) continue;
          const [m] = addr.includes("/") ? addr.split("/") : [null];
          if (!this.subScript) break;
          const r = await exec("sh", ["-c", this.subScript, "sh", i.transcript], m ? { on: m } : {}).catch(() => null);
          const list = (r?.stdout ?? "").split("\n").filter(Boolean).map((l) => { const [id, at, desc, type, model, start, tokens, effort, window, done] = l.split("\t"); return { id, at: +at, desc, type, model, start: +start || null, tokens: +tokens || 0, effort: effort || null, window: +window || 200000, done: done === "1" }; });
          if (list.length) subs[addr] = list.sort((x, y) => y.at - x.at);
        }
        // Antigravity's (agy-subagents.py, same lines): the conversations under its own,
        // here only (it reads /proc and agy's databases).
        for (const [addr, i] of Object.entries(info)) {
          if (i.agent !== "antigravity" || addr.includes("/")) continue;
          const r = await python(["-I", `${appHome()}/mods/over9k/agy-subagents.py`, addr, i.conversation ?? ""]).catch(() => null);
          const list = (r?.stdout ?? "").split("\n").filter(Boolean).map((l) => { const [id, at, desc, type, model, start, tokens, effort, window, done] = l.split("\t"); return { id, at: +at, desc: sentenceCase(desc), type, model, start: +start || null, tokens: +tokens || 0, effort: effort || null, window: +window || 1048576, done: done === "1" }; });
          if (list.length) subs[addr] = list.sort((x, y) => y.at - x.at);
        }
        // An ssh from the worktree of a subagent that's finished is the running one
        // that carries on there: its transcript names the folder most (others may
        // name it once, in a shared note). Kept while it runs.
        this.wtOwner ??= {};
        for (const [addr, e] of Object.entries(this.sshTo ?? {})) {
          const live = (subs[addr] ?? []).filter((x) => !x.done), dir = info[addr]?.transcript?.replace(/\.jsonl$/, "");
          if (!dir || !e.subs?.length) continue;
          e.subs = await Promise.all(e.subs.map(async (c) => ({ ...c, id: await (async (w) => {
            if (live.some((x) => x.id === w)) return w;
            const key = `${addr}|${w}`, had = this.wtOwner[key];
            if (had && live.some((x) => x.id === had)) return had;
            const r = live.length ? await exec("grep", ["-c", "-F", w, ...live.map((x) => `${dir}/subagents/${x.id}.jsonl`), "/dev/null"]).catch(() => null) : null;
            const counts = (r?.stdout ?? "").split("\n").map((l) => /([^/]+)\.jsonl:(\d+)$/.exec(l)).filter((m) => m && +m[2] > 1).sort((x, y) => y[2] - x[2]);
            const owner = counts[0]?.[1];
            if (owner) this.wtOwner[key] = owner;
            return owner ?? w;
          })(c.id) })));
        }
        // Each subagent's last ssh, kept a minute: tests ssh one command at a time.
        const at = Date.now();
        this.subSsh = Object.fromEntries(Object.entries(this.subSsh ?? {}).filter(([, v]) => at - v.at < 60000));
        for (const [addr, e] of Object.entries(this.sshTo ?? {})) if (e.at === this.sshSeen) for (const c of e.subs ?? []) {
          const key = `${addr}|${c.id}`;
          this.subSsh[key] = { to: c.to, paths: c.paths.length ? c.paths : (this.subSsh[key]?.paths ?? []), at };
        }
        // And what each has running in the background, or scheduled (tasks.sh):
        // its shells and monitors (processes too) and its cron jobs.
        this.taskScript ??= await readTextFile(`${appHome()}/mods/over9k/tasks.sh`).catch(() => null);
        const tasks = {};
        for (const [addr, i] of Object.entries(info)) {
          if (!i.transcript || !this.taskScript) continue;
          const [m] = addr.includes("/") ? addr.split("/") : [null];
          const r = await exec("sh", ["-c", this.taskScript, "sh", i.transcript], m ? { on: m } : {}).catch(() => null);
          const list = (r?.stdout ?? "").split("\n").filter(Boolean).map((l) => { const [kind, id, desc, start, schedule, output] = l.split("\t"); return { kind, id, desc, start: +start || null, schedule: schedule || null, output: output || null }; });
          if (list.length) tasks[addr] = list;
        }
        // A Codex agent's own subagents and running commands (codex.sh), here or on
        // the agent's computer.
        this.codexScript ??= await readTextFile(`${appHome()}/mods/over9k/codex.sh`).catch(() => null);
        for (const a of [...listed, ...kids].filter((x) => isCodex(x) || /^codex/.test(x.agent ?? ""))) {
          if (!this.codexScript) break;
          const [m, t] = a.address.includes("/") ? a.address.split("/") : [null, a.address];
          const r = await exec("sh", ["-c", this.codexScript, "sh", t], m ? { on: m } : {}).catch(() => null);
          const list = (r?.stdout ?? "").split("\n").filter(Boolean).map((l) => { const [kind, id, desc, start, schedule] = l.split("\t"); return { kind, id, desc, start: +start || null, schedule: schedule || null, output: null }; });
          if (list.length) tasks[a.address] = [...(tasks[a.address] ?? []), ...list];
        }
        const subsChanged = JSON.stringify([subs, tasks]) !== JSON.stringify([this.subs ?? {}, this.tasks ?? {}]);
        this.subs = subs;
        this.tasks = tasks;
        // What's gone is forgotten: when started terminals were first seen, viewers kept.
        const live = new Set(terminals().filter((k) => k.state === "live").map((k) => k.address));
        for (const k of Object.keys(this.kidSeen ?? {})) if (!live.has(k)) delete this.kidSeen[k];
        for (const [k, v] of Object.entries(this.viewers ?? {})) if (!live.has(v)) delete this.viewers[k];
        // This computer's folders changed (over9k-options): look again.
        const folders = JSON.stringify(shared("sidebar.options")?.locations ?? {});
        if (this.scannedWith !== undefined && this.scannedWith !== folders) this.scanProjects(cx);
        this.scannedWith = folders;
        // An agent that was working and now isn't: it just finished.
        let finished = false;
        for (const a of agents()) {
          if (a.status === "working") this.wasWorking[a.address] = true;
          else if (this.wasWorking[a.address]) { delete this.wasWorking[a.address]; this.lastWork[a.address] = Date.now(); finished = true; }
        }
        if (finished) {
          const live = new Set(agents().map((a) => a.address));
          for (const k of Object.keys(this.lastWork)) if (!live.has(k)) delete this.lastWork[k];
          localStorage.setItem("agents.lastWork", JSON.stringify(this.lastWork));
        }
        // Pi's model, thinking level and context: its footer, per terminal.
        const pi = {};
        for (const a of agents()) {
          if (!isPi(a)) continue;
          const r = await hc(["read", a.address, "--lines", "8"]).catch(() => null);
          const f = piFooter(r?.stdout);
          if (f) pi[a.address] = f;
        }
        // Models by id from Pi's list (~/.pi/agent/models.json): their names and
        // servers; a server here runs at the effort its command line gives.
        const models = {};
        try {
          const list = JSON.parse(await readTextFile(`${homeDir()}/.pi/agent/models.json`));
          for (const prov of Object.values(list.providers ?? {}))
            for (const m of prov.models ?? []) {
              const port = /^https?:\/\/(?:127\.0\.0\.1|localhost):(\d+)/.exec(prov.baseUrl ?? "")?.[1] ?? null;
              models[m.id] = { name: (m.name ?? m.id).replace(/\s*\(local\)$/i, ""), port };
            }
        } catch {}
        // Servers here for those models: running (pid by port), and their effort.
        const effort = {}, up = {};
        const ports = new Set(Object.values(models).map((m) => m.port).filter(Boolean));
        if (ports.size) {
          const r = await exec("ps", ["-eo", "pid=,args="]).catch(() => null);
          for (const line of (r?.stdout ?? "").split("\n")) {
            const port = /--port\s+(\d+)/.exec(line)?.[1], e = /--reasoning-effort\s+(\S+)/.exec(line)?.[1];
            if (!port || !ports.has(port) || /<defunct>/.test(line)) continue;
            up[port] = Number(line.trim().split(/\s+/)[0]);
            if (e) effort[port] = e;
          }
        }
        const next = JSON.stringify([info, pi, models, effort, up]);
        if (next !== JSON.stringify([this.info, this.piInfo, this.models, this.serverEffort, this.serversUp])) {
          this.info = info; this.piInfo = pi; this.models = models; this.serverEffort = effort; this.serversUp = up;
          cx.notify();
        } else if (ssh || subsChanged || Object.values(subs).some((l) => l.some((x) => Date.now() / 1000 - x.at < 70))) {
          cx.notify(); // a connection started, is still going, or ended
        }
      } finally { if (this.infoBusy === run) this.infoBusy = 0; }
    });
  }

  // A chip on This computer's heading per local model server running (its
  // model's logo and name): it's holding the GPU. Hovered it reads "Stop …";
  // a click asks first (over9k-server-stop), naming the agents on that model.
  serverChips(t) {
    return Object.entries(this.serversUp).map(([port, pid]) => {
      const m = Object.values(this.models).find((x) => x.port === port);
      const fam = FAMILY.find((f) => f.match.test(m?.name ?? ""));
      const armed = this.hoverServer === port;
      return h_flex().id(`server-${port}`).h(18).px(5).gap(4).flex_none().rounded(5).items_center().cursor_pointer()
        .border(1).border_color(armed ? t.ansi1 : t.border).text_size(10.5).text_color(armed ? t.ansi1 : t.dim)
        .hover((s) => s.bg(t.hover))
        .on_hover((on, cx) => { if (on) this.hoverServer = port; else if (this.hoverServer === port) this.hoverServer = null; cx.notify(); })
        .on_mouse_down("left", (_e, cx) => cx.stop_propagation())
        .on_click((_e, cx) => { cx.stop_propagation(); this.hoverServer = null; this.askStop(port, pid, m?.name ?? `port ${port}`, cx); })
        .when(Boolean(fam), (el) => el.child(svg(fam?.icon ?? "").size(10).text_color(fam?.color)))
        .child(armed ? `Stop ${(m?.name ?? "server").split(" ")[0]}` : (m?.name ?? `:${port}`).split(" ")[0]);
    });
  }

  askStop(port, pid, name, cx) {
    cx.spawn(async () => {
      let stop = null;
      try {
        const entry = JSON.parse(await readTextFile(`${appHome()}/mods/over9k-new-menu/servers.json`))[`http://127.0.0.1:${port}`];
        stop = typeof entry === "object" ? entry?.stop : null;
      } catch {}
      // The agents on a model this server holds, by the names the rows show.
      const users = agents().filter((a) => {
        const raw = isCodex(a) ? codexTitle(a.title) : isPi(a) ? this.piInfo[a.address] : this.info[a.address];
        return raw && (this.models[raw.id] ?? this.models[raw.model])?.port === port;
      }).map((a) => agentTask(a, this.frame?.ps.find((p) => p.terminal === a.address)?.cwd) || appName(a) || a.address);
      openOverlay({ mod: "over9k-server-stop", kind: "dialog", width: 400, height: 170, props: { name, port, pid, stop, agents: users } });
    });
  }

  // How long ago an agent last worked: "3m", "2h", "1d" (null when unknown).
  since(a, i) {
    const at = Math.max(this.lastWork[a.address] ?? 0, (i?.lastAt ?? 0) * 1000);
    if (!at) return null;
    const m = Math.max(0, Math.round((Date.now() - at) / 60000));
    return m < 60 ? `${m}m` : m < 1440 ? `${Math.round(m / 60)}h` : `${Math.round(m / 1440)}d`;
  }

  // An agent's info with its model named: one from Pi's list goes by its name
  // and family logo, and Claude Code on a local server by that server's effort.
  withModel(i, a) {
    const m = this.models[i.id] ?? this.models[i.model];
    if (!m) return i;
    const fam = FAMILY.find((f) => f.match.test(`${i.model} ${m.name}`));
    return { ...i, model: m.name, family: fam ?? null, effort: (isClaude(a) && m.port && this.serverEffort[m.port]) || i.effort };
  }

  // "Opus 5.5 · high · 24% · 3m" after the agent's name: model, effort, context
  // used (its percent green, yellow from 50%, red from 80%; "medium" shows as
  // "med", a purple * after it while ultracode is on), time since it last
  // worked; then a red "exp."
  // once the prompt cache has run out. Clicking it starts over (freshStart);
  // hovering says so ("clear + recap").
  // What shows is up to over9k-options (o): each item, joined by dots.
  // How many agents, subagents and processes an agent has started (BOT / SUB / CPU), a
  // click shows or hides them (subRows); hovered, in words.
  subsChip(a, p, t) {
    const id = `subs-${a.address}`;
    const chevron = () => svg(`mods/workspace-chrome/chevron-${this.subsOpen.has(a?.address) ? "down" : "right"}.svg`).size(8);
    // White (the theme's text colour) on a faint wash of it.
    const fg = t.foreground, wash = (a) => (/^#[0-9a-f]{6}$/i.test(fg) ? fg + a : t.raised);
    const chip = () => h_flex().h(16).px(4).gap(3).items_center().rounded(4).text_size(10.5).text_color(fg);
    const n = this.subCounts(a);
    // An icon and count for each kind it has (compact: just how many in all); a
    // click shows or hides them (subRows).
    const compact = this.frame.options.layout === "compact";
    // A dot (its link's colour) for each of its subagents ssh'd into another
    // computer; the agent's own shows as its link chip.
    const away = (this.subs?.[a.address] ?? []).filter((x) => !x.done && this.sshedTo(a.address, x.id)).slice(0, 3).map((x) => this.linkColor(`${a.address}|${x.id}`));
    return div().id(id).flex_none()
      .on_mouse_down("left", (_e, cx) => cx.stop_propagation())
      .on_click((_e, cx) => {
        cx.stop_propagation();
        this.subsOpen.has(a.address) ? this.subsOpen.delete(a.address) : this.subsOpen.add(a.address);
        localStorage.setItem("agents.subsOpen", JSON.stringify([...this.subsOpen]));
        cx.notify();
      })
      // Brighter while its row is hovered (a click anywhere on the row folds it too).
      .child(chip().bg(wash(this.hoverTerm === p.pane ? "29" : "1a"))
        .when(compact, (el) => el.child(String(n.agents + n.inner + n.processes + n.crons)))
        .when(!compact && n.agents > 0, (el) => el.child(svg(BOT).size(10).flex_none()).child(String(n.agents)))
        .when(!compact && n.inner > 0, (el) => el.child(svg(SUB).size(13).flex_none().ml(n.agents > 0 ? 3 : 0)).child(String(n.inner)))
        .when(!compact && n.processes > 0, (el) => el.child(svg(CPU).size(10).flex_none().ml(n.agents + n.inner > 0 ? 3 : 0)).child(String(n.processes)))
        .when(!compact && n.crons > 0, (el) => el.child(svg(CLOCK).size(10).flex_none().ml(n.agents + n.inner + n.processes > 0 ? 3 : 0)).child(String(n.crons)))
        .children(away.map((c, i) => div().size(5).rounded(3).flex_none().bg(c).when(i === 0, (el) => el.ml(1))))
        .child(chevron()));
  }

  // An agent row's details and its subagents chip. `withChip` false: the row
  // shows the chip elsewhere (expanded, at its end).
  // What goes at the end of an agent row: its link chip when it also works on
  // another computer (ssh'd there: findSsh; listed there too, sshRows, and
  // hovering either row lights up the other), then its count chip.
  endChips(a, p, t) {
    const to = this.sshedTo(p.terminal, "self");
    const els = [
      to && linkChip(t, `ssh-${p.terminal}`, { dir: "out", icon: a ? BOT : CPU, color: this.linkColor(p.terminal), to }),
      a && this.subCount(a) > 0 && this.subsChip(a, p, t),
    ].filter(Boolean);
    return els.length ? h_flex().flex_none().gap(5).items_center().children(els) : null;
  }

  agentDetails(info, t, a, p, opt, withChip = true) {
    const chip = withChip ? this.endChips(a, p, t) : null;
    return this.infoLine(info, t, a.address, agentTask(a, p.cwd), opt, chip);
  }

  // `extra`: an element at the end of the line (an agent's subagents chip).
  infoLine(i, t, terminal, name, o, extra = null) {
    const pct = Math.round(i.context ?? 0);
    const color = pct >= 80 ? t.ansi1 : pct >= 50 ? t.ansi3 : t.ansi2;
    const parts = [
      // Listed by state (agentSections): where it is first: its folder, in its
      // space's colour, and the computer when it's another.
      this.tagWhere ? div().text_color(this.tagWhere.color ?? t.dim).child(this.tagWhere.folder) : null,
      this.tagWhere?.machine ? div().child(this.tagWhere.machine) : null,
      o.model && i.model ? div().child(i.model) : null,
      o.effort && i.effort ? h_flex().items_center().child(i.effort === "medium" ? "med" : i.effort)
        .when(Boolean(i.ultracode), (el) => el.child(div().text_color(MARK.ansi5).child("*"))) : null,
      // Context always shows when on: 0% before the first reply.
      o.context ? div().text_color(color).child(`${pct}%`) : null,
      // How long since it last worked, while it isn't.
      o.since && i.since ? div().child(i.since) : null,
    ].filter(Boolean);
    return h_flex().flex_none().items_center().text_size(11).text_color(t.dim)
      .children(dotted(parts))
      .when(Boolean(o.cache && i.cold), (el) => el.child(div().id(`exp-${terminal}`).ml(4).px(2).rounded(4).cursor_pointer().text_color(t.ansi1)
        .hover((s) => s.bg(t.hover))
        .on_mouse_down("left", (_e, cx) => cx.stop_propagation())
        .on_hover((on, cx) => { if (on) this.hoverExp = terminal; else if (this.hoverExp === terminal) this.hoverExp = null; cx.notify(); })
        .on_click((_e, cx) => { cx.stop_propagation(); this.freshStart(terminal, i.transcript, name, cx); })
        .child(this.hoverExp === terminal ? "clear + recap" : "exp.")))
      .when(Boolean(extra), (el) => el.child(extra.ml(5)));
  }

  // With the cache gone the next message pays for the whole conversation again,
  // so start a new one (/clear) and have it read the old transcript for context.
  // The old one is renamed "[Cleared] <name>" first, so Claude's own /resume
  // picker tells them apart. The new one is named from the first line of
  // Claude's recap ("Name: ..."): its automatic title would only be about
  // reading a transcript, and carrying that forward named every one the same.
  freshStart(terminal, transcript, name, cx) {
    // An automatic title taken from an earlier recap prompt says nothing.
    if (name && /transcript recap/i.test(name)) name = null;
    cx.spawn(async (cx) => {
      if (name) {
        await hc(["send", terminal, `/rename [Cleared] ${name}`]).catch(() => null);
        await cx.sleep(800);
      }
      await hc(["send", terminal, "/clear"]).catch(() => null);
      if (!transcript) return;
      // A prompt sent before /clear finishes is lost: wait until claude-info.py
      // reports the new conversation's transcript (up to 35s), then a moment more.
      let fresh = null;
      for (let n = 0; n < 70; n++) {
        await cx.sleep(500);
        const now = await readTextFile(`${this.infoDir}/${terminal}.json`).catch(() => null);
        try { fresh = now && JSON.parse(now).transcript; } catch { fresh = null; }
        if (fresh && fresh !== transcript) break;
        fresh = null;
      }
      await cx.sleep(500);
      await hc(["send", terminal, `We just cleared the conversation because its prompt cache expired. For context, read the previous conversation's transcript at ${transcript} (JSONL; mostly its last part: what I asked, what was done, what's still open). Start your reply with one line "Name: <3 to 5 words naming what we're working on>" (it becomes this session's name), then tell me in a few lines where we left off, and wait for my next message.`]).catch(() => null);
      if (!fresh) return;
      // Watch for the reply (up to 5 minutes) and rename as soon as it lands,
      // before there's much chance of a half-typed message for /rename to join.
      for (let n = 0; n < 300; n++) {
        await cx.sleep(1000);
        const got = recapName(await readTextFile(fresh).catch(() => null));
        if (!got) continue;
        await hc(["send", terminal, `/rename ${got}`]).catch(() => null);
        return;
      }
    });
  }

  // Which row each terminal lists under: the space or project its live folder is
  // in (the most specific folder wins); at ~ itself, the home space; anywhere
  // else, a row of its own for that folder (its repo's top when it's in one).
  // Only this computer's; another machine's stay with their space. Map key ->
  // panes, key a space id or "d:<folder>" for a project or folder with no space.
  assign(sp, ps) {
    const spaceOfTab = new Map();
    for (const s of sp) for (const tab of s.tabs ?? []) spaceOfTab.set(tab.id, s);
    const local = sp.filter((s) => !s.machine);
    const trim = (d) => d.replace(/\/+$/, "");
    const homeSpace = local.find((s) => trim(s.folder) === homeDir());
    const own = local.filter((s) => s !== homeSpace && s.folder);
    // A project with a space made in it (or a folder inside it) is that space.
    const places = [
      ...own.map((s) => ({ dir: trim(s.folder), key: s.id })),
      ...this.projects.map((d) => ({ dir: d, key: own.find((s) => trim(s.folder) === d)?.id ?? own.find((s) => inside(s.folder, d))?.id ?? `d:${d}` })),
    ];
    const groups = new Map();
    this.wantTops = new Set();
    for (const p of ps) {
      const mine = p.terminal && spaceOfTab.get(p.tab);
      if (!mine) continue;
      let key = mine.id;
      if (!mine.machine && p.cwd) {
        const cwd = trim(p.cwd) || "/";
        const best = places.filter((x) => inside(cwd, x.dir)).sort((a, b) => b.dir.length - a.dir.length)[0];
        if (best) key = best.key;
        else if (cwd === homeDir()) key = homeSpace?.id ?? mine.id;
        else {
          // Anywhere else: a row for that folder (its repo, once known).
          if (!this.tops.has(cwd)) this.wantTops.add(cwd);
          key = `d:${this.tops.get(cwd) ?? cwd}`;
        }
      }
      if (!groups.has(key)) groups.set(key, []);
      groups.get(key).push({ p, space: mine, tab: mine.tabs.find((x) => x.id === p.tab) });
    }
    return groups;
  }

  // A row's terminals: status, icon, name, and for an agent its model · effort ·
  // context % when known. Click shows it; Ctrl+click picks it to close. A
  // worktree's terminals sit one step further in than the worktree row.
  termRows(key, t, indent = 0) {
    const { byPane } = this.frame;
    // Something an agent started (open beside it) is listed under that agent
    // (subRows), not again on its own, while the agent runs.
    const live = new Map((this.frame.terms ?? []).filter((k) => k.state === "live").map((k) => [k.address, k]));
    const child = (term) => Boolean(live.get(term)?.parent && live.has(live.get(term).parent))
      // A subagent's or a process's live view (view()) too: its row is under the agent.
      || live.get(term)?.labels?.over9k === "view" || Object.values(this.viewers ?? {}).includes(term);
    return (this.frame.groups.get(key) ?? []).filter(({ p }) => this.passes(byPane.get(p.pane)) && !child(p.terminal) && (!this.onlyPane || p.pane === this.onlyPane)).flatMap(({ p, space, tab }) => {
      this.vis.push(`p:${p.pane}`);
      const a = byPane.get(p.pane);
      const idle = !a || a.status === "idle" || a.status === "done";
      // Claude Code's status line writes its info to a file; Codex's is in its title.
      const codex = a && isCodex(a) ? codexTitle(a.title) : null;
      const raw = a && (codex ? (codex.model ? codex : null) : isPi(a) ? this.piInfo[a.address] : this.info[a.address]);
      const info = raw && { ...this.withModel(raw, a), since: a.status !== "working" ? this.since(a, raw) : null };
      // Two lines (name, then details): expanded, or listed by state (agentSections:
      // its folder leads the second line, then the details).
      const opt = this.frame.options, two = Boolean(this.tagWhere) || (info && opt.layout === "expanded");
      const prog = (a ?? p).program;
      // Picked itself, or going with a picked space (its own) or folder row.
      const picked = this.sel.has(`p:${p.pane}`) || this.sel.has(`s:${space.id}`) || (key.startsWith("d:") && this.sel.has(key));
      // Expanded (over9k-options): an agent with info takes two lines, its name
      // then the info under it; compact keeps the info on the name's line.
      // Its two lines sit close (tight line heights), with room above and below.
      // SSH'd elsewhere: lit while its row there is hovered, and hovering it lights that one (sshRows).
      const sshed = this.sshedTo(p.terminal, "self");
      const row = lit(h_flex().id(`term-${p.terminal}`), this.hoverLink?.source === p.terminal && this.hoverLink).h(two ? 36 : 26).flex_none().pl(4 + indent).pr(8).gap(8).items_center().rounded(7)
        .when(space.active && p.focused && !picked, (el) => el.bg(t.hover))
        .when(picked, (el) => el.bg(t.accent + "38"))
        .hover((s) => s.bg(t.hover))
        .on_hover((on, cx) => {
          if (on) this.hoverTerm = p.pane; else if (this.hoverTerm === p.pane) this.hoverTerm = null;
          // Lights up every row linked to it: its own ssh's, its subagents' and what
          // it started working elsewhere (each in its link's colour).
          if (on) this.hoverLink = { color: sshed ? this.linkColor(p.terminal) : null, visitor: sshed ? p.terminal : null, parent: p.terminal };
          else if (this.hoverLink?.parent === p.terminal) this.hoverLink = null;
          cx.notify();
        })
        .on_click((e, cx) => {
          if (multi(e)) return this.pick(`p:${p.pane}`, cx, e);
          if (e.click_count === 2) return this.renamePane(p, a, tab);
          this.sel.clear();
          this.anchor = `p:${p.pane}`;
          // An agent with things under it: a click shows or hides them too (as its chip does).
          if (a && this.subCount(a) > 0) {
            this.subsOpen.has(a.address) ? this.subsOpen.delete(a.address) : this.subsOpen.add(a.address);
            localStorage.setItem("agents.subsOpen", JSON.stringify([...this.subsOpen]));
            cx.notify();
          }
          if (!space.active) run("space.select", { id: space.id });
          run("pane.focus", { pane: p.pane });
        })
        .on_mouse_down("right", (_e, cx) => {
          cx.stop_propagation();
          this.rightClick(`p:${p.pane}`, () => openOverlay({ mod: "over9k-menu", kind: "popup", width: 220, height: 300, props: { tab: "pane", target: { pane: p.pane, terminal: p.terminal } } }));
        })
        // The agent's status left of its icon, so what follows can sit flush right;
        // on hover an x there closes the terminal. An agent's own icon; a plain
        // terminal's is always the terminal's (not whatever it runs now, like sleep's).
        .child(h_flex().flex_none().gap(4).items_center()
          .child(h_flex().w(16).flex_none().justify_center()
            .when(this.hoverTerm === p.pane, (el) => el.child(this.closeButton(`close-${p.terminal}`, t, () => closeAsk({ panes: [p.pane] }))))
            .when(this.hoverTerm !== p.pane && Boolean(a), (el) => el.child(this.mark(a, t))))
          .when(!a, (el) => el.child(svg("icons/shell.svg").size(14).flex_none().text_color(t.foreground)))
          // On a model with a logo of its own (Qwen): that logo as a badge on its corner.
          .when(Boolean(a && prog?.icon), (el) => el.child(badge(prog.tint
            ? svg(prog.icon).size(14).flex_none().text_color(t.foreground)
            : image(prog.icon).w(14).h(14).flex_none(), info?.family, t.chrome))))
        .child(v_flex().flex_1().min_w(0)
          .child(h_flex().min_w(0).gap(6).items_center()
            .child(div().min_w(0).truncate().text_size(12.5).text_color(idle ? t.muted : t.foreground)
              .when(Boolean(two), (el) => el.line_height("15px"))
              .child(a ? agentName(a, tab, p.cwd) : this.termName(p, tab, key)))
            // Its link and count chips: after its details (infoLine) on one line; on
            // two (expanded) or with no details, here on the name's line, at its end,
            // so the line under has the whole width.
            .when(!info || two, (el) => el.when(Boolean(two), (x) => x.child(div().flex_1())).children([this.endChips(a, p, t)].filter(Boolean))))
          .when(Boolean(two), (el) => el.overflow_hidden().child(info ? this.agentDetails(info, t, a, p, opt, false).line_height("13px")
            : h_flex().min_w(0).items_center().text_size(11).line_height("13px").text_color(t.dim)
              .children(dotted([div().text_color(this.tagWhere?.color ?? t.dim).child(this.tagWhere?.folder ?? ""), this.tagWhere?.machine && div().child(this.tagWhere.machine)].filter(Boolean))))))
        .when(Boolean(info) && !two, (el) => el.child(this.agentDetails(info, t, a, p, opt)));
      // Its sub-agents nested under it (subRows), unless folded.
      return [row, ...(a && this.subsOpen.has(a.address) ? this.subRows(a, p, t, indent) : [])];
    });
  }

  // Double-click: rename it, as the pane menu's Rename does (over9k-rename: an
  // agent's session by its own command, a plain terminal's tab).
  renamePane(p, a, tab) {
    const named = tab && !/^(\d+|tb?[0-9a-z]+)$/.test(tab.name) && tab.name !== (a ?? p)?.program?.name ? tab.name : "";
    openOverlay({ mod: "over9k-rename", kind: "dialog", width: 380, height: 200,
      props: { pane: p.pane, terminal: p.terminal, tab: tab?.id, alone: this.frame.ps.filter((x) => x.tab === p.tab).length === 1,
        value: named || (a ? agentTask(a, p.cwd) : ""), title: a ? `Rename ${a.program?.name ?? "agent"} session` : "Rename terminal" } });
  }

  // Under an agent, what it started: agents it ran in terminals of their own
  // (hc run: the core records the parent; they have no pane) with their
  // status, a click peeks at one; and Claude Code's own subagents (the Agent
  // tool, read from its transcript folder: subagents/*.meta.json), a spinner
  // while one works, then how long ago it finished, for 10 minutes. One working
  // in another space says which.
  // Goes to a pane: its space, its tab, then the pane (in order, through the CLI,
  // so a split that follows lands beside it).
  async goTo(pane) {
    const p = panes().find((x) => x.pane === pane);
    if (!p) return;
    const w = spaces().find((x) => (x.tabs ?? []).some((tb) => tb.id === p.tab));
    const go = (command, args) => exec("herdr-app", ["do", command, JSON.stringify(args)]).catch(() => null);
    if (w && !w.active) await go("space.select", { id: w.id });
    await go("tab.select", { id: p.tab });
    await go("pane.focus", { pane });
  }

  // Shows a terminal in the panel on the right (where Files and Changes open), in
  // the panel's stack (PANEL_VIEW, added to this layout the first time): a header
  // with its `title` and a close button (the over9k-panel mod), the terminal under
  // it. No tab, no pane, no row of its own. One at a time: a viewer this mod
  // started for the one before (`viewer`) ends. Clicked again while it shows: the
  // panel closes. A layout without that panel: a peek.
  showInPanel(terminal, viewer = false, title = "") {
    const was = shared("over9k.panelView");
    const panel = find(layout(), "panel");
    if (was?.terminal === terminal && panel && !panel.hidden && find(layout(), "panel-body")?.active === PANEL_VIEW) {
      run("layout.hide", { id: "panel" });
      run("layout.select", { stack: "panel-body", child: "files" });
      if (was.viewer) hc(["kill", terminal]).catch(() => null);
      return setShared("over9k.panelView", null);
    }
    // The layout's own file, not layout() (that's as drawn, without the nodes a
    // single child folds away, like the panel's own column): only the view's
    // terminal changes in it; showing and choosing stay clicks, so the Files and
    // Changes buttons still hide the panel.
    // Herdr's own layouts can't be changed this way: a peek there.
    const name = shared("layout") ?? "main";
    if (["main", "terminals", "win98"].includes(name)) return run("terminal.peek", { terminal });
    readTextFile(`${appHome()}/layouts/${name}.json`).then((text) => {
      let tree = null;
      try { tree = JSON.parse(text); } catch {}
      const stack = tree && find(tree, "panel-body");
      if (!stack) return run("terminal.peek", { terminal });
      const term = find(stack, `${PANEL_VIEW}-term`);
      if (term) term.content = { terminal };
      else stack.children = [...(stack.children ?? []), { id: PANEL_VIEW, type: "column", children: [
        { id: `${PANEL_VIEW}-head`, type: "block", size: { px: 30 }, content: { mod: "over9k-panel" } },
        { id: `${PANEL_VIEW}-term`, type: "block", content: { terminal } },
      ] }];
      setShared("over9k.panelView", { terminal, viewer, title });
      run("layout.set", { layout: tree });
      run("layout.select", { stack: "panel-body", child: PANEL_VIEW });
      run("layout.show", { id: "panel" });
      if (was?.viewer && was.terminal !== terminal) hc(["kill", was.terminal]).catch(() => null);
    }).catch(() => run("terminal.peek", { terminal }));
  }

  // A click on a sub-row opens it; a press on its stop button doesn't.
  // `key`: its pick (Shift/Cmd/Ctrl+click picks it, as any row; a plain click
  // drops the picks).
  subClick(e, cx, key, open) {
    if (Date.now() - (this.btnAt ?? 0) < 400) return;
    if (multi(e)) return this.pick(key, cx, e);
    if (this.sel.size) { this.sel.clear(); cx.notify(); }
    this.anchor = key;
    this.showing = key; // the row whose view showSub puts up (it stays highlighted)
    if (e.click_count === 1) open();
  }

  // Shows what an agent started in place of the pane you're in, for now (Herdr's
  // terminal.show): nothing splits, nothing new is listed. Clicked again: back.
  // A viewer this mod started for the one before ends. Alt+click: in the side
  // panel instead (showInPanel).
  showSub(terminal, viewer = false, title = "", e = null) {
    if (e?.modifiers?.alt) return this.showInPanel(terminal, viewer, title);
    // Still up only while the focused pane shows it (clicked elsewhere: it isn't).
    const was = this.shownSub, up = was && [undefined, was.terminal].includes(focused()?.shown);
    if (up && was.terminal === terminal) {
      this.shownSub = null;
      run("terminal.show", {});
      if (was.viewer) hc(["kill", terminal]).catch(() => null);
      return;
    }
    this.shownSub = { terminal, viewer, key: this.showing };
    run("terminal.show", { terminal });
    if (was?.viewer) hc(["kill", was.terminal]).catch(() => null);
  }

  // Closes picked sub-rows (rightClick's "Close selected", through shared
  // "over9k.closeSubs"): a terminal ends; a Codex command's process ends; what only
  // its agent can stop (Claude's subagents, shells, monitors, scheduled prompts;
  // Codex's subagents) it's asked to, one message per agent.
  closeSubs(list) {
    const asks = {};
    for (const x of list) {
      if (x.kind === "terminal") run("terminal.kill", { terminal: x.terminal });
      else if (x.kind === "pid") exec("kill", [String(x.pid)]).catch(() => null);
      else (asks[x.agent] ??= []).push(x.text);
    }
    for (const [agent, items] of Object.entries(asks))
      hc(["send", agent, `Stop these of yours, then tell me in one line: ${items.join("; ")}.`]).catch(() => null);
  }

  // A live view in the panel (showInPanel): `script` (a file in this mod, sent
  // inline so nothing needs installing on the agent's computer) run with `args`
  // on `addr`'s computer. One per `key`: a second click shows the same one.
  view(key, addr, script, args, cx, title, e = null) {
    const [m] = addr.includes("/") ? addr.split("/") : [null];
    cx.spawn(async (cx) => {
      this.scripts ??= {};
      this.scripts[script] ??= await readTextFile(`${appHome()}/mods/over9k/${script}`).catch(() => null);
      if (!this.scripts[script]) return;
      this.viewers ??= {};
      const open = this.viewers[key];
      if (open && terminals().some((k) => k.address === open && k.state === "live")) return this.showSub(open, true, title, e);
      const r = await hc(["run", "--bg", "--json", "--label", "over9k=view", ...(m ? ["--on", m] : []), "--", "sh", "-c", this.scripts[script], "sh", ...args]).catch(() => null);
      let t = null;
      try { t = JSON.parse(r?.stdout ?? "").address; } catch {}
      if (!t) return;
      const at = m && !t.includes("/") ? `${m}/${t}` : t;
      // A moment for the window to know the new terminal, else the block is empty.
      await cx.sleep(500);
      this.viewers[key] = at;
      this.showSub(at, true, title, e);
    });
  }

  // A Claude subagent's transcript, live and readable (subagent-view.sh).
  viewSubagent(addr, id, cx, title, e = null) {
    const transcript = this.info[addr]?.transcript;
    if (!transcript) return;
    const file = `${transcript.replace(/\.jsonl$/, "")}/subagents/${id}.jsonl`;
    this.view(file, addr, "subagent-view.sh", [file], cx, title, e);
  }

  // Sub-agents (hc run, no pane of their own) working in space `w` while
  // their parent is somewhere else: listed here too, "from <parent>", with
  // their status; a click peeks at one. Only while they run. They also stay
  // under their parent (subRows).
  visitorRows(w, t, indent = 0) {
    const m = w.machine ?? null, folder = (w.folder ?? "").replace(/\/+$/, "");
    if (!folder) return [];
    const at = (addr) => (addr.includes("/") ? addr.split("/")[0] : null);
    // Without a pane, working here while what started it counts as elsewhere
    // (an agent of an agent working where that one does is listed under it).
    const here = (this.frame.terms ?? []).filter((k) => k.parent && k.state === "live" && k.cwd && at(k.address) === m
      && !this.frame.ps.some((p) => p.terminal === k.address) && this.workSpace(k.address)?.id === w.id && this.workSpace(k.parent)?.id !== w.id);
    return here.map((k) => {
      const ka = this.frame.ag.find((x) => x.address === k.address) ?? (k.program?.agent || isAgentProgram(k.agent) ? k : null);
      const kind = ka || k.program?.agent ? "agent" : "process";
      const c = this.linkColor(k.address);
      // Hovered: its row under the agent that started it lights up.
      return lit(h_flex().id(`visit-${k.address}`), (this.hoverLink?.visitor === k.address || this.hoverLink?.parent === k.parent) && { color: c })
        .on_hover((h, cx) => { if (h) this.hoverLink = { color: c, source: k.address }; else if (this.hoverLink?.source === k.address) this.hoverLink = null; cx.notify(); })
        .h(26).flex_none().pl(4 + indent).pr(8).gap(8).items_center().rounded(7)
        .hover((s) => s.bg(t.hover)).on_mouse_down("left", (e, cx) => this.subClick(e, cx, `k:${k.address}`, () => this.showSub(k.address, false, this.helperTitle(k.address) || k.name || (ka && agentTask(ka, k.cwd)) || appName(ka) || k.program?.name || k.agent, e)))
        .child(h_flex().flex_none().gap(4).items_center()
          .child(h_flex().w(16).flex_none().justify_center().when(Boolean(ka), (el) => el.child(this.mark(ka, t))))
          .child(kind === "process" ? svg(CPU).size(14).flex_none().text_color(t.foreground) : progIcon((ka ?? k).program, t, 14)))
        .child(h_flex().flex_1().min_w(0).child(div().min_w(0).truncate().line_height("15px").text_size(12.5).text_color(t.muted).child(this.helperTitle(k.address) || k.name || (ka && agentTask(ka, k.cwd)) || appName(ka) || k.program?.name || k.address)))
        .child(linkChip(t, `visit-chip-${k.address}`, { dir: "in", icon: kind === "process" ? CPU : BOT, color: c }));
    });
  }

  // What an agent has going besides terminals: a Claude Code session's
  // background shells and monitors, or a Codex agent's running commands (procs);
  // Claude's scheduled prompts and wakeups (crons): tasks.sh; a Codex agent's
  // own subagents (csubs): codex.sh.
  bgTasks(a) {
    const all = this.tasks?.[a.address] ?? [];
    const of = (...kinds) => all.filter((x) => kinds.includes(x.kind));
    return { procs: of("shell", "monitor", "cshell"), crons: of("cron", "wakeup"), csubs: of("csub") };
  }

  // Claude's subagents still going: a finished (or stopped) one leaves the list
  // at once. A quiet one is waiting (on its own background work, a long command)
  // and stays; only one silent for a day goes (its session died without saying).
  liveSubs(a) {
    return (this.subs?.[a.address] ?? []).filter((x) => !x.done && Date.now() / 1000 - x.at < 86400);
  }

  // What an agent has started, for the chip's icons: agents it ran in a terminal
  // of their own (Herdr's), subagents (inner: Claude's, Codex's), processes and
  // scheduled prompts, its agents' included.
  subCounts(a) {
    const kids = (this.frame.terms ?? []).filter((k) => k.parent === a.address && k.state === "live");
    const agents = kids.filter((k) => this.frame.ag.some((x) => x.address === k.address) || k.program?.agent || isAgentProgram(k.agent)).length;
    const bg = this.bgTasks(a);
    const n = { inner: this.liveSubs(a).length + bg.csubs.length, agents, processes: kids.length - agents + bg.procs.length, crons: bg.crons.length };
    // And what its agents started, and theirs (all under its one chip).
    for (const k of kids) {
      if (!(this.frame.ag.some((x) => x.address === k.address) || k.program?.agent || isAgentProgram(k.agent))) continue;
      const m = this.subCounts(this.frame.ag.find((x) => x.address === k.address) ?? k);
      for (const key of Object.keys(n)) n[key] += m[key];
    }
    return n;
  }

  // One colour per agent that started something: the faint background of all it
  // started (subagents and processes, wherever they're listed) matches.
  // A link's colour (by the terminal at its near end, or "terminal|subagent"):
  // the first of LINK_COLORS no other live link has, kept while it lives (a
  // subagent's while its ssh does, so finished ones free theirs). All taken: the
  // least used.
  linkColor(address) {
    this.linkColors ??= {};
    if (!this.linkColors[address]) {
      const live = new Set((this.frame.terms ?? []).filter((k) => k.state === "live").map((k) => k.address));
      for (const k of Object.keys(this.linkColors))
        if (!live.has(k.split("|")[0]) || (k.includes("|") && !this.subSsh?.[k])) delete this.linkColors[k];
      const n = (c) => Object.values(this.linkColors).filter((x) => x === c).length;
      this.linkColors[address] = LINK_COLORS.reduce((a, c) => (n(c) < n(a) ? c : a));
    }
    return this.linkColors[address];
  }

  // The place a terminal counts as being in: its pane's space, else (something
  // an agent started) the most specific folder on its computer holding its own:
  // an open space's, or a pinned project's that has none (Not open: { id, folder,
  // machine, project }, its row then lifted into the list, lifted()).
  workSpace(address) {
    const p = this.frame.ps.find((x) => x.terminal === address);
    if (p) return this.frame.sp.find((s) => (s.tabs ?? []).some((tb) => tb.id === p.tab)) ?? null;
    const k = (this.frame.terms ?? []).find((x) => x.address === address);
    const m = address.includes("/") ? address.split("/")[0] : null, cwd = (k?.cwd ?? "").replace(/\/+$/, "");
    if (!cwd) return null;
    const open = this.frame.sp.filter((s) => (s.machine ?? null) === m && s.folder && inside(cwd, s.folder.replace(/\/+$/, "")));
    const closed = this.closedOn(m).filter((d) => inside(cwd, d)).map((d) => ({ id: m ? `r:${m}:${d}` : `c:${d}`, folder: d, machine: m, project: true }));
    return [...open, ...closed].sort((a, b) => b.folder.replace(/\/+$/, "").length - a.folder.replace(/\/+$/, "").length)[0] ?? null;
  }

  // Pinned projects with no open space, here (closedProjects) or on computer `m`
  // (its list, listedOn), once a render (this.frame.closed).
  closedOn(m) {
    return ((this.frame.closed ??= {})[m ?? ""] ??= m
      ? this.listedOn(m).filter((d) => !this.frame.sp.some((s) => s.machine === m && inside((s.folder ?? "").replace(/\/+$/, ""), d)))
      : this.closedProjects(this.frame.ps));
  }

  // Those of them something an agent started works in now (elsewhere than that
  // agent): listed with the spaces while it does, what works there under it.
  lifted(m) {
    const live = (this.frame.terms ?? []).filter((k) => k.parent && k.state === "live" && (k.address.includes("/") ? k.address.split("/")[0] : null) === m
      && !this.frame.ps.some((p) => p.terminal === k.address));
    // On another computer, also one an agent here (or its subagent) is ssh'd into.
    const home = m && this.remote[m]?.home;
    const full = (d) => (home ? d.replace(/^~(?=\/|$)/, home) : d);
    const sshed = !m ? [] : [
      ...Object.values(this.sshTo ?? {}).filter((e) => e.self && e.to === m && e.at === this.sshSeen),
      ...Object.entries(this.subSsh ?? {}).filter(([k, v]) => v.to === m && this.subs?.[k.split("|")[0]]?.some((x) => x.id === k.split("|")[1] && !x.done)).map(([, v]) => v),
    ].flatMap((e) => (e.paths ?? []).map(full));
    return this.closedOn(m).filter((d) => {
      const id = m ? `r:${m}:${d}` : `c:${d}`;
      return live.some((k) => this.workSpace(k.address)?.id === id && this.workSpace(k.parent)?.id !== id) || sshed.some((x) => inside(x, d));
    });
  }

  // A helper (hc run) goes by its `task` label, what the agent that started it wrote
  // (hc run --label task=...). Without one, an Antigravity helper goes by the title
  // agy gave it, since its --name is a short handle for hc commands, not something to
  // read: agy-info.py's title, else the terminal's (its database doesn't always have
  // one), but not agy's placeholder.
  helperTitle(address) {
    const k = (this.frame.terms ?? []).find((x) => x.address === address);
    if (k?.labels?.task) return k.labels.task;
    const i = this.info[address];
    if (i?.agent !== "antigravity") return null;
    const live = k && agentTask(k, k.cwd);
    return sentenceCase(i.title || (live === APP_NAMES.antigravity ? "" : live));
  }

  // A terminal by the name its row shows: an agent's (agentName), a plain
  // terminal's (termName), else what it was started as.
  nameOf(address) {
    const p = this.frame.ps.find((x) => x.terminal === address), a = this.frame.ag.find((x) => x.address === address);
    if (p) { const tab = this.frame.sp.flatMap((s) => s.tabs ?? []).find((tb) => tb.id === p.tab); return a ? agentName(a, tab, p.cwd) : this.termName(p, tab, ""); }
    const k = (this.frame.terms ?? []).find((x) => x.address === address);
    return this.helperTitle(address) || k?.name || (k && this.frame.ag.some((x) => x.address === address) && agentTask(k, k.cwd)) || appName(k) || address;
  }

  // Where a terminal is ssh'd to (findSsh), while it is: the computer's name.
  // `who`: "self" only its own (not its subagents'), a subagent's id only that
  // one's (in the last minute).
  sshedTo(address, who = null) {
    if (who && who !== "self") return this.subSsh?.[`${address}|${who}`]?.to ?? null;
    const e = this.sshTo?.[address];
    return e && e.at === this.sshSeen && (!who || e.self) ? e.to : null;
  }

  subCount(a) {
    const n = this.subCounts(a);
    return n.agents + n.inner + n.processes + n.crons;
  }

  // `nest`: how far in, for an agent's agents (one under another's row); `indent`
  // is the space's (a worktree's rows go in further). `rails`: where lines of
  // the agents above go on down past these rows (to their next item).
  subRows(a, p, t, indent, nest = 0, rails = []) {
    const kids = (this.frame.terms ?? []).filter((k) => k.parent === a.address && k.state === "live");
    const inner = this.liveSubs(a);
    const bg = this.bgTasks(a);
    const isAgent = (k) => Boolean(this.frame.ag.some((x) => x.address === k.address) || k.program?.agent || isAgentProgram(k.agent));
    // Agents, then subagents (Claude's, Codex's), then processes, then scheduled
    // prompts and wakeups (as on the chip).
    const items = [
      ...kids.filter(isAgent).map((k) => ({ type: "kid", k })),
      ...inner.map((x) => ({ type: "sub", x })),
      ...bg.csubs.map((x) => ({ type: "csub", x })),
      ...kids.filter((k) => !isAgent(k)).map((k) => ({ type: "kid", k })),
      ...[...bg.procs, ...bg.crons].map((x) => ({ type: "task", x })),
    ];
    if (!items.length) return [];
    // Its line's middle, from the row's left: under the agent's icon (status 12, a gap, half the line's 12).
    const x0 = indent + nest + 10 + 12 + 3 + 6;
    // One line each: its status (spinner, stop: under the agent's own), its line
    // with what it is on it, then the rest. Picked (Shift/Cmd/Ctrl+click), it
    // shows so, and closes with the other picks (rightClick, closeSubs).
    // `hover`: more to do on hovering it (a row with a link chip lights its other end).
    const row = (id, key, pick, hover = null) => {
      this.vis.push(key);
      this.subPicks.set(key, pick);
      return rails.reduce((el, x) => el.child(div().absolute().left(x - 0.75).top(0).bottom(0).w(1.5).bg(t.input)), h_flex().id(id).relative())
        .h(22).flex_none().pl(indent + nest + 10).pr(8).gap(3).items_center().rounded(7).text_size(12)
        .hover((s) => s.bg(t.hover))
        .when(this.sel.has(key), (el) => el.bg(t.accent + "38"))
        // Shown in place now (showSub): highlighted, as a focused row is.
        .when(!this.sel.has(key) && this.shownSub?.key === key && terminals().some((k) => k.address === this.shownSub.terminal && k.state === "live")
          && [undefined, this.shownSub.terminal].includes(focused()?.shown), (el) => el.bg(t.hover))
        .on_hover((h, cx) => { if (h) this.hoverSub = id; else if (this.hoverSub === id) this.hoverSub = null; hover?.(h); cx.notify(); })
        .on_mouse_down("right", (_e, cx) => { cx.stop_propagation(); if (this.sel.has(key) && this.sel.size > 1) this.rightClick(key, () => {}); });
    };
    const now = Date.now() / 1000;
    // How long it has run.
    const ranFor = (sec) => div().child(span(sec));
    // Context used, coloured as on an agent's row (infoLine).
    const ctx = (pct) => { pct = Math.round(pct ?? 0); return div().text_color(pct >= 80 ? t.ansi1 : pct >= 50 ? t.ansi3 : t.ansi2).child(`${pct}%`); };
    this.kidSeen ??= {}; // when a started terminal was first seen (if Herdr gives no created_ms)
    // Its name, then what goes beside it (details, → space).
    const body = (name, side = []) => h_flex().flex_1().min_w(0).gap(6).items_center()
      .child(h_flex().flex_1().min_w(0).child(name.min_w(0).truncate().line_height("15px"))).children(side);
    // Its details beside its name, dimmed, dotted (as an agent's: infoLine).
    const facts = (...parts) => h_flex().flex_none().items_center().text_size(11).text_color(t.dim)
      .children(dotted(parts.filter(Boolean).map((x) => (typeof x === "string" ? div().child(x) : x))));
    // A small button shown while the row is hovered.
    // Its press is marked so the row under it doesn't also open (subClick).
    const btn = (id, icon, fn) => h_flex().id(id).flex_none().w(12).h(12).justify_center().items_center().rounded(4).cursor_pointer()
      .text_color(t.foreground).hover((s) => s.bg(t.hover))
      .on_mouse_down("left", (_e, cx) => { this.btnAt = Date.now(); cx.stop_propagation(); })
      .on_click((_e, cx) => { cx.stop_propagation(); fn(cx); })
      .child(svg(icon).size(8));
    // Its status slot: hovered, a stop button; else a spinner while it works.
    // A pixel lower than the middle, in line with the text and logo.
    const status = (id, stop, working) => h_flex().w(12).pt(2).flex_none().justify_center()
      .when(this.hoverSub === id, (el) => el.child(btn(`stop-${id}`, "mods/over9k/stop.svg", stop)))
      .when(this.hoverSub !== id && Boolean(working), (el) => el.child(working));
    const spinner = () => svg("mods/workspace-chrome/spinner.svg").size(10).text_color(t.working).spin(900);
    // The line down from the agent above (under its icon's middle, as a
    // worktree's), with what each one is on it, small, the line broken around it:
    // BOT (an agent), SUB (a subagent), CPU (a process) or CLOCK (a scheduled
    // prompt or wakeup), as on the count chip. The last one's line ends at it.
    const lead = (icon, last) => v_flex().w(12).h(22).flex_none().items_center()
      .child(div().w(1.5).h(icon === SUB ? 5 : 6).flex_none().bg(t.input))
      .child(svg(icon).size(icon === SUB ? 12 : 9).flex_none().my(1).text_color(t.dim))
      .child(div().w(1.5).flex_1().when(!last, (el) => el.bg(t.input)));
    const pname = this.nameOf(a.address);
    // Beside the name, which agent it is (Claude, Codex, Pi: an agent can run
    // another kind); a process has only its icon on the line.
    const agentIcon = (prog) => progIcon(prog, t, 13);
    // Its agent, for what has no view of its own (a scheduled prompt, a Codex
    // subagent or command): its pane, or, with none (an agent's agent), shown in place.
    const toAgent = (e) => this.frame.ps.some((x) => x.terminal === a.address) ? this.goTo(p.pane) : this.showSub(a.address, false, pname, e);
    // Asking the agent that started it (Claude's and Codex's own take orders only from it).
    const ask = (text) => hc(["send", a.address, text]).catch(() => null);

    const kidRow = (k, last) => {
      // An agent in it: Herdr's agents list has it when it has a pane; else its terminal says.
      const ka = this.frame.ag.find((x) => x.address === k.address) ?? (isAgent(k) ? k : null);
      const kind = ka ? "agent" : "process";
      const name = this.helperTitle(k.address) || k.name || (ka && agentTask(ka, k.cwd)) || appName(ka) || k.program?.name || k.address;
      // The space it works in, only when that isn't where the agent that started it
      // is (workSpace): then a chip goes there.
      const home = this.workSpace(k.address);
      const where = home && home.id !== this.workSpace(a.address)?.id ? home : null;
      // Or on another computer (over ssh): the same link, to there (sshRows).
      const sshed = this.sshedTo(k.address);
      const c = (where || sshed) && this.linkColor(k.address);
      // An agent's details as on any agent row: model, context, time.
      const codex = ka && isCodex(ka) ? codexTitle(ka.title) : null;
      const raw = ka && (codex ? (codex.model ? codex : null) : isPi(ka) ? this.piInfo[ka.address] : this.info[ka.address]);
      const info = raw && this.withModel(raw, ka);
      // Herdr's start time when it gives one, else when first seen here.
      const ran = ranFor(now - (k.created_ms ? k.created_ms / 1000 : (this.kidSeen[k.address] ??= now)));
      const id = `kid-${k.address}`, key = `k:${k.address}`;
      // Hovered, with a chip: its row in that space lights up.
      const hover = where || sshed ? (h) => { if (h) this.hoverLink = { color: c, visitor: k.address }; else if (this.hoverLink?.visitor === k.address) this.hoverLink = null; } : null;
      return lit(row(id, key, { kind: "terminal", terminal: k.address }, hover), (this.hoverLink?.source === k.address || (c && this.hoverLink?.parent === a.address)) && { color: c })
        .on_mouse_down("left", (e, cx) => this.subClick(e, cx, key, () => this.showSub(k.address, false, name, e)))
        .child(status(id, () => run("terminal.kill", { terminal: k.address }), ka && this.mark(ka, t, 10)))
        .child(lead(kind === "process" ? CPU : BOT, last))
        .when(Boolean(ka), (el) => el.child(agentIcon((ka ?? k).program)))
        .child(body(div().text_color(t.muted).child(name), [
          facts(info?.model && modelName(info.model), info && ctx(info.context), ran),
          // "→ space" (a click goes to that space).
          (where || sshed) && linkChip(t, `kid-chip-${k.address}`, { dir: "out", icon: kind === "process" ? CPU : BOT, color: c, to: !where && sshed }),
        ].filter(Boolean)));
    };

    // A Claude subagent: what it's doing, "waiting" once it's been quiet a minute
    // (on its own background work), its type, tokens used and how long it has run.
    // A click: its live transcript (viewSubagent).
    const subRow = (x, last) => {
      const id = `sub-${a.address}-${x.id}`, key = `x:${a.address}|sub|${x.id}`;
      const stop = `Stop your subagent "${x.desc}" (agent id ${x.id.replace(/^agent-/, "")}) with TaskStop, then tell me in one line.`;
      // SSH'd to another computer (findSsh): a chip saying where, linked like the agent's.
      const link = `${a.address}|${x.id}`, sshed = this.sshedTo(a.address, x.id), c = sshed && this.linkColor(link), o = this.frame.options;
      const hover = sshed ? (h) => { if (h) this.hoverLink = { color: c, visitor: link }; else if (this.hoverLink?.visitor === link) this.hoverLink = null; } : null;
      return lit(row(id, key, { kind: "ask", agent: a.address, text: `subagent "${x.desc}" (agent id ${x.id.replace(/^agent-/, "")}): TaskStop` }, hover), (this.hoverLink?.source === link || (sshed && this.hoverLink?.parent === a.address)) && { color: c })
        .on_mouse_down("left", (e, cx) => this.subClick(e, cx, key, () => this.viewSubagent(a.address, x.id, cx, x.desc || "Subagent", e)))
        .child(status(id, () => ask(stop), spinner()))
        .child(lead(SUB, last))
        .child(agentIcon(a.program))
        .child(body(div().text_color(t.muted).child(x.desc || "Subagent"),
          [facts(now - x.at > 60 && "waiting", o.subModel && x.model && modelName(x.model), o.subEffort && effortName(x.effort),
            x.type && x.type.toLowerCase() !== "general-purpose" && x.type.toLowerCase(), o.subContext && x.tokens > 0 && tokensK(x.tokens), o.subTime && x.start && ranFor(now - x.start)),
            sshed && linkChip(t, `sub-chip-${a.address}-${x.id}`, { dir: "out", icon: SUB, color: c, to: sshed })].filter(Boolean)));
    };

    // A Codex agent's own subagent (codex.sh): its nickname and task, its role and
    // how long it has run. Codex shows it (its agents list), so a click goes there.
    const csubRow = (x, last) => {
      const id = `csub-${a.address}-${x.id}`, key = `x:${a.address}|csub|${x.id}`;
      return row(id, key, { kind: "ask", agent: a.address, text: `subagent "${x.desc}": close it` })
        .on_mouse_down("left", (e, cx) => this.subClick(e, cx, key, () => toAgent(e)))
        .child(status(id, () => ask(`Close your subagent "${x.desc}", then tell me in one line.`), spinner()))
        .child(lead(SUB, last))
        .child(agentIcon(a.program))
        .child(body(div().text_color(t.muted).child(x.desc || "Subagent"), [facts(x.schedule !== "subagent" && x.schedule, x.start && ranFor(now - x.start))]));
    };

    // A Claude Code session's background shell, monitor, scheduled prompt or
    // wakeup, or a Codex agent's running command. Stop: Claude's own take orders
    // only from their session, so it's asked; a Codex command is a process here,
    // so it's ended. A click: a shell's or monitor's output, live; anything else,
    // its agent (where it runs, or where Codex's /ps shows it).
    const taskRow = (x, last) => {
      const id = `task-${a.address}-${x.id}`, key = `x:${a.address}|${x.kind}|${x.id}`;
      const cron = x.kind === "cron" || x.kind === "wakeup";
      const order = x.kind === "cron" ? `scheduled prompt ${x.id}: CronDelete`
        : x.kind === "wakeup" ? "scheduled wakeup: ScheduleWakeup with stop: true"
        : `background ${x.kind} "${x.desc}" (task id ${x.id}): TaskStop`;
      const stop = x.kind === "cshell" ? () => exec("kill", [x.id]).catch(() => null) : () => ask(`Stop your ${order}, then tell me in one line.`);
      // Beside its name: a scheduled prompt's schedule, a wakeup's time to go, a
      // command's kind and how long it has run.
      const what = x.kind === "cron" ? facts(short(x.schedule ?? "").replace(/^./, (ch) => ch.toLowerCase()))
        : x.kind === "wakeup" ? facts("wakeup", span(Math.max(0, +x.schedule - now)))
        : facts(x.kind === "cshell" ? "command" : x.kind, x.start && ranFor(now - x.start));
      return row(id, key, x.kind === "cshell" ? { kind: "pid", pid: x.id } : { kind: "ask", agent: a.address, text: order })
        .on_mouse_down("left", (e, cx) => this.subClick(e, cx, key, () => x.output ? this.view(x.output, a.address, "output-view.sh", [x.output, x.desc], cx, x.desc, e)
          // A scheduled prompt or wakeup: itself, in place (note-view.sh): when, whose, what.
          : cron ? this.view(`note-${x.kind}-${x.id}`, a.address, "note-view.sh", [
            x.kind === "wakeup" ? "Wakeup" : "Scheduled prompt",
            x.kind === "wakeup" ? `In ${span(Math.max(0, +x.schedule - Date.now() / 1000))}` : short(x.schedule ?? ""),
            `For ${pname}`, "", x.kind === "wakeup" ? `Why: ${x.desc}` : x.desc], cx, x.desc, e)
          : toAgent(e)))
        .child(status(id, stop, null))
        .child(lead(cron ? CLOCK : CPU, last))
        .child(body(div().text_color(t.muted).child(x.desc || (cron ? "Scheduled prompt" : "Background command")), [what]));
    };

    return items.flatMap((it, i) => {
      const last = i === items.length - 1;
      if (it.type === "sub") return [subRow(it.x, last)];
      if (it.type === "csub") return [csubRow(it.x, last)];
      if (it.type === "task") return [taskRow(it.x, last)];
      // An agent it started: what that one started under it, one step in (its line
      // under that agent's icon), this line going on past them unless it was the
      // last. Always shown: the top agent's chip folds the lot and counts it all.
      const kidEls = [kidRow(it.k, last)];
      if (!isAgent(it.k)) return kidEls;
      const ka = this.frame.ag.find((x) => x.address === it.k.address) ?? it.k;
      return [...kidEls, ...this.subRows(ka, this.frame.ps.find((x) => x.terminal === it.k.address) ?? p, t, indent, nest + 16, last ? rails : [...rails, x0])];
    });
  }


  // A plain terminal's name: its tab's when someone renamed it, else the last
  // command run in it (readCommands), else "New CLI". An agent that hasn't
  // reported yet (Codex's update prompt) already goes by its agent name.
  termName(p, tab, key) {
    if (p.program?.agent) return agentName(p, tab, p.cwd);
    if (!/^(\d+|t[0-9a-z]+)$/.test(tab.name) && tab.name !== p.program?.name) return tab.name;
    // Started straight on an ssh (no prompt to read): that command (findSsh).
    const command = this.lastCmd[p.terminal] ?? this.titleCommand(p.title, p.program?.name ?? "") ?? this.sshTo?.[p.terminal]?.cmd;
    if (command) return command.length > 48 ? `${command.slice(0, 47)}\u2026` : command;
    return "New CLI";
  }

  // Each shell's screen (here or on a connected computer), for its last prompt line. Only what changed is shared.
  readCommands(cx) {
    if (this.reading || !this.frame) return;
    // Here, and on other computers that are connected (read over Herdr's link).
    const up = new Set(this.machines.filter((m) => m.state === "connected").map((m) => m.name));
    const reachable = new Set(this.frame.sp.filter((s) => !s.machine || up.has(s.machine)).flatMap((s) => (s.tabs ?? []).map((t) => t.id)));
    const shells = this.frame.ps.filter((p) => p.terminal && reachable.has(p.tab) && !this.frame.byPane.get(p.pane));
    if (!shells.length) return;
    this.reading = true;
    cx.spawn(async (cx) => {
      let changed = false;
      for (const p of shells) {
        const r = await hc(["read", p.terminal, "--lines", "200"]).catch(() => null);
        const lines = (r?.stdout ?? "").split("\n").map((l) => /^\s*\u276f\s+(\S.*?)\s*$/.exec(l)?.[1]).filter(Boolean);
        const last = lines[lines.length - 1];
        if (last && last !== this.lastCmd[p.terminal]) { this.lastCmd[p.terminal] = last; changed = true; }
      }
      const live = new Set(this.frame.ps.map((p) => p.terminal));
      for (const t of Object.keys(this.lastCmd)) if (!live.has(t)) { delete this.lastCmd[t]; changed = true; }
      if (changed) setShared("terminals.last", { ...this.lastCmd });
      this.reading = false;
      if (changed) cx.notify();
    });
  }

  // Every terminal of the space picked one by one: closing them closes it too.
  allPicked(w) {
    if (!this.sel.size) return false;
    const tabs = new Set((w.tabs ?? []).map((x) => x.id));
    const mine = this.frame.ps.filter((p) => p.terminal && tabs.has(p.tab));
    return mine.length > 0 && mine.every((p) => this.sel.has(`p:${p.pane}`));
  }

  // The command a shell's title names, if any: Pure's "folder: cmd - prog" while
  // it runs; "folder - fish" names none; any other title is taken as the command.
  titleCommand(title, shell) {
    title = (title ?? "").trim();
    const running = /^[^:]*: (.+) [-\u2014\u2013] \S+$/.exec(title);
    if (running) return running[1].trim();
    if (!title || title === shell || title.endsWith(` ${shell}`)) return null;
    // "user@host:~/folder", as many shells title themselves (another computer's): names nothing.
    if (/^[^@\s]+@[^:\s]+:\S*$/.test(title)) return null;
    return title;
  }

  hasTerms(key) {
    return Boolean(this.frame.groups.get(key)?.length);
  }

  // Shift+click picks every row from the last one clicked to this one (in the
  // order they're shown); Cmd/Meta or Ctrl+click adds or drops one row.
  pick(key, cx, e) {
    const order = this.visible ?? [];
    const from = order.indexOf(this.anchor), to = order.indexOf(key);
    if (e?.modifiers?.shift && from >= 0 && to >= 0) {
      if (!(e.modifiers.platform || e.modifiers.control)) this.sel.clear();
      // Terminal to terminal takes only the terminals between (not the spaces
      // they pass, which would close whole spaces); space to space only spaces.
      const term = (k) => /^[pkx]:/.test(k);
      const same = term(this.anchor) === term(key);
      order.slice(Math.min(from, to), Math.max(from, to) + 1).filter((k) => !same || term(k) === term(key)).forEach((k) => this.sel.add(k));
    } else {
      this.sel.has(key) ? this.sel.delete(key) : this.sel.add(key);
      this.anchor = key;
    }
    cx.notify();
  }

  // Right-click on a picked row: one menu for all the picks (over9k-menu's
  // "selection": close them, unpin the spaces among them). On any other row,
  // the picks go and that row's own menu opens, as on a row that's the only pick.
  rightClick(key, own) {
    if (!this.sel.has(key) || this.sel.size === 1) { this.sel.clear(); return own(); }
    const picked = { spaces: [], panes: [], folders: [] };
    const listed = new Set(this.projects), trim = (d) => (d ?? "").replace(/\/+$/, "");
    for (const k of this.sel) {
      const v = k.slice(2);
      if (k.startsWith("s:")) {
        picked.spaces.push(v);
        const f = trim(this.frame.sp.find((s) => s.id === v)?.folder);
        if (listed.has(f)) picked.folders.push(f);
      } else if (k.startsWith("p:")) picked.panes.push(v);
      else if (k.startsWith("d:")) {
        picked.panes.push(...(this.frame.groups.get(k) ?? []).map((x) => x.p.pane));
        if (listed.has(v)) picked.folders.push(v);
      } else if (k.startsWith("c:")) picked.folders.push(v);
      else if (this.subPicks.has(k)) (picked.subs ??= []).push(this.subPicks.get(k));
    }
    // The picks stay shown while the menu is open (and after Esc); closed or
    // unpinned rows drop out of them by themselves.
    openOverlay({ mod: "over9k-menu", kind: "popup", width: 240, height: 120, props: { tab: "selection", target: picked } });
  }

  // A spinner while working, a dot when done (or waiting on you); nothing when idle.
  // `size`: the spinner's (a sub-row's is smaller).
  mark(a, t, size = 12) {
    if (a.status === "working") return svg("mods/workspace-chrome/spinner.svg").size(size).text_color(t.working).spin(900);
    if (a.status === "blocked") return div().size(7).rounded(4).bg(t.blocked);
    if (a.status === "done") return div().size(7).rounded(4).bg(t.done ?? t.accent);
    return div();
  }

  // Folders set up for an agent (MARKED), but not home, /tmp, or a folder that
  // only holds projects (~/Code). The menu reads them (shared) to offer Hide or Pin.
  scanProjects(cx) {
    cx.spawn(async cx => {
      try {
        const set = shared("sidebar.options")?.locations ?? {};
        const full = (d) => d.replace(/^~(?=\/|$)/, homeDir());
        const named = set.projects ? null : (await exec("sh", ["-c", PROJECTS_FROM_RULES]).catch(() => null))?.stdout.trim();
        const where = { chats: set.chats ? full(set.chats) : homeDir(), projects: set.projects ? full(set.projects) : named ? full(named) : homeDir() };
        const code = [where.projects];
        // Shared for handoff.sh, the + menu's scan and over9k-options.
        if (JSON.stringify(where) !== JSON.stringify(shared("over9k.locations"))) setShared("over9k.locations", where);
        if (JSON.stringify(code) !== JSON.stringify(shared("projects.codeFolders"))) setShared("projects.codeFolders", code);
        const r = await exec("sh", ["-c", MARKED, "sh", ...code]);
        if (r.code !== 0) return;
        const all = r.stdout.split("\n").filter(Boolean).map((d) => d.replace(/\/+$/, ""));
        const dirs = all.filter((d) => d !== homeDir() && !inside(d, "/tmp") && !SKIP.has(base(d)) && !all.some((o) => o !== d && inside(o, d)));
        if (JSON.stringify(dirs) !== JSON.stringify(this.auto)) {
          this.auto = dirs;
          setShared("projects.auto", dirs);
          cx.notify();
        }
        this.firstRun();
        this.autoPin(dirs);
      } catch {}
    });
  }

  // The same on other computers, run there over SSH: their Projects (set, or the
  // first usual folder there) and the projects in it. Kept (localStorage) and
  // looked for again only when a computer connects again or its folders change;
  // never while it's away. `only`: just these computers.
  scanRemote(cx, only = null) {
    const set = shared("sidebar.options")?.computers ?? {};
    const up = this.machines.filter((m) => m.state === "connected").map((m) => m.name)
      .filter((m) => (only ? only.includes(m) : !this.remote[m] || JSON.stringify(set[m] ?? {}) !== JSON.stringify(this.remote[m].asked ?? {})));
    if (!up.length) return;
    cx.spawn(async (cx) => {
      const set = shared("sidebar.options")?.computers ?? {};
      const found = {};
      for (const m of up) {
        try {
          const own = set[m] ?? {};
          const named = own.projects ? null : (await exec("sh", ["-c", PROJECTS_FROM_RULES], { on: m }).catch(() => null))?.stdout.trim();
          const where = { chats: own.chats ?? "~", projects: own.projects ?? (named || "~") };
          const r = await exec("sh", ["-c", MARKED, "sh", where.projects], { on: m });
          const home = (await exec("sh", ["-c", "printf %s \"$HOME\""], { on: m }))?.stdout ?? "";
          const all = (r?.stdout ?? "").split("\n").filter(Boolean).map((d) => d.replace(/\/+$/, ""));
          const dirs = all.filter((d) => d !== home && !inside(d, "/tmp") && !SKIP.has(base(d)) && !all.some((o) => o !== d && inside(o, d)));
          found[m] = { ...where, home, dirs, asked: own };
          this.autoPin(dirs, m);
        } catch {}
      }
      const all = { ...this.remote, ...found };
      const autoOn = Object.fromEntries(Object.entries(all).map(([m, f]) => [m, f.dirs ?? []]));
      if (JSON.stringify(autoOn) !== JSON.stringify(shared("projects.autoOn") ?? {})) setShared("projects.autoOn", autoOn);
      const shown = Object.fromEntries(Object.entries(all).map(([m, f]) => [m, { chats: f.chats, projects: f.projects }]));
      if (JSON.stringify(shown) !== JSON.stringify(shared("over9k.remoteLocations") ?? {})) setShared("over9k.remoteLocations", shown);
      if (JSON.stringify(all) !== JSON.stringify(this.remote)) {
        this.remote = all;
        localStorage.setItem("remote.projects", JSON.stringify(all));
        cx.notify();
      }
    });
  }

  // The project list: marked folders unless hidden, and pinned ones, by name.
  // Another computer's list, as listed() is this one's: what was found there
  // (kept from its last scan) less what's unpinned, plus what's pinned.
  listedOn(m) {
    return [...new Set(shared("projects.on")?.[m]?.pinned ?? [])].sort((a, b) => base(a).localeCompare(base(b), undefined, { sensitivity: "base" }));
  }

  // The list is what's pinned (per computer, listedOn); what the scans find
  // only gets pinned by the setup (over9k-options), the + menu, or "Keep sidebar
  // up to date" (autoPin). Open spaces show whatever they are.
  listed() {
    return [...new Set(shared("projects.pinned") ?? [])].sort((a, b) => base(a).localeCompare(base(b), undefined, { sensitivity: "base" }));
  }

  // "Keep sidebar up to date" (over9k-options): what a scan found that's new
  // (not pinned, and not unpinned by hand) gets pinned. m: another computer.
  autoPin(found, m = null) {
    if (!shared("sidebar.options")?.keepUpToDate) return;
    const on = m ? shared("projects.on")?.[m] ?? {} : null;
    const pinned = new Set(m ? on.pinned ?? [] : shared("projects.pinned") ?? []);
    const off = new Set(m ? [...(on.unpinned ?? []), ...(on.hidden ?? [])] : [...(shared("projects.unpinned") ?? []), ...(shared("projects.hidden") ?? [])]);
    const add = found.filter((d) => !pinned.has(d) && !off.has(d));
    if (!add.length) return;
    add.forEach((d) => pinned.add(d));
    if (m) setShared("projects.on", { ...(shared("projects.on") ?? {}), [m]: { ...on, pinned: [...pinned] } });
    else setShared("projects.pinned", [...pinned]);
  }

  // Pins folders (as over9k-menu's Pin: not hidden, not unpinned any more).
  pinHanded(dirs, m = null) {
    const all = shared("projects.on") ?? {}, on = m ? all[m] ?? {} : null;
    const pinned = new Set(m ? on.pinned ?? [] : shared("projects.pinned") ?? []);
    const hidden = new Set(m ? on.hidden ?? [] : shared("projects.hidden") ?? []);
    const unpinned = new Set(m ? on.unpinned ?? [] : shared("projects.unpinned") ?? []);
    for (const d of dirs) { pinned.add(d); hidden.delete(d); unpinned.delete(d); }
    if (m) return setShared("projects.on", { ...all, [m]: { ...on, pinned: [...pinned], hidden: [...hidden], unpinned: [...unpinned] } });
    setShared("projects.pinned", [...pinned]);
    setShared("projects.hidden", [...hidden]);
    setShared("projects.unpinned", [...unpinned]);
  }

  // The first time this version runs: everything the list showed before
  // (found less unpinned, plus pinned, on every computer) becomes pinned, so
  // nothing goes; then Options opens in setup mode (over9k-options).
  firstRun() {
    if (shared("over9k.setupDone")) return;
    const hidden = new Set(shared("projects.hidden") ?? []);
    setShared("projects.pinned", [...new Set([...(shared("projects.pinned") ?? []), ...this.auto.filter((d) => !hidden.has(d))])]);
    const on = { ...(shared("projects.on") ?? {}) };
    for (const [m, f] of Object.entries(this.remote ?? {})) {
      const h = new Set(on[m]?.hidden ?? []);
      on[m] = { ...(on[m] ?? {}), pinned: [...new Set([...(on[m]?.pinned ?? []), ...(f.dirs ?? []).filter((d) => !h.has(d))])] };
    }
    setShared("projects.on", on);
    setShared("over9k.setupDone", true);
    openOverlay({ mod: "over9k-options", kind: "dialog", width: 560, height: 600, props: { setup: true } });
  }

  // Terminals' folders whose repo top isn't known yet: looked up one by one.
  resolveTops(cx) {
    const want = [...(this.wantTops ?? [])].filter((c) => !this.tops.has(c));
    if (!want.length || this.resolving) return;
    this.resolving = true;
    cx.spawn(async (cx) => {
      for (const c of want) {
        const r = await exec("git", ["rev-parse", "--show-toplevel"], { cwd: c }).catch(() => null);
        this.tops.set(c, r?.code === 0 ? r.stdout.trim() : c);
      }
      this.resolving = false;
      cx.notify();
    });
  }

  // Projects with no space on this computer made in them.
  spaceless(sp) {
    const local = sp.filter((s) => !s.machine);
    return this.projects.filter((d) => !local.some((s) => inside(s.folder, d)));
  }

  // Folders with no space but a terminal in them now (it cd'd there), with those
  // terminals under them: a listed project in its color after the spaces, any
  // other folder in plain white right after ~ (right-click to pin it).
  looseRows(t, collapsed, projects) {
    const listed = new Set(this.projects);
    return this.loose.filter((d) => listed.has(d) === projects).flatMap((dir) => {
      const key = `d:${dir}`, name = this.alias(dir), g = this.git[JSON.stringify([null, dir])] ?? null;
      this.vis.push(key);
      const folded = this.agentsFolded.has(key);
      const row = h_flex().id(`loose-${name}`).h(collapsed ? 26 : 30).flex_none().px(collapsed ? 0 : 8).gap(9).items_center().rounded(8)
        .when(collapsed, (el) => el.justify_center())
        .hover((s) => s.bg(t.hover))
        .when(this.sel.has(key), (el) => el.bg(t.accent + "38"))
        .on_hover((on, cx) => { if (on) this.hoverSpace = key; else if (this.hoverSpace === key) this.hoverSpace = null; cx.notify(); })
        .on_mouse_down("right", () => this.rightClick(key, () => this.folderMenu(dir)))
        .on_click((e, cx) => {
          if (multi(e)) return this.pick(key, cx, e);
          this.sel.clear();
          this.anchor = key;
          folded ? this.agentsFolded.delete(key) : this.agentsFolded.add(key);
          localStorage.setItem("agents.folded", JSON.stringify([...this.agentsFolded]));
          cx.notify();
        })
        .when(collapsed, (el) => el.text_color(projects ? MARK[hue(name)] : t.foreground).child([...name][0]?.toUpperCase() ?? "?"))
        .when(!collapsed, (el) => el
          .child(div().flex_shrink(0).max_w(150).truncate().text_color(projects ? MARK[hue(name)] : t.foreground).child(name))
          .when(Boolean(g?.web) && this.frame.options.github, (el) => el.child(this.ghLink(g, t)))
          .when(Boolean(g), (el) => el.children(this.counts(g, t, (cx) => this.showChanges({ name, folder: dir }, cx))))
          .child(h_flex().w(FOLD).flex_none().items_center().justify_center()
            .child(svg(`mods/workspace-chrome/chevron-${folded ? "right" : "down"}.svg`).size(10).text_color(t.dim).opacity(this.hoverSpace === key ? 1 : 0)))
          .child(this.tail(g, null, name, t, this.hoverSpace === key && dir))
          .children(this.closedBot(dir, t, null, key))
          .child(this.plusButton(`loose-add-${name}`, this.hoverSpace === key, t, () => this.openProject(dir))));
      return [row, ...(collapsed || folded ? [] : this.termRows(key, t))];
    });
  }

  // Projects with no space on this computer made there or with a terminal in it now.
  // `ps`: panes(), read once by the caller.
  closedProjects(ps) {
    const local = this.frame.sp.filter(s => !s.machine);
    const tabs = new Set(local.flatMap(s => (s.tabs ?? []).map(t => t.id)));
    const cwds = ps.filter(p => tabs.has(p.tab)).map(p => p.cwd);
    return this.projects.filter(d => !local.some(s => inside(s.folder, d)) && !cwds.some(c => inside(c, d)));
  }

  // A project's name: the one given with Rename (projects.names), else its folder's.
  // A space's name: another computer's home is "~" there too (Herdr would call
  // it after the folder), and its renamed projects go by their names.
  title(w) {
    if (!w.machine || w.named) return title(w);
    const r = this.remote[w.machine], f = (w.folder ?? "").replace(/\/+$/, "");
    if (r?.home && (f === r.home || !f)) return "~";
    return shared("projects.on")?.[w.machine]?.names?.[f] || w.name;
  }

  alias(dir, m = null) {
    const names = m ? shared("projects.on")?.[m]?.names : this.frame.names;
    return (names ?? {})[dir] || base(dir) || dir;
  }

  // A + that shows while the pointer is on its row.
  plusButton(id, shown, t, fn) {
    const slot = h_flex().w(ADD).flex_none().justify_center();
    if (!shown) return slot;
    return slot.child(h_flex().id(id).size(18).items_center().justify_center().rounded(5).cursor_pointer().text_color(t.dim)
      .hover((s) => s.bg(t.hover).text_color(t.foreground))
      .on_mouse_down("left", (_e, cx) => cx.stop_propagation())
      .on_click((_e, cx) => { cx.stop_propagation(); fn(); })
      .child(svg("mods/workspace-chrome/plus.svg").size(12)));
  }

  // The x on a hovered terminal row, in its status slot.
  closeButton(id, t, fn) {
    return h_flex().id(id).size(16).items_center().justify_center().rounded(4).cursor_pointer().text_color(t.dim)
      .hover((s) => s.bg(t.hover).text_color(t.foreground))
      .on_mouse_down("left", (_e, cx) => cx.stop_propagation())
      .on_click((_e, cx) => { cx.stop_propagation(); fn(); })
      .child(svg("mods/pane/close.svg").size(11));
  }

  // The + menu for a space not open yet: what's picked there opens it.
  openProject(dir, m = null) {
    openOverlay({ mod: "over9k-new-menu", kind: "popup", width: 340, height: 640, props: { folder: dir, name: this.alias(dir, m), ...(m ? { machine: m } : {}) } });
  }

  // A space not open: a click picks it (Shift/Cmd too, to unpin several), a
  // double-click opens it with a terminal; its +
  // (on hover) opens the + menu, where what's picked opens it.
  // On another computer (m): no git counts or menu (both are this computer's);
  // opening makes its space there.
  closedRow(dir, t, collapsed, m = null) {
    const name = this.alias(dir, m);
    const key = m ? `r:${m}:${dir}` : `c:${dir}`;
    if (!m) this.vis.push(key);
    return h_flex().id(`project-${name}`).h(collapsed ? 26 : 30).flex_none().px(collapsed ? 0 : 8).gap(9).items_center().rounded(8)
      .when(collapsed, el => el.justify_center())
      .text_color(t.muted).hover(s => s.bg(t.hover).text_color(t.foreground))
      .when(this.sel.has(key), (el) => el.bg(t.accent + "38"))
      .on_hover((on, cx) => { if (on) this.hoverSpace = key; else if (this.hoverSpace === key) this.hoverSpace = null; cx.notify(); })
      .on_click((e, cx) => {
        if (multi(e) && !m) return this.pick(key, cx, e);
        // Twice: open it, with a terminal, as the + menu's Terminal does.
        if (e.click_count === 2) {
          // Its space, made once: a second double-click shows the one there.
          this.sel.clear();
          const there = spaces().find((s) => (s.machine ?? null) === m && (s.folder ?? "").replace(/\/+$/, "") === dir);
          return there ? run("space.select", { id: there.id }) : run("space.new", { name, folder: dir, machine: m ?? "" });
        }
        this.sel = new Set([key]);
        this.anchor = key;
        cx.notify();
      })
      .on_mouse_down("right", () => (m ? this.folderMenu(dir, m) : this.rightClick(`c:${dir}`, () => this.folderMenu(dir))))
      .when(collapsed, el => el.child([...name][0]?.toUpperCase() ?? "?"))
      .when(!collapsed, el => (g => el
        .child(div().flex_shrink(0).max_w(150).truncate().child(name))
        .when(Boolean(g?.web) && this.frame.options.github, el => el.child(this.ghLink(g, t)))
        .when(Boolean(g), el => el.children(this.counts(g, t, (cx) => this.showChanges({ name, folder: dir }, cx))))
        .child(this.tail(g, null, name, t, this.hoverSpace === key && dir))
        .children(this.closedBot(dir, t, m, key))
        .child(this.plusButton(`open-${m ?? ""}-${name}`, this.hoverSpace === key, t, () => this.openProject(dir, m)))
        )(this.git[JSON.stringify([m, dir])]));
  }

  // One look at a time, each place once however often it was asked for meanwhile.
  refreshGit(keys, cx) {
    for (const k of keys) this.pending.add(k);
    if (this.refreshing) return;
    this.refreshing = true;
    cx.spawn(async (cx) => {
      while (this.pending.size) {
        const keys = [...this.pending];
        this.pending.clear();
        for (const key of keys) await this.check(key, cx);
      }
      const used = new Set(Object.values(this.git).filter(Boolean).map((g) => JSON.parse(g.repo)).filter(([on]) => !on).map(([, repo]) => repo));
      for (const repo of this.watching) if (!used.has(repo)) this.watching.delete(repo);
      this.refreshing = false;
      cx.notify();
    });
  }

  // One place's git: branch, ahead/behind, its repo.
  async check(key, cx) {
    const [on, cwd] = JSON.parse(key);
    this.checked[key] = Date.now();
    this.unsure.delete(key);
    try {
      // No optional locks: a status that touched the index would wake the watch again.
      // Writes nothing under .git (index lock, fsmonitor cookie): watch() would wake on it.
      const r = await exec("git", ["--no-optional-locks", "-c", "core.fsmonitor=false", "status", "--porcelain=v2", "--branch", "--untracked-files=all"], { cwd, on });
      if (r.code !== 0) {
        // Only git's own "no" is remembered as no repo; anything else is asked again.
        if (!/not a git repository/i.test(r.stderr)) this.unsure.add(key);
        this.git[key] = null;
        return;
      }
      // The repo's own .git folder names it; a worktree's top differs from it.
      const top = await exec("git", ["rev-parse", "--show-toplevel"], { cwd, on });
      const common = await exec("git", ["rev-parse", "--path-format=absolute", "--git-common-dir"], { cwd, on });
      const repo = common.stdout.trim();
      const name = repo.endsWith("/.git") ? base(repo.slice(0, -5)) : base(repo).replace(/\.git$/, "");
      const info = { name, branch: null, ahead: 0, behind: 0, dirty: 0, web: null, slug: null, top: top.stdout.trim(), repo: JSON.stringify([on, repo]), linked: repo !== `${top.stdout.trim()}/.git` };
      for (const line of r.stdout.split("\n")) {
        if (line && !line.startsWith("#")) info.dirty++;
        else if (line.startsWith("# branch.head ")) info.branch = line.slice(14);
        else if (line.startsWith("# branch.ab ")) {
          const [a, b] = line.slice(12).split(" ");
          info.ahead = Math.abs(parseInt(a, 10)) || 0;
          info.behind = Math.abs(parseInt(b, 10)) || 0;
        }
      }
      // A GitHub remote (origin first) becomes a link to the repo's page.
      const urls = (await exec("git", ["remote", "-v"], { cwd, on })).stdout.split("\n")
        .map((l) => l.split(/\s+/)).filter(([n, , kind]) => kind === "(fetch)").sort(([a], [b]) => (b === "origin") - (a === "origin"));
      for (const [, url] of urls) {
        const m = /github\.com[:/]+([^/]+\/[^/]+?)(?:\.git)?\/?$/.exec(url ?? "");
        if (m) { info.web = `https://github.com/${m[1]}`; info.slug = m[1]; break; }
      }
      this.git[key] = info;
      if (!on) this.watch(repo, cx);
    } catch {
      // Couldn't ask (the machine is away): keep what it showed, look again later.
      this.git[key] ??= null;
      this.unsure.add(key);
    }
  }

  watch(repo, cx) {
    if (this.watching.has(repo)) return;
    this.watching.add(repo);
    cx.spawn(async (cx) => {
      try {
        while (this.watching.has(repo)) {
          await watchFolder(repo);
          const mine = JSON.stringify([null, repo]);
          if (this.watching.has(repo)) this.refreshGit(Object.keys(this.git).filter((k) => this.git[k]?.repo === mine), cx);
        }
      } catch { this.watching.delete(repo); }
    });
  }

  // Right-click on a row with no space: open it, pin it, hide it.
  folderMenu(folder, m = null) {
    openOverlay({ mod: "over9k-menu", kind: "popup", width: 200, height: 191, props: { tab: "project", target: { folder, name: this.alias(folder, m), ...(m ? { machine: m } : {}) } } });
  }

  menu(w) {
    // A popup is as tall as its items; height is only the most.
    openOverlay({ mod: "over9k-menu", kind: "popup", width: 200, height: 291, props: { tab: "space", target: { id: w.id } } });
  }

  // Spaces in order, each worktree space moved under its main checkout's.
  ordered() {
    const { sp, ps } = this.frame;
    const ready = (w) => this.shown.has(w.id) || where(w, ps) in this.git || Date.now() - (this.born[w.id] ??= Date.now()) > 1500;
    for (const w of sp) if (!this.shown.has(w.id) && ready(w)) this.shown.add(w.id);
    const list = sp.map((w, i) => ({ w, i, g: this.git[where(w, ps)] ?? null })).filter((r) => this.shown.has(r.w.id));
    const mains = new Set(list.filter((r) => r.g && !r.g.linked).map((r) => r.g.repo));
    const nested = (r) => r.g?.linked && mains.has(r.g.repo);
    const out = [];
    const placed = new Set(); // repos whose worktrees are listed (under the first of its spaces)
    for (const r of list) {
      if (nested(r)) continue;
      out.push({ ...r, tree: null });
      if (!r.g || r.g.linked || placed.has(r.g.repo)) continue;
      placed.add(r.g.repo);
      const kids = list.filter((k) => nested(k) && k.g.repo === r.g.repo);
      kids.forEach((k, n) => out.push({ ...k, tree: n === kids.length - 1 ? "└─" : "├─", under: r.w.id }));
    }
    return out;
  }

  // Whether an agent (a pane's, or none) shows under the filter.
  passes(a) {
    if (this.section) return a?.status === this.section; // drawing one of Agents' sections
    return !this.filter || Boolean(a && FILTERS.find((f) => f.id === this.filter)?.has(a.status));
  }

  // A space with an agent the filter lets through.
  spaceMatches(id) {
    return (this.frame.groups.get(id) ?? []).some(({ p }) => this.passes(this.frame.byPane.get(p.pane)));
  }

  // The filter at the top: All, or only agents (with how many). A click picks
  // one; picking it again goes back to All. With Agents, at the end: by Space
  // or by State (sections).
  filterBar(t) {
    // Every running agent: those with a pane and those other agents started.
    // (Not those on a computer that isn't connected: they're only as last seen.)
    const up = (addr) => !addr.includes("/") || this.machines.some((x) => x.name === addr.split("/")[0] && x.state === "connected");
    const ag = [...this.frame.ag, ...(this.frame.terms ?? []).filter((k) => k.state === "live" && (k.program?.agent || isAgentProgram(k.agent)) && !this.frame.ag.some((x) => x.address === k.address))]
      .filter((a) => up(a.address));
    const pick = (id) => (_e, cx) => {
      this.filter = this.filter === id || !id ? null : id;
      try { localStorage.setItem("agents.filter", this.filter ?? ""); } catch {}
      cx.notify();
    };
    const chip = (id, label, n, color) => {
      const on = (this.filter ?? null) === id;
      return h_flex().id(`filter-${id ?? "all"}`).h(20).px(7).gap(4).flex_none().items_center().rounded(5).cursor_pointer()
        .text_color(on ? t.foreground : n === 0 ? t.dim : t.muted).when(on, (el) => el.bg(t.raised))
        .hover((s) => s.bg(t.hover).text_color(t.foreground))
        .on_click(pick(id))
        .when(Boolean(color) && n > 0, (el) => el.child(div().size(6).rounded(3).flex_none().bg(color)))
        .child(label)
        .when(n > 0, (el) => el.child(div().text_color(t.dim).child(String(n))));
    };
    const by = (id, label) => h_flex().id(`agents-by-${id}`).h(18).px(6).flex_none().items_center().rounded(4).cursor_pointer()
      .text_color(this.agentsBy === id ? t.foreground : t.dim).when(this.agentsBy === id, (el) => el.bg(t.raised))
      .hover((s) => s.text_color(t.foreground))
      .on_click((_e, cx) => { this.agentsBy = id; try { localStorage.setItem("agents.by", id); } catch {} cx.notify(); })
      .child(label);
    return h_flex().flex_none().h(30).px(8).gap(2).items_center().text_size(11.5)
      .child(chip(null, "All", 0, null))
      .children(FILTERS.map((f) => chip(f.id, f.label, ag.filter((a) => f.has(a.status)).length, t[f.color])))
      .when(this.filter === "agents", (el) => el.child(div().flex_1()).child(h_flex().flex_none().gap(1).p(1).rounded(5).border_1().border_color(t.border).text_size(11)
        .child(by("space", "Space")).child(by("state", "Status"))));
  }

  // A space's colour as its row draws it (null: home, or not a listed project).
  // A folder as you'd type it: ~ for home, here or on another computer (its home kept from its scan).
  where(folder, m = null) {
    const d = (folder ?? "").replace(/\/+$/, ""), h = m ? this.remote[m]?.home : homeDir();
    return h && (d === h || d.startsWith(h + "/")) ? `~${d.slice(h.length)}` : d || "~";
  }

  spaceColor(w, t) {
    const color = this.frame.colors[w.id];
    return !color || this.title(w) === "~" ? null : color.startsWith("#") ? color : (MARK[color] ?? t[color]);
  }

  // Agents (the filter) by state, as Herdr's Priority view: Needs you, Done,
  // Working, Idle (only those with any), each with how many; in each, every
  // computer's agents together, most recently changed first, each naming its space
  // (and its computer when that's another) and with what it started. A computer
  // that isn't connected: its agents faded, as last seen.
  agentSections(t, rows) {
    const off = (m) => Boolean(m) && !this.machines.some((x) => x.name === m && x.state === "connected");
    const at = new Map(); // pane -> where it's drawn from: its space (or ~'s folder) and what it's called
    for (const r of rows) for (const { p } of this.frame.groups.get(r.w.id) ?? [])
      at.set(p.pane, { key: r.w.id, color: this.spaceColor(r.w, t), off: off(r.w.machine),
        folder: this.where(r.w.folder, r.w.machine), machine: r.w.machine ?? null });
    for (const d of this.loose ?? []) for (const { p } of this.frame.groups.get(`d:${d}`) ?? []) at.set(p.pane, { key: `d:${d}`, off: false, folder: tilde(d), machine: null });
    const out = [];
    for (const sec of SECTIONS) {
      const list = this.frame.ag.filter((a) => a.status === sec.status && at.has(a.pane)).sort((x, y) => (y.seq ?? 0) - (x.seq ?? 0));
      if (!list.length) continue;
      out.push(h_flex().id(`section-${sec.status}`).h(26).mt(out.length ? 8 : 2).px(8).gap(6).flex_none().items_center().text_size(11.5).text_color(t.muted)
        .child(div().size(6).rounded(3).flex_none().bg(t[sec.status] ?? t.dim))
        .child(sec.label).child(div().text_color(t.dim).child(String(list.length))));
      for (const a of list) {
        const g = at.get(a.pane);
        // Its own row (and what it started) only, naming where it is.
        this.onlyPane = a.pane;
        this.tagWhere = { color: g.color, folder: g.folder, machine: g.machine };
        const els = this.termRows(g.key, t, 0);
        this.onlyPane = this.tagWhere = null;
        if (g.off) out.push(v_flex().flex_none().opacity(0.4).children(els));
        else out.push(...els);
      }
    }
    return out;
  }

  // The rows, under a heading per computer: This computer always, then each other one.
  grouped(t, collapsed) {
    // This computer's rows: ~, then spaces in folders that aren't projects (white),
    // then projects, each group in Herdr's order.
    const listed = new Set(this.projects);
    const rank = (r) => r.w.machine ? 0 : (r.w.folder ?? "").replace(/\/+$/, "") === homeDir() ? 0 : r.tree || listed.has((r.w.folder ?? "").replace(/\/+$/, "")) ? 2 : 1;
    const rows = this.drawn = this.ordered().map((r, n) => ({ r, n })).sort((a, b) => (a.r.w.machine ? 0 : rank(a.r)) - (b.r.w.machine ? 0 : rank(b.r)) || a.n - b.n).map((x) => x.r);
    if (this.filter === "agents" && this.agentsBy === "state" && !collapsed) return this.agentSections(t, rows);
    // A worktree folds away with its main space (under).
    const on = Boolean(this.filter);
    const draw = (r) => (on && !this.spaceMatches(r.w.id) ? [] : r.under && this.agentsFolded.has(r.under) && !on ? [] : collapsed ? [this.compact(r, t)] : [this.row(r, t), ...(this.agentsFolded.has(r.w.id) && !on ? [] : this.termRows(r.w.id, t, r.tree ? TREE : 0)),
      // Another computer's space: this computer's agents connected and working in it.
      ...(r.w.machine && r.w.folder && !on ? this.sshRows(r.w.machine, t, r.w.folder.replace(/\/+$/, "")) : []),
      // Sub-agents started elsewhere that are working in this space.
      ...(this.agentsFolded.has(r.w.id) || on ? [] : this.visitorRows(r.w, t, r.tree ? TREE : 0))]);
    const remote = [...new Set([...rows.map(r => r.w.machine).filter(Boolean), ...this.machines.map(m => m.name)])].sort();
    const loading = m => {
      const layout = this.frame.ms.find(k => k.name === m)?.layout;
      return layout === "loading" || (!layout && this.machines.some(k => k.name === m && k.state === "connected"))
        || this.frame.sp.some(s => (s.machine ?? null) === m && !this.shown.has(s.id));
    };
    const loadingRow = m => div().id(`machine-loading-${m ?? "local"}`).h(28).flex_none().px(8).text_size(12).text_color(t.dim).child(collapsed ? "…" : "Loading…");
    // Built top to bottom (functions, called in order) so this.vis, which Shift+click
    // ranges follow, is in the order shown.
    // Not open projects something works in now, lifted into the list (lifted).
    const busy = (m) => on || collapsed ? [] : this.lifted(m).flatMap((d) => [this.closedRow(d, t, collapsed, m),
      ...this.visitorRows({ id: m ? `r:${m}:${d}` : `c:${d}`, machine: m, folder: d }, t), ...(m ? this.sshRows(m, t, d) : [])]);
    const closed = () => on ? [] : [...busy(null), ...this.looseRows(t, collapsed, true), ...this.closedSection(t, collapsed)];
    // Other folders' rows go right after ~ (first, when there's no ~ space).
    const others = () => on ? [] : this.looseRows(t, collapsed, false);
    const atHome = (r) => !r.w.machine && (r.w.folder ?? "").replace(/\/+$/, "") === homeDir();
    const homeAt = rows.findIndex(atHome);
    const drawAll = (list) => list.flatMap((r) => [...draw(r), ...(r === rows[homeAt] ? others() : [])]);
    // This computer always gets its heading (its +, local servers), others too.
    const machineNames = [null, ...remote];
    return machineNames.flatMap((m) => {
      const mine = rows.filter((r) => (r.w.machine ?? null) === m);
      const machine = this.machines.find(k => k.name === m);
      const connected = !m || machine?.state === "connected";
      const folded = this.folded.has(m);
      // The heading keeps the arrow (it folds on a click); its + gets the hand.
      const head = h_flex().id(`machine-${m ?? "local"}`).h(31).flex_none().px(collapsed ? 2 : 8).gap(7).items_center().text_size(11.5).text_color(t.dim)
        .hover(s => s.bg(t.hover))
        .on_click((_e, cx) => {
          folded ? this.folded.delete(m) : this.folded.add(m);
          localStorage.setItem("machines.folded", JSON.stringify([...this.folded]));
          cx.notify();
        })
        .child(svg(`mods/workspace-chrome/${m ? "server" : "monitor"}.svg`).size(14).flex_none())
        // Name, then whether it's reachable and the fold chevron right after it; the + at the far end.
        .when(!collapsed, el => el.child(div().min_w(0).truncate().child(m ?? "This computer"))
          .child(div().size(6).rounded(3).flex_none().bg(connected ? t.ansi2 : t.dim))
          .child(svg(`mods/workspace-chrome/chevron-${folded ? "right" : "down"}.svg`).size(11).flex_none())
          .when(!m, el => el.children(this.serverChips(t)))
          .child(div().flex_1())
          .children(this.computerBot(m, t))
          .when(connected, el => el.child(h_flex().id(`machine-add-${m ?? "local"}`).size(18).flex_none().items_center().justify_center().rounded(5).cursor_pointer()
            .hover(s => s.bg(t.hover).text_color(t.foreground))
            .on_mouse_down("left", (_e, cx) => cx.stop_propagation())
            .on_click((_e, cx) => { cx.stop_propagation(); this.addHome(m); })
            .child(svg("mods/workspace-chrome/plus.svg").size(12)))));
      const drawn = m ? [...(on ? [] : this.sshRows(m, t)), ...mine.flatMap(draw), ...busy(m)] : [...(homeAt < 0 ? others() : []), ...drawAll(mine)];
      const extra = on ? [] : m ? this.closedSection(t, collapsed, m) : closed();
      // Filtered: a computer with nothing that passes isn't listed at all.
      if (on && !drawn.length) return [];
      // Nothing under a machine with no spaces: its heading's + makes one.
      // Not connected: what's there is as last seen, faded (nothing in it is live).
      const shown = connected ? [...drawn, ...extra] : [v_flex().flex_none().opacity(0.4).children([...drawn, ...extra])];
      return [head, ...(folded ? [] : mine.length || extra.length || drawn.length ? shown : loading(m) ? [loadingRow(m)] : [])];
    });
  }

  // A row's right side: while hovered, its folder (a button's hover text wins);
  // otherwise nothing.
  tail(g, tree, name, t, path) {
    const tip = g && this.tip?.repo === g.repo ? this.tip.text : null;
    const text = tip ?? (path ? tilde(path) : "");
    return h_flex().flex_1().min_w(0).justify_end().items_center().text_size(11).text_color(t.dim)
      .when(Boolean(text), (el) => el.child(div().min_w(0).truncate().child(text)));
  }

  // Next to the name (after its GitHub icon), each a button: uncommitted files
  // (shows Changes), commits not pushed (push, on a second click), commits to
  // pull (pull, fast-forward only), open pull requests, open issues and stars
  // (each opens its page on GitHub; issues and stars only on a repo you can
  // push to, not one you only cloned). Each kind only when over9k-options shows
  // it (dirty, sync, prs, issues, stars).
  counts(g, t, show) {
    const out = [], o = this.frame.options;
    if (o.dirty && g.dirty > 0) out.push(this.action(div().id(`dirty-${g.repo}`).text_color(t.ansi3), g, t,
      `See ${plural(g.dirty, "uncommitted file")}`, show).child(String(g.dirty)));
    if (o.sync && g.ahead > 0) {
      const can = this.canPush(g);
      const armed = this.armed?.repo === g.repo;
      out.push(this.action(div().id(`ahead-${g.repo}`).text_color(t.ansi2).when(armed, (el) => el.bg(t.hover)), g, t,
        armed ? "Click again to push" : can ? `Push ${plural(g.ahead, "commit")}` : this.write[g.slug] === false ? `${plural(g.ahead, "commit")} not pushed (not your repo)` : `${plural(g.ahead, "commit")} not pushed (shared main: use a PR)`,
        can ? (cx) => this.push(g, cx) : null).child(`\u2191${g.ahead}`));
    }
    if (o.sync && g.behind > 0) out.push(this.action(div().id(`behind-${g.repo}`).text_color(t.ansi1), g, t,
      `Pull ${plural(g.behind, "new commit")}`, (cx) => this.gitOp(g, ["pull", "--ff-only", "--quiet"], `Pulled ${g.name}`, cx))
      .child(`\u2193${g.behind}`));
    const pr = g.slug && this.prs[g.slug];
    if (o.prs && pr?.open) out.push(this.action(h_flex().id(`pr-${g.repo}`).gap(2).items_center().text_color(pr.review ? t.blocked : t.dim), g, t,
      pr.review ? `${plural(pr.open, "pull request")}, ${pr.review} needs your review` : `Open ${plural(pr.open, "pull request")}`,
      (cx) => cx.open_url(`${g.web}/pulls`)).child(svg("mods/over9k/pull-request.svg").size(11)).child(String(pr.open)));
    const info = g.slug && this.write[g.slug] && this.repoInfo[g.slug];
    if (o.issues && info?.issues) out.push(this.action(h_flex().id(`issues-${g.repo}`).gap(2).items_center().text_color(t.dim), g, t,
      `Open ${plural(info.issues, "issue")}`, (cx) => cx.open_url(`${g.web}/issues`))
      .child(svg("mods/over9k/issue.svg").size(11)).child(String(info.issues)));
    if (o.stars && info?.stars) out.push(this.action(h_flex().id(`stars-${g.repo}`).gap(2).items_center().text_color(t.dim), g, t,
      `${plural(info.stars, "star")} on GitHub`, (cx) => cx.open_url(`${g.web}/stargazers`))
      .child(svg("mods/over9k/star.svg").size(11)).child(String(info.stars)));
    return out.length ? [h_flex().flex_none().gap(3).items_center().text_size(11.5).children(out)] : [];
  }

  // A number you can click: `text` says what the click does while the pointer is on it.
  action(el, g, t, text, fn) {
    el = this.explained(el.px(2).rounded(4), g, text);
    if (!fn) return el;
    return el.cursor_pointer().hover((s) => s.bg(t.hover))
      .on_mouse_down("left", (_e, cx) => cx.stop_propagation())
      .on_click((_e, cx) => { cx.stop_propagation(); fn(cx); });
  }

  // A repo you can push to: your own, or your team's off its main branch (a shared
  // repo's main takes PRs).
  canPush(g) {
    if (g.slug && this.write[g.slug] === false) return false;
    const owner = g.slug?.split("/")[0];
    return Boolean(this.me && owner === this.me) || !["main", "master"].includes(g.branch);
  }

  push(g, cx) {
    if (!(this.armed?.repo === g.repo && Date.now() < this.armed.until)) {
      this.armed = { repo: g.repo, until: Date.now() + 4000 };
      this.tip = { repo: g.repo, text: "Click again to push" };
      cx.timer.after(4000, (cx) => { if (this.armed?.repo === g.repo) { this.armed = null; cx.notify(); } });
      cx.notify();
      return;
    }
    this.armed = null;
    this.gitOp(g, ["push", "--quiet"], `Pushed ${g.name}`, cx);
  }

  // Runs git in the repo, says how it went, and looks at the repo again.
  gitOp(g, args, done, cx) {
    this.tip = { repo: g.repo, text: args[0] === "push" ? "Pushing\u2026" : "Pulling\u2026" };
    cx.notify();
    cx.spawn(async (cx) => {
      const r = await exec("env", [...QUIET, "git", ...args], { cwd: g.top, on: JSON.parse(g.repo)[0] ?? undefined });
      const why = (r.stderr || r.stdout).trim().split("\n").filter(Boolean).pop() ?? "";
      notify(r.code === 0 ? { title: done, level: "success" } : { title: `Couldn't ${args[0]} ${g.name}`, body: why, level: "error" });
      if (this.tip?.repo === g.repo) this.tip = null;
      this.refreshGit(Object.keys(this.git).filter((k) => this.git[k]?.repo === g.repo), cx);
      cx.notify();
    });
  }

  // The project's space in front (made if it isn't open), with the Changes panel showing.
  // The panel waits until the space is in front: the tab bar restores each space's
  // own panel when it switches, which would hide one shown before.
  showChanges(target, cx) {
    const there = () => spaces().find((s) => s.active && (target.id ? s.id === target.id : !s.machine && s.folder.replace(/\/+$/, "") === target.folder));
    const show = () => { run("layout.select", { stack: "panel-body", child: "changes" }); run("layout.show", { id: "panel" }); };
    if (there()) return show();
    if (target.id) run("space.select", { id: target.id });
    else run("space.new", { machine: "", ...target });
    let tries = 0;
    const wait = (cx) => cx.timer.after(50, (cx) => (there() ? cx.timer.after(150, () => show()) : ++tries < 60 && wait(cx)));
    wait(cx);
  }

  // Each GitHub repo in the list, one after another: fetch, then count its open
  // PRs, open issues and stars.
  refreshRemote(cx) {
    if (this.remoteBusy) return;
    this.remoteBusy = true;
    cx.spawn(async (cx) => {
      try {
        if (!this.me) this.me = (await exec("gh", ["api", "user", "--jq", ".login"])).stdout.trim() || null;
        const seen = new Set();
        for (const [k, g] of Object.entries(this.git)) {
          if (!g?.slug || seen.has(g.repo)) continue;
          seen.add(g.repo);
          // Fetched where the repo is (another computer's over SSH); its PRs come from GitHub.
          const on = JSON.parse(k)[0];
          if (on && !this.machines.some((x) => x.name === on && x.state === "connected")) continue;
          await exec("env", [...QUIET, "git", "fetch", "--quiet"], { cwd: g.top, on: on ?? undefined });
          const v = await exec("gh", ["repo", "view", g.slug, "--json", "viewerPermission,stargazerCount,issues",
            "--jq", "[.viewerPermission, .stargazerCount, .issues.totalCount] | @tsv"]);
          if (v.code === 0) {
            const [perm, stars, issues] = v.stdout.trim().split("\t");
            this.write[g.slug] = ["ADMIN", "MAINTAIN", "WRITE"].includes(perm);
            this.repoInfo[g.slug] = { stars: Number(stars) || 0, issues: Number(issues) || 0 };
          }
          const r = await exec("gh", ["pr", "list", "--repo", g.slug, "--state", "open", "--limit", "100", "--json", "number,reviewRequests,author"]);
          if (r.code === 0) {
            // Someone else's project you only cloned: just the PRs that involve you.
            const list = JSON.parse(r.stdout).filter((p) => this.write[g.slug] !== false || p.author?.login === this.me
              || (p.reviewRequests ?? []).some((q) => q.login === this.me));
            this.prs[g.slug] = { open: list.length, review: list.filter((p) => (p.reviewRequests ?? []).some((q) => q.login === this.me)).length };
          }
          this.refreshGit(Object.keys(this.git).filter((x) => this.git[x]?.repo === g.repo), cx);
        }
      } catch {}
      this.remoteBusy = false;
      cx.notify();
    });
  }

  // While the pointer is on `el`, `text` says what it is, in the row's free
  // space on the right (tail). Herdr's own tooltips don't show in this list.
  explained(el, g, text) {
    return el.on_hover((on, cx) => {
      if (on) this.tip = { repo: g.repo, text };
      else if (this.tip?.text === text) this.tip = null;
      cx.notify();
    });
  }

  // The agents in the order they were last focused (shared "over9k.recentAgents",
  // for over9k-switcher); gone ones drop off.
  trackRecent() {
    const all = agents(), now = all.find((a) => a.focused)?.address;
    const live = new Set(all.map((a) => a.address));
    const next = [...(now ? [now] : []), ...this.recent.filter((x) => x !== now && live.has(x))];
    if (JSON.stringify(next) === JSON.stringify(this.recent)) return;
    this.recent = next;
    setShared("over9k.recentAgents", next);
  }

  row({ w, i, g, tree }, t) {
    this.vis.push(`s:${w.id}`);
    const on = w.active;
    const color = this.frame.colors[w.id];
    // Home (here or on another computer) stays uncoloured.
    const fill = !color || this.title(w) === "~" ? t.foreground : color.startsWith("#") ? color : (MARK[color] ?? t[color]);
    return v_flex()
      .relative()
      .id(`space-${w.id}`)
      .px(8)
      .h(rowHeight({ tree }))
      .flex_none()
      .justify_center()
      .rounded(8)
      .when(on, (el) => el.bg(t.selected))
      .when(!on, (el) => el.hover((s) => s.bg(t.hover)))
      .when(this.sel.has(`s:${w.id}`) || this.allPicked(w), (el) => el.bg(t.accent + "38"))
      .when(this.pressed === i && this.over !== i, (el) => el.opacity(0.5))
      .when(this.pressed !== null && this.over === i && this.pressed !== i, (el) => el.child(
        div().absolute().left(0).right(0).h(2).bg(t.accent)
          .when(this.pressed < i, line => line.bottom(0))
          .when(this.pressed > i, line => line.top(0)),
      ))
      .on_mouse_down("left", () => {
        this.pressed = i;
        this.over = i;
      })
      .on_mouse_move((_e, cx) => {
        const source = spaces()[this.pressed];
        const over = source && (source.machine ?? null) === (w.machine ?? null) ? i : null;
        if (this.pressed !== null && this.over !== over) {
          this.over = over;
          cx.notify();
        }
      })
      .on_mouse_up("left", (_e, cx) => {
        const from = this.pressed;
        const over = this.over;
        this.pressed = null;
        this.over = null;
        if (from !== null && over === i && from !== i) run("space.move", { id: spaces()[from].id, index: i + 1 });
        else if (from === i && multi(_e)) this.pick(`s:${w.id}`, cx, _e);
        else if (from === i) { this.sel.clear(); this.anchor = `s:${w.id}`; this.clickSpace(w); }
        cx.notify();
      })
      .on_mouse_down("right", () => this.rightClick(`s:${w.id}`, () => this.menu(w)))
      .on_hover((on, cx) => {
        if (on) this.hoverSpace = w.id;
        else if (this.hoverSpace === w.id) this.hoverSpace = null;
        cx.notify();
      })
      .child(
        h_flex()
          .gap(9)
          .items_center()
          .when(Boolean(tree), el => el.pl(16).child(svg("mods/workspace-chrome/branch.svg").size(13).text_color(t.dim)))
          .child(div().flex_shrink(0).max_w(150).truncate().text_color(fill).child(this.title(w)))
          .when(Boolean(g?.web) && !tree && this.frame.options.github, el => el.child(this.ghLink(g, t)))
          .when(Boolean(g), el => el.children(this.counts(g, t, (cx) => this.showChanges({ id: w.id }, cx))))
          .child(this.agentFold(w, t))
          .child(this.tail(g, tree, w.name, t, this.hoverSpace === w.id && w.folder))
          .children(this.spaceBot(w, t))
          .child(this.addSlot(w, t)),
      );
  }

  // Right after the name, when the repo is on GitHub: its icon, which opens the repo.
  ghLink(g, t) {
    if (!g?.web) return null;
    return this.explained(div().id(`web-${g.web}`).flex_none().ml(-5).p(2).rounded(4).cursor_pointer().text_color(t.dim), g,
      "Open in GitHub")
      .hover((s) => s.bg(t.hover).text_color(t.foreground))
      .on_mouse_down("left", (_e, cx) => cx.stop_propagation())
      .on_click((_e, cx) => { cx.stop_propagation(); cx.open_url(g.web); })
      .child(svg("mods/over9k/github.svg").size(13));
  }

  // A device's pinned default (the Pin in over9k-new-menu, shared "over9k.startPin"): a
  // little bot left of the +, on its heading and, while hovered like the +, on its
  // spaces', starting that agent there. Nothing without a pin, or while the device
  // can't be reached.
  startBot(m, t, start) {
    const pin = (shared("over9k.startPin") ?? {})[m ?? ""];
    if (!pin || (m && this.machines.find((k) => k.name === m)?.state !== "connected")) return [];
    return [h_flex().id(`start-${m ?? ""}`).size(18).flex_none().items_center().justify_center().rounded(5).cursor_pointer().text_color(t.dim)
      .hover((s) => s.bg(t.hover).text_color(t.foreground))
      .on_mouse_down("left", (_e, cx) => cx.stop_propagation())
      .on_click((_e, cx) => { cx.stop_propagation(); start(pin); })
      .child(svg("mods/over9k/bot.svg").size(13))];
  }

  // Starts `pin`'s agent in that space, shown; made if there's none yet.
  startIn(there, made, pin) {
    if (!there) return run("space.new", { machine: "", ...made, tab: pin.name, argv: pin.run });
    if (!there.active) run("space.select", { id: there.id });
    run("tab.new", { space: there.id, name: pin.name, argv: pin.run });
  }

  // A computer's: in its home space, where its +'s menu starts things (homeSpace).
  computerBot(m, t) {
    return this.startBot(m, t, (pin) => {
      const { there, made } = this.homeSpace(m);
      this.startIn(there, { ...made, ...(m ? { machine: m } : {}) }, pin);
    });
  }

  spaceBot(w, t) {
    return this.hoverSpace === w.id ? this.startBot(w.machine ?? null, t, (pin) => this.startIn(w, null, pin)) : [];
  }

  // A project with no space open (hovered, as `key`): starting one makes its space.
  closedBot(dir, t, m, key) {
    if (this.hoverSpace !== key) return [];
    return this.startBot(m, t, (pin) => {
      const there = spaces().find((s) => (s.machine ?? null) === m && (s.folder ?? "").replace(/\/+$/, "") === dir);
      this.startIn(there, { name: this.alias(dir, m), folder: dir, ...(m ? { machine: m } : {}) }, pin);
    });
  }

  // "+", while the pointer is on the row: the new-tab menu (a terminal or any
  // installed agent) for this space; over9k-new-menu is the tab bar's menu
  // without "New space".
  addSlot(w, t) {
    const slot = h_flex().w(ADD).flex_none().justify_center();
    if (this.hoverSpace !== w.id) return slot;
    return slot.child(h_flex().id(`add-${w.id}`).size(18).items_center().justify_center().rounded(5).cursor_pointer().text_color(t.dim)
      .hover((s) => s.bg(t.hover).text_color(t.foreground))
      .on_mouse_down("left", (_e, cx) => cx.stop_propagation())
      .on_click((_e, cx) => {
        cx.stop_propagation();
        if (!w.active) run("space.select", { id: w.id });
        openOverlay({ mod: "over9k-new-menu", kind: "popup", width: 340, height: 640 });
      })
      .child(svg("mods/workspace-chrome/plus.svg").size(12)));
  }

  // A chevron, only while the pointer is on a row with terminals, says whether
  // they're folded. Clicking the row folds them.
  agentFold(w, t) {
    if (!this.hasTerms(w.id)) return div().w(FOLD).flex_none();
    const folded = this.agentsFolded.has(w.id);
    return h_flex().w(FOLD).flex_none().items_center().justify_center().text_size(11).text_color(t.dim)
      .child(svg(`mods/workspace-chrome/chevron-${folded ? "right" : "down"}.svg`).size(10).opacity(this.hoverSpace === w.id ? 1 : 0));
  }

  // A click on the shown space folds or shows its agents; on another space it
  // shows that space, with its agents.
  clickSpace(w) {
    const folded = this.agentsFolded.has(w.id);
    if (!w.active) {
      run("space.select", { id: w.id });
      if (!folded) return;
      this.agentsFolded.delete(w.id);
    } else if (!this.hasTerms(w.id)) return;
    else folded ? this.agentsFolded.delete(w.id) : this.agentsFolded.add(w.id);
    localStorage.setItem("agents.folded", JSON.stringify([...this.agentsFolded]));
  }

  // A computer's +: the new-tab menu (a terminal or an agent) in its home space,
  // so nothing new lands outside a project or ~. With none yet, the menu makes it
  // with what's picked there (nothing starts on its own).
  addHome(m) {
    const { there, made } = this.homeSpace(m);
    if (there && !there.active) run("space.select", { id: there.id });
    openOverlay({ mod: "over9k-new-menu", kind: "popup", width: 340, height: 640, props: { computer: true, ...made, ...(m ? { machine: m } : {}) } });
  }

  // A computer's home space (there), or what making it takes (made).
  homeSpace(m) {
    // This computer's chats start in its Chats folder (over9k-options; home unless set).
    // Another computer's in its own (over9k-options; its home unless set).
    const r = m && this.remote[m];
    const chats = m ? (r?.home ? (r.chats ?? "~").replace(/^~(?=\/|$)/, r.home) : null) : shared("over9k.locations")?.chats ?? homeDir();
    const there = spaces().find((s) => (s.machine ?? null) === m && (m && !chats ? s.name === "~" : (s.folder ?? "").replace(/\/+$/, "") === chats));
    const home = m ? r?.home : homeDir();
    return { there, made: there ? {} : { folder: chats ?? undefined, name: !chats || chats === home ? "~" : base(chats) } };
  }

  // Projects with no space, under one header, folded until opened.
  // On another computer (m): its listed projects with no space open.
  closedSection(t, collapsed, m = null) {
    const busy = new Set(this.lifted(m));
    const list = this.closedOn(m).filter((d) => !busy.has(d));
    if (!list.length) return [];
    const open = m ? Boolean(this.closedOpenOn[m]) : this.closedOpen;
    const head = h_flex().id(`projects-closed-${m ?? "local"}`).h(26).flex_none().mt(6).px(collapsed ? 2 : 8).gap(7).items_center().text_size(11).text_color(t.dim)
      .rounded(7).hover((s) => s.bg(t.hover))
      .on_click((_e, cx) => {
        if (m) {
          this.closedOpenOn[m] = !open;
          localStorage.setItem("projects.closedOpenOn", JSON.stringify(this.closedOpenOn));
        } else {
          this.closedOpen = !this.closedOpen;
          localStorage.setItem("projects.closedOpen", String(this.closedOpen));
        }
        cx.notify();
      })
      .child(svg(`mods/workspace-chrome/chevron-${open ? "down" : "right"}.svg`).size(11).flex_none())
      .when(!collapsed, (el) => el.child(div().flex_1().truncate().child("Parked")));
    return [head, ...(open ? list.map((d) => this.closedRow(d, t, collapsed, m)) : [])];
  }

  compact({ w, i }, t) {
    return h_flex()
      .id(`space-${w.id}`)
      .h(26)
      .flex_none()
      .justify_center()
      .gap(4)
      .when(w.active, (el) => el.bg(t.raised))
      .hover((s) => s.bg(t.hover))
      .on_click(() => run("space.select", { id: w.id }))
      .child(div().text_color(w.active ? t.foreground : t.muted).child(String(i + 1)))
      .child(div().text_color(tone(t, w.status)).child(glyph(w.status)));
  }

  render() {
    const t = theme();
    const collapsed = narrow();
    const sp = spaces();
    const ids = new Set(sp.map(p => p.id));
    const colors = shared("space.colors") ?? {};
    const kept = Object.fromEntries(Object.entries(colors).filter(([id]) => ids.has(id)));
    let changed = Object.keys(kept).length !== Object.keys(colors).length;
    // Only listed projects get a color; any other folder's space stays white.
    const listedNow = new Set(this.listed());
    for (const p of sp) {
      const want = !p.machine && listedNow.has((p.folder ?? "").replace(/\/+$/, "")) ? hue(project(p)) : p.machine ? hue(project(p)) : null;
      if (kept[p.id] === want || (!want && !kept[p.id])) continue;
      if (want) kept[p.id] = want;
      else delete kept[p.id];
      changed = true;
    }
    if (changed) setShared("space.colors", kept);
    // One read of panes and agents per render (each read copies them all).
    const ps = panes(), ag = agents();
    this.projects = this.listed();
    if (this.projects.join("\n") !== this.shared) { this.shared = this.projects.join("\n"); setShared("projects.listed", this.projects); }
    this.frame = { sp, ps, ag, terms: terminals(), colors: kept, ms: machines(), names: shared("projects.names") ?? {}, options: { ...OPTIONS, ...(shared("sidebar.options") ?? {}) }, byPane: new Map(ag.map((a) => [a.pane, a])), groups: this.assign(sp, ps) };
    // Picked sub-rows closed from the selection menu (over9k-menu): once each.
    const closing = shared("over9k.closeSubs");
    if (closing?.at && closing.at !== this.closedAt) { this.closedAt = closing.at; this.closeSubs(closing.list ?? []); this.sel.clear(); }
    this.vis = [];
    this.subPicks = new Map(); // a sub-row's pick -> how it closes (subRows)
    this.loose = [...this.frame.groups.keys()].filter((k) => k.startsWith("d:")).map((k) => k.slice(2))
      .sort((a, b) => base(a).localeCompare(base(b), undefined, { sensitivity: "base" }));
    const list = this.grouped(t, collapsed);
    this.visible = this.vis;
    // Agents in the order the list shows them (agent.next / prev follow it).
    const keys = [...(this.drawn ?? []).map((r) => r.w.id), ...this.loose.map((d) => `d:${d}`)];
    const byPaneAgent = this.frame.byPane;
    const order = keys.flatMap((k) => (this.frame.groups.get(k) ?? []).map((x) => byPaneAgent.get(x.p.pane)?.address).filter(Boolean));
    if (order.join() !== this.order) { this.order = order.join(); setAgentOrder(order); }
    // Picks of rows that are gone are dropped.
    const alive = new Set([...sp.map((s) => `s:${s.id}`), ...ps.map((p) => `p:${p.pane}`), ...this.loose.map((d) => `d:${d}`), ...this.projects.map((d) => `c:${d}`), ...this.subPicks.keys()]);
    for (const k of this.sel) if (!alive.has(k)) this.sel.delete(k);
    const none = this.filter && !this.frame.ag.some((a) => this.passes(a));
    return v_flex().size_full().min_h(0).bg(t.chrome).text_size(13)
      .when(!collapsed, (el) => el.child(this.filterBar(t)))
      .when(Boolean(none), (el) => el.child(div().px(16).py(6).text_size(12).text_color(t.dim).child(FILTERS.find((f) => f.id === this.filter)?.empty ?? "")))
      .child(v_flex().id("spaces-scroll").flex_1().min_h(0).px(8).pb(14).overflow_y_scrollbar().mode("always")
        .on_mouse_up("left", (_e, cx) => { this.pressed = null; cx.notify(); })
        .children(list))
      // On its own (no Over9k footer in this window): its help and options here.
      .when(!collapsed && !hasMod(layout(), "over9k-footer"), (el) => el.child(h_flex().id("over9k-options-row").h(32).flex_none().mx(8).mb(6).px(8).gap(9)
        .items_center().rounded(7).cursor_pointer().text_color(t.muted).border_t(1).border_color(t.border)
        .hover((s) => s.bg(t.hover).text_color(t.foreground))
        .on_click(() => openOverlay({ mod: "over9k-options", kind: "dialog", width: 740, height: 600 }))
        .child(svg("mods/workspace-chrome/settings.svg").size(14).flex_none()).child("Over9k help & options")));
  }
}


// The "Name: ..." line Claude's recap starts with, once it's there (Claude may
// say something before reading the transcript, so any of its replies counts).
function recapName(jsonl) {
  for (const line of (jsonl ?? "").split("\n")) {
    if (!line.includes('"assistant"')) continue;
    let m;
    try { m = JSON.parse(line); } catch { continue; }
    if (m.type !== "assistant") continue;
    const text = (Array.isArray(m.message?.content) ? m.message.content : []).filter((c) => c.type === "text").map((c) => c.text).join("\n");
    const got = text.match(/^\s*\**Name:\**\s*(.+)$/m)?.[1].replace(/[*`"]/g, "").trim().slice(0, 60);
    if (got) return got;
  }
  return undefined;
}
