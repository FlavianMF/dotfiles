#!/usr/bin/env python3
# What the sidebar shows under each Claude Code agent, read from Claude Code's
# own files (no status line involved):
#   ~/.claude/sessions/<pid>.json   each running Claude Code: its session and folder
#   the process's HC_TERMINAL_ID    which Herdr terminal it runs in
#   ~/.claude/projects/<folder>/<session>.jsonl   its conversation: model, effort
#                                   (the last API request), context (the last reply's
#                                   input tokens), when the prompt cache runs out,
#                                   when it last replied, ultracode
# Writes ~/.cache/over9k/agents/<terminal>.json for each (only when it changed) and
# prints them all as one JSON object keyed by terminal. Python 3, standard library.
import glob, json, os, re, subprocess, sys, time
from datetime import datetime

HOME = os.path.expanduser("~")
OUT = os.path.join(HOME, ".cache", "over9k", "agents")
TAIL = 4 * 1024 * 1024  # enough of the conversation's end for the last reply and request


def alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except PermissionError:
        return True
    except (OSError, ValueError):
        return False


def terminal_of(pid):
    # Linux: the process's environment; macOS: ps shows it for your own processes.
    try:
        with open(f"/proc/{pid}/environ", "rb") as f:
            for kv in f.read().split(b"\0"):
                if kv.startswith(b"HC_TERMINAL_ID="):
                    return kv.split(b"=", 1)[1].decode()
        return None
    except FileNotFoundError:
        pass
    except OSError:
        return None
    try:
        out = subprocess.run(["ps", "-wwE", "-p", str(pid), "-o", "command="], capture_output=True, text=True, timeout=3).stdout
        m = re.search(r"(?:^|\s)HC_TERMINAL_ID=(\S+)", out)
        return m.group(1) if m else None
    except Exception:
        return None


def transcript_of(session, cwd):
    if not session:
        return None
    if cwd:
        p = os.path.join(HOME, ".claude", "projects", re.sub(r"[^A-Za-z0-9]", "-", cwd), f"{session}.jsonl")
        if os.path.isfile(p):
            return p
    found = glob.glob(os.path.join(HOME, ".claude", "projects", "*", f"{session}.jsonl"))
    if found:
        return found[0]
    # A new conversation (just after /clear) has no file until its first message:
    # its path still says which one it is.
    return os.path.join(HOME, ".claude", "projects", re.sub(r"[^A-Za-z0-9]", "-", cwd), f"{session}.jsonl") if cwd else None


def seconds(ts):
    try:
        return int(datetime.fromisoformat(ts.replace("Z", "+00:00")).timestamp())
    except Exception:
        return None


def model_name(mid):
    # "claude-opus-5-5" -> "Opus 5.5"; Bedrock's "us.anthropic.claude-opus-5-5-v1:0" too.
    if not mid:
        return None
    m = re.search(r"claude-([a-z]+)-(\d+)(?:-(\d{1,2}))?(?![\d])", mid)
    if not m:
        return mid
    return f"{m.group(1).capitalize()} {m.group(2)}{'.' + m.group(3) if m.group(3) else ''}"


def window(mid, used):
    # The context window: 1M for [1m] models and the 5 family on; 200k before.
    if mid and "[1m]" in mid:
        return 1_000_000
    m = re.search(r"claude-[a-z]+-(\d+)", mid or "")
    w = 1_000_000 if m and int(m.group(1)) >= 5 else 200_000
    return 1_000_000 if used > w else w


def read(path):
    with open(path, "rb") as f:
        f.seek(0, 2)
        size = f.tell()
        f.seek(max(0, size - TAIL))
        data = f.read()
    lines = data.split(b"\n")
    if size > TAIL:
        lines = lines[1:]
    reply = request = None
    ultra = None
    for raw in reversed(lines):
        if reply and request and ultra is not None:
            break
        if not raw.strip():
            continue
        if ultra is None and b"Ultracode o" in raw and b'"content":"<local-command-stdout>' in raw:
            # Only /effort's own output counts: a user entry whose content is
            # the command's stdout as a plain string. The same words inside a
            # tool result (a file that quotes it) or assistant text don't.
            try:
                j = json.loads(raw)
            except Exception:
                j = {}
            text = (j.get("message") or {}).get("content") if j.get("type") == "user" and not j.get("isSidechain") else None
            if isinstance(text, str) and text.startswith("<local-command-stdout>"):
                hit = re.findall(r"Ultracode o(n|ff)", text)
                if hit:
                    ultra = hit[-1] == "n"
        if (reply is None and b'"type":"assistant"' in raw) or (request is None and b'"type":"api-request"' in raw):
            try:
                j = json.loads(raw)
            except Exception:
                continue
            if j.get("type") == "assistant" and reply is None and (j.get("message") or {}).get("usage") and not j.get("isSidechain"):
                reply = j
            elif j.get("type") == "api-request" and request is None and j.get("querySource", "repl_main_thread") == "repl_main_thread":
                request = j
    info = {"model": None, "id": None, "effort": None, "ultracode": bool(ultra), "lastAt": None, "context": None, "cacheUntil": None, "transcript": path}
    params = (request or {}).get("params") or {}
    mid = params.get("model") or ((reply or {}).get("message") or {}).get("model")
    info["id"] = mid
    info["model"] = model_name(mid)
    effort = (params.get("output_config") or {}).get("effort") or (params.get("effort") or {}).get("effort")
    info["effort"] = effort if isinstance(effort, str) else None
    if reply:
        u = reply["message"]["usage"]
        used = (u.get("input_tokens") or 0) + (u.get("cache_creation_input_tokens") or 0) + (u.get("cache_read_input_tokens") or 0)
        info["context"] = round(used * 100 / window(mid, used))
        at = seconds(reply.get("timestamp") or "")
        info["lastAt"] = at
        cc = u.get("cache_creation") or {}
        ttl = 3600 if (cc.get("ephemeral_1h_input_tokens") or 0) > 0 else 300
        info["cacheUntil"] = at + ttl if at else None
    return info


def main():
    os.makedirs(OUT, exist_ok=True)
    found = {}
    for f in glob.glob(os.path.join(HOME, ".claude", "sessions", "*.json")):
        try:
            s = json.load(open(f))
            pid = int(s.get("pid"))
        except Exception:
            continue
        if not alive(pid):
            continue
        term = terminal_of(pid)
        if not term or not re.fullmatch(r"[A-Za-z0-9_.-]+", term):
            continue
        path = transcript_of(s.get("sessionId"), s.get("cwd"))
        if not path:
            continue
        try:
            found[term] = read(path) if os.path.isfile(path) else {"model": None, "id": None, "effort": None, "ultracode": False,
                "lastAt": None, "context": None, "cacheUntil": None, "transcript": path}
        except Exception:
            continue
    for term, info in found.items():
        dest = os.path.join(OUT, f"{term}.json")
        text = json.dumps(info, separators=(",", ":"))
        try:
            if open(dest).read() == text:
                continue
        except OSError:
            pass
        tmp = dest + ".tmp"
        with open(tmp, "w") as f:
            f.write(text)
        os.replace(tmp, dest)
    # Terminals no Claude Code runs in any more: their file goes (only this
    # script's: Antigravity's status line keeps its own here too).
    for dest in glob.glob(os.path.join(OUT, "*.json")):
        if os.path.basename(dest)[:-5] in found or time.time() - os.path.getmtime(dest) <= 60:
            continue
        try:
            mine = "/.claude/projects/" in (json.load(open(dest)).get("transcript") or "").replace(os.sep, "/")
        except Exception:
            mine = False
        if mine:
            try:
                os.remove(dest)
            except OSError:
                pass
    json.dump(found, sys.stdout, separators=(",", ":"))


main()
