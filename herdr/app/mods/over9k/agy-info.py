#!/usr/bin/env python3
# What the sidebar shows under each Antigravity (agy) agent, read from agy's own
# files (no status line involved):
#   the agy process's HC_TERMINAL_ID   which Herdr terminal it runs in
#   presence/<id>.lock it holds open   which conversation it's in (/proc on Linux,
#                                      lsof on macOS)
#   conversations/<id>.db              model and effort ("Gemini 4 Argon (Medium)")
#                                      from its newest gen_metadata
#   conversation_summaries.db          its title, and when it last changed
# Prints one JSON object keyed by terminal, in the fields Antigravity's status
# line saves ({model, id, effort, agent, context, lastAt, conversation, title});
# context stays null: agy keeps it in a form that can't be read. Python 3,
# standard library (sqlite3).
import json, os, re, sqlite3, subprocess, sys, time

HOME = os.path.expanduser("~/.gemini/antigravity-cli")
LOCK = re.compile(r"/presence/([0-9a-f-]{36})\.lock$")


def agy_pids():
    # Linux: /proc; elsewhere: ps.
    if os.path.isdir("/proc"):
        out = []
        for p in os.listdir("/proc"):
            if not p.isdigit():
                continue
            try:
                comm = open(f"/proc/{p}/comm").read().strip()
            except OSError:
                continue
            if comm in ("agy", "antigravity"):
                out.append(int(p))
        return out
    try:
        r = subprocess.run(["ps", "-axo", "pid=,comm="], capture_output=True, text=True, timeout=3).stdout
    except Exception:
        return []
    return [int(l.split()[0]) for l in r.splitlines() if l.split() and os.path.basename(l.split()[-1]) in ("agy", "antigravity")]


def terminal_of(pid):
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


def conversation_of(pid):
    if os.path.isdir(f"/proc/{pid}/fd"):
        try:
            for fd in os.listdir(f"/proc/{pid}/fd"):
                try:
                    m = LOCK.search(os.readlink(f"/proc/{pid}/fd/{fd}"))
                except OSError:
                    continue
                if m:
                    return m.group(1)
        except OSError:
            pass
        return None
    try:
        out = subprocess.run(["lsof", "-p", str(pid), "-Fn"], capture_output=True, text=True, timeout=3).stdout
    except Exception:
        return None
    for line in out.splitlines():
        m = LOCK.search(line[1:]) if line.startswith("n") else None
        if m:
            return m.group(1)
    return None


def model_of(cid):
    try:
        db = sqlite3.connect(f"file:{HOME}/conversations/{cid}.db?mode=ro", uri=True, timeout=1)
        row = db.execute("select data from gen_metadata order by idx desc limit 1").fetchone()
        db.close()
    except sqlite3.Error:
        return None, None
    m = re.search(rb"(Gemini [\x20-\x7e]{1,40}?|Claude [\x20-\x7e]{1,40}?|GPT[\x20-\x7e]{1,40}?) \((Minimal|Low|Medium|High|Xhigh|Max)\)", row[0] if row else b"")
    return (m.group(1).decode(), m.group(2).decode().lower()) if m else (None, None)


def secs(t):
    t = re.sub(r"(\.\d{6})\d*", r"\1", t or "")
    try:
        return int(time.mktime(time.strptime(t[:19], "%Y-%m-%d %H:%M:%S")) - time.timezone)
    except ValueError:
        return None


def summary_of(cid):
    try:
        db = sqlite3.connect(f"file:{HOME}/conversation_summaries.db?mode=ro", uri=True, timeout=1)
        row = db.execute("select title, last_modified_time from conversation_summaries where conversation_id = ?", (cid,)).fetchone()
        db.close()
    except sqlite3.Error:
        return None, None
    return (row[0] or None, secs(row[1])) if row else (None, None)


def main():
    found = {}
    if not os.path.isdir(HOME):
        print("{}")
        return
    for pid in agy_pids():
        term = terminal_of(pid)
        if not term or not re.fullmatch(r"[A-Za-z0-9_.-]+", term):
            continue
        cid = conversation_of(pid)
        info = {"model": None, "id": None, "effort": None, "agent": "antigravity", "context": None,
                "lastAt": None, "conversation": cid, "title": None}
        if cid:
            name, effort = model_of(cid)
            if name:
                info.update(model=name, id=f"{name} ({effort.capitalize()})" if effort else name, effort=effort)
            info["title"], info["lastAt"] = summary_of(cid)
        found[term] = info
    json.dump(found, sys.stdout, separators=(",", ":"))


main()
