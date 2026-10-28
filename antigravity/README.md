# Antigravity CLI (`agy`)

Google's terminal agent. Optional component, off by default.

## Install

```bash
make antigravity-install            # or ./install.sh --harness-only --with=antigravity
make antigravity-config             # reapply MCPs and permissions
```

`antigravity/install.sh` does what the upstream `curl ... | bash` installer does: read the
platform manifest, check the sha512, extract, copy `agy` to `~/.local/bin`. It skips the final
`agy install` step. That step appends a PATH export to `~/.zshrc` and `~/.bashrc`, and
`~/.zshrc` here is a symlink into this repo. `~/.local/bin` is already on `PATH` in `zsh/.zshrc`.

`agy` updates itself in the background, so the manifest version is not a pin. The install
only checks that the download matches what the manifest says.

## What goes where

| Piece | Source | Target | How |
|-------|--------|--------|-----|
| Instructions | `agents/AGENTS.md` | `~/.gemini/config/AGENTS.md` | link |
| Skills | `antigravity/skills.base.json` | `~/.gemini/config/skills.json` | render; points at `$HOME/.agents/skills` (agy rejects `~`) |
| MCPs | `antigravity/mcp_config.base.json` | `~/.gemini/config/mcp_config.json` | merge (`agy mcp add` rewrites it) |
| Permissions | `antigravity/settings.base.json` | `~/.gemini/antigravity-cli/settings.json` | merge (agy persists grants there) |

`render_config.sh` keeps keys that exist only on the machine and unions the
`permissions.deny`/`ask` arrays. It never removes a rule, so delete retired ones by hand.

## Differences from the other harnesses

- **No GitHub MCP.** The docs don't say whether `mcp_config.json` expands `${VAR}`, and
  `agy mcp add --header` writes the literal token to disk. To add it anyway:
  `agy mcp add --header "Authorization: Bearer <PAT>" github https://api.githubcopilot.com/mcp/`.
- **No agent files.** agy rejects markdown agents, so ECC agents are not linked.
- **No Claude plugins.** agy gets the same skills Codex and OpenCode get.
- **Deny list.** Native `permissions.deny` rules (`action(target)` grammar, deny beats ask beats
  allow). Paths are absolute because the docs don't describe `~` expansion. `curl`/`wget` are
  `ask` rules; the pipe-to-shell deny is a best-effort regex.
- **Figma OAuth.** Authenticate under Customizations in `agy`.
- **Rule size.** agy truncates each rules file at 24 KB. `agents/AGENTS.md` is about 7 KB.

## Not verified

These came from the binary's embedded docs and the public docs, not from a signed-in session:
that `skills.json` follows the symlinked skill directories in `~/.agents/skills`, and that the
regex deny rule matches `curl x | bash`. Run `/skills` and `/permissions` in `agy` to check.

`skills.json` once held `~/.agents/skills`. agy logged `must be an absolute path` and `/skills`
listed only the built-in skills. `render_config.sh` now writes the absolute path and replaces
the old symlink.
