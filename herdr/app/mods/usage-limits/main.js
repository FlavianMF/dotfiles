import { View } from "gpui-kit";
import { focused, theme, props, shared, setShared } from "herdr";
import { PROVIDERS } from "./providers/index.js";
import { KEY_PREFS, KEY_REFRESH, KEY_STATE, nowS, refreshCooling, states, viewActions } from "./actions.js";
import { runProviderHelper, readTerminalSession } from "./io/helpers.js";
import { PANEL, barModel, cardModel, chooseDensity, sessionNumbersWidth, wanted } from "./lib/view.js";
import { effectivePrefs, inPanel } from "./lib/prefs.js";
import { sessionOnBar, sessionView } from "./lib/session.js";
import { NEVER_FETCHED, crashedState, fetchedState } from "./lib/fetch-state.js";
import { statusBar } from "./ui/bar.js";
import { limitsPanel } from "./ui/panel.js";
import { settingsPanel } from "./ui/settings.js";

const FETCH_EVERY_S = 5 * 60;
const NOT_INSTALLED_FETCH_EVERY_S = 60 * 60;
const TICK_MS = 60 * 1000;
const BAR_PADDING_W = 24;

const sessionWanted = (prefs) => inPanel(prefs, "session") || prefs.sessionOnBar.length > 0;

function panelIsEmpty(view, panel, session, prefs) {
  const sessionPending = inPanel(prefs, "session") && (view.sessionChoices || view.sessionManual);
  return panel.empty && !session && !sessionPending;
}

export default class UsageLimits extends View {
  init(_props, cx) {
    Object.assign(this, {
      width: 0, panel: PANEL.LIMITS, leftAtMs: null, hovered: null,
      terminal: null, session: null, sessionReadAtMs: 0, sessionBusy: false, sessionChoices: null,
      sessionChoosing: false, sessionManual: false, sessionRevision: 0,
      lastFetchAtS: {}, fetching: {}, unwanted: {},
    });
    this.act = viewActions(this);
    this.sessionWas = sessionWanted(this.prefs());
    this.seenRefresh = shared(KEY_REFRESH) ?? 0;
    this.tick(cx, true);
    cx.timer.every(TICK_MS, (next) => this.tick(next, false));
  }

  prefs() {
    return effectivePrefs(shared(KEY_PREFS), props());
  }

  tick(cx, force) {
    const st = states();
    const prefs = this.prefs();
    for (const p of PROVIDERS) {
      if (!wanted(prefs, p, st)) continue;
      const every = st[p.id]?.installed === false ? NOT_INSTALLED_FETCH_EVERY_S : FETCH_EVERY_S;
      if (force || nowS() - (this.lastFetchAtS[p.id] ?? 0) >= every) this.fetch(p, cx);
    }
    this.readSession(cx);
    cx.notify();
  }

  fetch(p, cx) {
    if (this.fetching[p.id]) return;
    this.fetching[p.id] = true;
    this.lastFetchAtS[p.id] = nowS();
    cx.spawn(async (later) => {
      const prev = states()[p.id] ?? NEVER_FETCHED;
      const next = await runProviderHelper(p).then((r) => fetchedState(prev, p, r, nowS())).catch((e) => crashedState(prev, p, e, nowS()));
      this.fetching[p.id] = false;
      setShared(KEY_STATE, { ...states(), [p.id]: next });
      later.notify();
    });
  }

  forgetSession() {
    this.session = null;
    this.sessionChoices = null;
  }

  readSession(cx) {
    if (!sessionWanted(this.prefs())) return this.forgetSession();
    if (this.sessionBusy) return undefined;
    const { terminal, sessionRevision } = this;
    this.sessionReadAtMs = Date.now();
    if (!terminal) return this.forgetSession();
    this.sessionBusy = true;
    cx.spawn(async (later) => {
      const read = await readTerminalSession(terminal);
      this.sessionBusy = false;
      if (terminal !== this.terminal || sessionRevision !== this.sessionRevision) return this.readSession(later);
      const keep = sessionWanted(this.prefs());
      this.session = keep ? read.session : null;
      this.sessionChoices = keep ? read.choices : null;
      this.sessionManual = read.manual;
      return later.notify();
    });
    return undefined;
  }

  followFocus(cx, prefs) {
    const focus = focused();
    const terminal = focus?.terminal ?? focus?.agent ?? null;
    const wantedNow = sessionWanted(prefs);
    if (terminal !== this.terminal) {
      Object.assign(this, { terminal, session: null, sessionChoices: null, sessionChoosing: false, sessionManual: false });
      this.readSession(cx);
    } else if (wantedNow && !this.sessionWas) {
      this.readSession(cx);
    }
    this.sessionWas = wantedNow;
  }

  fetchNewlyWanted(cx, prefs) {
    const st = states();
    const want = PROVIDERS.filter((p) => wanted(prefs, p, st));
    for (const p of want) if (this.unwanted[p.id]) this.fetch(p, cx);
    this.unwanted = Object.fromEntries(PROVIDERS.filter((p) => !want.includes(p)).map((p) => [p.id, true]));
    const asked = shared(KEY_REFRESH) ?? 0;
    if (asked === this.seenRefresh) return;
    this.seenRefresh = asked;
    for (const p of want) this.fetch(p, cx);
  }

  drawPanel(t, prefs) {
    const st = states();
    const panel = cardModel(st, nowS(), PROVIDERS, prefs);
    const session = inPanel(prefs, "session") ? sessionView(this.session?.data, this.session?.title) : null;
    const empty = panelIsEmpty(this, panel, session, prefs);
    if (empty) this.panel = PANEL.SETTINGS;
    const draw = {
      t, act: this.act, prefs, hovered: this.hovered, cooling: refreshCooling(),
      choosing: this.sessionChoosing, choices: this.sessionChoices, manual: this.sessionManual,
    };
    return this.panel === PANEL.SETTINGS ? settingsPanel(!empty, st, draw) : limitsPanel(panel, session, draw);
  }

  render(cx) {
    const prefs = this.prefs();
    this.followFocus(cx, prefs);
    this.fetchNewlyWanted(cx, prefs);
    const t = theme();
    const model = barModel(states(), prefs, nowS());
    const numbers = sessionOnBar(this.session?.data, prefs);
    const room = this.width ? this.width - BAR_PADDING_W - sessionNumbersWidth(numbers) : Infinity;
    return statusBar({
      model, numbers, density: chooseDensity(model, room, prefs.showBars),
      panel: this.drawPanel(t, prefs), onResize: this.act.resize, onHover: this.act.hover,
    }, t);
  }
}
