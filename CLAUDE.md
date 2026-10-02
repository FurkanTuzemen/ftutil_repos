# CLAUDE.md

Guidance for working in this repo. See `README.md` for the full intent.

## What this repo is

Reproducible bootstrap/automation scripts to set up tools (OpenSSH, Docker, Git, …) **identically across many machines**: Windows/Linux PCs and a fleet of Raspberry Pis.

## Platform strategy (decisions)

- **Linux** — either **Docker** (for tools that can run containerized) **or** a host-level **`bootstrap.sh`** (for things Docker can't install into itself: the SSH daemon, the Docker engine, Git, system packages). Reproducibility on the Pi fleet comes from `git clone` + running the script identically on each device.
- **Windows** — native **PowerShell only, no Docker**. Prefer **winget** for installs.

## Conventions when adding or editing a project

- **Layout:** one folder per tool → `<project>/{linux,windows}/`. Shared helpers in `lib/`. Scaffold new projects from `_template/`.
- **Idempotent:** every script checks-before-acting and is safe to re-run.
- **Bash:** start with `set -euo pipefail`; source `lib/linux/common.sh` for `log` / `require_root` / `command_exists` / `detect_distro`. Keep the executable bit with `git update-index --chmod=+x <script>.sh` (the repo is authored on Windows, which doesn't track it).
- **PowerShell:** start with `#Requires -Version 5.1` + `#Requires -RunAsAdministrator`; set `$ErrorActionPreference = 'Stop'`; import `lib/windows/Common.psm1` for `Write-Log` / `Test-CommandExists` / `Assert-IsAdmin`. **Must run on both Windows PowerShell 5.1 and PowerShell 7+ (`pwsh`).**
- **Run manual:** every project ships a `RUNNING.md` **next to its scripts** (in `linux/` and `windows/`) with exact run steps — the Windows one includes PowerShell 7 instructions.
- **Post-install access info:** if a project sets up something you connect to/use, the installer **prints the access details at the end** and the project ships a standalone `connection-info.ps1` / `connection-info.sh` (no admin/root required) to reprint them on demand. `openssh/` is the reference: it prints user/hostname/reachable IPs (LAN vs Tailscale)/port and ready-to-copy `ssh` commands.

## openssh notes (non-obvious details)

- **Windows key auth:** accounts in the Administrators group are authorized via the GLOBAL `C:\ProgramData\ssh\administrators_authorized_keys` (per sshd_config's `Match Group administrators`), NOT `~\.ssh\authorized_keys`. That file must be owned by Administrators/SYSTEM and writable only by them or `sshd` silently ignores it. `authorize-ssh-key.ps1` handles this; it uses **`icacls`** (not `Set-Acl`) for the ACL because `Set-Acl` on an already-protected file tries to write the SACL and fails with `SeSecurityPrivilege`.
- **Empty passphrase:** `-N ''` in `new-ssh-key.ps1` is reliable under PowerShell 7; on Windows PowerShell 5.1 the empty arg can be dropped (ssh-keygen then prompts). Default is to prompt, which works everywhere.
- **No secrets** committed; scripts must be safe to run unattended.
- `.gitattributes` forces **LF** on `*.sh` and **CRLF** on `*.ps1`.

## net-failover notes (non-obvious details)

- **Not containerized, by design.** It drives the host's NetworkManager and real
  radios, so it is a host-level `bootstrap.sh`. Docker is used only to pin a
  reproducible environment for its **test suite** (`net-failover/test/`), which
  runs the real daemon against mock `nmcli`/`curl`/`ping`/`ip` on `PATH`.
- **`nmcli con modify` silently rejects `key-mgmt` and `psk` passed in a single
  call**, leaving a profile that looks correct but has no stored secret and
  fails at the 4-way handshake. Set each property in its own invocation.
- **A stored WPA key is hashed together with the SSID**, so a key saved under a
  misspelled SSID can never authenticate against the correct one — the
  plain-text passphrase is required. Symptom in `journalctl -u NetworkManager`:
  `4way_handshake -> disconnected`, then "asking for new key".
- **An IPv6 default route does not imply an IPv6 address.** If an RA
  advertises a default route but no global prefix, curl still prefers the
  AAAA answer and every HTTP probe stalls for the whole `PROBE_TIMEOUT`,
  so only the ICMP fallback answers and captive-portal detection silently
  stops working. `probe_iface` pins curl to `-4` unless the interface has
  a global IPv6 address. The Windows twin is unaffected - it binds probes
  to the adapter's IPv4 (`curl.exe --interface <ip>`), already v4-only.
- **Link state is not internet.** Reachability must be probed per interface with
  `SO_BINDTODEVICE` (`curl --interface`, `ping -I`), because carrier + a DHCP
  lease + a default route says nothing about whether the uplink works.
- **Demote, don't down.** A dead ethernet link keeps its IP (so LAN/SSH stays
  reachable) and only loses the default route, via `nmcli device modify` — a
  runtime-only change that does not rewrite the saved profile.
- **Secrets:** `/etc/net-failover/networks.conf` holds plain-text passphrases,
  is mode `0600`, is `.gitignore`d, and `bootstrap.sh` never overwrites it. Only
  `networks.conf.example` is committed.
- **Windows twin** (`net-failover/windows/`): same policy and `networks.conf`
  format. Interface metrics (`Set-NetIPInterface`, 10 good / 5000 dead / 50
  WiFi) instead of route metrics; `netsh wlan` XML profiles (`nf-` prefix,
  `connectionMode=manual`) instead of nmcli; a SYSTEM scheduled task at boot
  instead of a systemd unit. `-Status`/`-Check` need no admin.
- **Never parse localized `netsh` labels.** Only the literal `SSID` tokens are
  locale-stable; connection state comes from `Get-NetAdapter`
  (`MediaConnectionState`) + `Get-NetIPAddress`, and SSID→profile-name mapping
  reads wlansvc's XML store (`%ProgramData%\Microsoft\Wlansvc\Profiles`).
- **`ping.exe` exits 0 on "Destination host unreachable"** (a reply arrived,
  just not from the target) — success requires `TTL=` in the output.
- **Interface-bound probes on Windows** bind to the adapter's IPv4
  (`curl.exe --interface <ip>`, `ping -S <ip>`); the default strong-host model
  then forces egress out that NIC. `curl.exe --interface` only takes an IP on
  Windows, not an interface name.
- **`icacls` with SID form** (`*S-1-5-32-544`), never group names — names like
  `Administrators` don't exist on non-English Windows.
- **Win11 gates WiFi scans** behind Location services (verified: even elevated
  shells get "Access is denied" with Location off) and has no forced rescan,
  so an empty scan makes the daemon try the configured list blind instead of
  concluding nothing is in range.

## conan-server notes (non-obvious details)

- **Version pin = ConanAutomation.** `conan-server/versions.env` must equal
  `conan_version`/`python_version` in ConanAutomation's `ftdeps/model.py`;
  `bootstrap.sh` re-reads that pin each run and rewrites `versions.env` on
  drift (commit it). Transitive pip deps are locked per version in
  `linux/server/constraints/` - an unlocked resolve already drifted
  (PyJWT/idna/charset-normalizer) two months after the first deploy.
- **Packages live on the root filesystem by default** (`CONAN_DISK_UUID=none`,
  `/srv/conan-server-data`, ext4 SD card). Until 2026-10-02 they were on an
  NTFS USB disk shared with personal data; `ntfs3` refuses to mount a *dirty*
  volume (`volume is dirty and "force" flag is not set!`), and with `nofail`
  the Pi boots fine without it, so nothing looked wrong for ~8 weeks. A
  dedicated disk is still supported (`CONAN_DISK_UUID=<uuid>`) - use ext4.
- **`create_host_path: false`** on the data bind mount is deliberate: a missing
  disk must fail the container, not silently create an empty dir on the SD card.
  Docker does not retry that start failure - hence the systemd unit with
  `RequiresMountsFor=` (also stops the container before unmount on shutdown).
- **`CONAN_PUBLIC_HOSTNAME`** is baked into the signed upload/download URLs, so
  it must be the Tailscale address CI runners reach, not localhost/LAN.
- **`CONAN_READ_USERS=?`** = authenticated users only; an *empty* store still
  answers anonymous searches with 200 `[]` (nothing to permission-check).
- **conan-monitor runs on ftbitpi** (`conan-server/monitor/`): ssh to the
  server with a `restrict,command="…/doctor.sh"` key + HTTP ping, email via
  Resend. Two traps: ftbeepi has **Tailscale SSH** on, so ssh to its tailnet
  address hangs on an interactive browser check (use `ftbeepi.local`); and the
  Resend key is domain-restricted to **gorucusu.com** (`550 … not authorized
  to send emails from …` for any other `from`).
- **Testing without touching production:** run a second instance on the Pi
  with `sudo CONAN_INSTALL_SYSTEMD=0 CONAN_CONTAINER_NAME=conan-server-test
  COMPOSE_PROJECT_NAME=conan-server-test CONAN_PUBLIC_PORT=9301 CONAN_DATA_DIR=/var/tmp/conan-test-data ./bootstrap.sh`
  from a *separate copy* of the directory (it gets its own `.env`), then
  `docker compose down` there. Both name overrides are required: with the
  default project name, `--remove-orphans`/`down` would hit the real server.
  The test build shares the image tag `ftutil/conan-server:<ver>` with
  production - don't `docker rmi` it afterwards (that untags the image the
  real container runs on).

## Verifying changes

- Bash syntax: `bash -n <script>.sh`; lint with shellcheck (on the Pi:
  `docker run --rm -v "$PWD:/mnt" -w /mnt koalaman/shellcheck:stable -x <scripts>`).
- PowerShell syntax: parse-check with
  `[System.Management.Automation.Language.Parser]::ParseFile($path,[ref]$null,[ref]$errs)`.
  This machine has `pwsh` 7.x — prefer running checks under it to confirm PS7 compatibility.

## Commit / PR

- Clear, imperative commit subjects. End commit messages with the `Co-Authored-By` trailer.
- Commit and push only when the user asks.
