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
- Without FUSE, the launcher sets `APPIMAGE_EXTRACT_AND_RUN=1`, so the AppImage extracts itself on each run.
- Traycer in WSL is a separate host from Traycer on Windows.

## State

Login and state live in `~`. Nothing from Traycer goes into git.
