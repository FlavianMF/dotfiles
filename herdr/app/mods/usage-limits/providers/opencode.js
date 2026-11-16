import { spendReport, errorReport } from "../lib/report.js";

const SOURCE = "OpenCode usage";

const isNum = (v) => typeof v === "number" && Number.isFinite(v);
const isObj = (v) => v !== null && typeof v === "object" && !Array.isArray(v);
const num = (v) => (v > 0 ? v : 0);

const missingOrNumber = (v) => v === undefined || isNum(v);
const missingOrObject = (v) => v === undefined || isObj(v);

function totalInKnownFormat(reply) {
  const t = reply?.tokens;
  if (!isObj(t) || !isNum(t.input) || !isNum(t.output)) return null;
  if (!missingOrNumber(t.reasoning) || !missingOrObject(t.cache)) return null;
  const c = t.cache ?? {};
  if (!missingOrNumber(c.read) || !missingOrNumber(c.write)) return null;
  return num(t.input) + num(t.output) + num(t.reasoning) + num(c.read) + num(c.write);
}

export function parse(text, now) {
  let data;
  try {
    data = JSON.parse(String(text ?? ""));
  } catch {
    data = null;
  }
  const today = totalInKnownFormat(data?.today);
  const week = totalInKnownFormat(data?.week);
  if (today === null || week === null) return errorReport(SOURCE, "No stats from OpenCode", now);
  return spendReport(SOURCE, now, today, week);
}

export default {
  id: "opencode",
  name: "OpenCode",
  icon: "icons/opencode.svg",
  kind: "spend",
  oneColorGlyph: true,
  helper: "helpers/opencode-spend.sh",
  parse,
};
