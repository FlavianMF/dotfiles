import { makeWindow, okReport, errorReport, unavailableReport, toEpoch, jsonLines } from "../lib/report.js";

const SOURCE = "claude CLI";
const HOUR = 3600;
const WEEK = 7 * 24 * HOUR;

function scopeName(scope) {
  return scope?.model?.display_name || scope?.surface || null;
}

function prefixWindow(w, profile) {
  if (!profile) return w;
  return {
    ...w,
    id: `${profile}:${w.id}`,
    short: `${profile} ${w.short}`,
    long: `${profile} · ${w.long}`,
  };
}

function windowFromLimit(l, profile) {
  const kind = String(l.kind ?? "limit");
  const scope = scopeName(l.scope);
  const resetsAt = toEpoch(l.resets_at);
  let w;
  if (kind === "session") w = makeWindow({ id: "session", short: "5h", long: "5-hour", percent: l.percent, resetsAt, durationSec: 5 * HOUR });
  else if (kind === "weekly_all") w = makeWindow({ id: "weekly_all", short: "wk", long: "Weekly", percent: l.percent, resetsAt, durationSec: WEEK });
  else if (kind === "weekly_scoped" && scope) {
    w = makeWindow({ id: `weekly_scoped:${scope}`, short: scope, long: `Weekly · ${scope}`, percent: l.percent, resetsAt, durationSec: WEEK });
  } else {
    const name = scope ?? kind.replace(/_/g, " ");
    w = makeWindow({ id: scope ? `${kind}:${scope}` : kind, short: name, long: name, percent: l.percent, resetsAt });
  }
  return prefixWindow(w, profile);
}

function legacyWindows(rl, profile) {
  const out = [];
  if (rl.five_hour?.utilization != null) {
    out.push(prefixWindow(makeWindow({ id: "session", short: "5h", long: "5-hour", percent: rl.five_hour.utilization, resetsAt: toEpoch(rl.five_hour.resets_at), durationSec: 5 * HOUR }), profile));
  }
  if (rl.seven_day?.utilization != null) {
    out.push(prefixWindow(makeWindow({ id: "weekly_all", short: "wk", long: "Weekly", percent: rl.seven_day.utilization, resetsAt: toEpoch(rl.seven_day.resets_at), durationSec: WEEK }), profile));
  }
  return out;
}

function extractEntries(text) {
  const lines = jsonLines(text);
  const tagged = lines.filter((m) => m.profile && m.reply?.type === "control_response");
  if (tagged.length > 0) return tagged;
  const raw = lines.find((m) => m.type === "control_response");
  return raw ? [{ profile: null, reply: raw }] : [];
}

export function parse(text, now) {
  const entries = extractEntries(text);
  if (entries.length === 0) return errorReport(SOURCE, "No reply from the claude CLI", now);

  const multi = entries.length > 1;
  const windows = [];
  const plans = [];
  let lastErr = null;
  let hadSuccess = false;

  for (const entry of entries) {
    const res = entry.reply?.response ?? {};
    if (res.subtype !== "success") {
      lastErr = String(res.error ?? "claude CLI could not read usage");
      continue;
    }
    hadSuccess = true;
    const body = res.response ?? {};
    if (body.subscription_type) plans.push(body.subscription_type);
    const rl = body.rate_limits ?? {};
    const label = multi ? entry.profile : null;
    const w = Array.isArray(rl.limits)
      ? rl.limits.filter((l) => l && l.percent != null).map((l) => windowFromLimit(l, label))
      : legacyWindows(rl, label);
    windows.push(...w);
  }

  if (!hadSuccess) return errorReport(SOURCE, lastErr ?? "claude CLI could not read usage", now);
  if (windows.length === 0) return unavailableReport(SOURCE, "No subscription limits", now);
  const plan = plans.length ? [...new Set(plans)].join(" / ") : null;
  return okReport(SOURCE, now, windows, plan);
}

export default {
  id: "claude",
  name: "Claude",
  icon: "icons/claude.svg",
  helper: "helpers/claude-usage.sh",
  parse,
};
