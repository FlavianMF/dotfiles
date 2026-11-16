// What closing the picked spaces, tabs and terminals (ids) takes, as the
// fewest commands: a tab whose terminals are all picked closes as a tab, a space
// whose tabs all go closes as a space. The same file is copied into each mod
// that closes things (mods can't import from each other); over9k-close's is the
// original.
import { spaces, panes, agents } from "herdr";

export const plural = (n, word) => `${n} ${word}${n === 1 ? "" : "s"}`;

// { commands, spaces, spaceNames, terminals, agents, working, label }: working,
// the agents among them still working (or waiting on you); label names the one
// thing picked (a space, a tab, or "this agent"/"this CLI"), else null.
export function plan(p) {
  const sp = spaces(), ps = panes().filter((x) => x.terminal), ag = new Set(agents().map((a) => a.pane));
  const busy = new Set(agents().filter((a) => a.status === "working" || a.status === "blocked").map((a) => a.pane));
  const tabOf = new Map(), spaceOf = new Map();
  for (const s of sp) for (const t of s.tabs ?? []) { tabOf.set(t.id, t); spaceOf.set(t.id, s); }
  const S = new Set(p.spaces ?? []), T = new Set(), P = new Set();
  for (const id of p.tabs ?? []) if (tabOf.has(id) && !S.has(spaceOf.get(id).id)) T.add(id);
  for (const id of p.panes ?? []) {
    const x = ps.find((q) => q.pane === id);
    if (x && !T.has(x.tab) && !S.has(spaceOf.get(x.tab)?.id)) P.add(id);
  }
  // Every terminal of a tab picked: the tab goes. Every tab of a space: the space.
  for (const tab of new Set(ps.filter((x) => P.has(x.pane)).map((x) => x.tab)))
    if (ps.filter((x) => x.tab === tab).every((x) => P.has(x.pane))) {
      T.add(tab);
      ps.filter((x) => x.tab === tab).forEach((x) => P.delete(x.pane));
    }
  for (const s of new Set([...T].map((id) => spaceOf.get(id))))
    if ((s.tabs ?? []).every((t) => T.has(t.id))) { S.add(s.id); s.tabs.forEach((t) => T.delete(t.id)); }
  const ending = ps.filter((x) => P.has(x.pane) || T.has(x.tab) || S.has(spaceOf.get(x.tab)?.id));
  const agentCount = ending.filter((x) => ag.has(x.pane)).length;
  const named = (s) => sp.find((x) => x.id === s)?.name;
  const label = S.size === 1 && !T.size && !P.size ? named([...S][0])
    : !S.size && T.size === 1 && !P.size ? tabOf.get([...T][0])?.name
    : !S.size && !T.size && P.size === 1 ? (agentCount ? "this agent" : "this CLI")
    : null;
  return {
    commands: [
      ...[...S].map((id) => ({ name: "space.close", args: { id, confirmed: true } })),
      ...[...T].map((id) => ({ name: "tab.close", args: { id, confirmed: true } })),
      ...[...P].map((pane) => ({ name: "pane.close", args: { pane } })),
    ],
    spaces: S.size, spaceNames: [...S].map(named), terminals: ending.length - agentCount, agents: agentCount,
    working: ending.filter((x) => busy.has(x.pane)).length, label,
  };
}

