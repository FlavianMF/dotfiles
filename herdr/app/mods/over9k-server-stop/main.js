// Asks before stopping a local model server (over9k' chip on This
// computer's heading). Props { name, port, pid, stop, agents }: stop is
// servers.json's command for it (else the process is ended), agents the ones
// on that model (any: it says they stop until it's back).
// Enter stops, Esc cancels.

import { View, div } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { props, closeOverlay, theme, exec, notify } from "herdr";

export default class ServerStop extends View {
  init(_props, cx) {
    this.handle = cx.focus_handle();
    this.handle.focus();
  }

  stop() {
    const p = props();
    closeOverlay(p.overlay);
    const done = p.stop ? exec("sh", ["-c", p.stop]) : exec("kill", [String(p.pid)]);
    done.catch(() => null).then((r) => notify(r?.code === 0
      ? { title: `Stopped ${p.name}`, level: "success" }
      : { title: `Couldn't stop ${p.name}`, body: (r?.stderr || r?.stdout || "").trim().split("\n").pop(), level: "error" }));
  }

  render() {
    const t = theme();
    const p = props() ?? {};
    const agents = p.agents ?? [];
    const button = (id, label, bg, fg, onClick) =>
      h_flex().id(id).h(32).px(14).items_center().rounded(8).border_1().border_color(id === "no" ? t.input : bg).bg(bg).text_color(fg).cursor_pointer().hover((s) => s.opacity(0.88)).on_click(onClick).child(label);
    return v_flex().id("over9k-server-stop").track_focus(this.handle)
      .on_key_down((e, cx) => {
        if (e.key === "enter") this.stop();
        else if (e.key === "escape") closeOverlay(props().overlay);
        else return;
        cx.stop_propagation();
      })
      .size_full().min_h(0).p(18).gap(12).bg(t.popover).text_size(13)
      .child(h_flex().items_center().child(div().flex_1().text_size(15).font_semibold().text_color(t.foreground).child(`Stop ${p.name ?? "the model server"}?`))
        .child(div().text_size(11).text_color(t.dim).child("Esc")))
      .child(div().flex_1().min_h(0).text_color(t.muted).child(
        `${agents.length ? "Any agent using it stops until it's back. " : ""}It starts again when you open or resume a session on it.`))
      .child(h_flex().justify_end().gap(8).text_size(12)
        .child(button("no", "Cancel", t.raised, t.foreground, () => closeOverlay(props().overlay)))
        .child(button("yes", "Stop", t.ansi1, t.background, () => this.stop())));
  }
}
