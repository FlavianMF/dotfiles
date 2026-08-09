---
name: second-brain-sync
description: >
  Connects and keeps in sync a personal Obsidian "second brain" vault (git submodule
  at docs/second_brain/) across every project. Three behaviors: (1) bootstrap the
  vault submodule into a project that doesn't have it yet, (2) read the vault via its
  generated manifests (00_META/manifests/) via grep instead of opening every note or
  relying on Dataview blocks, which are inert outside the Obsidian app, (3) autonomously
  distill and push new patterns/decisions/traps to the vault + bump the submodule
  pointer at the end of any dev task in a project that already has the submodule — no
  confirmation needed. Use when: user says "connect the second brain / vault", "sync my
  notes", "update the vault"; mentions "obsidian vault" or "docs/second_brain"; OR —
  auto-trigger — you are about to finish a coding task in a project that has
  docs/second_brain/, or you need prior context/patterns before starting one.
---

Connects a git-submodule-based Obsidian vault to the current project, reads it
efficiently, and keeps it updated autonomously as work happens.

## Prerequisites

- `docs/second_brain/` exists as a git submodule and is checked out on `master`
  (not detached HEAD) — see Behavior 1 if it doesn't exist yet.
- `python3` on PATH (scripts are stdlib-only, no pip install needed).
- `gh` authenticated with an HTTPS git credential helper wired into
  `~/.gitconfig` (`credential.https://github.com.helper`) so push works without
  extra SSH setup.

## Behavior 1 — Initial Connection

Run when a project wants the vault but doesn't have it yet:

1. Confirm the project is already a git repo. Do not `git init` it yourself —
   that's a separate, explicit user action.
2. Ensure `docs/` exists.
3. `git submodule add https://github.com/FlavianMF/obisidian_vault.git docs/second_brain`
4. `git config -f .gitmodules submodule.docs/second_brain.branch master`
5. **`git -C docs/second_brain checkout master`** — critical. `submodule add`
   leaves the checkout in detached HEAD at whatever commit was `origin/master`'s
   tip at add-time. Skip this and a later sync commit lands on an unreachable
   detached-HEAD commit that can't be pushed to `master`.
6. `git add .gitmodules docs/second_brain && git commit -m "chore: connect second-brain vault as submodule at docs/second_brain"`

## Behavior 2 — Manifest-First Read

Before reading vault content:

1. Read `docs/second_brain/00_META/manifests/INDEX.md` — small, always safe to read in full.
2. **`grep` — never `Read` in full** — the relevant `docs/second_brain/00_META/manifests/by_type/<type>*.md`
   file(s) for your keyword. The glob covers shards automatically if a type has
   grown past the shard threshold. This keeps context cost proportional to how
   many rows match, not to how large the vault has grown.
3. Open (Read tool) only the shortlisted full notes from the grep matches.
4. Inside a note you may follow one hop of its `[[wikilinks]]` for traceability
   (existing vault convention) — don't re-scan manifests recursively for every link.
5. If Gemini-CLI-style `obsidian_rag_query`/`obsidian_read_note`/`obsidian_link_audit`
   tools happen to be available (they aren't in Claude Code), those remain
   preferred per the vault's own `Agent-Instruction.md` — this behavior is the
   concrete fallback for agents that don't have them.

## Behavior 3 — Autonomous End-of-Task Sync

Trigger: you are finishing a dev task in a project that has `docs/second_brain/`.
**Do this without asking for confirmation** — that's an explicit user decision,
not an oversight.

1. If you learned a generalizable pattern, decision, or trap, draft/update a note
   (typically under `20_Permanent_Notes/`) with the standardized frontmatter
   (see below), `provenance: <this-project-name>`.
2. Run:
   ```
   python3 <skill-dir>/scripts/vault_sync.py \
     --vault-path docs/second_brain \
     --note "20_Permanent_Notes/<Your Note>.md" \
     --project-name <this-project-name> \
     --message "<concise commit message>"
   ```
   This pulls `--ff-only`, regenerates manifests, stages only the note + any
   manifest files that actually changed, commits, and pushes to the vault's
   `master`. It refuses to run if the vault has unrelated dirty files.
3. In the **parent** project (not the vault), bump the pointer locally — do not
   push the parent project, that repo's own push/PR discipline is untouched:
   ```
   git add docs/second_brain
   git commit -m "chore: bump second_brain to <short-sha> - <summary>"
   ```

**Explicit tradeoff**: every other already-cloned consumer project's
`docs/second_brain` gitlink stays at the old commit until that project's own
next sync runs. This is accepted, not a bug.

## Frontmatter Schema

Canonical copy lives in the vault at `docs/second_brain/00_META/Frontmatter-Schema.md`
(so any agent reading the vault directly sees it, not just ones with this skill).

| field | required | notes |
|---|---|---|
| `title` | yes | human-readable, may differ from filename |
| `type` | yes | `meta, pattern, decision, concept, trap, project, literature, moc, inbox, template, unclassified` |
| `tags` | yes | list, may be `[]` |
| `created` | yes | `YYYY-MM-DD` |
| `provenance` | recommended | `manual` for hand-authored notes; originating project name for agent-distilled notes |
| `project` | optional | freeform, already used ad hoc |

`path` is never a frontmatter field — it's manifest-only, computed metadata.

## Guardrails

- Never `--force` push. Never rewrite vault history.
- Never `git add -A` inside the vault — only explicit paths.
- One concern per commit.
- Never delete or overwrite an existing note without a clearly superseding reason.
- The submodule pointer bump happens in the same flow as the vault push, not later.
- Staleness of *other* consumer projects after a sync is expected and acceptable.

## Examples

Connecting a new project:
```
git submodule add https://github.com/FlavianMF/obisidian_vault.git docs/second_brain
git config -f .gitmodules submodule.docs/second_brain.branch master
git -C docs/second_brain checkout master
git add .gitmodules docs/second_brain
git commit -m "chore: connect second-brain vault as submodule at docs/second_brain"
```

Reading before answering "how did I handle Docker sandboxing before":
```
grep -il docker docs/second_brain/00_META/manifests/by_type/*.md
```

Syncing a learned pattern at the end of a task:
```
python3 ~/.claude/skills/second-brain-sync/scripts/vault_sync.py \
  --vault-path docs/second_brain \
  --note "20_Permanent_Notes/OAuth Refresh Token Race.md" \
  --project-name hermes_docker \
  --message "docs(vault): distill OAuth refresh race condition pattern"
```

## Boundaries

Does not touch the parent project's own branch/PR flow — that's governed by
whatever conventions already apply there; this skill only adds one local
commit for the pointer bump. Does not push the parent project. Does not
modify vault content the agent didn't author this session, except via the
one-time `backfill_frontmatter.py` migration pass, which is idempotent and
never overwrites an existing populated field. "stop caveman" / mode changes
elsewhere don't affect this skill's behavior — it has no persona of its own.
