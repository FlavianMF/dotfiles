// Over9k's help and options (the over9k sidebar reads the options). Options:
// this computer's Chats and Projects, the hand-off rule, what space and agent
// rows show, and whether agent rows are compact (one line) or expanded (the
// name, then its info under it). Saved in shared "sidebar.options" as they
// change. Help: what Over9k adds. Opened from the sidebar footer
// (over9k-footer). Esc closes. The title bar links to the repo, to star it.

import { View, div, svg, image } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { FolderPick } from "./folder-pick.js";
import { helpTopics } from "./help.js";
import { props, closeOverlay, openOverlay, theme, shared, setShared, home, appHome, pickFolder, exec, machines, readTextFile, notify } from "herdr";

export const DEFAULTS = { keepUpToDate: false, handoffRule: false, todos: true, todoLog: true, todoSync: false, timeline: true, claudeStatus: false, agyStatus: false, todoFile: false, layout: "expanded", model: true, effort: true, context: true, since: true, cache: true, github: true, dirty: true, sync: true, prs: true, stars: true, issues: true,
  subModel: true, subEffort: true, subContext: true, subTime: true,
  usage: true, usageClaude: true, usageCodex: true, usageGemini: true, checkUpdates: true };
// The To-do panel (over9k-todos) and the `todo` command agents use.
const TODO_ITEMS = [
  ["todos", "To-do", "The To-do panel, and agents keeping each project's list: the rule in CLAUDE.md and AGENTS.md, the todo command (~/.local/bin) and Claude Code's note on each message. Log and Sync are switched per project in the panel's header"],
];
// The mods folder as the shell scripts below get it ($3): forward slashes, which
// sh and Python take on Windows too.
const MODS = () => `${appHome().replace(/\\/g, "/")}/mods`;
// What the switches set up outside Herdr (the to-do rule, command and hook,
// the Log / Sync defaults):
// setup.sh, next to this file, which install.sh runs too.
const SETUP = () => `${MODS()}/over9k-options/setup.sh`;
// Each [key, label, a note under it]; the sample above shows what each looks like.
const AGENT_ITEMS = [
  ["model", "Model"],
  ["effort", "Effort"],
  ["context", "Context used"],
  ["since", "Time since last reply"],
  ["cache", "Expired cache", "Click it to start fresh from a short recap"],
];
// What a Claude subagent's row shows after its task (under its agent).
const SUB_ITEMS = [
  ["subModel", "Model"],
  ["subEffort", "Effort"],
  ["subContext", "Context used"],
  ["subTime", "Running for"],
];
// Options' pages (the navigator on the left).
const PAGES = [["folders", "Folders"], ["spaces", "Space rows"], ["agents", "Agent rows"], ["subs", "Subagent rows"], ["usage", "Usage"], ["todos", "To-do"], ["timeline", "Timeline"], ["claude", "Session footers"]];
// The usage section above Settings (over9k-usage): whether it shows, and which services.
const USAGE_ITEMS = [
  ["usage", "Show usage", "Limits per service, above Settings"],
  ["usageClaude", "Claude", "Needs Claude Code's session footer."],
  ["usageCodex", "Codex", "From Codex's latest session"],
  ["usageGemini", "Gemini", "Includes 3rd-party (Claude, GPT) limits. Needs Antigravity's session footer."],
];
// over9k's handoff.sh as over9k installs it (relative to home): agents run it
// by that path, so it lives outside the mod. Its --rule on|off writes or removes
// the marked hand-off block in ~/.claude/CLAUDE.md, ~/.codex/AGENTS.md and
// ~/.pi/agent/AGENTS.md; only the switch below (or changing a folder while it's
// on) runs it.
const HANDOFF_SCRIPT = ".local/share/over9k/handoff.sh";
// What Hand off project work does (on this computer or another).
const HANDOFF = "Chats outside a project pass project work to a new agent in it. Adds a rule to CLAUDE.md and AGENTS.md";
// Update ($1 the clone Over9k was installed from, $2 its branch, $3 Herdr's
// home): pull only if it's a fast-forward (local changes stop it, and say so),
// then install.sh again. Settings, lists and Claude Code's settings stay as
// they are; Herdr reloads the mods as they land.
const UPDATE = `{
  cd "$1" || exit 1
  b=$(git symbolic-ref --short -q HEAD)
  [ "$b" = "$2" ] || { echo "$1 is on \${b:-no branch}, not $2. Switch it back to $2, or update it yourself."; exit 1; }
  export GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="\${GIT_SSH_COMMAND:-ssh -o BatchMode=yes -o ConnectTimeout=10}"
  git pull -q --no-rebase --ff-only origin "$2" && sh ./install.sh --yes --no-claude --home "$3"
} 2>&1`;
// The setup's wider scan (as the + menu's): git repos up to two levels under
// home, and folders Claude Code has worked in.
const MORE = `{
  find "$HOME" -maxdepth 3 \\( -path "$HOME/.*" -o -name node_modules \\) -prune -o -name .git -print 2>/dev/null | sed 's#/[^/]*$##'
  for d in "$HOME"/.claude/projects/*/; do
    f=$(ls -t "$d"*.jsonl 2>/dev/null | head -n 1); [ -n "$f" ] || continue
    grep -m 1 -o '"cwd":"[^"]*"' "$f" | cut -d '"' -f 4
  done
} | while read -r d; do [ -d "$d" ] && echo "$d"; done | sort -u`;

// Over9k on GitHub, where the title bar's Star on GitHub goes.
const REPO = "https://github.com/herunan/herdr-over9k";
// Each a button on the row: what clicking it does, under its name. Git's from
// the repo itself; GitHub's from GitHub (gh), every 5 minutes.
const SPACE_ITEMS = [
  ["dirty", "Uncommitted files", "Opens Changes"],
  ["sync", "Commits to push or pull", "Click to push (twice) or pull"],
];
const GITHUB_ITEMS = [
  ["github", "GitHub link", "Opens the repo"],
  ["prs", "Pull requests", "Red if your review is wanted"],
  ["issues", "Open issues", "On your repos; opens them"],
  ["stars", "Stars", "On your repos; opens who starred it"],
];

export default class SidebarOptions extends View {
  init(_props, cx) {
    this.handle = cx.focus_handle();
    this.handle.focus();
    this.tab = "options";
    this.page = "folders"; // Options' page (PAGES)
    this.claude = {}; // what ~/.claude/settings.json has of Over9k's (readClaude)
    this.readClaude();
    cx.timer.every(500, (cx) => { if (this.dirty) { this.dirty = false; cx.notify(); } });
    this.topic = 0; // Help's page (helpTopics)
    this.setup = Boolean(props()?.setup); // setup mode: over9k's first run, or Run setup again
    this.tip = null; // the samples' hover text ("agent:…" while on the agent sample)
    this.armed = false; // the sample ↑ clicked once
    this.computer = null; // whose folders show: null for this one, else a machine's name
    this.editing = null; // another computer's folder being typed: { key, input }
  }

  // Which of Over9k's Claude Code pieces are really set up (the switches show
  // that, not just the last click): the to-do hook.
  readClaude() {
    readTextFile(`${home()}/.claude/settings.json`).then((text) => {
      let j = {};
      try { j = JSON.parse(text ?? "{}"); } catch {}
      const cmds = (ev) => (j.hooks?.[ev] ?? []).flatMap((h) => h.hooks ?? []).map((h) => h.command ?? "");
      this.claude = {
        todoHook: cmds("UserPromptSubmit").some((c) => c.includes("todo-hook.sh")),
        claudeStatus: /over9k[^/"]*\/claude-statusline\.sh/.test(j.statusLine?.command ?? ""),
        agyStatus: this.claude?.agyStatus ?? false,
      };
      this.dirty = true;
    }).catch(() => null);
    // Antigravity's (its own settings.json): whether its status line is Over9k's.
    readTextFile(`${home()}/.gemini/antigravity-cli/settings.json`).then((text) => {
      this.agyHere = text != null;
      let j = {};
      try { j = JSON.parse(text ?? "{}"); } catch {}
      this.claude = { ...this.claude, agyStatus: /agy-statusline\.sh/.test(j.statusLine?.command ?? "") };
      this.dirty = true;
    }).catch(() => null);
  }

  set(key, value) {
    setShared("sidebar.options", { ...DEFAULTS, ...(shared("sidebar.options") ?? {}), [key]: value });
    // The rule lives in each agent's own instructions file: handoff.sh puts it in or takes it out.
    const o = { ...DEFAULTS, ...(shared("sidebar.options") ?? {}) };
    // The rule goes into CLAUDE.md and AGENTS.md (over9k's handoff.sh); it names
    // the folders, so it's written again when one changes while it's on.
    const on = o[key] ? "on" : "off";
    const args = { todos: ["todo", on, MODS()], todoLog: ["default", "log", on], todoSync: ["default", "sync", on],
      claudeStatus: ["status", on, MODS()], agyStatus: ["agy", on, MODS()] }[key];
    if (args) exec("sh", [SETUP(), ...args]).then((r) => {
      if (r?.code === 4) notify({ title: "Over9k needs jq", body: "Install jq (jqlang.org) for this switch, then try again.", level: "warning" });
      this.readClaude();
    }).catch(() => null);
    if (key === "handoffRule" || (key === "locations" && o.handoffRule))
      exec("sh", ["-c", '[ -f "$HOME/$2" ] && sh "$HOME/$2" --rule "$1"', "sh", o.handoffRule ? "on" : "off", HANDOFF_SCRIPT]).catch(() => null);
  }

  // One page (PAGES): a heading and a line on what it's for, then its settings.
  // Setup mode: Folders, then the spaces to pin.
  options(t, o, cx) {
    o = { ...o, ...this.claude }; // the Claude Code switches show what's set up
    const group = (title, about, first) => v_flex().flex_none().pt(first ? 0 : 24).pb(10).gap(3)
      .child(div().text_size(16).font_semibold().text_color(t.foreground).child(title))
      .when(Boolean(about), (el) => el.child(div().text_size(12).text_color(t.dim).child(about ?? "")));
    const choice = (id, text, on) => h_flex().id(id).flex_1().h(30).items_center().justify_center().rounded(7).cursor_pointer()
      .border_1().border_color(on ? t.accent : t.input).bg(on ? t.accent + "26" : t.raised).text_color(on ? t.foreground : t.muted)
      .hover((s) => s.text_color(t.foreground)).on_click(() => this.set("layout", id)).child(text);
    // A note beneath the label (under) when it needs one.
    const check = ([key, text, under]) => h_flex().id(`show-${key}`).min_h(30).py(5).px(4).gap(10).items_center().rounded(7).cursor_pointer()
      .hover((s) => s.bg(t.hover)).on_click(() => this.set(key, !o[key]))
      .child(h_flex().size(16).flex_none().rounded(4).items_center().justify_center()
        .border_1().border_color(o[key] ? t.accent : t.input).bg(o[key] ? t.accent : t.background)
        .when(o[key], (el) => el.child(svg("mods/workspace-chrome/check.svg").size(11).text_color(t.accent_foreground))))
      .child(v_flex().flex_1().min_w(0).child(div().text_color(t.foreground).child(text))
        .when(Boolean(under), (el) => el.child(div().text_size(11).text_color(t.dim).child(under ?? ""))));
    // Where things live on the picked computer (over9k's: set, or found there),
    // with ~ for home. This computer's folders are picked; another's typed.
    const tilde = (d) => (d === home() ? "~" : d.startsWith(home() + "/") ? `~${d.slice(home().length)}` : d);
    const m = this.computer;
    const where = m ? { ...(shared("over9k.remoteLocations")?.[m] ?? {}), ...(o.computers?.[m] ?? {}) } : shared("over9k.locations") ?? {};
    const save = (key, value) => m
      ? this.set("computers", { ...(o.computers ?? {}), [m]: { ...(o.computers?.[m] ?? {}), [key]: value } })
      : this.set("locations", { ...(o.locations ?? {}), [key]: value });
    // Change… opens a folder chooser under the row (type, click through, or
    // Browse… here): the same on every computer (folder-pick.js).
    const place = (key, text) => v_flex().flex_none()
      .child(h_flex().id(`where-${key}`).h(30).px(4).gap(10).items_center().rounded(7)
        .child(div().w(100).flex_none().text_color(t.foreground).child(text))
        .child(div().flex_1().min_w(0).truncate().text_color(t.muted).child(where[key] ? (m ? where[key] : tilde(where[key])) : m ? "not found yet" : "\u2026"))
        .child(h_flex().id(`where-change-${key}`).h(22).px(8).flex_none().rounded(6).items_center().cursor_pointer()
          .border_1().border_color(t.input).text_size(11.5).text_color(t.dim).hover((s) => s.text_color(t.foreground))
          .on_click((_e, cx) => {
            this.editing = this.editing?.key === key ? null : { key, pick: new FolderPick({ value: where[key] ? (m ? where[key] : tilde(where[key])) : "~", machine: m, home: home(),
              done: (v) => { save(key, v); this.editing = null; } }) };
            cx.notify();
          })
          .child(this.editing?.key === key ? "Cancel" : "Change\u2026")))
      .when(this.editing?.key === key, (el) => el.child(div().px(4).pb(6).child(this.editing.pick.view(t, cx))));
    // A dropdown of computers: this one, then each other one Herdr knows.
    const others = (machines() ?? []).map((x) => x.name).filter(Boolean);
    const item = (name) => h_flex().id(`computer-${name ?? "local"}`).h(28).px(10).items_center().rounded(6).cursor_pointer()
      .text_color(m === name ? t.foreground : t.muted).when(m === name, (el) => el.bg(t.raised)).hover((s) => s.bg(t.hover).text_color(t.foreground))
      .on_click((_e, cx) => { this.computer = name; this.editing = null; this.picking = false; cx.notify(); }).child(name ?? "This computer");
    const dropdown = v_flex().flex_none().pb(6)
      .child(h_flex().id("computer-pick").h(30).px(10).gap(8).items_center().rounded(7).cursor_pointer()
        .border_1().border_color(this.picking ? t.accent : t.input).bg(t.background).hover((s) => s.border_color(t.accent))
        .on_click((_e, cx) => { this.picking = !this.picking; cx.notify(); })
        .child(svg(`mods/workspace-chrome/${m ? "server" : "monitor"}.svg`).size(13).flex_none().text_color(t.dim))
        .child(div().flex_1().min_w(0).truncate().child(m ?? "This computer"))
        .child(svg(`mods/workspace-chrome/chevron-${this.picking ? "right" : "down"}.svg`).size(11).flex_none().text_color(t.dim)))
      .when(Boolean(this.picking), (el) => el.child(v_flex().mt(4).p(4).rounded(8).border_1().border_color(t.border).bg(t.popover)
        .child(item(null)).children(others.map(item))));
    if (!this.setup && this.page !== "folders") return this.viewPage(t, o, group, check, choice);
    return v_flex().flex_none()
      .child(group("Folders", "Each git repo in Projects gets a space.", true))
      // This dialog in setup mode again: folders, which spaces are pinned, the options.
      .when(!m && !this.setup, (el) => el.child(h_flex().id("run-setup").h(26).px(8).mb(6).gap(6).flex_none().self_start().rounded(6).items_center().cursor_pointer()
        .border_1().border_color(t.input).text_size(11.5).text_color(t.dim).hover((s) => s.text_color(t.foreground))
        .on_click((_e, cx) => { this.setup = true; this.tab = "options"; cx.notify(); })
        .child(svg("mods/workspace-chrome/settings.svg").size(12)).child("Run setup again")))
      .when(others.length > 0, (el) => el.child(dropdown))
      .child(place("chats", "Chats"))
      .child(place("projects", "Projects"))
      .when(!m, (el) => el.child(check(["keepUpToDate", "Add new projects automatically", "Off: add them from + \u203a Add spaces"])))
      .child(m ? this.remoteHandoff(t, o, m) : check(["handoffRule", "Hand off project work", HANDOFF]))
      // The footer's look for a newer Over9k (the Update chip, the notice above).
      .when(!m && !this.setup, (el) => el.child(group("Updates", null)).child(check(["checkUpdates", "Check for updates", "Every few hours, from the folder you installed from"])))
      // Setup mode: the spaces to pin, then Done (the view settings stay in Options).
      .when(Boolean(this.setup), (el) => el.child(this.spacesGroup(t, group, cx)));
  }

  // Setup's Spaces: everything found (and pinned), each with Pin / Pinned as in
  // the + menu's lists; Pin all; Automatically scan for spaces adds the wider scan.
  spacesGroup(t, group, cx) {
    const pinned = new Set(shared("projects.pinned") ?? []);
    const found = [...new Set([...(shared("projects.auto") ?? []), ...pinned, ...(this.more ?? [])])]
      .sort((a, b) => a.split("/").pop().localeCompare(b.split("/").pop(), undefined, { sensitivity: "base" }));
    const pin = (dirs, on) => {
      const p = new Set(shared("projects.pinned") ?? []), u = new Set(shared("projects.unpinned") ?? []);
      dirs.forEach((d) => { if (on) { p.add(d); u.delete(d); } else { p.delete(d); u.add(d); } });
      setShared("projects.pinned", [...p]);
      setShared("projects.unpinned", [...u]);
    };
    const button = (id, text, on, fn) => h_flex().id(id).h(20).px(6).flex_none().rounded(5).items_center().cursor_pointer()
      .border(1).border_color(t.border).text_size(11).text_color(on ? t.foreground : t.dim).hover((s) => s.bg(t.hover).text_color(t.foreground))
      .on_click((_e, cx) => { fn(); cx.notify(); }).child(text);
    const all = found.length > 0 && found.every((d) => pinned.has(d));
    return v_flex().flex_none()
      .child(group("Spaces", "Pinned ones stay in the sidebar."))
      .child(h_flex().px(4).pb(4).justify_end().child(button("pin-all", "Pin all", all, () => pin(found, true))))
      .child(div().id("spaces-wrap").flex_none().on_scroll_wheel((_e, cx) => cx.stop_propagation()).child(
        v_flex().id("spaces-list").h(200).flex_none().overflow_y_scrollbar().rounded(8).border_1().border_color(t.border).p(4)
          .children(found.map((d) => h_flex().id(`sp-${d}`).h(28).px(6).gap(10).items_center().rounded(6)
            .child(div().flex_1().min_w(0).truncate().text_color(t.foreground).child(d.split("/").pop()))
            .child(div().flex_none().text_size(11).text_color(t.dim).child((d.startsWith(home() + "/") ? `~${d.slice(home().length)}` : d).split("/").slice(0, -1).join("/")))
            .child(button(`pin-${d}`, pinned.has(d) ? "Pinned" : "Pin", pinned.has(d), () => pin([d], !pinned.has(d))))))))
      .child(h_flex().id("scan-more").mt(6).h(30).px(4).gap(10).items_center().rounded(7).cursor_pointer()
        .hover((s) => s.bg(t.hover)).on_click((_e, cx) => this.scanMore(cx))
        .child(svg("mods/workspace-chrome/search.svg").size(14).flex_none().text_color(t.foreground))
        .child(div().flex_1().text_color(t.foreground).child("Find more in your home folder"))
        .child(div().flex_none().text_size(11).text_color(t.dim).child(this.scanning ? "Scanning\u2026" : this.more?.length ? `${this.more.length} found` : "")));
  }

  // Wider than the sidebar's own: git repos up to two levels under home and
  // folders Claude Code has worked in (the + menu's scan does the same).
  scanMore(cx) {
    this.scanning = true;
    cx.notify();
    cx.spawn(async (cx) => {
      const r = await exec("sh", ["-c", MORE]).catch(() => null);
      this.more = (r?.stdout ?? "").split("\n").filter((d) => d && d !== home() && !d.startsWith("/tmp/"));
      this.scanning = false;
      cx.notify();
    });
  }

  // Space rows, Agent rows or Subagent rows: heading, sample, then what it shows.
  viewPage(t, o, group, check, choice) {
    // A note that some of a page's details need an agent's footer, with a link to
    // the Session footers page (and from there back to the pages they fill).
    const goTo = (id, page, label) => h_flex().id(id).flex_none().gap(3).items_center().cursor_pointer().text_color(t.accent)
      .hover((s) => s.text_color(t.foreground)).on_click((_e, cx) => { this.page = page; cx.notify(); })
      .child(label).child(svg("mods/workspace-chrome/chevron-right.svg").size(10));
    const needs = (id, text, page = "claude", label = "Session footers") => h_flex().flex_none().flex_wrap().pt(10).gap_x(6).gap_y(2).items_center()
      .text_size(11.5).text_color(t.dim).child(text).child(goTo(`link-${id}`, page, label));
    const page = v_flex().flex_none();
    if (this.page === "spaces") return page
      .child(group("Space rows", "Shown next to the name. All clickable.", true))
      .child(this.sample(t, this.spaceSample(t, o)))
      .child(group("Git", "From the repo on this computer.", false))
      .children(SPACE_ITEMS.map(check))
      .child(group("GitHub", "For repos on GitHub. Counts need gh, signed in; checked every 5 minutes.", false))
      .children(GITHUB_ITEMS.map(check));
    if (this.page === "agents") return page
      .child(group("Agent rows", "Compact: one line. Expanded: details below the name (always, in Agents \u203a Status).", true))
      .child(h_flex().gap(8).pb(8)
        .child(choice("compact", "Compact", o.layout === "compact"))
        .child(choice("expanded", "Expanded", o.layout === "expanded")))
      .child(this.sample(t, this.agentSample(t, o)))
      .children(AGENT_ITEMS.map(check))
      .child(needs("agents", "Antigravity's context needs its session footer."));
    if (this.page === "usage") return page
      .child(group("Usage", "Each service's 5-hour and weekly limits. Green, yellow from 50%, red from 80%. Click a row for every limit, and a limit to make it that row's headline.", true))
      .children(USAGE_ITEMS.map(check))
      .child(needs("usage", "Claude's and Gemini's limits need their session footer."));
    if (this.page === "timeline") return page
      .child(group("Timeline", "Your prompts in the agent you're in, in the right panel: what it did, how long it worked, when it finished, tokens.", true))
      .child(check(["timeline", "Timeline", "On: the Timeline button and panel. Off: both hidden"]));
    if (this.page === "claude") return page
      .child(group("Session footers", "The line under an agent's prompt. Agent rows, subagent rows and Usage read each agent directly: its files, or the session footer it already shows. Some details only reach a session footer, so those agents need Over9k's.", true))
      .child(check(["claudeStatus", "Claude Code", "Needed for Claude's 5-hour and weekly limits (or API spend) in Usage."]))
      .child(check(["agyStatus", "Antigravity", this.agyHere === false ? "Antigravity isn't installed on this computer." : "Needed for the agent's context in Agent rows, and Gemini's limits in Usage."]))
      .child(h_flex().flex_none().pt(4).gap(14).child(goTo("link-f-agents", "agents", "Agent rows")).child(goTo("link-f-usage", "usage", "Usage")))
      .child(div().pt(8).text_size(11).text_color(t.dim).child("Codex and Pi need none. While one is on, it shows instead of any session footer you set up yourself; yours comes back when it's off. Applies to agents you start next."));
    if (this.page === "todos") return page
      .child(group("To-do", "Each project's list, in the right panel. Agents add to it and tick it too.", true))
      .child(check(TODO_ITEMS[0]))
      .when(o.todos, (el) => el.child(group("Each project starts with", "Until you switch them for a project in the To-do panel (pick its pill).", false))
        .child(check(["todoLog", "Log", "Agents add what you ask for to the project's list"]))
        .child(check(["todoSync", "Sync", "The project's TODO.md follows the list"])));
    return page
      .child(group("Subagent rows", "Claude Code's subagents, listed under their agent.", true))
      .child(this.sample(t, this.agentSample(t, o, true)))
      .children(SUB_ITEMS.map(check));
  }

  // Another computer's Automatic hand off: kept with its folders; over9k installs
  // its helper there (or removes it) and writes the rule into its CLAUDE.md/AGENTS.md.
  remoteHandoff(t, o, m) {
    const on = Boolean(o.computers?.[m]?.handoffRule);
    return h_flex().id(`handoff-${m}`).min_h(30).py(5).px(4).gap(10).items_center().rounded(7).cursor_pointer()
      .hover((s) => s.bg(t.hover))
      .on_click(() => this.set("computers", { ...(o.computers ?? {}), [m]: { ...(o.computers?.[m] ?? {}), handoffRule: !on } }))
      .child(h_flex().size(16).flex_none().rounded(4).items_center().justify_center()
        .border_1().border_color(on ? t.accent : t.input).bg(on ? t.accent : t.background)
        .when(on, (el) => el.child(svg("mods/workspace-chrome/check.svg").size(11).text_color(t.accent_foreground))))
      .child(v_flex().flex_1().min_w(0).child(div().text_color(t.foreground).child("Hand off project work"))
        .child(div().text_size(11).text_color(t.dim).child(HANDOFF)));
  }

  // A made-up row drawn like the sidebar's (same sizes and gaps), showing what
  // the switches do: off parts are hidden, as there. Hovering and clicking act
  // as there too (hover text on the right, the push button asking twice, the ×,
  // "clear + recap"), only nothing really happens.
  sample(t, row) {
    return v_flex().flex_none().mb(6).rounded(8).bg(t.chrome).border_1().border_color(t.border).text_size(13).child(row);
  }

  // A part of the space sample: its hover text shows on the row's right; a
  // click shows what it would do (`then`, or the hover text again).
  part(t, key, el, text, then) {
    return el.id(`sample-${key}`).rounded(4).hover((s) => s.bg(t.hover))
      .on_hover((on, cx) => { if (on) this.tip = text; else if (this.tip === text) this.tip = null; cx.notify(); })
      .on_click((_e, cx) => { this.tip = then ? then() : text; cx.notify(); });
  }

  spaceSample(t, o) {
    const tip = this.tip && !this.tip.startsWith("agent:") ? this.tip : null;
    const on = this.spaceHover;
    return v_flex().id("sample-space").px(8).h(30).justify_center().rounded(8).hover((s) => s.bg(t.hover))
      .on_hover((h, cx) => { this.spaceHover = h; cx.notify(); })
      .child(h_flex().gap(9).items_center()
        .child(div().flex_none().text_color("#5b8def").child("my-project"))
        .when(o.github, (el) => el.child(this.part(t, "github", div().flex_none().ml(-5).p(2).text_color(t.dim).hover((s) => s.text_color(t.foreground)).child(svg("mods/over9k/github.svg").size(13)), "Open in GitHub")))
        .child(h_flex().flex_none().gap(3).items_center().text_size(11.5)
          .when(o.dirty, (el) => el.child(this.part(t, "dirty", div().px(2).text_color(t.ansi3).child("4"), "See 4 uncommitted files")))
          .when(o.sync, (el) => el
            .child(this.part(t, "ahead", div().px(2).text_color(t.ansi2).when(this.armed, (e) => e.bg(t.hover)).child("\u21912"),
              this.armed ? "Click again to push" : "Push 2 commits",
              () => { this.armed = !this.armed; return this.armed ? "Click again to push" : "Pushed 2 commits"; }))
            .child(this.part(t, "behind", div().px(2).text_color(t.ansi1).child("\u21931"), "Pull 1 new commit")))
          .when(o.prs, (el) => el.child(this.part(t, "prs", h_flex().px(2).gap(2).items_center().text_color(t.dim).child(svg("mods/over9k/pull-request.svg").size(11)).child("3"), "Open 3 pull requests")))
          .when(o.issues, (el) => el.child(this.part(t, "issues", h_flex().px(2).gap(2).items_center().text_color(t.dim).child(svg("mods/over9k/issue.svg").size(11)).child("2"), "Open 2 issues")))
          .when(o.stars, (el) => el.child(this.part(t, "stars", h_flex().px(2).gap(2).items_center().text_color(t.dim).child(svg("mods/over9k/star.svg").size(11)).child("8"), "8 stars on GitHub"))))
        // As there: the fold chevron and (FOLD), the hover text or folder, the + (ADD).
        .child(h_flex().w(16).flex_none().items_center().justify_center().text_color(t.dim)
          .child(svg("mods/workspace-chrome/chevron-down.svg").size(10).opacity(on ? 1 : 0)))
        .child(h_flex().flex_1().min_w(0).justify_end().items_center().text_size(11).text_color(t.dim)
          .when(Boolean(tip ?? on), (el) => el.child(div().min_w(0).truncate().child(tip ?? "~/Code/my-project"))))
        .child(h_flex().w(22).flex_none().justify_center()
          .when(Boolean(on), (el) => el.child(h_flex().size(18).items_center().justify_center().rounded(5).text_color(t.dim)
            .child(svg("mods/workspace-chrome/plus.svg").size(12))))));
  }

  // As the sidebar draws an agent now: its details dotted, then the link chip
  // (it works on another computer too) and the count chip (in compact, just the
  // total); under it, what it started on a line, each with its kind on it.
  // `subs`: the agent with two subagents, for Subagent rows.
  agentSample(t, o, subs = false) {
    const compact = o.layout === "compact";
    const hover = this.tip === "agent:row" || this.tip === "agent:exp";
    const dotted = (parts) => parts.flatMap((el, n) => (n ? [div().px(1).child("\u00b7"), el] : [el]));
    const info = h_flex().flex_none().items_center().text_size(11).text_color(t.dim)
      .children(dotted([
        o.model && div().child("Opus 5.5"),
        o.effort && div().child("high"),
        o.context && div().text_color(t.ansi2).child("42%"),
        o.since && div().child("3m"),
      ].filter(Boolean)))
      .when(o.cache, (el) => el.child(div().id("sample-exp").ml(4).px(2).rounded(4).text_color(t.ansi1).hover((s) => s.bg(t.hover))
        .on_hover((on, cx) => { this.tip = on ? "agent:exp" : "agent:row"; cx.notify(); })
        .child(this.tip === "agent:exp" ? "clear + recap" : "exp.")));
    const link = "#8b7cf6", fg = t.foreground, wash = (a) => (/^#[0-9a-f]{6}$/i.test(fg) ? fg + a : t.raised);
    const chips = h_flex().flex_none().gap(5).items_center()
      .child(h_flex().h(16).px(4).gap(3).items_center().rounded(4).bg(link + "26").text_size(10.5).text_color(link)
        .child(svg("mods/over9k/bot.svg").size(10)).child("\u2192"))
      .child(h_flex().h(16).px(4).gap(3).items_center().rounded(4).bg(wash(hover ? "29" : "1a")).text_size(10.5).text_color(fg)
        .when(compact, (el) => el.child("3"))
        .when(!compact, (el) => el.child(svg("mods/over9k/subagent.svg").size(10)).child("1")
          .child(svg("mods/over9k/cpu.svg").size(10).ml(3)).child("1").child(svg("mods/over9k/clock.svg").size(10).ml(3)).child("1"))
        .child(svg("mods/workspace-chrome/chevron-down.svg").size(8)));
    const name = div().min_w(0).truncate().text_size(12.5).text_color(t.foreground).when(!compact, (el) => el.line_height("15px")).child("Fix the login bug");
    const agent = h_flex().id("sample-agent").h(compact ? 26 : 36).pl(4).pr(8).gap(8).items_center().rounded(7).hover((s) => s.bg(t.hover))
      .on_hover((on, cx) => { if (on) this.tip = this.tip === "agent:exp" ? this.tip : "agent:row"; else if (this.tip?.startsWith("agent:")) this.tip = null; cx.notify(); })
      .child(h_flex().flex_none().gap(4).items_center()
        .child(h_flex().w(16).flex_none().justify_center()
          .when(hover, (el) => el.child(h_flex().size(16).items_center().justify_center().rounded(4).text_color(t.dim).hover((s) => s.bg(t.hover).text_color(t.foreground))
            .child(svg("mods/pane/close.svg").size(11))))
          .when(!hover, (el) => el.child(svg("mods/workspace-chrome/spinner.svg").size(12).text_color(t.working).spin(900))))
        .child(image("icons/claude.svg").w(14).h(14).flex_none()))
      // As there: compact, the chips end the details' line; expanded, they end
      // the name's line, the details under it.
      .when(compact, (el) => el.child(v_flex().flex_1().min_w(0).child(h_flex().min_w(0).gap(6).items_center().child(name)))
        .child(info.child(chips.ml(5))))
      .when(!compact, (el) => el.child(v_flex().flex_1().min_w(0).overflow_hidden()
        .child(h_flex().min_w(0).gap(6).items_center().child(name).child(div().flex_1()).child(chips))
        .child(info.line_height("13px"))));
    // A sub-row: status, its kind on the line (the last one's line ends there), name, details.
    const sub = (icon, logo, text, details, last, spin) => h_flex().h(22).pl(10).pr(8).gap(3).items_center().text_size(12)
      .child(h_flex().w(12).pt(2).flex_none().justify_center().when(spin, (el) => el.child(svg("mods/workspace-chrome/spinner.svg").size(10).text_color(t.working).spin(900))))
      .child(v_flex().w(12).h(22).flex_none().items_center()
        .child(div().w(1.5).h(icon.endsWith("subagent.svg") ? 5 : 6).flex_none().bg(t.input))
        .child(svg(icon).size(icon.endsWith("subagent.svg") ? 12 : 9).flex_none().my(1).text_color(t.dim))
        .child(div().w(1.5).flex_1().when(!last, (el) => el.bg(t.input))))
      .when(Boolean(logo), (el) => el.child(image(logo).w(13).h(13).flex_none()))
      .child(h_flex().flex_1().min_w(0).gap(6).items_center()
        .child(h_flex().flex_1().min_w(0).child(div().min_w(0).truncate().line_height("15px").text_color(t.muted).child(text)))
        .child(h_flex().flex_none().items_center().text_size(11).text_color(t.dim).children(dotted(details.map((d) => div().child(d))))));
    // A subagent's details, as Subagent rows says: model, effort, its type when
    // not the usual one, context, running for.
    const subFacts = (model, effort, type, k, ran) => [o.subModel && model, o.subEffort && effort, type, o.subContext && k, o.subTime && ran].filter(Boolean);
    if (subs) return v_flex().flex_none()
      .child(agent)
      .child(sub("mods/over9k/subagent.svg", "icons/claude.svg", "Read the auth code", subFacts("Haiku 5.5", "low", "explore", "18k", "2m"), false, true))
      .child(sub("mods/over9k/subagent.svg", "icons/claude.svg", "Write the tests", subFacts("Sonnet 5.5", "med", null, "98k", "13m"), true, true));
    return v_flex().flex_none()
      .child(agent)
      .child(sub("mods/over9k/subagent.svg", "icons/claude.svg", "Read the auth code", subFacts("Haiku 5.5", "low", "explore", "18k", "2m"), false, true))
      .child(sub("mods/over9k/cpu.svg", null, "npm run dev", ["shell", "5m"], false, false))
      .child(sub("mods/over9k/clock.svg", null, "Check the deploy", ["every 1h at :07"], true, false));
  }


  // Help: a picture of each thing Over9k adds, and how to use it (help.js).
  // The left column: Options' pages, or Help's pages under their parts. The
  // picked one is highlighted.
  nav(t) {
    const item = (id, text, on, pick) => h_flex().id(`nav-${id}`).h(28).px(10).items_center().rounded(7).cursor_pointer()
      .text_color(on ? t.foreground : t.muted).when(on, (el) => el.bg(t.raised).font_medium()).hover((s) => s.bg(t.hover).text_color(t.foreground))
      .on_click((_e, cx) => { pick(); cx.notify(); }).child(div().truncate().child(text));
    const head = (text) => div().px(10).pt(12).pb(4).text_size(10.5).text_color(t.dim).child(text.toUpperCase());
    const col = v_flex().id("nav").w(176).flex_none().h_full().overflow_y_scrollbar().pr(10).border_r_1().border_color(t.border);
    if (this.tab !== "help") return col.children(PAGES.map(([id, text]) => item(id, text, this.page === id, () => { this.page = id; })));
    const topics = helpTopics(this, theme());
    return col.children(topics.flatMap((x, i) => [...(i === 0 || topics[i - 1].part !== x.part ? [head(x.part)] : []),
      item(`help-${i}`, x.title, this.topic === i, () => { this.topic = i; })]));
  }

  // One Help page: its part and title, the page, then Previous and Next.
  help(t) {
    const topics = helpTopics(this, t), i = Math.min(this.topic, topics.length - 1), x = topics[i];
    const step = (id, label, to) => h_flex().id(id).h(28).px(10).gap(6).items_center().rounded(7).cursor_pointer()
      .border_1().border_color(t.input).text_size(12).text_color(t.muted).hover((s) => s.bg(t.hover).text_color(t.foreground))
      .on_click((_e, cx) => { this.topic = to; cx.notify(); }).child(label);
    return v_flex().flex_none().gap(14)
      .child(v_flex().gap(3)
        .child(div().text_size(10.5).text_color(t.dim).child(x.part.toUpperCase()))
        .child(div().text_size(16).font_semibold().text_color(t.foreground).child(x.title)))
      .child(x.el)
      .child(h_flex().pt(10).gap(8)
        .when(i > 0, (el) => el.child(step("help-prev", `\u2190 ${topics[i - 1].title}`, i - 1)))
        .child(div().flex_1())
        .when(i < topics.length - 1, (el) => el.child(step("help-next", `${topics[i + 1].title} \u2192`, i + 1))));
  }

  // The options as they are now (help.js draws its samples with them).
  opts() {
    return { ...DEFAULTS, ...(shared("sidebar.options") ?? {}) };
  }

  // A newer Over9k where it was installed from (the footer looks: shared
  // "over9k.update"): how many changes, what they are (each commit's subject,
  // newest first), and Update. A failed update shows why here.
  updateCard(t) {
    const u = shared("over9k.update") ?? {};
    const log = (u.log ?? []).slice(0, 8), more = u.behind - log.length;
    const lines = (this.updateError ?? "").split("\n").filter(Boolean).slice(-8);
    return v_flex().id("update").flex_none().mt(14).p(12).gap(4).rounded(8).border_1().border_color(t.accent + "66").bg(t.accent + "14")
      .child(h_flex().gap(10).pb(2).items_center()
        .child(div().flex_1().min_w(0).font_semibold().child(`Update available \u00b7 ${u.behind} change${u.behind === 1 ? "" : "s"}`))
        .child(h_flex().id("update-now").h(26).px(12).flex_none().rounded(7).items_center().bg(t.solid).text_color(t.solid_foreground)
          .when(!this.updating, (el) => el.cursor_pointer().hover((s) => s.opacity(0.88)).on_click((_e, cx) => this.update(u, cx)))
          .when(Boolean(this.updating), (el) => el.opacity(0.7))
          .child(this.updating ? "Updating\u2026" : "Update")))
      .children(log.map((s, i) => h_flex().id(`update-${i}`).gap(7).text_size(12).text_color(t.muted)
        .child(div().flex_none().text_color(t.dim).child("\u2022")).child(div().flex_1().min_w(0).truncate().child(s))))
      .when(more > 0, (el) => el.child(div().pl(14).text_size(11.5).text_color(t.dim).child(`and ${more} more`)))
      .when(lines.length > 0, (el) => el.child(v_flex().mt(6).p(8).rounded(6).bg(t.background).text_size(11.5).text_color(t.ansi1)
        .child(div().text_color(t.foreground).child("Couldn't update:"))
        .children(lines.map((l) => div().child(l)))));
  }

  // Pulls and installs the newer Over9k (UPDATE). Herdr reloads the mods as
  // they land, this one too, so the shared state and the note go first.
  update(u, cx) {
    this.updating = true;
    this.updateError = null;
    cx.notify();
    cx.spawn(async (cx) => {
      const r = await exec("sh", ["-c", UPDATE, "sh", u.path, u.branch, appHome()]).catch((e) => ({ code: 1, stdout: String(e) }));
      if (r?.code === 0) {
        setShared("over9k.update", { behind: 0, checked: Date.now() });
        notify({ title: "Over9k updated", body: "Already running: no restart needed.", level: "success" });
      } else this.updateError = (r?.stdout || r?.stderr || "").trim() || "It stopped without saying why.";
      this.updating = false;
      cx.notify();
    });
  }

  render(cx) {
    const t = theme();
    const o = { ...DEFAULTS, ...(shared("sidebar.options") ?? {}) };
    const tab = (id, text) => div().id(`tab-${id}`).px(10).h(26).flex().items_center().rounded(6).cursor_pointer()
      .text_color(this.tab === id ? t.foreground : t.dim).when(this.tab === id, (el) => el.bg(t.raised))
      .hover((s) => s.text_color(t.foreground)).on_click((_e, cx) => { this.tab = id; cx.notify(); }).child(text);
    return v_flex().id("over9k-options").track_focus(this.handle)
      .on_key_down((e, cx) => { if (e.key === "escape") { closeOverlay(props().overlay); cx.stop_propagation(); } })
      .size_full().min_h(0).p(18).bg(t.popover).text_size(12.8).text_color(t.foreground)
      // Setup mode (first run, or Run setup again): its own title, no tabs, a Done button.
      .child(h_flex().items_center().gap(8)
        .child(div().text_size(15).font_semibold().child(this.setup ? "Set up Over9k" : "Over9k"))
        .child(h_flex().flex_1().gap(2).pl(8).when(!this.setup, (el) => el.child(tab("options", "Options")).child(tab("help", "Help"))))
        .when(!this.setup, (el) => el.child(h_flex().id("star-github").h(24).px(8).gap(5).flex_none().items_center().rounded(6).cursor_pointer()
          .text_size(11.5).text_color(t.dim).hover((s) => s.bg(t.hover).text_color(t.foreground))
          .on_click((_e, cx) => cx.open_url(REPO))
          .child(svg("mods/over9k-options/star.svg").size(12).flex_none()).child("Star on GitHub")))
        .child(div().text_size(11).text_color(t.dim).child("Esc")))
      // A newer Over9k (not in setup): above Options and Help alike.
      .when(!this.setup && o.checkUpdates && shared("over9k.update")?.behind > 0, (el) => el.child(this.updateCard(t)))
      // The navigator (not in setup), then the page, which scrolls when it's long.
      .child(h_flex().flex_1().min_h(0).pt(14).gap(18).items_start()
        .when(!this.setup, (el) => el.child(this.nav(t)))
        .child(v_flex().id(`body-${this.tab}-${this.tab === "help" ? this.topic : this.page}`).flex_1().min_w(0).h_full().overflow_y_scrollbar()
          // Room on the right for the scrollbar.
          .child(div().pr(14).pb(8).child(this.tab === "help" ? this.help(t) : this.options(t, o, cx)))))
      .when(Boolean(this.setup), (el) => el.child(h_flex().pt(12).justify_end()
        .child(h_flex().id("setup-done").h(32).px(16).rounded(8).items_center().cursor_pointer().bg(t.solid).text_color(t.solid_foreground)
          .hover((s) => s.opacity(0.88)).on_click(() => closeOverlay(props().overlay)).child("Done"))));
  }
}
