// Artifacts do épico Traycer mais recente (leitura apenas).
// Lê o frontmatter (title, kind, status) de ~/.traycer/epics/<id>/artifacts/*/index.md
// e */*/index.md na máquina do space ativo. Mesma fonte do hook traycer-epic-context.sh.

import { View } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { div } from "gpui-kit";
import { exec, spaces, theme, checking } from "herdr";

const MAX = 30;
const EVERY_MS = 5000;

// Saída: "EPIC\t<id>" e depois "<rel>\t<title>\t<kind>\t<status>\t<mtime>" por artifact.
// O épico é o dono do index.md modificado por último.
const SCRIPT = String.raw`
root="$HOME/.traycer/epics"
[ -d "$root" ] || exit 0
newest=$(ls -t "$root"/*/artifacts/*/index.md "$root"/*/artifacts/*/*/index.md 2>/dev/null | head -n 1)
[ -n "$newest" ] || exit 0
epic=\${newest#"$root"/}; epic=\${epic%%/*}
printf 'EPIC\t%s\n' "$epic"
for f in "$root/$epic"/artifacts/*/index.md "$root/$epic"/artifacts/*/*/index.md; do
  [ -f "$f" ] || continue
  rel=\${f#"$root/$epic"/artifacts/}; rel=\${rel%/index.md}
  mt=$(stat -c %Y "$f" 2>/dev/null || echo 0)
  awk -v rel="$rel" -v mt="$mt" '
    NR == 1 { if ($0 != "---") exit; next }
    $0 == "---" { exit }
    /^(title|kind|status):/ {
      k = $0; sub(/:.*/, "", k)
      v = $0; sub(/^[^:]*:[ \t]*/, "", v); gsub(/^["\x27]|["\x27][ \t]*$/, "", v)
      m[k] = v
    }
    END { printf "%s\t%s\t%s\t%s\t%s\n", rel, (m["title"] != "" ? m["title"] : rel), m["kind"], m["status"], mt }
  ' "$f"
done
`.replaceAll("\\${", "${");

function age(sec) {
  const s = Math.max(0, Date.now() / 1000 - sec);
  if (s < 3600) return `${Math.max(1, Math.floor(s / 60))}m`;
  if (s < 86400) return `${Math.floor(s / 3600)}h`;
  return `${Math.floor(s / 86400)}d`;
}

export default class Epic extends View {
  init(_props, cx) {
    this.epic = "";
    this.items = [];
    this.err = "";
    this.busy = false;
    if (checking()) return;
    cx.timer.every(EVERY_MS, (cx) => this.refresh(cx));
    this.refresh(cx);
  }

  refresh(cx) {
    if (this.busy) return;
    this.busy = true;
    cx.spawn(async (cx) => {
      try {
        const active = spaces().find((s) => s.active) ?? spaces()[0];
        const r = await exec("sh", ["-c", SCRIPT], { on: active?.machine ?? null, timeout: 8000 });
        const lines = r.stdout.split("\n").filter(Boolean);
        this.epic = "";
        this.items = [];
        for (const line of lines) {
          const [a, b, c, d, e] = line.split("\t");
          if (a === "EPIC") this.epic = b ?? "";
          else this.items.push({ rel: a, title: b, kind: c, status: d, mtime: Number(e) || 0 });
        }
        this.items.sort((x, y) => y.mtime - x.mtime);
        this.err = r.code === 0 ? "" : (r.stderr.trim().split("\n")[0] ?? `exit ${r.code}`);
      } catch (e) {
        this.err = String(e?.message ?? e);
      }
      this.busy = false;
      cx.notify();
    });
  }

  render(_cx) {
    const t = theme();
    const head = h_flex().id("epic-head").gap(8).items_center().justify_between()
      .child(div().font_semibold().text_size(13).text_color(t.foreground).child("Traycer · épico"))
      .child(div().text_size(11).text_color(t.dim).child(this.epic ? this.epic.slice(0, 8) : ""));

    let body;
    if (this.err) {
      body = div().text_size(12).text_color(t.muted).child(this.err);
    } else if (!this.items.length) {
      body = div().text_size(12).text_color(t.muted).child("Nenhum artifact em ~/.traycer/epics.");
    } else {
      body = v_flex().gap(2).children(
        this.items.slice(0, MAX).map((it) =>
          h_flex().id(`a-${it.rel}`).gap(8).px(6).py(3).rounded(6).items_center().justify_between()
            .hover((s) => s.bg(t.raised))
            .child(div().flex_1().truncate().text_size(12).text_color(t.foreground).child(it.title))
            .child(div().text_size(11).text_color(t.muted).child([it.kind, it.status].filter(Boolean).join(" · ")))
            .child(div().text_size(11).text_color(t.dim).child(age(it.mtime)))));
    }

    return v_flex().id("epic-root").size_full().bg(t.surface).p(10).gap(8)
      .child(head)
      .child(div().flex_1().overflow_y_scrollbar().child(body));
  }
}
