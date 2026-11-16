const normalize = (p) => ({
  hidden: [...(p?.hidden ?? [])],
  hiddenWindows: [...(p?.hiddenWindows ?? [])],
  showResetTime: p?.showResetTime === true,
  showBars: p?.showBars !== false,
  sessionOnBar: [...(p?.sessionOnBar ?? [])],
  panelHidden: [...(p?.panelHidden ?? [])],
  folded: [...(p?.folded ?? [])],
  spendOnBar: { ...(p?.spendOnBar ?? {}) },
});

export function effectivePrefs(saved, layoutPresets) {
  return normalize(saved ?? layoutPresets);
}

export function isShown(prefs, providerId, windowId) {
  if (prefs.hidden.includes(providerId)) return false;
  return windowId == null || !prefs.hiddenWindows.includes(`${providerId}:${windowId}`);
}

const flip = (list, item) => (list.includes(item) ? list.filter((x) => x !== item) : [...list, item]);

export function toggleProvider(prefs, providerId) {
  return { ...normalize(prefs), hidden: flip(prefs.hidden, providerId) };
}

export function toggleWindow(prefs, providerId, windowId) {
  return { ...normalize(prefs), hiddenWindows: flip(prefs.hiddenWindows, `${providerId}:${windowId}`) };
}

export function toggleShowResetTime(prefs) {
  return { ...normalize(prefs), showResetTime: !prefs.showResetTime };
}

export function toggleShowBars(prefs) {
  return { ...normalize(prefs), showBars: !prefs.showBars };
}

export const isOnBar = (prefs, row) => prefs.sessionOnBar.includes(row);

export function toggleOnBar(prefs, row) {
  return { ...normalize(prefs), sessionOnBar: flip(prefs.sessionOnBar, row) };
}

export const inPanel = (prefs, id) => !(prefs.panelHidden ?? []).includes(id);

export function togglePanel(prefs, id) {
  const n = normalize(prefs);
  return { ...n, panelHidden: flip(n.panelHidden, id) };
}

export const isFolded = (prefs, providerId) => (prefs.folded ?? []).includes(providerId);

export function toggleFolded(prefs, providerId) {
  const n = normalize(prefs);
  return { ...n, folded: flip(n.folded, providerId) };
}

export function spendOnBar(prefs, providerId, byDefault) {
  const v = prefs.spendOnBar?.[providerId];
  return typeof v === "boolean" ? v : byDefault;
}

export function toggleSpendOnBar(prefs, providerId, current) {
  const n = normalize(prefs);
  return { ...n, spendOnBar: { ...n.spendOnBar, [providerId]: !current } };
}
