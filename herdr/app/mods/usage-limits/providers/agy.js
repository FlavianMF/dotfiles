import { makeWindow, okReport, errorReport, unavailableReport, toEpoch, jsonLines } from "../lib/report.js";

// Provider novo para o Antigravity (agy), escrito para este fork.
// Fonte: `agy -p "/usage" --output-format json` -> command.data.groups[].buckets[].
const SOURCE = "agy /usage";
const HOUR = 3600;
const DURATION = { "5h": 5 * HOUR, weekly: 7 * 24 * HOUR };
const SHORT = { "5h": "5h", weekly: "wk" };
const LONG = { "5h": "5-hour", weekly: "Weekly" };
// Primeiro grupo (Gemini) usa 5h/wk puros. Os outros ganham o prefixo.
const PREFIX = { "Claude and GPT models": "Claude", "Gemini 4 Argon": "Argon" };

function windowOf(group, bucket, first) {
  if (typeof bucket.remaining_fraction !== "number") return null;
  const w = bucket.window;
  const prefix = first ? null : (PREFIX[group.name] ?? group.name);
  const short = SHORT[w] ?? w ?? "limit";
  const long = LONG[w] ?? bucket.name ?? short;
  return makeWindow({
    id: bucket.id,
    short: prefix ? `${prefix} ${short}` : short,
    long: prefix ? `${prefix} · ${long}` : long,
    percent: Math.min(100, Math.max(0, (1 - bucket.remaining_fraction) * 100)),
    resetsAt: toEpoch(bucket.reset_time),
    durationSec: DURATION[w] ?? null,
  });
}

export function parse(text, now) {
  const msg = jsonLines(text).find((m) => m.command?.name === "usage");
  if (!msg) return errorReport(SOURCE, "No reply from agy", now);
  const groups = msg.command?.data?.groups;
  if (!Array.isArray(groups)) return errorReport(SOURCE, String(msg.error ?? "agy could not read usage"), now);
  const windows = groups.flatMap((g, i) => [...(g.buckets ?? [])].sort((a, b) => (DURATION[a.window] ?? 0) - (DURATION[b.window] ?? 0)).map((b) => windowOf(g, b, i === 0)).filter(Boolean));
  if (windows.length === 0) return unavailableReport(SOURCE, "No Antigravity limits", now);
  return okReport(SOURCE, now, windows, null);
}

export default {
  id: "agy",
  name: "Antigravity",
  icon: "icons/antigravity.svg",
  helper: "helpers/agy-usage.sh",
  parse,
};
