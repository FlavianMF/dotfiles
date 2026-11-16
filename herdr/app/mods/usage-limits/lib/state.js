export function nextState(prev, report, installed) {
  const lastGood = prev?.lastGood ?? null;
  if (!installed) return { report: null, lastGood, installed: false };
  if (report.status === "ok") return { report, lastGood: report, installed: true };
  const { fallback } = report;
  const fallbackIsFresher = fallback && fallback.observedAt != null && (!lastGood || fallback.observedAt > lastGood.observedAt);
  return { report, lastGood: fallbackIsFresher ? fallback : lastGood, installed: true };
}
