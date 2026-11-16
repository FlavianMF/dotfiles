import { div } from "gpui-kit";
import { h_flex, v_flex } from "gpui-base";
import { SESSION_TITLE, iconButton, levelColor, rule, sessionNumberColor, usageBar } from "./kit.js";
import { limitsGroup, spendLine } from "./card.js";
import { inPanel } from "../lib/prefs.js";

const PANEL_W = 340;
const SESSION_BAR_W = 60;

export function panelShell(panel) {
  const { t, act } = panel;
  return v_flex().id("ul-panel-body").w(PANEL_W).p(12).gap(10).rounded(8).border(1).border_color(t.border).bg(t.popover).shadow_lg()
    .text_size(12).text_color(t.foreground)
    .on_hover((on, cx) => act.hoverPanel(on, cx));
}

function sessionBlock(v, t) {
  const stats = [v.who, v.context.detail, v.calls, v.compactions, v.last].filter(Boolean).join(" · ");
  return v_flex().gap(4)
    .child(h_flex().gap(6).items_center()
      .child(div().flex_none().font_semibold().child(SESSION_TITLE))
      .child(div().flex_1().min_w(0).truncate().text_color(t.dim).child(v.title))
      .when(v.context.fill != null, (r) => r.child(usageBar(SESSION_BAR_W, v.context.fill, null, levelColor(v.context.level, t), t)))
      .child(div().flex_none().whitespace_nowrap().text_color(sessionNumberColor(v.context.level, v.context.text, t)).child(`ctx ${v.context.text}`)))
    .child(div().text_size(11).text_color(t.dim).child(stats));
}

function choiceRow(row, panel) {
  return div().id(`ul-session-${row.id}`).py(4).px(6).rounded(4)
    .cursor_pointer().hover((s) => s.bg(panel.t.hover)).on_click((_e, cx) => panel.act.chooseSession(row, cx))
    .child(div().truncate().child(row.title || row.id));
}

function sessionPicker(panel) {
  const { t, act, choosing, choices } = panel;
  return v_flex().gap(5)
    .child(div().font_semibold().child(SESSION_TITLE))
    .child(div().id("ul-pick-session").text_size(11).text_color(t.dim).cursor_pointer()
      .on_click((_e, cx) => act.togglePicker(cx))
      .child(choosing ? "Cancel" : "Choose Codex session…"))
    .when(choosing, (el) => el.children(choices.choices.map((row) => choiceRow(row, panel))));
}

const changeSession = (panel) => div().id("ul-change-session").text_size(11).text_color(panel.t.dim).cursor_pointer()
  .on_click((_e, cx) => panel.act.changeSession(cx)).child("Change Codex session");

function footer(panel) {
  const { t, act, cooling } = panel;
  return h_flex().gap(2).justify_end().items_center()
    .child(iconButton({ id: "ul-refresh", icon: "refresh", label: cooling ? "Refreshing…" : "Refresh now", enabled: !cooling, onClick: act.refresh }, t))
    .child(iconButton({ id: "ul-settings", icon: "gear", label: "Settings", enabled: true, onClick: (cx) => act.show("settings", cx) }, t));
}

export function limitsPanel(model, session, panel) {
  const { t } = panel;
  const body = panelShell(panel);
  const sessionInPanel = inPanel(panel.prefs, "session");
  if (session) body.child(sessionBlock(session, t)).child(rule(t));
  if (sessionInPanel && panel.manual) body.child(changeSession(panel));
  if (sessionInPanel && panel.choices) body.child(sessionPicker(panel)).child(rule(t));
  model.groups.forEach((g, i) => {
    if (i > 0) body.child(rule(t));
    body.child(g.kind === "spend" ? spendLine(g, t) : limitsGroup(g, model.arrows, panel));
  });
  return body.child(rule(t)).child(footer(panel));
}
