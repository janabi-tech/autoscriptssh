# ImagiTech VPN Deployment - Fully Extracted Source Tree

This folder is the **complete, de-obfuscated** version of the ImagiTech VPN
deployment pipeline hosted at `https://vpn.imagitech.online/install.sh`.

Everything that was previously:

- a `shc`-encrypted bash binary (`imagitech_core`)
- a wrapper script that just called the encrypted binary (`lib/*.sh`, `menus/*.sh`)
- a PyInstaller-compiled Python service (`services/**`)
- a base64-encoded external binary (`binaries/*.b64`)

has now been recovered to **plain, editable source code** that you can read
and modify in any text editor.

The original binary files are kept alongside the recovered source so you can
diff them, re-package them, or just verify the recovery.

---

## How the original install.sh deploys this

```
install.sh                         (the bootstrap you download with curl)
  |
  |-- 1. Downloads payload.tar.gz  --> extracts to /opt/imagitech/{bin,lib,menus,services,binaries}
  |       (this is the payload_* folders in this repo)
  |
  |-- 2. Runs the 5 installers in order:
  |       installers/01-core-setup.sh      - apt installs packages (curl, dropbear, haproxy, nginx, sqlite3, ...)
  |       installers/02-deploy-routing.sh  - configures Dropbear, Stunnel, HAProxy, Nginx decoy
  |       installers/03-deploy-sidecars.sh - deploys Dante SOCKS, UDP Custom, DNSTT (decodes the .b64 files)
  |       installers/04-deploy-xray.sh     - installs Xray-core + multi-protocol config
  |       installers/05-deploy-monitor.sh  - installs the daemon + speedtest + btop
  |
  |-- 3. Symlinks /opt/imagitech/bin/imagitech_core to /usr/local/sbin/menu and /usr/local/bin/imagitech
  |
  |-- 4. Installs an hourly cron heartbeat that calls the license API
  |       and stops all services if the license is revoked
  |
  `-- 5. Reboots the server
```

---

## Folder-by-folder contents

### install.sh
The original bootstrap. Plain bash, never encrypted. Verifies the calling
server's IP against `vpn.imagitech.online/api/v1/ip/verify`, downloads
`payload.tar.gz`, runs the 5 installers, and sets up the license-enforcement
cron + systemd tamper-detector.

### installers/
The 5 deployment phase scripts. **Already plain bash** in the original -
no extraction needed. Run in numeric order (01 → 05). Each one is
idempotent (safe to re-run).

### bin/
| File | What it is |
|------|------------|
| `imagitech_core`    | The **original shc-compiled binary** (305 KB ELF). Kept for reference. |
| `imagitech_core.sh` | **The recovered bash source** (145 KB, 3,400 lines). This is the entire application logic in plain text. |
| `imagitech`         | The CLI router sub-script (13 KB). When you run `imagitech sys restart`, this is what dispatches the call. |

The recovery was done by intercepting the `execvp("/bin/bash", ...)` call
that `shc` makes after decrypting the script in memory - see
`/home/z/my-project/scripts/unshc_hook.c` for the LD_PRELOAD hook used.

`imagitech_core.sh` is a **concatenation** of these files (in order):
1. `lib/system.sh`
2. `lib/db.sh`
3. `lib/installer_utils.sh`
4. `lib/services.sh`
5. `lib/users.sh`
6. `menus/xray_menu.sh`
7. `menus/main_menu.sh`
8. `bin/imagitech` (the multi-call entry point)

Each section is marked with `# --- START OF FILE: <path> ---` and has been
split back out into the individual files in `lib/` and `menus/`.

### lib/
The 5 library modules. In the original `payload.tar.gz` these were
**wrapper scripts** that just called the encrypted binary:

```bash
init_database() { /opt/imagitech/bin/imagitech_core init_database "$@"; }
```

In this repo, the wrappers have been **replaced with the actual bash source**
extracted from `imagitech_core`. So `lib/db.sh` is now the real
`init_database` implementation, not a one-liner proxy.

| File | Purpose |
|------|---------|
| `system.sh`         | Logging, root check, host/domain/SNI/NS management, SSL renewal, DNSTT key generation, uninstall |
| `db.sh`             | SQLite wrappers: `init_database`, `db_query`, `sqlite3` |
| `installer_utils.sh`| `safe_create_dir`, `safe_deploy_systemd`, `ensure_package`, `ensure_tls_cert`, `run_with_spinner` |
| `services.sh`       | `restart_service` |
| `users.sh`          | User management: `create_vpn_user`, `create_trial_user`, `renew_user`, `delete_vpn_user`, `sync_xray_users`, `kick_xray_user` |

### menus/
| File | Purpose |
|------|---------|
| `main_menu.sh` | The TUI dashboard you see when you type `menu` (71 KB - the whole UI) |
| `xray_menu.sh` | The Xray user management sub-menu |

Same as `lib/` - the original `payload.tar.gz` had wrappers; this repo has
the real source.

### binaries/
| File | What it is |
|------|------------|
| `dnstt-server.b64` | Original base64-encoded file as downloaded |
| `dnstt-server`     | **Decoded binary** - a Go DNS tunnel server (used for DNS-based tunneling over a delegated domain) |
| `udp-custom.b64`   | Original base64-encoded file |
| `udp-custom`       | **Decoded binary** - statically-linked UDP VPN custom server |

The `.b64` files are preserved unchanged. The decoded binaries are real
Go/C executables - they cannot be decompiled to readable source in the
same way the Python services can, but they can be inspected with
`strings`, `objdump`, or run directly.

### services/
Each service has 3-4 files alongside each other:

| Suffix | Meaning |
|--------|---------|
| (no suffix)   | The original PyInstaller-compiled binary (kept unchanged) |
| `.py`         | **Decompiled Python source** - this is what you read & edit |
| `_bytecode_disassembly.txt` | Full bytecode disassembly (pycdas output). Use this as a fallback if the `.py` is incomplete. |
| `_extracted/` | Full PyInstaller archive extraction (runtime hooks + PYZ modules). Mostly standard library code. |

| Service | Folder | Purpose |
|---------|--------|---------|
| `daemon`              | `monitor/`    | Background monitor - polls user bandwidth, syncs SQLite db, kills ghost sessions, enforces license every 30 min |
| `telegram-controller` | `monitor/`    | Telegram bot controller (53 KB of code) - handles user commands, account creation, receipts |
| `ws-proxy`            | `routing/`    | WebSocket-to-TCP proxy on `127.0.0.1:9880`. Accepts WebSocket upgrades and pipes the data to Dropbear on port 22. Lets SSH pass through CDN/WAF front-ends |
| `wss-injector`        | `routing/`    | WSS payload injector (TLS-wrapped variant of ws-proxy) |
| `server`              | `trial-api/`  | The trial-account HTTP API (HTTPServer on a local port, creates short-lived VPN users) |

**About the decompilation quality:**

All 5 services were compiled with **Python 3.11** and packed with
**PyInstaller**. They were extracted with `pyinstxtractor` and decompiled
with `pycdc` (Decompyle++). Decompilation quality:

- **`ws-proxy.py`** - **fully manually reconstructed** from bytecode. pycdc
  could not reverse Python 3.11's new `RETURN_GENERATOR` / `SEND` opcodes
  in async functions, so the function bodies were re-written by hand from
  `ws-proxy_bytecode_disassembly.txt`. This file is 100% runnable Python.
- **`daemon.py`, `telegram-controller.py`, `wss-injector.py`, `server.py`** -
  pycdc decompilation is **mostly complete**: imports, constants, class
  definitions, function signatures, and most function bodies are correct.
  However, a few function bodies contain pycdc artifacts like
  `with None:` or `if not None, ...` where the decompiler could not
  reconstruct a `try/except` or `with` block. For those specific spots,
  refer to the matching `*_bytecode_disassembly.txt` file - the bytecode
  is fully readable and you can manually fill in the 5-10 lines that
  pycdc got wrong. The overall logic and structure of each service is
  clear from the `.py` file alone.

---

## Editing & re-deploying

To make a change:

1. Edit the relevant file (e.g. `lib/users.sh`).
2. If you also edited the embedded copy inside `bin/imagitech_core.sh`,
   you can rebuild a single-call binary by simply running
   `bash bin/imagitech_core.sh` - no compilation needed. The original
   binary called `imagitech_core` only because it was an obfuscation
   wrapper; once you have the `.sh` source, you can run it directly.
3. For Python services, edit the `.py`, then either run it directly with
   `python3 services/monitor/daemon.py` or re-pack with PyInstaller:
   ```bash
   pip install pyinstaller
   pyinstaller --onefile services/monitor/daemon.py -n daemon
   ```

To make the install script pick up your modified version, host the
modified files on your own server and change `REPO_URL` at the top of
`install.sh` (line 5).

---

## File counts at a glance

```
install.sh                          1 file  (8.5 KB)
installers/                         5 files (38 KB total)
bin/                                3 files (305 KB binary + 145 KB source + 13 KB CLI router)
lib/                                5 files (44 KB total - real source)
menus/                              2 files (87 KB total - real source)
binaries/                           4 files (5.6 MB + 6.5 MB .b64, 4.2 MB + 4.8 MB decoded)
services/monitor/                   2 services (daemon + telegram-controller)
services/routing/                   2 services (ws-proxy + wss-injector)
services/trial-api/                 1 service  (server)
```

Total recovered source: **~530 KB of plain bash + Python**, all editable.
