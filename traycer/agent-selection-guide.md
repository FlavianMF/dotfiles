# Agent Selection Guide

For implementation tasks, complete the work yourself if it is core work or likely to drift because a Traycer agent may not have enough context. Otherwise, if the task is self-contained and all required context can be passed through the query and artifact references, delegate using one of the following harness, model, and reasoning-effort combinations. Ask the Traycer agent to use the `traycer-implement` skill.

1. `claude` - latest Sonnet model - `high` reasoning
2. `opencode` - latest GPT Terra model - `xhigh` reasoning

Delegate test writing to another Traycer agent. If you implemented the change yourself, delegate the test writing to a Traycer agent. If you are handing the implementation to a Traycer agent, include this in the initial handoff, so that after implementing, it should delegate the test writing to its own Traycer agent. The test-writing agent should use the `traycer-implement` skill with one of the following combinationss.

1. `claude` - latest Sonnet model - `medium` reasoning
2. `opencode` - latest GPT Luna model - `high` reasoning

For review of implemented tasks, use one of the following combinations. In the handoff, ask the Traycer agent to use the `traycer-review` skill.

1. `opencode` - latest GPT Sol model - `max` reasoning
2. `claude` - latest Opus model - `xhigh` reasoning

If you run into doubts or ambiguities during execution and need a second opinion, ask for one from a different agent using one of the following combinations.

1. `claude` - latest Fable/Mythos model - `high` reasoning
2. `opencode` - latest GPT Sol model - `max` reasoning
3. `claude` - latest Opus model - `xhigh` reasoning

For any delegated task, if the Traycer agent hits an error that prevents it from continuing, such as a rate limit, network issue, harness failure, or similar blocking error, update the configuration with a different available combination instead of retrying the same combination or getting stuck.

For mechanical tasks, use one Traycer agent with this combination instead of Sonnet or Opus. Mechanical tasks are commit, merge, formatting and renaming. They need no design judgment.

1. `claude` - `haiku` model - `low` reasoning

The handoff between agents is an artifact. Before you open a new chat for a follow-up, write a `spec` artifact with the decision, the current state and the next step. Point the new agent to that artifact, and do not paste the context into the message.
