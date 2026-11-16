// Over9k's clone of the shipped confirm: asks before closing spaces, tabs and terminals,
// and says what ends ("2 terminals, 1 agent"), not how many tabs. Opened as a
// dialog with props { spaces?, tabs?, panes? } (ids); close-plan.js works out
// the commands. Enter confirms, Esc cancels.

import { View, div } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { run, props, closeOverlay, theme } from "herdr";
import { plan, plural } from "./close-plan.js";

export default class CloseConfirm extends View {
  init(_props, cx) {
    this.handle = cx.focus_handle();
    this.handle.focus();
    this.plan = plan(props() ?? {});
  }

  yes() {
    closeOverlay(props().overlay);
    for (const c of this.plan.commands) run(c.name, c.args);
  }

  render(cx) {
    const t = theme();
    const p = this.plan;
    // One set of words: what ends (terminals, agents), then which spaces go.
    const and = (list) => list.length < 2 ? list.join("") : `${list.slice(0, -1).join(", ")} and ${list[list.length - 1]}`;
    const ends = and([p.terminals && plural(p.terminals, "terminal"), p.agents && plural(p.agents, "agent")].filter(Boolean));
    const names = p.spaceNames.length > 3 ? [...p.spaceNames.slice(0, 3), `${p.spaceNames.length - 3} more`] : p.spaceNames;
    const still = !p.working ? "" : p.working === p.agents ? (p.agents === 1 ? "It's still working." : "They're still working.") : `${p.working} of them still working.`;
    const detail = [ends ? `Ends ${ends}.` : "Nothing running ends.", still, names.length ? `Closes ${and(names)}.` : ""].filter(Boolean).join(" ");
    const button = (id, label, bg, fg, onClick) =>
      h_flex().id(id).h(32).px(14).items_center().rounded(8).border_1().border_color(id === "no" ? t.input : bg).bg(bg).text_color(fg).cursor_pointer().hover((s) => s.opacity(0.88)).on_click(onClick).child(label);
    return v_flex()
      .id("over9k-close")
      .track_focus(this.handle)
      .on_key_down((e, cx) => {
        if (e.key === "enter") this.yes();
        else if (e.key === "escape") closeOverlay(props().overlay);
        else return;
        cx.stop_propagation();
      })
      .size_full()
      .min_h(0)
      .p(18)
      .gap(12)
      .bg(t.popover)
      .text_size(13)
      .child(h_flex().items_center().child(div().flex_1().truncate().text_size(15).font_semibold().text_color(t.foreground).child(p.label ? `Close ${p.label}?` : "Close selected?")).child(div().text_size(11).text_color(t.dim).child("Esc")))
      .child(div().flex_1().min_h(0).text_color(t.muted).child(detail))
      .child(
        h_flex()
          .justify_end()
          .gap(8)
          .text_size(12)
          .child(button("no", "Cancel", t.raised, t.foreground, () => closeOverlay(props().overlay)))
          .child(button("yes", "Close", t.solid, t.solid_foreground, () => this.yes())),
      );
  }
}
