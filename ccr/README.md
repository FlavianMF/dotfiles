# Claude Code Router (CCR)

Local gateway that routes Claude Code to other providers (OpenRouter, NVIDIA Build). It is
optional and never replaces plain `claude`.

## Install

```bash
make ccr-install            # or ./install.sh --with=ccr
make ccr-update VERSION=x.y.z   # bump the pin in ccr/VERSION and install it
```

The version lives in `ccr/VERSION`. The package goes to `~/.local` and needs Node 22+.

## Why no config file in the repo

CCR 3.x keeps providers, keys and routes in `~/.claude-code-router/config.sqlite`. It has no
declarative JSON config and no `$VAR` references. Keys stay inside that directory, outside git.
Do not commit anything from it, including the output of **Settings -> Export data**.

## One-time setup (manual)

1. Run `ccr ui`.
2. Add the providers:
   - OpenRouter (built in). Paste the key in the UI.
   - NVIDIA Build, as a custom OpenAI-compatible provider. Base URL `https://integrate.api.nvidia.com/v1`.
3. Under **Routing**: strong OpenRouter model for default and think, a cheap NVIDIA model for
   background, a long-context OpenRouter model for long context.
4. Under **Agent Config**: create and enable a Claude Code profile named `Claude Code`.
5. Open a new shell and run `ccrc`.

## Use

- `ccrc [claude args]` starts the gateway (`127.0.0.1:3456`) if needed and launches the profile.
- Set `CCR_PROFILE` to use another profile name or id.
- `ccr stop` stops the background service. `ccr ui` opens the management UI (`127.0.0.1:3458`).
