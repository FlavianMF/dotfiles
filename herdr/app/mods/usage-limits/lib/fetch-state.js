import { nextState } from "./state.js";
import { errorReport } from "./report.js";

export const NOT_FOUND_EXIT_CODE = 127;
export const NEVER_FETCHED = { report: null, lastGood: null, installed: null };

const isSpend = (p) => p.kind === "spend";
const messageOf = (error) => String(error?.message ?? error);

export function fetchedState(prev, p, result, now) {
  if (result.code === NOT_FOUND_EXIT_CODE) return nextState(prev, null, false);
  if (isSpend(p) && result.code !== 0) return nextState(prev, errorReport(p.helper, `Couldn't count ${p.name} tokens`, now), true);
  return nextState(prev, p.parse(result.stdout, now), true);
}

export function crashedState(prev, p, error, now) {
  const report = errorReport(p.helper, messageOf(error), now);
  return isSpend(p) ? nextState(prev, report, true) : { ...prev, report };
}
