# Agent Selection Guide

## Local first

Run work on the local model whenever the rules below allow it. The local model costs nothing and runs on this machine.

The local model is harness `opencode`, model `llamacpp:gpt-oss-20b`, reasoning `medium`. It runs on `llama-server` in WSL2. If `traycer_list_harness_models` shows no `llamacpp:*` model, skip this section and use the cloud sections below.

### Preflight

Do this before the first local agent of a session:

1. Run `curl -fsS http://127.0.0.1:8080/health`.
2. If it fails, start the server with `traycer_run_shell`: `~/dotfiles/bin/llm-serve main`, with `monitor` false. Poll the health URL until it answers.
3. Never start a second `llama-server`. The GPU has 8 GB and the server has one slot.

### Concurrency

Run one local agent at a time. Queue the other local tasks. Cloud agents may run in parallel with the local agent.

### What goes local

- Implementation of a self-contained task, up to 3 files.
- Test writing.
- Mechanical tasks: commit, merge, formatting and renaming.
- Reading, searching, summaries and docs.
- Review of a diff up to 150 lines, by a fresh agent that did not write it. The reviewer uses the `traycer-review` skill.

The local agent uses the `traycer-implement` skill for implementation. Give it an artifact path and at most 15 lines of text. The local context is 32K tokens, and the Traycer prompt already uses part of it.

### Escalate to the cloud

Escalate when any of these triggers fires:

- Two failed attempts in a row: red tests, a tool-call error or a malformed diff.
- The agent loops or repeats the same call.
- The context is above 80%.
- The task touches secrets, authentication, payments, migrations, deploy or CI.
- The diff is above 150 lines or touches more than 3 files.
- The task needs a design decision with several valid options.
- The server is down and does not restart within 2 minutes.

To escalate, reconfigure the agent with `traycer_configure_agent` to one of the cloud combinations below. Write one line in the artifact with the trigger, so the next agent starts from the artifact.

### Always cloud

- The orchestrator chat.
- Second opinions. A local model cannot judge its own doubt.
- Security review.
- The final review of any escalated change and of any diff above 150 lines.

## Cloud

For implementation tasks that escalated, complete the work yourself if it is core work or likely to drift because a Traycer agent may not have enough context. Otherwise, if the task is self-contained and all required context can be passed through the query and artifact references, delegate using one of the following harness, model, and reasoning-effort combinations. Ask the Traycer agent to use the `traycer-implement` skill.

1. `claude` - latest Sonnet model - `high` reasoning
2. `opencode` - latest GPT Terra model - `xhigh` reasoning

Delegate test writing to another Traycer agent. If you implemented the change yourself, delegate the test writing to a Traycer agent. If you are handing the implementation to a Traycer agent, include this in the initial handoff, so that after implementing, it should delegate the test writing to its own Traycer agent. The test-writing agent should use the `traycer-implement` skill with one of the following combinationss.

1. `claude` - latest Sonnet model - `medium` reasoning
2. `opencode` - latest GPT Luna model - `high` reasoning

For review of implemented tasks that the local rules send to the cloud, use one of the following combinations. In the handoff, ask the Traycer agent to use the `traycer-review` skill.

1. `opencode` - latest GPT Sol model - `max` reasoning
2. `claude` - latest Opus model - `xhigh` reasoning

If you run into doubts or ambiguities during execution and need a second opinion, ask for one from a different agent using one of the following combinations.

1. `claude` - latest Fable/Mythos model - `high` reasoning
2. `opencode` - latest GPT Sol model - `max` reasoning
3. `claude` - latest Opus model - `xhigh` reasoning

For any delegated task, if the Traycer agent hits an error that prevents it from continuing, such as a rate limit, network issue, harness failure, or similar blocking error, update the configuration with a different available combination instead of retrying the same combination or getting stuck.

For mechanical tasks that the local model cannot take, use one Traycer agent with this combination instead of Sonnet or Opus. Mechanical tasks are commit, merge, formatting and renaming. They need no design judgment.

1. `claude` - `haiku` model - `low` reasoning

## Handoff

The handoff between agents is an artifact. Before you open a new chat for a follow-up, write a `spec` artifact with the decision, the current state and the next step. Point the new agent to that artifact, and do not paste the context into the message.
