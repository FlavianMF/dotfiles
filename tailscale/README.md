# Tailscale behind Fortinet / SSL Inspection (WSL2)

When the local network's Fortinet firewall intercepts HTTPS (`x509: certificate signed by unknown authority` on `controlplane.tailscale.com`), you can tunnel `tailscaled` through an external VPS over SSH.

## 1. Enable the SSH SOCKS5 proxy for `tailscaled`

```bash
make tailscale-proxy-on
```

- Opens `ssh -f -N -D 1080 vps` (override with `VPS=... PORT=...`).
- Configures `/etc/systemd/system/tailscaled.service.d/proxy.conf` with `ALL_PROXY=socks5://127.0.0.1:1080` and restarts `tailscaled`.

To disable and clean up:

```bash
make tailscale-proxy-off
```

## 2. Use an exit node without breaking the SSH tunnel

Enabling `--exit-node` routes all traffic through `tailscale0`, which would break the `ssh vps` tunnel itself unless `vps` is pinned to your local gateway:

```bash
make tailscale-exit-on
```

To disable the exit node and remove the static route:

```bash
make tailscale-exit-off
```

## 3. Bypass Fortinet in a Windows browser

WSL2's Tailscale exit node only routes WSL2 Linux traffic. To route a Windows browser through the same `127.0.0.1:1080` SOCKS5 tunnel (forwarded automatically by WSL2):

- **Firefox:** Settings → General → Network Settings → Manual proxy configuration → SOCKS Host `127.0.0.1`, Port `1080`, **SOCKS v5**, and check **Proxy DNS when using SOCKS v5**.
- **Chrome / Edge:** Close all browser windows and launch with:
  ```powershell
  chrome.exe --proxy-server="socks5://127.0.0.1:1080" --host-resolver-rules="MAP * ~NOTFOUND , EXCLUDE 127.0.0.1"
  ```
  *(Use `msedge.exe` for Edge.)*
