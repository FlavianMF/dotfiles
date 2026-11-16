// Abas para o cabeçalho de uma pilha (stack) do layout.
// Props: { stack: "<id da pilha>", tabs: [["<id do filho>", "<rótulo>"], ...] }.
// Clicar numa aba chama layout.select. A aba ativa vem de layout().

import { View, div } from "gpui-kit";
import { h_flex } from "gpui-base";
import { layout, props, run, theme } from "herdr";

function find(node, id) {
  if (node?.id === id) return node;
  for (const child of node?.children ?? []) {
    const found = find(child, id);
    if (found) return found;
  }
  return null;
}

export default class LowerTabs extends View {
  render(_cx) {
    const t = theme();
    const { stack = "", tabs = [] } = props() ?? {};
    const active = find(layout(), stack)?.active;
    return h_flex().id("lower-tabs").size_full().px(8).gap(4).items_center().bg(t.surface).children(
      tabs.map(([child, label]) =>
        div().id(`lt-${child}`).px(10).py(3).rounded(6).text_size(12)
          .text_color(child === active ? t.foreground : t.muted)
          .bg(child === active ? t.raised : t.surface)
          .hover((s) => s.bg(t.raised))
          .on_click(() => run("layout.select", { stack, child }))
          .child(label)));
  }
}
