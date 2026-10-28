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

## Antigravity: Claude and GPT-OSS models

Traycer's ACP handshake sends no `clientInfo`, so `agy_acp_server` hides the non-Gemini models.
It offers them only to clients named JetBrains, Zed or Xcode. `traycer/agy-acp-wrapper` adds
`clientInfo: {name: "zed"}` to `initialize` and passes everything else through. It identifies
Traycer as Zed, so Google can change that rule at any time.

`traycer/install.sh` runs `traycer/install_agy_wrapper.sh`. The script puts the wrapper in
`~/.local/bin/agy_acp_server`, with a `localharness_external` symlink beside it. It touches
nothing under `~/.traycer`. Rerun it after Traycer installs a new Antigravity pack.

Then, in Traycer, open Settings → Providers → Antigravity, select the PATH install and restart
the host. The choice lands in `~/.traycer/host/config/provider-overrides.json` as
`"selected": {"kind": "path"}`. The default is `{"kind": "bundled"}`, which ignores the wrapper.
Env overrides: `TRAYCER_AGY_CLIENT_NAME`, `TRAYCER_AGY_CLIENT_VERSION`, `AGY_ACP_REAL`.
