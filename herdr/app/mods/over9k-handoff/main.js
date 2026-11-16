// Over9k's Hand off dialog (an agent's right-click menu): pick a space to hand
// the agent's work to, or type a name for a new one in Projects.
// The agent is asked to hand off (it writes the brief), through over9k's
// handoff.sh, the same as when its hand-off rule kicks in. Props { terminal, name }.
// Enter hands off to the first match (or a new space by that name), Esc cancels.

import { View, div, svg } from "gpui-kit";
import { v_flex, h_flex, InputState, Input } from "gpui-base";
import { props, closeOverlay, theme, exec, hc, home } from "herdr";

// over9k's handoff.sh, as over9k (syncHelpers) installs it on each computer:
// outside the mod folder because agents run it by this path (from the hand-off
// rule too), on whichever computer they are on. Relative to home.
const SCRIPT = ".local/share/over9k/handoff.sh";

export default class Handoff extends View {
  init(_props, cx) {
    this.text = "";
    this.spaces = [];
    this.input = InputState.new({ value: "", placeholder: "A space, or a name for a new one" });
    this.input.on("change", (_e, cx) => { this.text = this.input.value(); cx.notify(); });
    this.input.on("submit", () => this.go(this.matches()[0] ?? this.text.trim()));
    this.input.focus();
    cx.timer.after(600, () => this.input.focus());
    this.handle = cx.focus_handle();
    cx.spawn(async (cx) => {
      // The spaces on the agent's own computer ("laptop/t3" is another one's).
      const m = props()?.terminal?.includes("/") ? props().terminal.split("/")[0] : null;
      const r = await exec("sh", ["-c", '[ -f "$HOME/$1" ] || exit 3; sh "$HOME/$1" --list', "sh", SCRIPT], m ? { on: m } : {}).catch(() => null);
      this.missing = r?.code === 3; // no helper there: nothing to hand off with
      this.spaces = (r?.stdout ?? "").split("\n").filter(Boolean);
      cx.notify();
    });
  }

  // Existing spaces whose folder name has what's typed in it.
  matches() {
    const q = this.text.trim().toLowerCase();
    return q ? this.spaces.filter((d) => d.split("/").pop().toLowerCase().includes(q)) : this.spaces;
  }

  go(target) {
    const p = props();
    if (!target || this.missing) return;
    closeOverlay(p.overlay);
    const quoted = target.replace(/"/g, '\\"');
    hc(["send", p.terminal, `Hand this conversation off to ${target}: run \`sh ~/${SCRIPT} --to "${quoted}" --brief "<brief>"\`, with a self-contained brief (what I asked in my words, what you found, what's next, constraints). Then tell me in one line where it went and stop.`]).catch(() => null);
  }

  render() {
    const t = theme();
    const p = props() ?? {};
    const list = this.matches();
    const fresh = this.text.trim() && !this.spaces.some((d) => d.split("/").pop() === this.text.trim());
    const row = (id, icon, text, hint, target) => h_flex().id(id).h(30).px(8).gap(10).items_center().rounded(7).cursor_pointer()
      .hover((s) => s.bg(t.hover)).on_click(() => this.go(target))
      .child(svg(`mods/workspace-chrome/${icon}.svg`).size(14).flex_none().text_color(t.dim))
      .child(div().flex_1().min_w(0).truncate().text_color(t.foreground).child(text))
      .child(div().flex_none().text_size(11).text_color(t.dim).child(hint));
    return v_flex().id("handoff").track_focus(this.handle)
      .on_key_down((e, cx) => { if (e.key === "escape") { closeOverlay(props().overlay); cx.stop_propagation(); } })
      .size_full().min_h(0).p(18).gap(10).bg(t.popover).text_size(12.8).text_color(t.foreground)
      .child(h_flex().items_center().child(div().flex_1().min_w(0).truncate().text_size(15).font_semibold().child(`Hand off ${p.name ?? "this agent"}`))
        .child(div().text_size(11).text_color(t.dim).child("Esc")))
      .child(Input.new(this.input).h(36).px(10).rounded(9).border_1().border_color(t.accent).bg(t.background).text_size(12.8).text_color(t.foreground))
      // A fixed height, so it shows however the dialog is sized.
      .when(Boolean(this.missing), (el) => el.child(div().text_size(11.5).text_color(t.dim).child("Over9k's hand-off helper isn't on this computer yet.")))
      .child(v_flex().id("handoff-list").h(240).flex_none().overflow_y_scrollbar()
        .when(Boolean(fresh), (el) => el.child(row("new", "folder-plus", this.text.trim(), "new in your projects path", this.text.trim())))
        .children(list.map((d) => row(`to-${d}`, "folder", d.split("/").pop(), d.split("/").slice(0, -1).join("/"), d))));
  }
}
