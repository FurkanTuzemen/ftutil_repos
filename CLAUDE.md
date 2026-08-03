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
- **Link state is not internet.** Reachability must be probed per interface with
  `SO_BINDTODEVICE` (`curl --interface`, `ping -I`), because carrier + a DHCP
  lease + a default route says nothing about whether the uplink works.
- **Demote, don't down.** A dead ethernet link keeps its IP (so LAN/SSH stays
  reachable) and only loses the default route, via `nmcli device modify` — a
  runtime-only change that does not rewrite the saved profile.
- **Secrets:** `/etc/net-failover/networks.conf` holds plain-text passphrases,
  is mode `0600`, is `.gitignore`d, and `bootstrap.sh` never overwrites it. Only
  `networks.conf.example` is committed.

## Verifying changes

- Bash syntax: `bash -n <script>.sh`.
- PowerShell syntax: parse-check with
  `[System.Management.Automation.Language.Parser]::ParseFile($path,[ref]$null,[ref]$errs)`.
  This machine has `pwsh` 7.x — prefer running checks under it to confirm PS7 compatibility.

## Commit / PR

- Clear, imperative commit subjects. End commit messages with the `Co-Authored-By` trailer.
- Commit and push only when the user asks.
