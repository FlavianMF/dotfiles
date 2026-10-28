# Traycer

Desktop app that orchestrates Claude Code, Codex and Cursor. Optional component.

## Install

```bash
make traycer-install     # or ./install.sh --with=traycer
make traycer-update      # re-pin after upstream ships a new build
```

The AppImage goes to `~/.local/opt/traycer/` and the launcher to `~/.local/bin/traycer`.
Upstream publishes no version or checksum, so `traycer/SHA256` pins the build. If upstream
changes the build, the install fails with a mismatch. Review the new build, run
`make traycer-update`, check `git diff traycer/SHA256` and commit it.

## WSL2

- Use WSL 2 with WSLg (`wsl --update`).
- Enable systemd in `/etc/wsl.conf` (`[boot]` / `systemd=true`), then run `wsl --shutdown`. The Traycer host runs as a systemd user service.
- Set a default browser inside WSL. If none opens at sign-in, choose **Use code instead**.
- The installer runs `sudo apt-get install -y libfuse2t64` (`libfuse2` on Ubuntu 22.04) when `libfuse.so.2` is missing. `fusermount3` alone is not enough, and the `fuse` package is the wrong fix. If that step fails, the launcher still works but starts slower.
- Without that library or `/dev/fuse`, the launcher sets `APPIMAGE_EXTRACT_AND_RUN=1`, so the AppImage extracts itself on each run.
- Traycer in WSL is a separate host from Traycer on Windows.

## State

Login and state live in `~`. Nothing from Traycer goes into git.

## Agent selection guide

`traycer/agent-selection-guide.md` is the versioned copy of `~/.traycer/agent-selection-guide.md`. It routes mechanical tasks (commit, merge, formatting, renaming) to `claude` `haiku` with `low` reasoning and sets the artifact handoff rule.

`traycer/install.sh` calls `traycer/install_guide.sh`, which needs no network. It runs `cp` and never creates a symlink. The Traycer app can rewrite the guide, so a link could turn into a plain file or change the repo. `~/.traycer/.agent-selection-guide.meta.json` is not touched.

- If the destination is identical, the script does nothing.
- If the destination differs or is a symlink, the script keeps a `agent-selection-guide.md.bak.YYYYMMDD-HHMMSS` copy before it overwrites.
- `--dry-run` prints the actions and changes nothing.

To bring edits made in the Traycer UI back to the repo, compare the two files and copy what you want to keep:

```bash
diff ~/.traycer/agent-selection-guide.md traycer/agent-selection-guide.md
```
