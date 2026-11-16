import { makeWindow, okReport, errorReport, toEpoch, jsonLines } from "../lib/report.js";

const RPC_SOURCE = "codex app-server";
const DEFAULT_LIMIT = "codex";
const RPC_REPLY_ID = 2;
const LONG = { 300: "5-hour", 10080: "Weekly" };
const SHORT = { 300: "5h", 10080: "wk" };

function slotWindows(limitId, limitName, slots) {
  const prefix = limitId === "codex" ? null : (limitName || limitId);
  const out = [];
  for (const [slot, w] of slots) {
    if (!w || w.usedPercent == null) continue;
    const mins = Number(w.windowDurationMins) || null;
    const short = SHORT[mins] ?? (mins ? `${Math.round(mins / 60)}h` : slot);
    const long = LONG[mins] ?? (mins ? `${Math.round(mins / 60)}-hour` : slot);
    out.push(makeWindow({
      id: `${limitId}:${slot}`,
      short: prefix ? `${prefix} ${short}` : short,
      long: prefix ? `${prefix} · ${long}` : long,
      percent: w.usedPercent,
      resetsAt: toEpoch(w.resetsAt),
      durationSec: mins ? mins * 60 : null,
    }));
  }
  return out;
}

const defaultLimitFirst = (a, b) => Number(b === DEFAULT_LIMIT) - Number(a === DEFAULT_LIMIT);

function fromRpc(result, now) {
  const byId = result.rateLimitsByLimitId ?? (result.rateLimits ? { [result.rateLimits.limitId ?? "codex"]: result.rateLimits } : {});
  const ids = Object.keys(byId).sort(defaultLimitFirst);
  const windows = ids.flatMap((id) => {
    const r = byId[id];
    return slotWindows(id, r.limitName, [["primary", r.primary], ["secondary", r.secondary]]);
  });
  const plan = result.rateLimits?.planType ?? byId[ids[0]]?.planType ?? null;
  return windows.length ? okReport(RPC_SOURCE, now, windows, plan) : errorReport(RPC_SOURCE, "No limits in Codex reply", now);
}

function failingWithLoggedSnapshot(snap, now) {
  const failed = errorReport(RPC_SOURCE, "Codex app-server didn't answer", now);
  const at = toEpoch(snap.timestamp);
  const r = snap.payload?.rate_limits ?? {};
  const camel = (w) => w && { usedPercent: w.used_percent, windowDurationMins: w.window_minutes, resetsAt: w.resets_at };
  const windows = slotWindows(r.limit_id ?? "codex", r.limit_name, [["primary", camel(r.primary)], ["secondary", camel(r.secondary)]]);
  if (at == null || !windows.length) return failed;
  return { ...failed, fallback: okReport("Codex session log", now, windows, r.plan_type ?? null, at) };
}

export function parse(text, now) {
  for (const m of jsonLines(text)) {
    if (m.id === RPC_REPLY_ID && m.result) return fromRpc(m.result, now);
    if (m.id === RPC_REPLY_ID && m.error) return errorReport(RPC_SOURCE, String(m.error.message ?? "Codex error"), now);
    if (m.snapshot) return failingWithLoggedSnapshot(m.snapshot, now);
  }
  return errorReport(RPC_SOURCE, "No reply from Codex", now);
}

export default {
  id: "codex",
  name: "Codex",
  icon: "icons/codex.svg",
  helper: "helpers/codex-limits.sh",
  parse,
};
