// Context menus (Herdr's items). Opened as a popup with
// props { tab: "pane" | "tab" | "space" | "global", target }.
// ↑/↓ move, Enter runs, Esc closes. An item is [label, command, args];
// a command "worktree" opens the worktree dialog instead.

import { View, div, svg } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { plan } from "./close-plan.js";
import { agentTask } from "./agent-name.js";
import { run, props, closeOverlay, openOverlay, theme, themes, keys, terminals, spaces, panes, agents, exec, home, shared, setShared } from "herdr";

// Where a space is now: its first terminal's live folder, else where it was made.
function place(s) {
  const tabs = new Set((s.tabs ?? []).map((c) => c.id));
  return panes().find((p) => tabs.has(p.tab) && p.cwd)?.cwd || s.folder;
}

// A space's checkout: "main" (a repo's own), "linked" (a worktree), or null.
async function checkout(folder, on) {
  const top = await exec("git", ["rev-parse", "--show-toplevel"], { cwd: folder, on });
  const common = await exec("git", ["rev-parse", "--path-format=absolute", "--git-common-dir"], { cwd: folder, on });
  if (top.code !== 0 || common.code !== 0) return null;
  return common.stdout.trim() === `${top.stdout.trim()}/.git` ? "main" : "linked";
}

// Rename a pane: an agent's session by its own command (so its title, Herdr's
// rows and its resume lists all follow), a plain terminal's tab. over9k-rename
// asks for the name.
function renamePane({ pane, terminal }) {
  const p = panes().find((x) => x.pane === pane);
  const a = agents().find((x) => x.address === terminal);
  const tab = spaces().flatMap((s) => s.tabs ?? []).find((t) => t.id === p?.tab);
  const named = tab && !/^(\d+|tb?[0-9a-z]+)$/.test(tab.name) && tab.name !== (a ?? p)?.program?.name ? tab.name : "";
  // What the sidebar shows: a name given to its tab, else the conversation's.
  const value = named || (a ? agentTask(a, p?.cwd) : "");
  openOverlay({ mod: "over9k-rename", kind: "dialog", width: 380, height: 200,
    props: { pane, terminal, tab: tab?.id, alone: panes().filter((x) => x.tab === p?.tab).length === 1, value, title: a ? `Rename ${a.program?.name ?? "agent"} session` : "Rename terminal" } });
}


function items(p, git) {
  p = p ?? {};
  const tg = p.target ?? {};
  switch (p.tab) {
    case "pane": {
      // A kept sub-agent can go back under its parent, still running.
      const all = terminals();
      const term = all.find((t) => t.address === tg.terminal);
      const parent = term?.parent && all.find((t) => t.address === term.parent);
      // Once they go to the program, Shift+right-click still opens this menu.
      const toProgram = term?.labels?.["herdr.right-click"] === "program";
      return [
        ["Rename", "pane.rename", { pane: tg.pane, terminal: tg.terminal }],
        // An agent's work to a space of its own (over9k-handoff).
        ...(agents().some((a) => a.address === tg.terminal) ? [["Hand off\u2026", "pane.handoff", { terminal: tg.terminal }]] : []),
        ...folderItem(paneAt(tg.pane)),
        ["Split right", "pane.split", { direction: "right", pane: tg.pane }],
        ["Split down", "pane.split", { direction: "down", pane: tg.pane }],
        ["Zoom", "pane.zoom", { pane: tg.pane }],
        ...(term
          ? [
              toProgram
                ? ["Use Herdr right-click menu", "terminal.right_click", { terminal: term.address, to: "menu" }]
                : ["Send right-clicks to pane", "terminal.right_click", { terminal: term.address, to: "program" }],
            ]
          : []),
        ...(parent ? [[`Send back to ${parent.name || parent.address}`, "terminal.park", { terminal: term.address }]] : []),
        ["Close pane", "close-ask", { panes: [tg.pane] }],
      ];
    }
    case "tab":
      return [
        ["Rename", "tab.rename", { id: tg.id }],
        ["New tab", "tab.new", { space: tg.space }],
        ...folderItem(paneAt(panes().find((p) => p.tab === tg.id)?.pane)),
        ["Close", "close-ask", { tabs: [tg.id] }],
      ];
    case "space":
      return [
        ["Rename", "space.rename", { id: tg.id }],
        ...(git ? [["New worktree", "worktree", { space: tg.id, action: "new" }], ["Open worktree", "worktree", { space: tg.id, action: "open" }]] : []),
        ...(git === "linked" ? [["Remove worktree", "worktree", { space: tg.id, action: "remove" }]] : []),
        ...folderItem(spaces().find((s) => s.id === tg.id)),
        ...listItems(spaces().find((s) => s.id === tg.id)?.folder),
        ["Close", "close-ask", { spaces: [tg.id] }],
      ];
    // Rows picked in over9k (Shift/Cmd/Ctrl+click): close them all, or
    // unpin the projects among them.
    case "selection": {
      const closing = plan({ spaces: tg.spaces, panes: tg.panes });
      const { group, separate } = paneMoves(tg.panes ?? []);
      return [
        ...(group ? [["Group into one tab", "panes.group", group]] : []),
        ...(separate ? [["Separate into tabs", "panes.separate", separate]] : []),
        // With things agents started among them (over9k's sub-rows: subs), those
        // close too (over9k does it: shared "over9k.closeSubs").
        ...(closing.commands.length || tg.subs?.length ? [["Close selected", "close-many", { spaces: tg.spaces, panes: tg.panes, subs: tg.subs }]] : []),
        ...(tg.folders?.length ? [["Unpin selected", "list.unpin-many", { folders: tg.folders }]] : []),
      ];
    }
    // A project or folder row with no space (over9k): open it, keep it listed or not.
    case "project":
      return [
        ["Open", "project.open", { folder: tg.folder, name: tg.name, ...(tg.machine ? { machine: tg.machine } : {}) }],
        ["Rename", "project.rename", { folder: tg.folder, name: tg.name, machine: tg.machine ?? null }],
        ...folderItem(tg),
        ...listItems(tg.folder, tg.machine ?? null),
      ];
    default:
      return [
        ["New space", "space.new", {}],
        ["Keybinds", "app.help", {}],
        // The themes Herdr has (its own and any added in themes/), as many as fit.
        ...themes().slice(0, 5).map((x) => [`Theme: ${x.name.replace(/-/g, " ")}`, "app.theme", { name: x.name }]),
      ];
  }
}

// Whether a folder stays in the sidebar's project list (over9k reads
// these from shared state): ~/Code repos and agent-set-up folders are listed
// (pinned by default) until unpinned; any other folder once pinned.
// Another computer's lists (machine): shared "projects.on"[machine], its
// found projects "projects.autoOn"[machine] (over9k keeps both).
function lists(machine) {
  if (!machine) return { pinned: shared("projects.pinned") ?? [], hidden: shared("projects.hidden") ?? [], unpinned: shared("projects.unpinned") ?? [], auto: shared("projects.auto") ?? [] };
  const on = shared("projects.on")?.[machine] ?? {};
  return { pinned: on.pinned ?? [], hidden: on.hidden ?? [], unpinned: on.unpinned ?? [], auto: shared("projects.autoOn")?.[machine] ?? [] };
}

// The folder in the file manager (this computer's only).
// Where a pane's terminal is: its folder, and the computer (null: this one).
function paneAt(pane) {
  const p = pane && panes().find((x) => x.pane === pane);
  const sp = p && spaces().find((s) => (s.tabs ?? []).some((t) => t.id === p.tab));
  return p?.cwd ? { folder: p.cwd, machine: sp?.machine ?? null } : null;
}
function folderItem(at) {
  return at?.folder && !at.machine ? [["Open folder", "folder.reveal", { folder: at.folder }]] : [];
}
// Opens a folder in the file manager: Windows (Git Bash) Explorer, Linux xdg-open, macOS open.
const REVEAL = 'case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) explorer.exe "$(cygpath -w "$1" 2>/dev/null || printf %s "$1")" ;; *) if command -v xdg-open >/dev/null 2>&1; then xdg-open "$1"; else open "$1"; fi ;; esac';

function listItems(folder, machine = null) {
  folder = folder?.replace(/\/+$/, "");
  if (!folder || (!machine && folder === home())) return [];
  const { pinned, hidden, auto } = lists(machine);
  const at = machine ? { folder, machine } : { folder };
  // The list is what's pinned (over9k): Unpin takes it off and keeps it off.
  return pinned.includes(folder) ? [["Unpin from list", "list.unpin", at]] : [["Pin to list", "list.pin", at]];
}

// Grouping and separating picked terminals. Herdr can't move a pane between
// tabs, but a terminal can leave its pane and stay running (terminal.park) and
// then get a pane beside another one (terminal.keep), the same process and
// scrollback. A tab whose only pane leaves closes. Each step waits for Herdr to
// apply the last; a script, so it finishes after this menu closes.
const WAIT = `wait_for() { i=0; while [ $i -lt 40 ]; do
    if herdr-app ls | grep -q "\\"terminal\\": \\"$1\\""; then [ "$2" = in ] && return; else [ "$2" = out ] && return; fi
    i=$((i + 1)); sleep 0.1; done; }
move() { herdr-app do terminal.park "{\\"terminal\\":\\"$1\\"}" >/dev/null; wait_for "$1" out
  herdr-app do pane.focus "{\\"terminal\\":\\"$2\\"}" >/dev/null
  tab=$(herdr-app do terminal.keep "{\\"terminal\\":\\"$1\\"$3}" | sed -n 's/.*"tab": *"\\([^"]*\\)".*/\\1/p'); wait_for "$1" in; }`;
// $1 the terminal the rest join (the first is to its right, the others under that).
const GROUP = `${WAIT}
prev=$1; place=right; shift
for t in "$@"; do move "$t" "$prev" ",\\"place\\":\\"$place\\""; prev=$t; place=down; done`;
// Pairs: a terminal, then one that stays in its space (focused, so the new tab lands there).
const SEPARATE = `${WAIT}
# Herdr names a terminal's new tab after its address ("t3d"): back to its number.
while [ $# -ge 2 ]; do move "$1" "$2" ""; [ -n "$tab" ] && herdr-app do tab.rename "{\\"id\\":\\"$tab\\",\\"name\\":\\"\\"}" >/dev/null; shift 2; done`;

function movePanes(script, args) {
  exec("sh", ["-c", script, "sh", ...args]);
}

// What the picked panes allow: grouping 2+ terminals of one machine into the
// first one's tab (unless they're all there already), and separating those that
// share a tab with another pane into tabs of their own.
function paneMoves(picked) {
  const ps = panes().filter((p) => p.terminal), sp = spaces();
  const spaceOf = (p) => sp.find((s) => (s.tabs ?? []).some((t) => t.id === p.tab));
  const mine = picked.map((id) => ps.find((p) => p.pane === id)).filter(Boolean);
  const first = mine[0], machine = first && spaceOf(first)?.machine;
  const joining = mine.slice(1).filter((p) => p.tab !== first.tab && spaceOf(p)?.machine === machine);
  const group = first && joining.length ? [first.terminal, ...joining.map((p) => p.terminal)] : null;
  const pairs = mine.flatMap((p) => {
    const stays = ps.find((q) => q.tab === p.tab && q.pane !== p.pane && !picked.includes(q.pane))
      ?? ps.find((q) => q.tab === p.tab && q.pane !== p.pane && q.pane !== mine.find((m) => m.tab === p.tab)?.pane);
    return ps.filter((q) => q.tab === p.tab).length > 1 && stays ? [p.terminal, stays.terminal] : [];
  });
  return { group, separate: pairs.length ? pairs : null };
}

// Off the list: a pinned folder is unpinned, one listed by itself is hidden.
function unpin(folder) {
  const pinned = shared("projects.pinned") ?? [];
  listChange(pinned.includes(folder) ? "list.unpin" : "list.hide", folder);
}

function listChange(command, folder, machine = null) {
  const l = lists(machine);
  const pinned = new Set(l.pinned), hidden = new Set(l.hidden);
  // Unpinned by hand: the + menu's scan still offers it.
  const unpinned = new Set(l.unpinned);
  if (command === "list.pin") { pinned.add(folder); hidden.delete(folder); unpinned.delete(folder); }
  if (command === "list.unpin") { pinned.delete(folder); unpinned.add(folder); }
  if (command === "list.hide") hidden.add(folder);
  if (machine) {
    const all = shared("projects.on") ?? {};
    setShared("projects.on", { ...all, [machine]: { ...(all[machine] ?? {}), pinned: [...pinned], hidden: [...hidden], unpinned: [...unpinned] } });
    return;
  }
  setShared("projects.unpinned", [...unpinned]);
  setShared("projects.pinned", [...pinned]);
  setShared("projects.hidden", [...hidden]);
}

// Closing: asked first (in over9k-close, which counts terminals and agents)
// when a whole space would go, else at once, as Herdr does.
export function closeAsk(picked) {
  const p = plan(picked);
  if (!p.spaces && !p.working) for (const c of p.commands) run(c.name, c.args);
  else openOverlay({ mod: "over9k-close", kind: "dialog", width: 380, height: 150, props: picked });
}

function menuIcon(command) {
  if (command === "pane.handoff") return "mods/over9k/handoff.svg";
  const name = command === "folder.reveal" ? "folder" : command === "panes.group" ? "layers" : command === "panes.separate" ? "panel-right" : command === "project.rename" ? "square-pen" : command === "project.open" ? "plus" : command === "icon.paste" ? "square" : command === "icon.choose" ? "folder" : command === "icon.find" ? "search" : command === "icon.remove" ? "x" : command === "list.pin" ? "pin" : command.startsWith("list.") ? "pin-off" : command.endsWith(".close") || command === "close-ask" || command === "close-many" ? "x" : command.endsWith(".rename") ? "square-pen" : command.endsWith(".new") ? "plus" : command === "worktree" ? "git-branch" : command === "app.help" ? "terminal" : command === "app.theme" ? "settings" : command === "pane.split" ? "panel-right" : command === "pane.zoom" ? "square" : "terminal";
  return `mods/workspace-chrome/${name}.svg`;
}

// The key bound to a command, for the hint on the right.
function shortcut(name, args) {
  // `pane.split:right` binds pane.split with { direction: "right" }.
  const value = args && Object.values(args)[0];
  const k = keys().find((b) => b.section === "global" && (b.action === name || b.action === `${name}:${value}`));
  return k ? k.keys : "";
}

export default class Menu extends View {
  init(_props, cx) {
    this.at = 0;
    this.git = null;
    this.handle = cx.focus_handle();
    this.handle.focus();
    const p = props();
    const space = p?.tab === "space" && spaces().find((s) => s.id === p.target?.id);
    const folder = space && place(space);
    if (folder)
      cx.spawn(async (cx) => {
        this.git = await checkout(folder, space.machine).catch(() => null);
        cx.notify();
      });
  }

  choose(i, cx) {
    const it = items(props(), this.git)[i];
    if (!it) return;
    closeOverlay(props()?.overlay);
    if (it[1] === "worktree") openOverlay({ mod: "worktree", kind: "dialog", ...(it[2].action === "open" ? { width: 560, height: 480 } : { width: 440, height: 260 }), props: it[2] });
    else if (it[1] === "close-ask") closeAsk(it[2]);
    else if (it[1] === "project.open") openOverlay({ mod: "over9k-new-menu", kind: "popup", width: 340, height: 640, props: it[2] });
    else if (it[1] === "folder.reveal") exec("sh", ["-c", REVEAL, "sh", it[2].folder]).catch(() => null);
    else if (it[1] === "project.rename") openOverlay({ mod: "over9k-rename", kind: "dialog", width: 380, height: 200, props: { folder: it[2].folder, machine: it[2].machine, value: it[2].name, title: "Rename space" } });
    else if (it[1] === "pane.rename") renamePane(it[2]);
    else if (it[1] === "pane.handoff") {
      const a = agents().find((x) => x.address === it[2].terminal);
      const p = panes().find((x) => x.terminal === it[2].terminal);
      openOverlay({ mod: "over9k-handoff", kind: "dialog", width: 420, height: 360, props: { terminal: it[2].terminal, name: (a && agentTask(a, p?.cwd)) || a?.program?.name } });
    }
    else if (it[1] === "panes.group") movePanes(GROUP, it[2]);
    else if (it[1] === "panes.separate") movePanes(SEPARATE, it[2]);
    else if (it[1] === "close-many") {
      if (it[2].subs?.length) setShared("over9k.closeSubs", { list: it[2].subs, at: Date.now() });
      const rest = { spaces: it[2].spaces, panes: it[2].panes };
      if (plan(rest).commands.length) openOverlay({ mod: "over9k-close", kind: "dialog", width: 380, height: 150, props: rest });
    }
    else if (it[1] === "list.unpin-many") for (const f of it[2].folders) unpin(f);
    else if (it[1].startsWith("list.")) listChange(it[1], it[2].folder, it[2].machine ?? null);
    else run(it[1], it[2]);
  }

  render(cx) {
    const t = theme();
    const list = items(props(), this.git);
    return v_flex()
      .id("menu")
      .track_focus(this.handle)
      .w_full()
      .min_h(0)
      .p(5)
      .bg(t.popover)
      .text_size(12.8)
      .on_key_down((e, cx) => {
        if (e.key === "down") this.at = (this.at + 1) % list.length;
        else if (e.key === "up") this.at = (this.at + list.length - 1) % list.length;
        else if (e.key === "enter") this.choose(this.at, cx);
        else if (e.key === "escape") closeOverlay(props().overlay);
        else return;
        cx.notify();
      })
      .children(
        list.map((it, i) =>
          v_flex()
            .when(i > 0 && (it[1].endsWith(".close") || it[1] === "close-ask" || (it[1].startsWith("list.") && !list[i - 1][1].startsWith("list.")) || it[1] === "app.help" || (it[1] === "app.theme" && list[i - 1][1] !== "app.theme")), el => el.child(div().mx(7).my(4).h(1).bg(t.border)))
            .child(h_flex()
            .id(`mi-${i}`)
            .h(31)
            .px(8)
            .gap(9)
            .rounded(7)
            .items_center()
            .justify_between()
            .text_color(t.foreground)
            .when(i === this.at, (el) => el.bg(t.selected))
            .hover((s) => s.bg(t.hover))
            .on_click((_e, cx) => this.choose(i, cx))
            .child(svg(menuIcon(it[1])).size(14).flex_none().text_color(t.muted))
            .child(div().flex_1().child(it[0]))
            .child(div().text_size(11).text_color(t.dim).child(shortcut(it[1], it[2])))),
        ),
      );
  }
}
