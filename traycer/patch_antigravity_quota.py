#!/usr/bin/env python3
"""
patch_antigravity_quota.py: Enriches Traycer Antigravity rate limit resolution
to include Gemini Flash, Gemini Pro, and Gemini 4 Argon quota groups extracted
from `agy -p "/usage" --output-format json`.
"""
import os
import sys
import shutil
import subprocess

TARGET = os.path.expanduser("~/.traycer/host/install/host-runtime/host-main.cjs")

PATCH_MARKER = "/* __TRAYCER_ANTIGRAVITY_QUOTA_ENRICHER__ */"

ENRICHER_CODE = """/* __TRAYCER_ANTIGRAVITY_QUOTA_ENRICHER__ */
let _agyQCache = { d: null, t: 0, p: null };
async function _enrichAgyRateLimits(restBody, planName) {
  let agyGroups = null;
  let now = Date.now();
  if (_agyQCache.d && now - _agyQCache.t < 60000) {
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
      if (r) {
        _agyQCache.d = r;
        _agyQCache.t = Date.now();
        agyGroups = r;
      }
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
  if (merged.length > 0) {
    return zzf({ groups: merged }, planName);
  }
  return restBody ? zzf(restBody, planName) : null;
}
"""

TARGET_PATTERN = 'async function rll(L2,M5,G9,B6,F5){let u10=L2.project??M5;if(u10===null)return{kind:"done",rateLimits:to("antigravity","rate_limits_not_available")};let Y9=await oll(L2.endpoint+"/v1internal:retrieveUserQuotaSummary",G9,B6,{project:u10},F5);'

REPLACEMENT = ENRICHER_CODE + '\nasync function rll(L2,M5,G9,B6,F5){let u10=L2.project??M5;if(u10===null)return{kind:"done",rateLimits:to("antigravity","rate_limits_not_available")};let Y9=await oll(L2.endpoint+"/v1internal:retrieveUserQuotaSummary",G9,B6,{project:u10},F5);let _qRes=await _enrichAgyRateLimits(Y9.kind==="ok"?Y9.body:null,L2.planName);if(_qRes&&_qRes.available)return{kind:"done",rateLimits:_qRes};'


def patch_file(target_path: str = TARGET) -> bool:
    if not os.path.exists(target_path):
        print(f"Target file not found: {target_path}", file=sys.stderr)
        return False

    with open(target_path, "r", encoding="utf-8") as f:
        content = f.read()

    if PATCH_MARKER in content:
        print("Target file is already patched with antigravity quota enricher.")
        return True

    if TARGET_PATTERN not in content:
        print("Could not locate rll insertion point in host-main.cjs", file=sys.stderr)
        return False

    backup_path = target_path + ".bak"
    if not os.path.exists(backup_path):
        shutil.copy2(target_path, backup_path)
        print(f"Created backup at {backup_path}")

    patched_content = content.replace(TARGET_PATTERN, REPLACEMENT, 1)

    tmp_path = target_path + ".tmp.cjs"
    with open(tmp_path, "w", encoding="utf-8") as f:
        f.write(patched_content)

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


if __name__ == "__main__":
    success = patch_file()
    sys.exit(0 if success else 1)
