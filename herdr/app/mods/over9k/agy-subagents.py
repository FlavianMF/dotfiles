#!/usr/bin/env python3
# Antigravity CLI (agy) subagents of the agent in Herdr terminal argv[1], in
# subagents.sh's format: one line each, tab-separated: id, last write
# (seconds), description, type, model, when it started (seconds), context
# tokens (0: agy's aren't readable), effort, context window, 1 once it's done.
# Its conversation: the presence lock (~/.gemini/antigravity-cli/presence/
# <id>.lock) its processes hold open (Linux /proc), else argv[2] (the id its
# status line saved). Subagents are the conversations under it (any depth) in
# conversation_summaries.db; role from raw_summary (17.8.2), model and effort
# from the subagent's newest gen_metadata ("Gemini 4 Argon (Medium)"). Done:
# idle and not "not fully idle", or killed. Ones done over 10 minutes ago go.
import json, os, re, sqlite3, subprocess, sys, time

home = os.path.expanduser("~/.gemini/antigravity-cli")
term = sys.argv[1] if len(sys.argv) > 1 else ""
conv = sys.argv[2] if len(sys.argv) > 2 else ""


def procs_under(root):
    kids = {}
    for p in os.listdir("/proc"):
        if not p.isdigit():
            continue
        try:
            ppid = open(f"/proc/{p}/stat").read().rsplit(")", 1)[1].split()[1]
        except OSError:
            continue
        kids.setdefault(ppid, []).append(p)
    out, todo = [], [str(root)]
    while todo:
        p = todo.pop()
        out.append(p)
        todo += kids.get(p, [])
    return out


def live_conversation():
    try:
        pid = json.loads(subprocess.run(["hc", "get", term, "--json"], capture_output=True, text=True, timeout=5).stdout).get("pid")
    except Exception:
        return None
    if not pid or not os.path.isdir("/proc"):
        return None
    for p in procs_under(pid):
        try:
            for fd in os.listdir(f"/proc/{p}/fd"):
                m = re.search(r"/presence/([0-9a-f-]{36})\.lock$", os.readlink(f"/proc/{p}/fd/{fd}"))
                if m:
                    return m.group(1)
        except OSError:
            continue
    return None


def varint(b, i):
    n = s = 0
    while True:
        c = b[i]; i += 1
        n |= (c & 0x7F) << s; s += 7
        if c < 0x80:
            return n, i


def fields(b):
    i, out = 0, {}
    try:
        while i < len(b):
            key, i = varint(b, i)
            f, w = key >> 3, key & 7
            if w == 0:
                v, i = varint(b, i)
            elif w == 2:
                n, i = varint(b, i); v = b[i:i + n]; i += n
            elif w == 1:
                v = b[i:i + 8]; i += 8
            elif w == 5:
                v = b[i:i + 4]; i += 4
            else:
                break
            out.setdefault(f, []).append(v)
    except IndexError:
        pass
    return out


def role(raw):
    try:
        r = fields(fields(fields(raw)[17][0])[8][0])[2][0]
        return r.decode()
    except Exception:
        return ""


def model(cid):
    try:
        db = sqlite3.connect(f"file:{home}/conversations/{cid}.db?mode=ro", uri=True, timeout=1)
        row = db.execute("select data from gen_metadata order by idx desc limit 1").fetchone()
    except sqlite3.Error:
        return "", ""
    m = re.search(rb"(Gemini [\x20-\x7e]{1,40}?|Claude [\x20-\x7e]{1,40}?|GPT[\x20-\x7e]{1,40}?) \((Minimal|Low|Medium|High|Xhigh|Max)\)", row[0] if row else b"")
    return (m.group(1).decode(), m.group(2).decode().lower()) if m else ("", "")


def secs(t):
    t = re.sub(r"(\.\d{6})\d*", r"\1", t).replace("+00:00", "+0000")
    try:
        return int(time.mktime(time.strptime(t[:19], "%Y-%m-%d %H:%M:%S")) - time.timezone)
    except ValueError:
        return 0


cid = live_conversation() or conv
if not cid:
    sys.exit(0)
try:
    db = sqlite3.connect(f"file:{home}/conversation_summaries.db?mode=ro", uri=True, timeout=1)
    rows = db.execute("""with recursive k(id) as (select conversation_id from conversation_summaries where parent_conversation_id = ?
                         union select c.conversation_id from conversation_summaries c join k on c.parent_conversation_id = k.id)
                         select conversation_id, title, last_modified_time, status, agent_name, not_fully_idle, killed, raw_summary
                         from conversation_summaries where conversation_id in (select id from k)""", (cid,)).fetchall()
except sqlite3.Error:
    sys.exit(0)
now = time.time()
for id_, title, mod, status, agent, busy, killed, raw in rows:
    at = secs(mod)
    done = bool(killed) or (status not in ("CASCADE_RUN_STATUS_RUNNING", "CASCADE_RUN_STATUS_BUSY", "CASCADE_RUN_STATUS_CANCELING") and not busy)
    if done and now - at > int(os.environ.get("AGY_SUBS_KEEP", 600)):
        continue
    r = fields(raw or b"")
    start = fields(r[7][0]).get(1, [0])[0] if r.get(7) else 0
    name, effort = model(id_)
    desc = role(raw or b"") or title or agent or "subagent"
    print("\t".join(str(x) for x in [id_, at, desc.replace("\t", " "), agent or "subagent", name, start, 0, effort, 1048576, 1 if done else 0]))
