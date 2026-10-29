# Agent Selection Guide

Spend quota in this order: the `claude` Pro plan, then the `antigravity` Google AI Pro plan, then dollars. Use OpenRouter (paid `opencode` models) only after the user says yes.

## Roles

| Role | Harness | Model | Effort | Pool |
| --- | --- | --- | --- | --- |
| Orchestrator | `claude` | `sonnet` | `medium` | Pro |
| Orchestrator, on a trigger | `claude` | `opus` | `high` | Pro |
| Self-contained implementation, tests included | `claude` | `sonnet` | `high` | Pro |
| Bounded task, web research | `antigravity` | `gemini-3.8-flash` | `medium` | Gemini |
| Git operation (commit, merge, push, rebase) | `claude` | `haiku` | `low` | Pro |
| Mechanical task | `claude` | `haiku` | `low` | Pro |
| Review | `antigravity` | `claude-opus-5.5` | `high` | 3p |
| Second opinion | `claude` | `fable` | `high` | Pro |
| Second opinion, alternatives | `antigravity` | `claude-opus-5.5` or `gemini-4-argon` | `high` | 3p or Gemini |

- Orchestrator triggers for `opus`: an architecture decision, a debug stuck after 2 attempts, or the final review of a sensitive change. Return to `sonnet` afterwards.
- Mechanical tasks are formatting and renaming.
- Git operations always use `claude` `haiku` `low`. Give the agent the commit message and the file list, and tell it to follow the `git-ops` rules: no push, no AI attribution.
- Sensitive topics are secrets, authentication, payments, migrations, deploy and CI.
- Implementers and reviewers use the `traycer-implement` and `traycer-review` skills.

## Delegation

- Do coupled, sequential work inline. Delegate only self-contained or parallel tasks.
- The implementer writes the tests. Do not create a separate test agent.
- Create a separate reviewer only for a diff above 150 lines or a sensitive change.
- Give `gemini-3.8-flash` a task only if all hold: at most 2 files, at most 50 diff lines, an acceptance check in the handoff, no design decision, no sensitive topic. Otherwise use `sonnet`.
- Flash runs the acceptance check and returns the result with `git diff --stat`. Read its diff yourself before the commit. One Flash failure moves the task to `sonnet`.
- If the `antigravity` agent has no web search tool, send web research to `sonnet` with `WebSearch`.

## Sessions

- Plan the work in slices that fit in 100k tokens. The limit applies to every session, the orchestrator included.
- Near 80k tokens, finish the current step, write a `spec` artifact and continue in a new chat. Do not rely on auto-compaction.

## Quota guard

Before you create more than one agent, read `traycer_get_provider_profile_rate_limits` for `claude` and `antigravity`.

The thresholds apply to the 5h window and to the 7-day window. The higher one decides.

- Pro above 80%: no fan-out. Delegated `sonnet` moves to `antigravity` `claude-sonnet-5.5` `high`.
- Pro above 95% or rate limited: reading and mechanical tasks go to `gemini-3.8-flash`. Implementation waits for the window or goes to OpenRouter after the user says yes.
- 3p above 95% or rate limited: review moves to `claude` `opus` `high`, and delegated `sonnet` work stays inline.
- Gemini pool also exhausted: reading and mechanical tasks go to a free `opencode` model, such as `opencode:deepseek-v4.1-flash-free`.
- Before you use the 3p pool, check `traycer_list_harness_models antigravity`. If no `claude-*` model is listed, drop that pool for the session and tell the user.
- On a blocking error (rate limit, network, harness failure), switch to another combination. Do not retry the same one.

## Local (opt-in)

Harness `opencode`, model `llamacpp:gpt-oss-20b`, effort `medium`, on `llama-server` at `127.0.0.1:8080`. 32K context.

- Use it only for mechanical or reading tasks, and only if `curl -fsS http://127.0.0.1:8080/health` already passes. Do not start the server.
- When the health check passes, you may use it instead of `haiku` or Flash. It spends no quota.
- Run one local agent at a time. One failure moves the task to `haiku` (mechanical) or `sonnet` (reading).

## Handoff

The handoff between agents is an artifact. Before you open a new chat for a follow-up, write a `spec` artifact with the decision, the current state and the next step. Point the new agent to that artifact, and do not paste the context into the message.
