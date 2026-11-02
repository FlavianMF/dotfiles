#!/usr/bin/env python3
"""
patch_antigravity_quota.py: Enriches Traycer Antigravity rate limit resolution
to include Gemini Flash, Gemini Pro, and Gemini 4 Argon quota groups extracted
from `agy -p "/usage" --output-format json`.
"""
import os
import re
import sys
import shutil
import subprocess

TARGET = os.path.expanduser("~/.traycer/host/install/host-runtime/host-main.cjs")

PATCH_MARKER = "/* __TRAYCER_ANTIGRAVITY_QUOTA_ENRICHER_V2__ */"

ENRICHER_CODE = """/* __TRAYCER_ANTIGRAVITY_QUOTA_ENRICHER_V2__ */
let _agyQCache = { d: null, t: 0, p: null };
const _AGY_TTL_MS = 600000;
async function _enrichAgyBody(restBody) {
  let agyGroups = null;
  let now = Date.now();
  if (_agyQCache.d && now - _agyQCache.t < _AGY_TTL_MS) {
    agyGroups = _agyQCache.d;
  } else if (_agyQCache.p) {
    agyGroups = await _agyQCache.p;
  } else {
    _agyQCache.p = (async () => {
      try {
        let fs = require("fs"), path = require("path"), os = require("os"), cp = require("child_process");
        let agyBin = path.join(os.homedir(), ".local", "bin", "agy");
        let bin = fs.existsSync(agyBin) ? agyBin : "agy";
        let env = { ...process.env, PATH: (process.env.PATH || "") + ":" + path.join(os.homedir(), ".local", "bin") };
        return await new Promise(res => {
          cp.execFile(bin, ["-p", "/usage", "--output-format", "json"], { timeout: 6000, env }, (err, stdout) => {
            if (err || !stdout) return res(null);
            try {
              let parsed = JSON.parse(stdout);
              let raw = parsed?.command?.data?.groups;
              if (!Array.isArray(raw)) return res(null);
              let grps = raw.map(g => ({
                displayName: g.name,
                description: g.description,
                buckets: (g.buckets || []).map(b => ({
                  bucketId: b.id,
                  displayName: b.name,
                  window: b.window,
                  remainingFraction: b.remaining_fraction,
                  resetTime: b.reset_time,
                  description: b.description
                }))
              }));
              res(grps);
            } catch (_) {
              res(null);
            }
          });
        });
      } catch (_) {
        return null;
      }
    })();
    try {
      let r = await _agyQCache.p;
      _agyQCache.p = null;
      // Cacheia também a falha: sem isso cada consulta sobe um language server do agy.
      if (r) _agyQCache.d = r;
      _agyQCache.t = Date.now();
      agyGroups = _agyQCache.d;
    } catch (_) {
      _agyQCache.p = null;
    }
  }

  let merged = [];
  let seen = new Set();
  if (Array.isArray(agyGroups)) {
    for (let g of agyGroups) {
      if (g && g.displayName && !seen.has(g.displayName)) {
        seen.add(g.displayName);
        merged.push(g);
      }
    }
  }
  if (restBody && restBody.groups && Array.isArray(restBody.groups)) {
    for (let g of restBody.groups) {
      if (g && g.displayName && !seen.has(g.displayName)) {
        seen.add(g.displayName);
        merged.push(g);
      }
    }
  }
  return merged.length > 0 ? { groups: merged } : restBody;
}
"""

# Os nomes minificados mudam a cada release do Traycer, então o ponto de inserção
# é achado por regex. O caso "ok" de retrieveUserQuotaSummary converte o corpo da
# resposta (`PARSE(body, planName)`); o enricher mescla os grupos do agy no corpo.
TARGET_RE = re.compile(
    r'(async function [\w$]+\([\w$]+,[\w$]+,[\w$]+,[\w$]+,[\w$]+\)\{.{0,300}?'
    r'retrieveUserQuotaSummary.{0,600}?case"ok":return\{kind:"done",rateLimits:await [\w$]+\([\w$]+\()([\w$]+)\.body,',
    re.S,
)


def _write_validated(target_path: str, content: str) -> bool:
    backup_path = target_path + ".bak"
    if not os.path.exists(backup_path):
        shutil.copy2(target_path, backup_path)
        print(f"Created backup at {backup_path}")

    tmp_path = target_path + ".tmp.cjs"
    with open(tmp_path, "w", encoding="utf-8") as f:
        f.write(content)

    # Verify node syntax
    res = subprocess.run(["node", "-c", tmp_path], capture_output=True, text=True)
    if res.returncode != 0:
        print(f"Syntax validation failed on patched file:\n{res.stderr}", file=sys.stderr)
        if os.path.exists(tmp_path):
            os.remove(tmp_path)
        return False

    os.replace(tmp_path, target_path)
    print(f"Successfully patched {target_path}")
    return True


def patch_file(target_path: str = TARGET) -> bool:
    if not os.path.exists(target_path):
        print(f"Target file not found: {target_path}", file=sys.stderr)
        return False

    with open(target_path, "r", encoding="utf-8") as f:
        content = f.read()

    if PATCH_MARKER in content:
        print("Target file is already patched with antigravity quota enricher.")
        return True

    m = TARGET_RE.search(content)
    if m is None:
        print("Could not locate retrieveUserQuotaSummary call site in host-main.cjs", file=sys.stderr)
        return False

    var = m.group(2)
    patched_content = (
        content[: m.start()]
        + ENRICHER_CODE
        + "\n"
        + content[m.start() : m.end(1)]
        + f"await _enrichAgyBody({var}.body),"
        + content[m.end() :]
    )
    return _write_validated(target_path, patched_content)


if __name__ == "__main__":
    success = patch_file()
    sys.exit(0 if success else 1)
