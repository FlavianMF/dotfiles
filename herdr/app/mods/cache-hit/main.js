// Experimental Herdr App (GUI) front end for the cache-hit plugin.
// ADAPTADO para agentes no WSL (machine "wsl"): o scanner roda no WSL via wsl.exe,
// grava o estado numa pasta do home do Windows (/mnt/c/...) e o mod lê de lá.
// O endereço "wsl/t12" do app corresponde a "t12" no hc do WSL.
// Origem: e-kotov/herdr-cache-hit@9d88752 (herdr-app/mods/cache-hit).
// Install: scripts/install-herdr-app-mod.sh (copies this folder and records the checkout).
// Every 15 s it runs watch.sh through scripts/herdr-app-shim.sh, then shows
// the metadata the shim stored for each agent terminal. Display only: the
// shim refuses to type into terminals, so the cache warmer cannot run here.
import { View, div } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { svg, image } from "gpui-kit";
import { agents, appHome, exec, home, readTextFile, run, setShared, shared, terminals, theme } from "herdr";

const CLOCK = "mods/workspace-chrome/clock.svg";
const SPINNER = "mods/workspace-chrome/spinner.svg";
const EXPIRING_SECS = 300; // under 5 minutes: warn

// "42 min", "3 min", "50 s", "1 h 05"
function fmtLeft(secs) {
  if (secs < 60) return `${Math.max(0, Math.floor(secs))} s`;
  const m = Math.floor(secs / 60);
  return m < 60 ? `${m} min` : `${Math.floor(m / 60)} h ${String(m % 60).padStart(2, "0")}`;
}

const SCAN_MS = 15000;
// "C:\\Users\\User" -> "/mnt/c/Users/User"
const wslPath = (p) => p.replace(/^([A-Za-z]):[\\/]/, (_m, d) => `/mnt/${d.toLowerCase()}/`).replace(/\\/g, "/");
// "wsl/t12" -> "t12": o hc do WSL não prefixa a máquina.
const localId = (address) => (address.startsWith("wsl/") ? address.slice(4) : address);
// Separate from a Herdr TUI install of the plugin: pane ids, locks and timers differ.
const STATE_DIR = ".local/state/herdr/plugins/cache-hit-app";
// Its own config too, so settings for a Herdr TUI install do not apply here.
const CONFIG_DIR = ".config/herdr/plugins/config/cache-hit-app";

export default class CacheHit extends View {
  init(_props, cx) {
    this.meta = {};
    this.error = null;
    cx.spawn(async (cx) => {
      // The installer records where the plugin checkout lives.
      const dir = `${appHome()}/mods/cache-hit`;
      // Caminho WSL do checkout do plugin (herdr/install-cache-hit-app.sh grava aqui).
      this.root = (await readTextFile(`${dir}/plugin-root`))?.trim() || null;
      if (!this.root) this.error = "plugin-root ausente: rode herdr/install-cache-hit-app.sh";
      this.scan(cx);
    });
    cx.timer.every(SCAN_MS, (cx) => this.scan(cx));
  }

  // The plugin's environment, pointed at Herdr App. Os caminhos vão em forma WSL.
  env() {
    return [
      `HERDR_BIN_PATH=${this.root}/scripts/herdr-app-shim.sh`, "HERDR_NO_TIMER=1",
      "HERDR_CACHE_DISPLAY_ONLY=1",
      `HERDR_PLUGIN_STATE_DIR=${wslPath(home())}/${STATE_DIR}`,
      `HERDR_PLUGIN_CONFIG_DIR=${wslPath(home())}/${CONFIG_DIR}`,
    ];
  }

  // Roda um script do plugin dentro do WSL, com env().
  bashExec(vars, script, args = []) {
    // run.sh (criado pelo instalador) carrega o PATH de login do WSL (hc, jq, python3)
    // e roda `env "$@"`. Um script evita o reparse de aspas do wsl.exe.
    return exec("wsl.exe", ["-e", `${this.root}/herdr-app-run.sh`, ...vars, "bash", script, ...args]);
  }

  scan(cx) {
    if (!this.root || this.busy) return;
    this.busy = true;
    cx.spawn(async (cx) => {
      try {
        const r = await this.bashExec(this.env(), `${this.root}/watch.sh`);
        this.error = r.code === 0 ? null : (r.stderr.trim() || `watch.sh exited ${r.code}`);
        const dir = `${home()}/${STATE_DIR}/app-metadata`;
        const meta = {};
        for (const a of agents()) {
          const text = await readTextFile(`${dir}/${localId(a.address)}.json`);
          if (text) try { meta[a.address] = JSON.parse(text); } catch {}
        }
        this.meta = meta;
        this.publish(meta);
      } catch (e) {
        this.error = String(e);
      }
      this.busy = false;
      cx.notify();
    });
  }

  // Other mods (e.g. a cloned Agents sidebar) read shared("cache-hit").
  publish(meta) {
    const panes = {};
    for (const [address, m] of Object.entries(meta)) {
      const tok = m.tokens ?? {};
      if (!tok.cache) continue;
      panes[address] = { cache: tok.cache, state: tok.cache_state ?? null, deadline: Number(tok.cache_deadline) || null, expires_ms: m.expires_ms };
    }
    const value = { panes };
    if (JSON.stringify(shared("cache-hit")) !== JSON.stringify(value)) setShared("cache-hit", value);
  }

  render() {
    const t = theme();
    const now = Date.now();
    const progs = Object.fromEntries(terminals().map((k) => [k.address, k.program]));
    const rows = agents().map((a) => {
      const m = this.meta[a.address];
      const tok = m && m.expires_ms > now ? m.tokens : {};
      // Remaining time comes from the absolute deadline, so it stays right between scans.
      const dl = Number(tok.cache_deadline);
      const left = dl > 0 ? dl - now / 1000 : Number(tok.cache_remaining_secs) || 0;
      const known = Boolean(tok.cache_state) && tok.cache_state !== "unknown";
      const state = !known ? "unknown" : left <= 0 ? "cold" : left < EXPIRING_SECS ? "expiring" : "hot";
      const ttl = left > EXPIRING_SECS ? 3600 : EXPIRING_SECS; // 1 h or 5 min cache
      return { a, tok, left, state, frac: state === "unknown" ? 0 : Math.max(0, Math.min(1, left / ttl)) };
    }).sort((x, y) => (x.state === "unknown" || x.state === "cold" ? 1e9 : x.left) - (y.state === "unknown" || y.state === "cold" ? 1e9 : y.left));
    const color = { hot: t.done, expiring: t.blocked, cold: t.ansi1, unknown: t.dim };
    const icon = (prog) => prog?.icon
      ? (prog.tint ? svg(prog.icon).size(14).flex_none().text_color(t.foreground) : image(prog.icon).w(14).h(14).flex_none())
      : svg("icons/shell.svg").size(14).flex_none().text_color(t.foreground);
    const status = (state) => {
      const c = color[state];
      const clock = svg(CLOCK).size(11).flex_none().text_color(c);
      if (state === "expiring") return clock.loop("opacity", { from: 0.3, to: 1, period: 800 });
      if (state === "cold") return svg(CLOCK).size(11).flex_none().text_color(c);
      return clock;
    };
    const label = (r) => r.state === "cold" ? "expired" : r.state === "unknown" ? "–" : `${fmtLeft(r.left)}`;
    return v_flex().size_full().bg(t.chrome).p(10).gap(4).text_size(12.5).text_color(t.foreground)
      .child(h_flex().gap(6).items_center()
        .child(svg(CLOCK).size(11).flex_none().text_color(t.muted))
        .child(div().text_color(t.muted).text_size(11).child("PROMPT CACHE"))
        .when(this.busy, (el) => el.child(svg(SPINNER).size(10).flex_none().text_color(t.working).spin(900))))
      .when(Boolean(this.error), (el) => el.child(div().text_color(t.blocked).child(this.error)))
      .when(rows.length === 0, (el) => el.child(div().text_color(t.dim).text_size(11).child("No agents running.")))
      .children(rows.map((r) => {
        const { a, tok, state, frac } = r;
        const c = color[state];
        return v_flex().id(`c-${a.address}`).gap(4).px(6).py(4).rounded(5)
          .hover((s) => s.bg(t.hover))
          .on_click(() => run("agent.focus", { terminal: a.address }))
          .child(h_flex().gap(8).items_center().justify_between()
            .child(h_flex().gap(6).items_center().flex_1().min_w(0)
              .child(icon(progs[a.address]))
              .child(div().truncate().text_color(state === "cold" || state === "unknown" ? t.muted : t.foreground).child(`${a.space_name} / ${a.tab_name || a.tab_index}`)))
            .child(h_flex().gap(4).items_center().flex_none()
              .child(status(state))
              .child(div().text_color(c).text_size(12).font_semibold().child(label(r)))))
          .child(h_flex().gap(8).items_center()
            .child(div().flex_1().h(3).rounded(3).bg(t.raised).overflow_hidden()
              .child(div().h(3).rounded(3).bg(c).w(`${Math.round(frac * 100)}%`).transition("width", 600)))
            .child(div().flex_none().text_color(t.dim).text_size(11).child(tok.cache_tokens ?? "")));
      }));
  }
}
