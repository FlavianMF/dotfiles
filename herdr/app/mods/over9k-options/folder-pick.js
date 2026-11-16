// A folder chooser: type a path, or click through the folders in it (↑ goes
// up); on this computer Browse… also opens the system's folder picker. On
// another computer (machine) the folders are listed there. Over9k's settings
// use it to change their folders.
import { div, svg } from "gpui-kit";
import { v_flex, h_flex, InputState, Input } from "gpui-base";
import { exec, pickFolder } from "herdr";

// The folders in $1 (~ for home), one name per line; fails when it isn't one.
const LIST = 'case "$1" in "~") d=$HOME ;; "~/"*) d="$HOME/${1#"~/"}" ;; *) d=$1 ;; esac; [ -d "$d" ] || exit 1; for s in "$d"/*/; do [ -d "$s" ] && basename "$s"; done';

export class FolderPick {
  // `done(path, cx)` runs on Enter or Use; `home` turns this computer's home into ~.
  constructor({ value, machine = null, home = null, done }) {
    this.machine = machine;
    this.home = home;
    this.done = done;
    this.subs = null;
    this.input = InputState.new({ value: value || "~", placeholder: "~/folder" });
    this.input.on("change", (_e, cx) => this.list(cx));
    this.input.on("submit", (_e, cx) => this.use(cx));
    this.input.focus();
  }

  path() {
    return this.input.value().trim().replace(/(.)\/+$/, "$1");
  }

  // The folders in what's typed (none when it isn't a folder).
  list(cx) {
    const at = this.path();
    cx.spawn(async (cx) => {
      const r = await exec("sh", ["-c", LIST, "sh", at], this.machine ? { on: this.machine } : {}).catch(() => null);
      if (this.path() !== at) return; // typed on meanwhile
      this.subs = r?.code === 0 ? r.stdout.split("\n").filter(Boolean) : [];
      cx.notify();
    });
  }

  go(path, cx) {
    this.input.set_value(path);
    this.list(cx);
  }

  use(cx) {
    const p = this.path();
    if (p) this.done(p, cx);
    cx.notify();
  }

  tilde(d) {
    return this.home && (d === this.home || d.startsWith(this.home + "/")) ? `~${d.slice(this.home.length)}` : d;
  }

  view(t, cx) {
    if (this.subs === null) { this.subs = []; this.list(cx); }
    const p = this.path();
    const up = p === "/" || p === "~" ? null : p.replace(/\/[^/]*$/, "") || (p.startsWith("~") ? "~" : "/");
    const button = (id, text, primary, fn) => h_flex().id(id).h(28).px(9).flex_none().rounded(6).items_center().cursor_pointer()
      .border_1().border_color(primary ? t.solid : t.input).bg(primary ? t.solid : t.raised)
      .text_size(12).text_color(primary ? t.solid_foreground : t.foreground).hover((s) => s.opacity(0.88))
      .on_click((_e, cx) => fn(cx)).child(text);
    const row = (id, icon, text, fn) => h_flex().id(id).h(26).px(6).gap(8).flex_none().items_center().rounded(6).cursor_pointer()
      .text_color(t.muted).hover((s) => s.bg(t.hover).text_color(t.foreground)).on_click((_e, cx) => fn(cx))
      .child(svg(`mods/workspace-chrome/${icon}.svg`).size(12).flex_none()).child(div().flex_1().min_w(0).truncate().child(text));
    return v_flex().flex_none().gap(6)
      .child(h_flex().gap(6).items_center()
        .child(Input.new(this.input).flex_1().h(28).px(8).rounded(6).border_1().border_color(t.accent).bg(t.background).text_size(12.5))
        .when(!this.machine, (el) => el.child(button("pick-browse", "Browse…", false, (cx) => cx.spawn(async (cx) => {
          const d = await pickFolder({ prompt: "Choose a folder" });
          if (d) this.go(this.tilde(d.replace(/\/+$/, "")), cx);
        }))))
        .child(button("pick-use", "Use", true, (cx) => this.use(cx))))
      // The list scrolls itself; around it, the wheel stops so the dialog
      // behind doesn't scroll too.
      .child(div().id("pick-wrap").flex_none().on_scroll_wheel((_e, cx) => cx.stop_propagation()).child(
        v_flex().id("pick-list").h(160).flex_none().overflow_y_scrollbar().rounded(6).border_1().border_color(t.border).p(3)
        .when(Boolean(up), (el) => el.child(row("pick-up", "chevron-left", "↑ up", (cx) => this.go(up, cx))))
        .children(this.subs.map((name) => row(`pick-${name}`, "folder", name, (cx) => this.go(`${p === "/" ? "" : p}/${name}`, cx))))
        .when(this.subs.length === 0, (el) => el.child(div().px(6).py(4).text_size(11.5).text_color(t.dim).child("No folders here")))));
  }
}
