// Clone of the shipped new-menu, for the Spaces list's +: a terminal or an agent
// (simple harnesses like Pi or Hermes get a Model button: a local one from Pi's list),
// and past sessions to resume (Claude Code, Codex, Pi; one row each that opens
// its list in the menu): a space's own, or from the computer's + every space's
// newest, each resumed in its own space. No "New space" (that
// would open a home terminal, not one in the project).
// Props: none (the shown space), { folder, name } (a project with no space yet:
// its space is made with what's picked; a git one also gets New/Open worktree), { computer: true } (also, last, "Add
// spaces": Select manually, a folder and the folders in it; or Scan, every git
// repo up to two levels under home and every folder Claude Code has worked in
// that isn't on Over9k's list, unpinned ones too. Both list them the same way:
// open one, pin one, or pin them all).
// With the sidebar there, each agent has a Pin: it becomes this device's default,
// started by a little bot left of a + (over9k's startBot).

import { View, div, svg, image } from "gpui-kit";
import { h_flex, v_flex, InputState, Input } from "gpui-base";
import { theme, spaces, panes, knownAgents, run, openOverlay, closeOverlay, props, window, keys, exec, home, appHome, shared, setShared, notify, readTextFile, pickFolder, layout } from "herdr";

// Past sessions of each agent, newest first, as lines of id, when (seconds),
// title, the folder it ran in, and the model and provider it last used. With a folder ($1): those started there;
// without: the newest from every folder. Up to 40 each.
const SESSIONS = {
  // Claude Code keeps them in ~/.claude/projects/<folder, dashed>; the title is
  // its name as Claude's own picker shows it (one given with /rename, else the
  // one it made up), else its summary, else the first message. One that clear +
  // recap (over9k) started without a /rename takes the name of the one
  // it continues; that one gets a seventh field, "cleared".
  claude: `if [ -n "$1" ]; then set -- "$HOME/.claude/projects/$(printf %s "$1" | sed 's/[^a-zA-Z0-9]/-/g')"/*.jsonl
else set -- "$HOME"/.claude/projects/*/*.jsonl; fi
files=$(ls -t "$@" 2>/dev/null | head -n 40)
cleared=$(printf '%s\\n' "$files" | while read -r f; do [ -n "$f" ] && grep -h -o "previous conversation's transcript at [^ ]*\\.jsonl" "$f" 2>/dev/null; done | sed 's/.* at //')
named() { q='"'; grep -o "$q$2$q:$q[^$q]*$q" "$1" 2>/dev/null | tail -n 1 | cut -d "$q" -f 4; }
printf '%s\\n' "$files" | while read -r f; do
  [ -n "$f" ] || continue
  c=$(grep -m 1 -o '"cwd":"[^"]*"' "$f" | cut -d '"' -f 4)
  t=$(named "$f" customTitle)
  from=$(grep -m 1 -o "previous conversation's transcript at [^ ]*\\.jsonl" "$f" | sed 's/.* at //')
  [ -n "$t" ] || [ -z "$from" ] || t=$(named "$from" customTitle | sed 's/^\\[[Cc]leared\\] //; s/ (cleared)$//')
  [ -n "$t" ] || [ -z "$from" ] || t=$(named "$from" aiTitle)
  [ -n "$t" ] || t=$(named "$f" aiTitle)
  [ -n "$t" ] || t=$(grep -m 1 '"type":"summary"' "$f" | jq -r '.summary // empty' 2>/dev/null)
  [ -n "$t" ] || t=$(grep -m 30 '"type":"user"' "$f" | jq -r 'select(.isMeta != true) | .message.content | if type == "string" then . else (map(select(.type == "text") | .text) | join(" ")) end' 2>/dev/null | grep -v '^\\s*<' | grep -v '^\\s*$' | head -n 1 | cut -c1-90)
  m=$(grep -o '"model":"[^"<]*"' "$f" | tail -n 1 | cut -d '"' -f 4)
  x=""; printf '%s\\n' "$cleared" | grep -qxF "$f" && x=cleared
  printf '%s\\t%s\\t%s\\t%s\\t%s\\t\\t%s\\n' "$(basename "$f" .jsonl)" "$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f")" "$t" "$c" "$m" "$x"
done`,
  // Codex keeps its threads in a database; only ones a person started (not
  // its reviewers or sub-agents), not archived.
  codex: `db="$HOME/.codex/state_5.sqlite"; [ -f "$db" ] || exit 0
q="select id, updated_at, replace(replace(substr(coalesce(nullif(name, ''), nullif(title, ''), first_user_message), 1, 90), char(10), ' '), char(9), ' '), cwd, coalesce(model, ''), model_provider from threads
  where archived = 0 and coalesce(thread_source, '') in ('', 'user') and source not like '{%'"
if [ -n "$1" ]; then q="$q and cwd = '$(printf %s "$1" | sed "s/'/''/g")'"; fi
sqlite3 -separator "$(printf '\\t')" "$db" "$q order by updated_at desc limit 40" 2>/dev/null`,
  // Pi keeps them in ~/.pi/agent/sessions/--<folder, dashed>--; the title is
  // the first message.
  pi: `if [ -n "$1" ]; then set -- "$HOME/.pi/agent/sessions/-$(printf %s "$1" | tr / -)--"/*.jsonl
else set -- "$HOME"/.pi/agent/sessions/*/*.jsonl; fi
ls -t "$@" 2>/dev/null | head -n 40 | while read -r f; do
  head -n 1 "$f" | jq -r '[.id, .cwd] | @tsv' 2>/dev/null | { IFS="$(printf '\\t')" read -r id c
  t=$(grep -m 5 '"role":"user"' "$f" | jq -r '.message.content | if type == "string" then . else (map(select(.type == "text") | .text) | join(" ")) end' 2>/dev/null | grep -v '^\\s*$' | head -n 1 | cut -c1-90)
  pm=$(grep '"type":"model_change"' "$f" | tail -n 1 | jq -r '[.modelId, .provider] | @tsv' 2>/dev/null)
  printf '%s\\t%s\\t%s\\t%s\\t%s\\n' "$id" "$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f")" "$t" "$c" "$pm"; }
done`,
  // Antigravity (agy) keeps a summary of each conversation in a database; only
  // top-level ones (not subagents) that got as far as a message, and not open
  // now (a running agy holds its presence/<id>.lock; the files outlive it).
  // Its folder is the first workspace.
  antigravity: `db="$HOME/.gemini/antigravity-cli/conversation_summaries.db"; [ -f "$db" ] || exit 0
q="select conversation_id, strftime('%s', substr(last_modified_time, 1, 19)),
  replace(replace(substr(coalesce(nullif(title, ''), nullif(preview, ''), ''), 1, 90), char(10), ' '), char(9), ' '),
  replace(substr(json_extract(workspace_uris, '\\$[0]'), 8), '%20', ' '), '', '' from conversation_summaries
  where parent_conversation_id = '' and step_count > 0 and last_modified_time not like '0001-%'"
if [ -n "$1" ]; then q="$q and json_extract(workspace_uris, '\\$[0]') = 'file://$(printf %s "$1" | sed "s/'/''/g; s/ /%20/g")'"; fi
held=$(for d in /proc/[0-9]*/fd; do ls -l "$d" 2>/dev/null; done | grep -o 'antigravity-cli/presence/[0-9a-f-]*[.]lock' | sed 's#.*/##; s#[.]lock$##' | sort -u | tr '\\n' ' ')
sqlite3 -separator "$(printf '\\t')" "file:$db?mode=ro" "$q order by last_modified_time desc limit 40" 2>/dev/null | awk -F '\\t' -v held=" $held" 'index(held, " " $1 " ") == 0'`,
};

// Each one resumes through resume.sh, on the model the session used (starting
// its server if it's local and off).
const RESUME = { claude: true, codex: true, pi: true, antigravity: true };
// Simple harnesses: agents with no model of their own, so they pick a local one
// (add Hermes etc. here once resume.sh knows how to start them on a model).
const SIMPLE = new Set(["pi"]);
const RESUMER = `${appHome()}/mods/over9k-new-menu/resume.sh`;

// The model to show by a session: one that isn't the agent's own.
const ownModel = (key, x) => !x.model || (key === "claude" && /^claude-/.test(x.model)) || (key === "codex" && (!x.provider || x.provider === "openai"));

// Model families with a logo of their own (as in over9k).
const FAMILY = [{ match: /qwen/i, icon: "mods/over9k-new-menu/qwen.svg", color: "#6f69f7" }];
const norm = (url) => (url ?? "").replace(/\/+$/, "");
const hasMod = (node, mod) => Boolean(node) && (node.content?.mod === mod || (node.children ?? []).some((c) => hasMod(c, mod)));
// The folder a path is in, short enough to sit beside its name ("…" in front).
const where = (path) => { const p = path.replace(home(), "~").split("/").slice(0, -1).join("/"); return p.length > 30 ? `\u2026${p.slice(-29)}` : p; };

// A folder's space, here or on another computer (machine): each folder keeps
// one (Herdr's space.new always makes another). Open shows it, or makes it when
// there's none; with `tab` ({name?, argv?}) the program starts in a new tab there.
function openFolder(folder, name, tab, machine = null) {
  const there = spaces().find(s => (s.machine ?? null) === machine && norm(s.folder) === norm(folder));
  if (!there) return run("space.new", { name, folder, machine: machine ?? "", ...(tab?.argv ? { tab: tab.name, argv: tab.argv } : {}) });
  if (!there.active) run("space.select", { id: there.id });
  if (tab) run("tab.new", { space: there.id, folder, ...(tab.argv ? { name: tab.name, argv: tab.argv } : {}) });
}

// An agent's icon with a model's logo as a badge on its corner, when that
// model's family has one (Qwen in Claude Code, say); `bg` rings the badge.
function badged(el, model, bg) {
  const fam = model && FAMILY.find(f => f.match.test(model));
  if (!fam) return el;
  return div().relative().flex_none().child(el)
    .child(div().absolute().right(-4).bottom(-4).size(10).rounded(5).bg(bg).flex().items_center().justify_center()
      .child(svg(fam.icon).size(8).text_color(fam.color)));
}

// How long ago a session was last used: "3m", "2h", "1d".
const ago = (secs) => {
  const m = Math.max(0, Math.round((Date.now() / 1000 - secs) / 60));
  return m < 60 ? `${m}m` : m < 1440 ? `${Math.round(m / 60)}h` : `${Math.round(m / 1440)}d`;
};

const FOLDERS = `{
  find "$HOME" -maxdepth 3 \\( -path "$HOME/.*" -o -name node_modules \\) -prune -o -name .git -print 2>/dev/null | sed 's#/[^/]*$##'
  for d in "$HOME"/.claude/projects/*/; do
    f=$(ls -t "$d"*.jsonl 2>/dev/null | head -n 1); [ -n "$f" ] || continue
    grep -m 1 -o '"cwd":"[^"]*"' "$f" | cut -d '"' -f 4
  done
} | while read -r d; do [ -d "$d" ] && echo "$d"; done | sort -u`;

// Git and agent folders not in the sidebar: never listed, or unpinned by hand.
// Pinned or auto-listed ones are already there, and so is any with a space open.
// On another computer (machine) it runs there, against that computer's lists
// (shared "projects.on" and "projects.autoOn", kept by over9k).
async function scanFolders(machine = null) {
  const on = machine ? { on: machine } : {};
  const r = await exec("sh", ["-c", FOLDERS], on).catch(() => null);
  const h = machine ? ((await exec("sh", ["-c", 'printf %s "$HOME"'], on).catch(() => null))?.stdout ?? "") : home();
  const mine = machine ? shared("projects.on")?.[machine] ?? {} : null;
  // The Projects folder itself (over9k's, shared) only holds spaces.
  const code = new Set(machine ? [(shared("over9k.remoteLocations")?.[machine]?.projects ?? "~/Code").replace(/^~(?=\/|$)/, h)] : shared("projects.codeFolders") ?? [`${home()}/Code`]);
  const listed = new Set([
    ...(machine ? [...(shared("projects.autoOn")?.[machine] ?? []).filter(d => !(mine.hidden ?? []).includes(d)), ...(mine.pinned ?? [])] : shared("projects.listed") ?? []),
    ...spaces().filter(s => (s.machine ?? null) === machine).map(s => norm(s.folder))]);
  const off = new Set(machine ? [...(mine.hidden ?? []), ...(mine.unpinned ?? [])] : [...(shared("projects.hidden") ?? []), ...(shared("projects.unpinned") ?? [])]);
  return (r?.stdout ?? "").split("\n").filter(Boolean)
    .filter((d) => d !== h && !code.has(d) && !d.startsWith("/tmp/") && !listed.has(d))
    .map((d) => ({ dir: d, unpinned: off.has(d) }));
}

// On the list for good, as the project menu's Pin does (also undoing an unpin).
function pin(folders, machine = null) {
  const all = shared("projects.on") ?? {}, mine = machine ? all[machine] ?? {} : null;
  const pinned = new Set(machine ? mine.pinned ?? [] : shared("projects.pinned") ?? []);
  const hidden = new Set(machine ? mine.hidden ?? [] : shared("projects.hidden") ?? []), unpinned = new Set(machine ? mine.unpinned ?? [] : shared("projects.unpinned") ?? []);
  folders.forEach((d) => { pinned.add(d); hidden.delete(d); unpinned.delete(d); });
  if (machine) return setShared("projects.on", { ...all, [machine]: { ...mine, pinned: [...pinned], hidden: [...hidden], unpinned: [...unpinned] } });
  setShared("projects.pinned", [...pinned]);
  setShared("projects.hidden", [...hidden]);
  setShared("projects.unpinned", [...unpinned]);
}

// A folder (~ for home) and the folders directly in it, one per line.
const SUBFOLDERS = 'case "$1" in "~") d=$HOME ;; "~/"*) d="$HOME/${1#"~/"}" ;; *) d=$1 ;; esac; printf "%s\\n" "$d"; for s in "$d"/*/; do [ -d "$s" ] && printf "%s\\n" "${s%/}"; done';

// Resuming on another computer: the agent's own command (models and their
// servers are this computer's).
const RESUME_THERE = { claude: (id) => ["claude", "--resume", id], codex: (id) => ["codex", "resume", id], pi: (id) => ["pi", "--session", id], antigravity: (id) => ["agy", "--conversation", id] };

function shortcut(name) {
  const k = keys().find(b => b.section === "global" && b.action === name);
  if (!k?.keys.trim()) return "";
  const mac = window()?.platform === "macos";
  const names = mac ? { ctrl: "⌃", alt: "⌥", shift: "⇧", cmd: "⌘", fn: "fn" } : { ctrl: "Ctrl", alt: "Alt", shift: "Shift", cmd: "Super", fn: "Fn" };
  const alias = { secondary: mac ? "cmd" : "ctrl", super: "cmd", win: "cmd" };
  return k.keys.trim().split(/\s+/).map(stroke => {
    const parts = stroke.split("-");
    let key = parts.pop();
    if (key === "") { key = "-"; parts.pop(); }
    const held = new Set(parts.map(m => alias[m.toLowerCase()] ?? m.toLowerCase()));
    if (/^[A-Z]$/.test(key)) held.add("shift");
    const label = key.length === 1 ? key.toUpperCase() : key[0].toUpperCase() + key.slice(1).toLowerCase();
    return [...Object.keys(names).filter(m => held.has(m)).map(m => names[m]), label].join(mac ? "" : "+");
  }).join(" ");
}

export default class NewMenu extends View {
  init(_props, cx) {
    this.agents = [];
    this.sessions = {};
    this.list = null; // the agent whose sessions are shown instead of the menu
    // Models served on the computer it's for, from its Pi list: an agent can start on one.
    this.machine = props()?.machine ?? (props()?.folder || props()?.computer ? null : spaces().find(s => s.active)?.machine ?? null);
    const read = (path) => this.machine
      ? exec("sh", ["-c", `cat "$HOME/${path}"`], { on: this.machine }).then(r => (r.code === 0 ? r.stdout : null))
      : readTextFile(`${home()}/${path}`);
    this.local = [];
    this.codexBases = new Set();
    this.up = {}; // server address -> answering
    cx.spawn(async cx => {
      try {
        const list = JSON.parse(await read(".pi/agent/models.json"));
        this.local = Object.entries(list.providers ?? {}).filter(([, p]) => /^https?:\/\/(127\.0\.0\.1|localhost)[:/]/.test(p.baseUrl ?? ""))
          .flatMap(([provider, p]) => (p.models ?? []).map(m => ({ id: m.id, provider, base: norm(p.baseUrl), name: (m.name ?? m.id).replace(/\s*\(local\)$/i, "") })));
      } catch {}
      // Servers Codex has a provider for (config.toml's model_providers base_url).
      const toml = await read(".codex/config.toml").catch(() => "");
      let inProvider = false;
      for (const line of (toml ?? "").split("\n")) {
        if (/^\s*\[/.test(line)) inProvider = /^\s*\[model_providers\./.test(line);
        const url = inProvider && /^\s*base_url\s*=\s*"([^"]*)"/.exec(line)?.[1];
        if (url) this.codexBases.add(norm(url));
      }
      cx.notify();
      // Whether each local server is answering (an off one is started on use).
      for (const base of new Set(this.local.map(m => m.base))) {
        const r = await exec("curl", ["-sf", "-m", "1", "-o", "/dev/null", `${base}/models`], this.machine ? { on: this.machine } : {}).catch(() => null); // asked where the server runs
        this.up[base] = r?.code === 0;
      }
      cx.notify();
    });
    this.handle = cx.focus_handle();
    this.handle.focus();
    const space = spaces().find(s => s.active);
    this.folder = props()?.computer ? "" : props()?.folder ?? space?.folder;
    cx.spawn(async cx => {
      const on = props()?.machine ?? (props()?.folder ? null : space?.machine);
      try { this.agents = await knownAgents({ on }); }
      catch { this.failed = true; }
      cx.notify();
    });
    // A project with no space gets the worktree rows too, when it's a git repo.
    if (props()?.folder && !props()?.machine) cx.spawn(async cx => {
      const r = await exec("git", ["rev-parse", "--git-dir"], { cwd: props().folder }).catch(() => null);
      this.repo = r?.code === 0;
      cx.notify();
    });
    // The computer it's for: another one's sessions are looked for there.
    this.machine = props()?.machine ?? (props()?.folder || props()?.computer ? null : space?.machine ?? null);
    const there = this.machine ? { on: this.machine } : {};
    if (this.folder != null)
      for (const [key, script] of Object.entries(SESSIONS)) cx.spawn(async cx => {
        const r = await exec("sh", ["-c", script, "sh", this.folder.replace(/\/+$/, "")], there).catch(() => null);
        const list = (r?.stdout ?? "").split("\n").filter(Boolean).map(l => {
          const [id, when, title, cwd, model, provider, cleared] = l.split("\t");
          // Clear + recap renames the old one "[Cleared] <name>"; one found
          // continued elsewhere gets the same prefix.
          const plain = (title ?? "").replace(/^\[cleared\] /i, "").replace(/ \(cleared\)$/, "") || "Untitled session";
          const was = cleared === "cleared" || plain !== (title || "Untitled session");
          return { id, when: +when, title: was ? `[Cleared] ${plain}` : plain, cwd: (cwd || this.folder).replace(/\/+$/, ""), model, provider };
        });
        // Only ones that can be resumed where they ran: not in a folder that's
        // gone (old test runs in /tmp) or an agent's scratch folder.
        const dirs = [...new Set(list.map(x => x.cwd))];
        const here = await exec("sh", ["-c", 'for d; do [ -d "$d" ] && printf "%s\\n" "$d"; done', "sh", ...dirs], there).catch(() => null);
        const live = new Set((here?.stdout ?? "").split("\n").filter(Boolean));
        this.sessions[key] = list.filter(x => live.has(x.cwd) && !/^\/tmp\/claude-\d+\//.test(x.cwd));
        cx.notify();
      });
  }
  // Starts it: a tab in the shown space, or, for a space not open yet, its space.
  start(argv, name) {
    const p = props() ?? {};
    if (p.folder) openFolder(p.folder, p.name, { name, argv }, p.machine ?? null);
    else run("tab.new", { space: spaces().find(s => s.active)?.id, ...(argv ? { name, argv } : {}) });
  }

  // A past session resumes in the folder it ran in (Claude Code looks it up by
  // folder), in that folder's space: shown, opened, or made. Its tab gets no
  // name: the agent titles its terminal with the session's name, and a tab name
  // would hide a later /rename (the sidebar shows a tab's name first).
  resume(key, x) {
    const m = this.machine;
    const argv = m ? RESUME_THERE[key](x.id) : ["sh", RESUMER, key, x.id, x.model ?? "", x.provider ?? ""];
    const there = spaces().find(s => (s.machine ?? null) === m && s.folder.replace(/\/+$/, "") === x.cwd);
    const names = (m ? shared("projects.on")?.[m]?.names : shared("projects.names")) ?? {};
    if (there) {
      if (!there.active) run("space.select", { id: there.id });
      run("tab.new", { space: there.id, folder: x.cwd, argv });
    } else run("space.new", { machine: m ?? "", ...(!m && x.cwd === home() ? {} : { name: names[x.cwd] || x.cwd.split("/").pop() }), folder: x.cwd, argv });
  }
  // A menu row; `more`, when given, adds a "Model" button (before the hint) that opens
  // the agent's models (the row itself starts it on its usual one).
  row(id, icon, name, action, hint = "", enabled = true, more = null, extra = null) {
    const t = theme();
    return h_flex().id(id).h(31).px(9).gap(10).rounded(7).items_center().flex_none()
      .text_color(enabled ? t.foreground : t.dim).when(enabled, el => el.hover(s => s.bg(t.selected)))
      .on_click(() => { if (enabled) { const o = props().overlay; Promise.resolve(action()).finally(() => closeOverlay(o)); } })
      .when(Boolean(icon), el => el.child(icon)).child(div().flex_1().min_w(0).truncate().child(name))
      .when(Boolean(more), el => el.child(h_flex().id(`${id}-more`).h(20).px(6).gap(3).flex_none().rounded(5).items_center()
        .border(1).border_color(t.border).text_size(11).text_color(t.dim)
        .hover(s => s.bg(t.hover).text_color(t.foreground))
        .on_mouse_down("left", (_e, cx) => cx.stop_propagation())
        .on_click((_e, cx) => { cx.stop_propagation(); more(); cx.notify(); })
        .child("Model").child(svg("mods/workspace-chrome/chevron-right.svg").size(9))))
      .when(Boolean(extra), el => el.child(extra))
      .child(div().flex_none().text_size(11).text_color(t.dim).child(hint));
  }

  // Pin: this agent (and for one that picks a model, m: that model) is this device's
  // default, for all its spaces, from any of its + menus. Kept in shared
  // "over9k.startPin" per device with what over9k needs to start it. A simple harness
  // (Pi) is pinned only by model: its own row has no Pin. Only the sidebar shows pins.
  agentPin(a, m = null) {
    if (!hasMod(layout(), "over9k") || (!m && SIMPLE.has(a.key))) return null;
    const device = this.machine ?? "", all = shared("over9k.startPin") ?? {}, was = all[device];
    const on = was?.key === a.key && (!m || was.model === m.id);
    return this.button(m ? `model-${a.key}-${m.id}-pin` : `${a.key}-pin`, on ? "Pinned" : "Pin", () => {
      const { [device]: _old, ...rest } = all;
      const run = m ? ["sh", RESUMER, a.key, "", m.id, m.provider] : a.run;
      setShared("over9k.startPin", on ? rest : { ...rest, [device]: { key: a.key, name: a.name, run, ...(m ? { model: m.id } : {}) } });
    }, on);
  }
  render(cx) {
    const t = theme();
    const p = props() ?? {};
    const space = spaces().find(s => s.active);
    const installed = this.agents.filter(a => a.installed);
    const choices = installed; // agents not installed (OpenCode, Cursor…) aren't offered
    const heading = (text) => div().px(9).pt(8).pb(4).text_size(11).text_color(t.dim).child(text);
    const icon = (a) => a.tint ? svg(a.icon).size(14).text_color(t.foreground) : image(a.icon).size(14);
    // Agents with past sessions here, each a row that opens its list.
    const resumable = installed.filter(a => RESUME[a.key] && this.sessions[a.key]?.length);
    // The submenu shown instead of the menu: an agent's sessions or its models.
    const shown = this.list && installed.find(a => a.key === this.list.key);
    // The worktree dialog's props: the project's folder, else the shown space's.
    const tree = (action) => p.folder ? { folder: p.folder, action } : { space: space?.id, folder: panes().find(p => p.focused)?.cwd, action };
    return v_flex().min_h(0).w_full().bg(t.popover).p(5).text_size(12.8)
      .id("new-menu").track_focus(this.handle)
      .on_key_down((e, cx) => {
        if (e.modifiers.control || e.modifiers.platform || e.modifiers.alt) return;
        if (e.key === "escape") {
          if (this.list) { this.list = null; return cx.notify(); }
          return closeOverlay(p.overlay);
        }
        const agent = /^[1-9]$/.test(e.key) ? installed[Number(e.key) - 1] : null;
        if (!agent) return;
        closeOverlay(p.overlay);
        this.start(agent.run, agent.name);
      })
      .when(this.list?.kind === "scan", el => el.child(this.scanList()))
      .when(this.list?.kind === "add", el => el.child(this.addList(t, cx)))
      .when(Boolean(shown), el => el.child(this.list?.kind === "models" ? this.modelList(shown, () => icon(shown)) : this.sessionList(shown, () => icon(shown), p.computer)))
      .when(!shown && !this.list, el => el.child(v_flex().flex_none()
      .when(Boolean(p.folder), el => el.child(div().px(9).pt(4).pb(2).text_size(11).text_color(t.dim).child(`Open ${p.name}`)))
      .child(this.row("terminal", svg("icons/shell.svg").size(14), "CLI", () => this.start(null), p.folder ? "" : shortcut("tab.new")))
      .child(heading("Start an agent"))
      .child(v_flex().flex_none()
        .children(choices.map((a, i) => this.row(a.key, icon(a), a.name, () => this.start(a.run, a.name), a.installed ? (i < 9 ? String(i + 1) : "") : "not installed", a.installed,
          a.installed && this.modelsFor(a).length ? () => { this.list = { kind: "models", key: a.key }; } : null, this.agentPin(a))))
        .when(this.agents.length === 0, el => el.child(div().px(9).py(6).text_color(t.dim).child(this.failed ? "Could not load agents" : "Checking installed agents…"))))
      .when(resumable.length > 0, el => el
        .child(heading("Resume a session"))
        .children(resumable.map((a) => this.opener(`resume-${a.key}`, icon(a), a.name, String(this.sessions[a.key].length), () => { this.list = { kind: "sessions", key: a.key }; }))))
      // Worktrees belong to a space's repo: not on the computer's +.
      .when(!p.computer && (!p.folder || Boolean(this.repo)), el => el
        .child(div().h(1).mx(4).my(5).bg(t.border))
        .child(this.row("worktree", svg("mods/workspace-chrome/branch.svg").size(14), "New worktree…", () => openOverlay({ mod: "worktree", kind: "dialog", width: 460, height: 280, props: tree("new") }), "", Boolean(space || p.folder)))
        .child(this.row("worktree-open", svg("mods/workspace-chrome/branch.svg").size(14), "Open worktree\u2026", () => openOverlay({ mod: "worktree", kind: "dialog", width: 560, height: 480, props: tree("open") }), "", Boolean(space || p.folder))))
      // Last, on the computer's +: Add spaces, by choosing a folder or by a scan
      // for every git and agent folder not listed.
      .when(Boolean(p.computer), el => el
        .child(heading("Add spaces"))
        .child(this.opener("add", svg("mods/workspace-chrome/folder-plus.svg").size(14).text_color(t.foreground), "Select manually", "", (cx) => this.startAdd(cx)))
        .child(this.opener("scan", svg("mods/workspace-chrome/search.svg").size(14).text_color(t.foreground), "Scan", "", (cx) => this.scan(cx))))));
  }

  // A row that opens a list in the menu (a submenu): count and a chevron at the end.
  opener(id, icon, name, hint, open) {
    const t = theme();
    return h_flex().id(id).h(31).px(9).gap(10).rounded(7).items_center().flex_none().hover(s => s.bg(t.selected))
      .on_click((_e, cx) => { open(cx); cx.notify(); })
      .child(icon).child(div().flex_1().min_w(0).truncate().child(name))
      .child(div().flex_none().text_size(11).text_color(t.dim).child(hint))
      .child(svg("mods/workspace-chrome/chevron-right.svg").size(11).flex_none().text_color(t.dim));
  }

  // Scan for git and agent folders not listed, shown in the menu (found: null while scanning).
  scan(cx) {
    this.list = { kind: "scan" };
    this.found = null;
    cx.spawn(async cx => { this.found = await scanFolders(this.machine); cx.notify(); });
  }

  // Select manually: the folders in a folder (home to begin), listed as Scan
  // lists what it finds (listHead, folderRow), each with a › to go into it and an
  // Up row; the folder's path can be typed instead, and here Browse… picks one.
  startAdd(cx) {
    this.list = { kind: "add" };
    this.pathInput = InputState.new({ value: "~", placeholder: "~/folder" });
    this.pathInput.on("change", (_e, cx) => this.browseTo(this.pathInput.value().trim() || "~", cx, false));
    this.browseTo("~", cx);
  }

  // `dir` (~ for home) and the folders directly in it, here or there (SUBFOLDERS).
  browseTo(dir, cx, show = true) {
    dir = dir.replace(/(.)\/+$/, "$1");
    if (show) this.pathInput?.set_value(dir);
    this.browse = { dir, full: null, subs: null };
    cx.notify();
    cx.spawn(async (cx) => {
      const r = await exec("sh", ["-c", SUBFOLDERS, "sh", dir], this.machine ? { on: this.machine } : {}).catch(() => null);
      if (this.browse?.dir !== dir) return; // moved on meanwhile
      const lines = (r?.stdout ?? "").split("\n").filter(Boolean);
      this.browse = { dir, full: r?.code === 0 ? lines[0] : null, subs: r?.code === 0 ? lines.slice(1) : [] };
      cx.notify();
    });
  }

  // Select manually and Scan list folders the same way: a line saying what's
  // listed with Pin all, then a row each with Open (as a space) and Pin (keeps
  // it listed, then says Pinned); hovered, its path. In Select manually a click
  // on the row goes into the folder (opening one takes its button, so going in
  // never opens one by mistake); in Scan it opens it.
  button(id, text, fn, strong = false) {
    const t = theme();
    return h_flex().id(id).h(20).px(6).flex_none().rounded(5).items_center().cursor_pointer()
      .border(1).border_color(t.border).text_size(11).text_color(strong ? t.foreground : t.dim).hover(s => s.bg(t.hover).text_color(t.foreground))
      .on_mouse_down("left", (_e, cx) => cx.stop_propagation())
      .on_click((_e, cx) => { cx.stop_propagation(); fn(); cx.notify(); })
      .child(text);
  }
  open(d) {
    const o = props().overlay;
    openFolder(d, d.split("/").pop(), undefined, this.machine);
    closeOverlay(o);
  }
  openButton(id, d) {
    return this.button(id, "Open", () => this.open(d));
  }
  pinButton(id, dirs, all = false) {
    const t = theme();
    const pinned = new Set(this.machine ? shared("projects.on")?.[this.machine]?.pinned ?? [] : shared("projects.pinned") ?? []);
    const done = dirs.length > 0 && dirs.every((d) => pinned.has(d));
    return this.button(id, all ? (done ? "All pinned" : "Pin all") : done ? "Pinned" : "Pin", () => { if (!done) pin(dirs, this.machine); }, done);
  }
  listHead(id, text, dirs) {
    const t = theme();
    return h_flex().px(9).pt(8).pb(4).items_center()
      .child(div().flex_1().text_size(11).text_color(t.dim).child(text))
      .when(dirs.length > 1, (el) => el.child(this.pinButton(id, dirs, true)));
  }
  folderRow(id, d, into = false) {
    const t = theme();
    return h_flex().id(id).h(31).pl(9).pr(into ? 4 : 9).gap(6).rounded(7).items_center().flex_none().hover(s => s.bg(t.selected))
      .on_hover((on, cx) => { if (on) this.hoverDir = d; else if (this.hoverDir === d) this.hoverDir = null; cx.notify(); })
      .on_click((_e, cx) => { if (into) return this.browseTo(d, cx); this.open(d); })
      .child(svg("mods/workspace-chrome/folder.svg").size(13).flex_none().text_color(t.dim))
      .child(div().flex_1().min_w(0).truncate().pl(4).child(d.split("/").pop()))
      .child(div().flex_none().text_size(11).text_color(t.dim).child(this.hoverDir === d ? where(d) : ""))
      .child(this.openButton(`${id}-open`, d))
      .child(this.pinButton(`${id}-pin`, [d]))
      .when(into, el => el.child(svg("mods/workspace-chrome/chevron-right.svg").size(11).flex_none().ml(2).text_color(t.dim)));
  }

  addList(t, cx) {
    const b = this.browse ?? { dir: "~", full: null, subs: null };
    const up = b.full && b.full !== "/" ? b.full.replace(/\/[^/]*$/, "") || "/" : null;
    const subs = b.subs ?? [];
    // A row that moves around (the menu stays open), as the menu's own rows.
    const nav = (id, icon, text, fn) => h_flex().id(id).h(31).px(9).gap(10).rounded(7).items_center().flex_none().text_color(t.dim)
      .hover((s) => s.bg(t.selected).text_color(t.foreground)).on_click((_e, cx) => fn(cx))
      .child(svg(`mods/workspace-chrome/${icon}.svg`).size(12).flex_none()).child(div().flex_1().min_w(0).truncate().child(text));
    return v_flex().flex_none()
      .child(this.back("Select manually"))
      // Where it is: typed, or (here) Browse….
      .child(h_flex().px(4).pb(4).gap(6).items_center()
        .child(Input.new(this.pathInput).flex_1().h(26).px(8).rounded(6).border_1().border_color(t.input).bg(t.background).text_size(12))
        .when(!this.machine, (el) => el.child(h_flex().id("add-browse").h(26).px(8).flex_none().rounded(6).items_center().cursor_pointer()
          .border_1().border_color(t.input).text_size(11.5).text_color(t.dim).hover((s) => s.text_color(t.foreground))
          .on_click((_e, cx) => cx.spawn(async (cx) => { const d = await pickFolder({ prompt: "Choose a folder" }); if (d) this.browseTo(d.replace(/\/+$/, ""), cx); }))
          .child("Browse\u2026"))))
      .when(Boolean(up), (el) => el.child(nav("add-up", "chevron-left", "Up", (cx) => this.browseTo(up, cx))))
      // The folder itself (not a row: its Open and Pin by its name), then what's in it.
      .when(Boolean(b.full), (el) => el.child(h_flex().h(31).px(9).gap(6).items_center().flex_none()
        .child(div().flex_1().min_w(0).truncate().text_color(t.dim).child(`This folder: ${b.full === home() ? "~" : b.full.split("/").pop() || "/"}`))
        .child(this.openButton("add-this-open", b.full))
        .child(this.pinButton("add-this-pin", [b.full]))))
      .when(b.subs === null, (el) => el.child(div().px(9).py(6).text_color(t.dim).child("Looking\u2026")))
      .when(b.subs !== null && !b.full, (el) => el.child(div().px(9).py(6).text_color(t.dim).child("Not a folder")))
      .when(subs.length > 0, (el) => el.child(this.listHead("add-pin-all", `${subs.length} folder${subs.length === 1 ? "" : "s"} in it`, subs)))
      .child(v_flex().id(`add-list-${b.dir}`).flex_none().h(Math.min(subs.length, 12) * 31).overflow_y_scrollbar()
        .children(subs.map((d) => this.folderRow(`add-${d}`, d, true))));
  }

  // What the scan found (folders not on the list), as Select manually lists them.
  scanList() {
    const t = theme(), found = this.found, dirs = (found ?? []).map((f) => f.dir);
    return v_flex().flex_none()
      .child(this.back("Scan"))
      .when(found === null, el => el.child(div().px(9).py(6).text_color(t.dim).child("Scanning\u2026")))
      .when(found?.length === 0, el => el.child(div().px(9).py(6).text_color(t.dim).child("They're all listed already")))
      .when(found?.length > 0, el => el.child(this.listHead("scan-pin-all", `${dirs.length} folder${dirs.length === 1 ? "" : "s"} not listed`, dirs)))
      .child(v_flex().id("scan-list").flex_none().h(Math.min(dirs.length, 15) * 31).overflow_y_scrollbar()
        .children(dirs.map((d) => this.folderRow(`scan-${d}`, d))));
  }

  // The local models (Pi's list) an agent can run: only simple harnesses (Pi)
  // get a choice; Claude Code, Codex and the rest start as they are.
  modelsFor(a) {
    if (this.machine) return []; // local models are this computer's
    return SIMPLE.has(a.key) ? this.local : [];
  }

  // A submenu's top: a Back row saying what's listed, then a line.
  back(text) {
    const t = theme();
    return v_flex().flex_none()
      .child(h_flex().id("back").h(31).px(9).gap(8).rounded(7).items_center().flex_none().text_color(t.dim).hover(s => s.bg(t.selected).text_color(t.foreground))
        .on_click((_e, cx) => { this.list = null; cx.notify(); })
        .child(svg("mods/workspace-chrome/chevron-left.svg").size(11).flex_none())
        .child(div().flex_1().child(text)))
      .child(div().h(1).mx(4).my(4).bg(t.border));
  }

  // A running local server: its process (by the --port on its command line) and
  // servers.json's stop command, then over9k-server-stop asks before stopping it.
  async askStop(m) {
    const port = /:(\d+)/.exec(m.base)?.[1];
    if (!port) return;
    let pid = null, stop = null;
    const ps = await exec("ps", ["-eo", "pid=,args="], this.machine ? { on: this.machine } : {}).catch(() => null);
    for (const line of (ps?.stdout ?? "").split("\n")) {
      if (new RegExp(`--port[ =]${port}\\b`).test(line) && !/<defunct>/.test(line)) { pid = Number(line.trim().split(/\s+/)[0]); break; }
    }
    try {
      const entry = JSON.parse(await readTextFile(`${appHome()}/mods/over9k-new-menu/servers.json`))[`http://127.0.0.1:${port}`];
      stop = typeof entry === "object" ? entry?.stop : null;
    } catch {}
    if (!pid && !stop) return notify({ title: `Can't find ${m.name}'s server`, body: `Nothing here runs with --port ${port}.`, level: "warning" });
    openOverlay({ mod: "over9k-server-stop", kind: "dialog", width: 400, height: 170, props: { name: m.name, port: Number(port), pid, stop, agents: [] } });
  }

  // The models an agent can start on: each local one (its server started first
  // when it's off).
  modelList(a, icon) {
    const t = theme();
    return v_flex().flex_none()
      .child(this.back(`Start ${a.name} on`))
      .children(this.modelsFor(a).map(m => this.row(`model-${a.key}-${m.id}`, badged(icon(), `${m.id} ${m.name}`, t.popover), m.name,
        () => this.start(["sh", RESUMER, a.key, "", m.id, m.provider], a.name), this.up[m.base] === false ? "starts its server" : "", true, null, this.agentPin(a, m))))
      // Each running local server, to stop (asks first, as the sidebar's chip does).
      .children([...new Map(this.modelsFor(a).filter(m => this.up[m.base]).map(m => [m.base, m])).values()].map(m =>
        this.row(`stop-${m.base}`, svg("mods/over9k-new-menu/stop.svg").size(12).flex_none().text_color(t.dim), `Stop ${m.name}'s server`,
          () => this.askStop(m), m.base.replace(/^https?:\/\//, ""))));
  }

  // One agent's past sessions, under a Back row; the list scrolls. `icon` makes
  // one per row (an element can be used only once).
  sessionList(a, icon, computer) {
    const t = theme(), h = home(), list = this.sessions[a.key] ?? [];
    return v_flex().flex_none()
      .child(this.back(`Resume a ${a.name} session`))
      .child(v_flex().id(`sessions-${a.key}`).flex_none().h(Math.min(list.length, 16) * 31).overflow_y_scrollbar()
        .children(list.map((x) => this.row(`resume-${a.key}-${x.id}`, badged(icon(), x.model, t.popover), x.title, () => this.resume(a.key, x),
          [computer && (x.cwd === h ? "~" : x.cwd.split("/").pop()), !ownModel(a.key, x) && x.model, ago(x.when)].filter(Boolean).join(" \u00b7 ")))));
  }
}
