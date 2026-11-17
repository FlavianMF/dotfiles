// The Timeline: your prompts in the agent you're in, the right panel's "Timeline"
// (a child of the panel-body stack, id "prompts"; the tab bar has its button,
// over9k-options turns both off). Newest first, on a line with a dot each: the
// prompt, when you sent it, how long the agent worked on it and when it finished
// (or that it's still working), the tokens it wrote (↓, as the CLI counts them:
// while it works, the CLI's own counter, read off its screen, since the transcript
// only gets a message's tokens once it's finished), the files it changed and
// the commands it ran, and the start of its reply. Click one, or ↑/↓ then Enter,
// to read the whole prompt and the reply (Markdown) here; Esc closes it.
// Claude Code agents only: claude-info.py (Over9k's sidebar runs it; on its own, this
// mod's copy) says which conversation runs in each terminal, from Claude Code's own
// session files (~/.cache/over9k/agents/<terminal>.json); prompts.py reads it.
// Followed: the agent you're in, else the last one you were in.

import { View, div, svg } from "gpui-kit";
import { v_flex, h_flex, TextView } from "gpui-base";
import { theme, exec, home, appHome, focused, agents, panes, readTextFile, hc } from "herdr";

// Python 3 runs as "python3", else "python" (as on Windows): found once.
let PY = null;
const python = (args) => (PY ??= exec("python3", ["-c", "1"]).then((r) => (r?.code === 0 ? "python3" : "python"), () => "python"))
  .then((p) => exec(p, args));

const READER = () => `${appHome()}/mods/over9k-prompts/prompts.py`;
const pad = (n) => String(n).padStart(2, "0");

// "15:30" today, "yesterday 9:00", "mon 15:30", else the date.
function when(iso) {
  const d = new Date(iso);
  if (isNaN(d)) return "";
  const now = new Date(), day = (x) => new Date(x.getFullYear(), x.getMonth(), x.getDate());
  const diff = Math.round((day(now) - day(d)) / 86400000), hm = `${d.getHours()}:${pad(d.getMinutes())}`;
  if (diff === 0) return hm;
  if (diff === 1) return `yesterday ${hm}`;
  if (diff < 7) return `${["sun", "mon", "tue", "wed", "thu", "fri", "sat"][d.getDay()]} ${hm}`;
  return d.toLocaleDateString();
}
// Plain text from Markdown, on one line.
const plain = (s) => (s ?? "").replace(/```[\s\S]*?```/g, " ").replace(/\*\*|__|`|^#+\s*|^>\s*/gm, "").replace(/\[([^\]]+)\]\([^)]*\)/g, "$1").replace(/\s+/g, " ").trim();
// "45s", "5m 12s", "1h 3m".
function took(a, b) {
  const s = Math.max(0, Math.round((new Date(b) - new Date(a)) / 1000));
  if (isNaN(s)) return "";
  if (s < 60) return `${s}s`;
  if (s < 3600) return `${Math.floor(s / 60)}m${s % 60 ? ` ${s % 60}s` : ""}`;
  return `${Math.floor(s / 3600)}h${Math.floor(s / 60) % 60 ? ` ${Math.floor(s / 60) % 60}m` : ""}`;
}
// "840", "12.3k", "1.2M".
const count = (n) => (n < 1000 ? String(n) : n < 1e6 ? `${(n / 1000).toFixed(n < 1e4 ? 1 : 0)}k` : `${(n / 1e6).toFixed(1)}M`);
const hhmm = (iso) => { const d = new Date(iso); return isNaN(d) ? "" : `${d.getHours()}:${pad(d.getMinutes())}`; };
// The start of the reply to a prompt.
function summary(p) {
  // Its first sentence (two when the first is a word or two, like "Done.").
  const parts = plain(p.reply).split(/(?<=[.!?])\s/);
  const first = (parts[0]?.length < 25 && parts[1] ? `${parts[0]} ${parts[1]}` : parts[0]) ?? "";
  return first.length > 140 ? `${first.slice(0, 139)}…` : first;
}

export default class Prompts extends View {
  init(_props, cx) {
    this.handle = cx.focus_handle();
    this.agent = null; // the terminal followed
    this.transcript = null;
    this.size = null; // the transcript's size when last read
    this.prompts = [];
    this.open = null; // the index read in full
    this.at = 0; // the keyboard's row (newest first)
    this.note = "Open an agent to see its prompts";
    this.follow(cx);
    cx.timer.every(2000, (cx) => { this.follow(cx); if (agents().find((x) => x.address === this.agent)?.status === "working") this.readLive(cx); else this.live = null; });
  }

  // The agent you're in (else the last one), its transcript, re-read when it grows.
  follow(cx) {
    const f = focused();
    const here = f?.agent ?? (f?.terminal && agents().some((a) => a.address === f.terminal) ? f.terminal : null);
    if (here && here !== this.agent) { this.agent = here; this.transcript = null; this.size = null; this.open = null; this.at = 0; this.prompts = []; cx.notify(); }
    if (!this.agent || this.busy) return;
    this.busy = true;
    cx.spawn(async (cx) => {
      try {
        let info = await readTextFile(`${home()}/.cache/over9k/agents/${this.agent}.json`).catch(() => null);
        // On its own (no sidebar keeps those files): run claude-info.py here.
        if (!info) {
          const own = `${appHome()}/mods/over9k-prompts/claude-info.py`;
          const r = await python(["-I", (await readTextFile(own).catch(() => null)) != null ? own : `${appHome()}/mods/over9k/claude-info.py`]).catch(() => null);
          try { info = JSON.stringify(JSON.parse(r?.stdout || "{}")[this.agent] ?? null); } catch {}
        }
        let path = null;
        try { path = info && JSON.parse(info)?.transcript; } catch {}
        // Without that file: Claude Code's folder for the agent's
        // working directory (the reader takes its newest conversation).
        const a = agents().find((x) => x.address === this.agent);
        const cwd = panes().find((p) => p.terminal === this.agent)?.cwd;
        const claude = a && (a.app === "claude-code" || a.program?.key === "claude" || /claude/i.test(a.program?.name ?? ""));
        if (!path && claude && cwd) path = `${home()}/.claude/projects/${cwd.replace(/[^A-Za-z0-9]/g, "-")}`;
        if (!path) { this.note = "The timeline shows Claude Code agents"; this.prompts = []; this.transcript = null; cx.notify(); return; }
        // Read only when it has grown (the reader checks its size).
        const r = await python(["-I", READER(), path, this.transcript && this.size != null ? `${this.transcript}\t${this.size}` : ""]).catch(() => null);
        let got = null;
        try { got = JSON.parse(r?.stdout ?? ""); } catch {}
        const list = got?.prompts;
        if (!Array.isArray(list)) return;
        this.prompts = list.reverse();
        this.context = got.context ?? 0;
        this.transcript = got.path ?? path;
        this.size = got.size ?? null;
        this.note = this.prompts.length ? "" : "No prompts yet";
        if (this.at >= this.prompts.length) this.at = 0;
        cx.notify();
      } finally {
        this.busy = false;
      }
    });
  }

  // The working agent's own counter, from the bottom of its screen: Claude Code's
  // "(2m 5s · ↓ 11.4k tokens · …)". Null when it isn't showing.
  readLive(cx) {
    const at = this.agent;
    cx.spawn(async (cx) => {
      const r = await hc(["read", at]).catch(() => null);
      const lines = (r?.stdout ?? "").split("\n").filter((l) => /\(\s*(?:\d+h\s*)?(?:\d+m\s*)?\d+s\s*·\s*↓\s*[\d.]+k?\s*tokens/.test(l));
      const m = /\(\s*(?:(\d+)h\s*)?(?:(\d+)m\s*)?(\d+)s\s*·\s*↓\s*([\d.]+)(k?)\s*tokens/.exec(lines.pop() ?? "");
      this.live = at === this.agent && m ? { secs: (+(m[1] ?? 0)) * 3600 + (+(m[2] ?? 0)) * 60 + +m[3], tokens: Math.round(parseFloat(m[4]) * (m[5] ? 1000 : 1)) } : null;
      cx.notify();
    });
  }

  name() {
    const a = agents().find((x) => x.address === this.agent);
    return a?.tab_name || a?.program?.name || "";
  }

  render(cx) {
    const t = theme();
    const list = this.prompts;
    const working = agents().find((x) => x.address === this.agent)?.status === "working";
    const item = (p, i) => {
      const on = this.open === i, picked = this.at === i, live = i === 0 && working;
      const last = i === list.length - 1;
      // Plain words, joined by dots: done at, time worked, tokens, files, commands.
      const facts = [
        live ? "working" : p.done ? `done ${hhmm(p.done)}` : "",
        live && this.live ? took(0, this.live.secs * 1000) : p.done ? took(p.at, live ? new Date().toISOString() : p.done) : "",
        live && this.live ? `↓ ${count(this.live.tokens)} tokens` : p.tokens ? `↓ ${count(p.tokens)} tokens` : "",
        p.edits.length ? `${p.edits.length} file${p.edits.length > 1 ? "s" : ""}` : "",
        p.cmds ? `${p.cmds} command${p.cmds > 1 ? "s" : ""}` : "",
      ].filter(Boolean);
      // The line and its dot, then the card.
      return h_flex().id(`prompt-${i}`).items_stretch().gap(8).cursor_pointer()
        .on_click((_e, cx) => { this.at = i; this.open = on ? null : i; this.handle.focus(); cx.notify(); })
        .child(v_flex().w(14).flex_none().items_center()
          .child(div().w(2).h(14).bg(i === 0 ? t.background : t.border))
          .child(div().size(10).flex_none().rounded(5).border_2().border_color(live ? t.working : picked || on ? t.accent : t.border).bg(live ? t.working : t.background))
          .child(div().w(2).flex_1().bg(last ? t.background : t.border)))
        .child(v_flex().flex_1().min_w(0).my(4).px(10).py(7).gap(4).rounded(8)
          .bg(on || picked ? t.raised : t.background).border_1().border_color(on ? t.accent : picked ? t.border : t.background).hover((x) => x.bg(t.hover))
          .child(h_flex().gap(6).text_size(10.5).text_color(t.dim)
            .child(div().child(`#${list.length - i}`)).child(div().child(when(p.at))).child(div().flex_1()))
          .child(div().text_size(12.5).line_height("17px").text_color(t.foreground)
            .when(!on, (el) => el.truncate().child(plain(p.text))).when(on, (el) => el.whitespace_normal().child(p.text)))
          // Messages you sent while it worked on this one.
          .when(p.also?.length > 0 && !on, (el) => el.child(div().text_size(11).text_color(t.dim).truncate()
            .child(`+ ${p.also.length} more message${p.also.length > 1 ? "s" : ""}: ${p.also.map((m) => plain(m.text)).join(" · ")}`)))
          .when(p.also?.length > 0 && on, (el) => el.child(v_flex().gap(3).pl(8).border_l(2).border_color(t.border)
            .children(p.also.map((m) => h_flex().gap(6).items_start().text_size(12).line_height("16px")
              .child(div().flex_none().text_size(10.5).text_color(t.dim).pt(1).child(hhmm(m.at)))
              .child(div().flex_1().min_w(0).whitespace_normal().text_color(t.foreground).child(m.text))))))
          .when(facts.length > 0, (el) => el.child(div().text_size(11).text_color(t.dim).truncate()
            .when(live, (el) => el.child(h_flex().gap(0).child(div().text_color(t.working).child(facts[0])).child(div().child(` · ${facts.slice(1).join(" · ")}`))))
            .when(!live, (el) => el.child(facts.join(" · ")))))
          .when(!on && Boolean(p.reply), (el) => el.child(div().text_size(11.5).line_height("16px").text_color(t.muted).truncate().child(summary(p))))
          // Read in full: the reply as Markdown, then what it changed.
          .when(on, (el) => el.child(v_flex().mt(4).pt(6).gap(6).border_t_1().border_color(t.border)
            .child(p.reply ? TextView.markdown(`reply-${list.length - i}`, p.reply).selectable(true).text_size(12.5) : div().text_size(12).text_color(t.dim).child(live ? "Working…" : "(no reply text)"))
            .when(p.edits.length > 0, (el) => el.child(v_flex().gap(1).text_size(11).text_color(t.dim)
              .child(div().child("Changed"))
              .children(p.edits.map((x) => div().truncate().text_color(t.muted).child(x.replace(home(), "~")))))))));
    };
    return v_flex().id("over9k-prompts").track_focus(this.handle).size_full().min_h(0).rounded(10).overflow_hidden()
      .bg(t.background).border_1().border_color(t.border).text_color(t.foreground).text_size(13)
      .on_key_down((e, cx) => {
        if (!list.length) return;
        if (e.key === "down") this.at = Math.min(list.length - 1, this.at + 1);
        else if (e.key === "up") this.at = Math.max(0, this.at - 1);
        else if (e.key === "enter") this.open = this.open === this.at ? null : this.at;
        else if (e.key === "escape") this.open = null;
        else return;
        if (this.open != null && e.key !== "enter" && e.key !== "escape") this.open = this.at;
        cx.notify();
      })
      .child(h_flex().h(42).flex_none().px(14).gap(8).items_center().border_b(1).border_color(t.border)
        .child(div().flex_none().font_semibold().child("Timeline"))
        .when(list.length > 0, (el) => el.child(div().flex_none().px(5).py(1).rounded(4).border_1().border_color(t.border).text_size(10).text_color(t.muted)
          .child(`${list.length} prompt${list.length > 1 ? "s" : ""}`)))
        .child(div().flex_1().min_w(0).truncate().text_right().text_size(12).text_color(t.dim).child(this.name()))
        // As the CLI words them: ↓ what it wrote this session, and the context it holds now.
        .when(list.length > 0, (el) => el.child(div().flex_none().text_size(12).text_color(t.dim)
          .child([`↓ ${count(list.reduce((n, p, i) => n + (i === 0 && working && this.live ? this.live.tokens : p.tokens || 0), 0))}`,
            this.context ? `context ${count(this.context)}` : ""].filter(Boolean).join(" · ")))))
      .when(Boolean(this.note), (el) => el.child(div().px(14).py(10).text_size(12).text_color(t.dim).child(this.note)))
      .child(v_flex().id("prompts-scroll").flex_1().min_h(0).overflow_y_scrollbar().pl(8).pr(8).pt(6).pb(8)
        .children(list.map(item)));
  }
}
