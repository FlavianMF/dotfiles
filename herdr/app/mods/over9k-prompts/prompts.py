#!/usr/bin/env python3
# Your prompts in a Claude Code transcript, for the Prompts panel (over9k-prompts):
#   prompts.py <transcript.jsonl | folder> [last]
# A folder (Claude Code's for a working directory, ~/.claude/projects/<slug>):
# its newest conversation. last ("<path>\t<size>", what was read before): when
# that's still the file and its size, it prints {"same": true} and reads nothing.
# prints JSON: {prompts: [{at, done, text, also, reply, edits, cmds, tools, tokens}],
# oldest first, context}; context: what the agent holds now (its last reply's input,
# cached and not: the CLI status line's "context" figure). A prompt is
# a message you typed (not a tool result, a command's output or a system note),
# One you sent while it was working (a queued command) stays in that turn, in
# also: [{at, text}], as the CLI counts its time and tokens. reply: the agent's
# last text before your next prompt; edits: the files it changed; cmds: shell
# commands it ran; tools: every tool call; done: when its last step was (the
# time worked is done - at); tokens: what the agent wrote (output tokens, each
# message once: its blocks repeat its usage; the largest count is the final one).
import json, os, sys

SKIP = ("<command-", "<local-command", "<system-reminder", "<task-notification", "<bash-", "Caveat:", "[Request interrupted")


def text_of(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        if any(isinstance(b, dict) and b.get("type") == "tool_result" for b in content):
            return None
        return "\n".join(b.get("text", "") for b in content if isinstance(b, dict) and b.get("type") == "text")
    return None


def main():
    path = sys.argv[1]
    if not os.path.exists(path):
        print('{"prompts": [], "context": 0, "size": 0, "path": null}')
        return
    if os.path.isdir(path):
        files = [os.path.join(path, f) for f in os.listdir(path) if f.endswith(".jsonl")]
        if not files:
            print('{"prompts": [], "context": 0, "size": 0, "path": null}')
            return
        path = max(files, key=os.path.getmtime)
    size = os.path.getsize(path)
    if len(sys.argv) > 2 and sys.argv[2] == f"{path}\t{size}":
        print('{"same": true}')
        return
    sys.argv[1] = path
    out, cur, context = [], None, 0
    with open(sys.argv[1], encoding="utf-8", errors="replace") as f:
        for line in f:
            try:
                e = json.loads(line)
            except ValueError:
                continue
            said, queued = None, False
            if e.get("type") == "user" and not e.get("isMeta") and not e.get("isSidechain"):
                said = text_of((e.get("message") or {}).get("content"))
            elif e.get("type") == "attachment":
                a = e.get("attachment") or {}
                if a.get("type") == "queued_command" and (a.get("origin") or {}).get("kind", "human") == "human" and isinstance(a.get("prompt"), str):
                    said, queued = a["prompt"], True
            if said is not None:
                said = said.strip()
                if said and not said.startswith(SKIP) and queued and cur is not None:
                    cur["also"].append({"at": e.get("timestamp"), "text": said})
                elif said and not said.startswith(SKIP):
                    cur = {"at": e.get("timestamp"), "done": None, "text": said, "also": [], "reply": "", "edits": [], "cmds": 0, "tools": 0, "tokens": 0, "_tok": {}}
                    out.append(cur)
                continue
            if cur is None or e.get("isSidechain") or e.get("type") not in ("assistant", "user"):
                continue
            if e.get("timestamp"):
                cur["done"] = e["timestamp"]
            if e.get("type") != "assistant":
                continue
            m = e.get("message") or {}
            u = m.get("usage") or {}
            if u:
                context = (u.get("input_tokens") or 0) + (u.get("cache_read_input_tokens") or 0) + (u.get("cache_creation_input_tokens") or 0)
            n = u.get("output_tokens") or 0
            cur["_tok"][m.get("id")] = max(n, cur["_tok"].get(m.get("id"), 0))
            for b in (e.get("message") or {}).get("content") or []:
                if not isinstance(b, dict):
                    continue
                if b.get("type") == "text" and b.get("text", "").strip():
                    cur["reply"] = b["text"].strip()
                elif b.get("type") == "tool_use":
                    cur["tools"] += 1
                    i = b.get("input") or {}
                    if b.get("name") in ("Edit", "Write", "NotebookEdit", "MultiEdit"):
                        p = i.get("file_path") or i.get("notebook_path")
                        if p and p not in cur["edits"]:
                            cur["edits"].append(p)
                    elif b.get("name") == "Bash":
                        cur["cmds"] += 1
    for p in out:
        p["tokens"] = sum(p.pop("_tok").values())
    json.dump({"prompts": out, "context": context, "size": size, "path": path}, sys.stdout)


main()
