import { View, div, image, svg } from "gpui-kit";
import { h_flex, v_flex } from "gpui-base";
// Over9k's clone of the shipped workspace-chrome: the footer also has Over9k help & options.
import { theme, run, props, window, shared, setShared, updates, layout, openOverlay, exec } from "herdr";

// Where install.sh says Over9k was installed from: {path, commit, branch}.
const SOURCE = 'cat "${XDG_DATA_HOME:-$HOME/.local/share}/over9k/source.json"';
// What that clone's branch has had since ($1 path, $2 commit, $3 branch): fetch
// quietly (never asking for a password; Herdr stops it after 30s), then how many
// commits, then their subjects, newest first. Any failure: exits non-zero.
const NEWS = `export GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="\${GIT_SSH_COMMAND:-ssh -o BatchMode=yes -o ConnectTimeout=10}"
git -C "$1" -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=15 fetch -q origin "$3" || exit 1
git -C "$1" rev-list --count "$2..origin/$3" && git -C "$1" log -n 30 --format=%s "$2..origin/$3"`;
// How often to look again.
const EVERY = 6 * 60 * 60 * 1000;

function find(node, id) {
  if (node?.id === id) return node;
  for (const child of node?.children ?? []) {
    const found = find(child, id);
    if (found) return found;
  }
  return null;
}

// The sidebar's rail goes by its width, not a flag: dragging its edge narrows it too.
const narrow = () => (find(layout(), "sidebar")?.size?.px ?? Infinity) < 160;

// To the rail (on macOS wide enough for the traffic lights), or back to the width it had.
function toggleSidebar() {
  const width = find(layout(), "sidebar")?.size?.px;
  if (!narrow()) setShared("sidebar.width", width);
  // Mods edited before the rail went by width still read the flag.
  setShared("sidebar.collapsed", !narrow());
  run("layout.resize", { id: "sidebar", px: narrow() ? (shared("sidebar.width") ?? 268) : window()?.platform === "macos" ? 76 : 44 });
}

export default class WorkspaceChrome extends View {
  // The footer copy looks for a newer Over9k now and every few hours (the
  // option Check for updates); the brand row's copy doesn't.
  init(_props, cx) {
    this.footer = Boolean(props()?.footer);
    this.checking = shared("sidebar.options")?.checkUpdates !== false;
    if (!this.footer) return;
    this.check();
    cx.timer.every(EVERY, () => this.check());
  }

  // A newer Over9k where it was installed from (a git clone): its commits'
  // subjects go to shared "over9k.update" for the chip below and Help &
  // options' notice. Quiet on any failure (offline, not a clone, no git).
  async check() {
    if (!this.footer || shared("sidebar.options")?.checkUpdates === false) return;
    const src = await exec("sh", ["-c", SOURCE]).catch(() => null);
    let s = null;
    try { s = JSON.parse(src?.stdout ?? ""); } catch {}
    if (!s?.path || !s.commit || !s.branch) return;
    const r = await exec("sh", ["-c", NEWS, "sh", s.path, s.commit, s.branch]).catch(() => null);
    if (r?.code !== 0) return;
    const [count, ...log] = r.stdout.split("\n").filter(Boolean);
    const behind = Number(count) || 0;
    setShared("over9k.update", behind > 0 ? { behind, log, path: s.path, branch: s.branch, checked: Date.now() } : { behind: 0, checked: Date.now() });
  }

  button(id, label, action) {
    const t = theme();
    return div().id(id).size(26).flex_none().flex().items_center().justify_center().rounded(6).text_color(t.muted).hover(s => s.bg(t.hover).text_color(t.foreground))
      .on_mouse_down("left", (_e, cx) => cx.stop_propagation()).on_click(action).child(label);
  }
  render() {
    const t = theme();
    const collapsed = narrow();
    if (props()?.footer) {
      // Check for updates turned back on: looks now.
      const checking = shared("sidebar.options")?.checkUpdates !== false;
      if (checking && !this.checking) this.check();
      this.checking = checking;
      const news = checking && shared("over9k.update")?.behind > 0;
      const row = (id, icon, label, dim, action) => h_flex().id(id).h(28).px(8).gap(9).items_center().rounded(8)
        .text_color(dim ? t.dim : t.muted).hover(s => s.bg(t.hover).text_color(t.foreground)).cursor_pointer()
        .on_click(action).child(svg(`mods/over9k-footer/${icon}.svg`).size(14))
        .when(!collapsed, el => el.child(label));
      return v_flex().size_full().bg(t.chrome).border_t(1).border_color(t.border).px(8).pt(4).pb(8).text_size(13)
        .child(row("settings", "settings", "Settings", false, () => run("app.settings"))
          .when(Boolean(updates().app.ready), el => el.child(div().size(6).rounded_full().bg(t.accent))))
        // The Spaces list's help and options (over9k-options): Herdr's Settings has no room for a mod's.
        // A newer Over9k: an Update chip (on the rail, a dot), and the notice inside.
        .child(row("over9k-options", "panel-left", "Over9k help & options", false, () => openOverlay({ mod: "over9k-options", kind: "dialog", width: 740, height: 600 }))
          .when(news && !collapsed, el => el.child(div().ml_auto().flex_none().px(5).py(1).rounded(4).bg(t.ansi1 + "26").text_size(10.5).text_color(t.ansi1).child("Update")))
          .when(news && collapsed, el => el.child(div().size(6).rounded_full().bg(t.ansi1))))
        .child(row("machine", "plus", "Add machine", true, () => run("mod.open", { name: "machine-add" })));
    }
    return h_flex().size_full().bg(t.chrome).pl(collapsed ? 6 : 14).pr(10).gap(4).items_center().text_size(13.5)
      .when(window()?.platform === "macos" && !collapsed, el => el.pl(76))
      .when(!collapsed, el => el.child(h_flex().flex_1().gap(8).items_center().child(image("frame/welcome/herdr.png").size(20).rounded(5)).child(div().font_semibold().text_color(t.foreground).child("Herdr"))))
      .when(!collapsed, el => el.child(this.button("search", svg("mods/over9k-footer/search.svg").size(15), () => run("mod.open", { name: "picker" }))))
      // On the macOS rail the traffic lights fill the row; the agents list's » unfolds it.
      .when(!(collapsed && window()?.platform === "macos"), el => el.child(this.button("sidebar-toggle", svg("mods/over9k-footer/sidebar.svg").size(15), toggleSidebar)));
  }
}
