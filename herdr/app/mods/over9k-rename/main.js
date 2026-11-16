// Over9k's clone of the shipped prompt: names a space in the Spaces list that isn't open (props { folder, value }); saved in shared projects.names, which
// over9k shows and names its space with when it opens. An empty name
// goes back to the folder's. With { terminal, tab } it names a pane instead:
// an agent's session by the agent's own command (/rename, Pi's /name), a plain
// terminal's tab. Enter saves, Esc cancels.
import { View, div } from "gpui-kit";
import { v_flex, h_flex, InputState, Input } from "gpui-base";
import { props, closeOverlay, theme, shared, setShared, agents, run, hc, exec } from "herdr";

// How each agent renames its session.
const RENAME = { "claude-code": "/rename", claude: "/rename", codex: "/rename", pi: "/name" };

export default class Prompt extends View {
  init(_props, cx) {
    this.text = props()?.value ?? "";
    this.input = InputState.new({ value: this.text });
    if (this.text) this.input.set_selected_range({ start: 0, end: this.text.length });
    this.input.on("change", (_e, cx) => { this.text = this.input.value(); cx.notify(); });
    this.input.on("submit", () => this.submit());
    this.inputFocused = true;
    this.input.on("focus", (_e, cx) => { this.inputFocused = true; cx.notify(); });
    this.input.on("blur", (_e, cx) => { this.inputFocused = false; cx.notify(); });
    this.input.focus();
    cx.timer.after(600, () => this.input.focus());
    this.handle = cx.focus_handle();
  }

  submit() {
    const p = props();
    closeOverlay(p.overlay);
    if (p.terminal) {
      const a = agents().find((x) => x.address === p.terminal);
      const command = a && (RENAME[a.app] ?? RENAME[a.program?.key]);
      const name = this.text.trim();
      if (command && name) {
        // Sent once the agent is idle: typed mid-reply, it would wait in its
        // input queue instead of running (hc wait returns at once when idle).
        exec("sh", ["-c", 'hc wait "$1" >/dev/null 2>&1; hc send "$1" "$2"', "sh", p.terminal, `${command} ${name}`]).catch(() => null);
        // A tab name would show before it: the tab goes back to unnamed when
        // this agent is all it holds.
        if (p.tab && p.alone) run("tab.rename", { id: p.tab, name: "" });
      }
      else if (!command && p.tab) run("tab.rename", { id: p.tab, name });
      return;
    }
    // Another computer's (machine) names are kept with its lists ("projects.on").
    const all = shared("projects.on") ?? {};
    const names = { ...((p.machine ? all[p.machine]?.names : shared("projects.names")) ?? {}) };
    if (this.text.trim()) names[p.folder] = this.text.trim();
    else delete names[p.folder];
    if (p.machine) setShared("projects.on", { ...all, [p.machine]: { ...(all[p.machine] ?? {}), names } });
    else setShared("projects.names", names);
  }

  key(e, cx) {
    if (e.key === "escape") { closeOverlay(props().overlay); cx.stop_propagation(); }
  }

  render() {
    const t = theme();
    const p = props() ?? {};
    const label = (text) => div().pt(16).pb(7).text_size(11.5).text_color(t.dim).child(text);
    const button = (id, text, primary, action) => h_flex().id(id).h(32).px(14).items_center().rounded(8)
      .border_1().border_color(primary ? t.solid : t.input).bg(primary ? t.solid : t.raised)
      .text_color(primary ? t.solid_foreground : t.foreground).text_size(12.5).font_medium().cursor_pointer()
      .hover(s => s.opacity(0.88)).on_click(action).child(text);
    return v_flex().id("prompt").track_focus(this.handle).on_key_down((e, cx) => this.key(e, cx))
      .w_full().min_h(0).p(18).bg(t.popover).text_color(t.foreground)
      .child(h_flex().items_center().child(div().flex_1().text_size(15).font_semibold().child((p.title ?? "").replace(/^./, (c) => c.toUpperCase())))
        .child(div().text_size(11).text_color(t.dim).child("Esc")))
      .child(label("Name"))
      .child(Input.new(this.input).h(36).px(10).rounded(9).border_1().border_color(this.inputFocused ? t.accent : t.input).bg(t.background).text_size(12.8).text_color(t.foreground))
      .when(Boolean(p.hint), el => el.child(div().pt(6).text_size(11.5).text_color(t.dim).child(p.hint)))
      .child(h_flex().pt(20).gap(8).justify_end()
        .child(button("pm-cancel", "Cancel", false, () => closeOverlay(p.overlay)))
        .child(button("pm-save", "Save", true, () => this.submit())));
  }
}
