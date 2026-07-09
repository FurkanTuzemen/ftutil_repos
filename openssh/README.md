# openssh

Installs and configures the OpenSSH **server + client** consistently across machines. Both scripts are idempotent (safe to re-run).

## Linux (`linux/bootstrap.sh`)

Host-level install via the OS package manager — the SSH daemon can't be containerized, so this runs on the host and is meant to be cloned and run identically on every Raspberry Pi / PC.

- Installs `openssh-server` + `openssh-client` (supports apt, dnf, yum, pacman, zypper).
- Enables and starts the SSH service (`ssh` on Debian/Raspberry Pi OS, `sshd` elsewhere).

```bash
git clone <repo-url> ~/ftutil_repos
cd ~/ftutil_repos/openssh/linux
sudo ./bootstrap.sh
```

Full run steps: [`linux/RUNNING.md`](linux/RUNNING.md).

## Windows (`windows/install.ps1`)

Native install via **winget** (`Microsoft.OpenSSH.Preview` — Microsoft's Win32-OpenSSH MSI, which installs to `C:\Program Files\OpenSSH` and ships both `ssh.exe` client and `sshd.exe` server). No Docker.

> This is a *preview* build — currently the only Microsoft OpenSSH package in winget. The stable Windows OpenSSH ships as an optional feature (`Add-WindowsCapability`) instead; this repo standardises on winget for Windows installs.

- Installs the package with winget.
- Registers the `sshd` and `ssh-agent` services, sets them to start Automatically, and starts them.
- Adds an inbound firewall rule for TCP 22 (override with `-Port`).

```powershell
git clone <repo-url> C:\ftutil_repos
cd C:\ftutil_repos\openssh\windows
.\install.ps1            # or:  .\install.ps1 -Port 2222
```

Run from an **elevated (Administrator)** session. Works on both Windows PowerShell 5.1 and PowerShell 7+ — with pwsh:

```powershell
pwsh -File .\install.ps1
```

Requires winget (`App Installer` from the Microsoft Store). Under PowerShell 7 the firewall step loads the `NetSecurity` module through the Windows compatibility layer and may print a one-time WinPSCompatSession warning — this is expected and harmless.

Full run steps (elevation, execution policy, PowerShell 7 one-liner): [`windows/RUNNING.md`](windows/RUNNING.md).

## Connection details

Both installers **print how to SSH into the machine at the end** — user, hostname, the reachable IPv4 addresses (auto-labeled LAN vs Tailscale), the listening port, and ready-to-copy `ssh` commands.

To reprint them any time (no admin/root needed):

```powershell
# Windows
.\connection-info.ps1
```

```bash
# Linux
./connection-info.sh
```

## Key-based authentication (passwordless login)

Helper scripts live next to the installers. All are idempotent. **For a full client/server walkthrough see [`KEY-AUTH-GUIDE.md`](KEY-AUTH-GUIDE.md).**

**On the client** (the machine you connect *from*) — generate a key pair and print the public key:

```powershell
.\new-ssh-key.ps1                 # Windows; -NoPassphrase to skip the passphrase prompt
```
```bash
./new-ssh-key.sh                  # Linux;  --no-passphrase to skip the prompt
```

**On the server** (the machine you connect *to*) — authorize that public key:

```powershell
.\authorize-ssh-key.ps1 "ssh-ed25519 AAAA... you@client"
```
```bash
./authorize-ssh-key.sh "ssh-ed25519 AAAA... you@client"
```

The **Windows** authorize script handles the OpenSSH admin quirk automatically: accounts in the **Administrators** group are authorized via the global `C:\ProgramData\ssh\administrators_authorized_keys` (not `~\.ssh\authorized_keys`), and it locks that file's ACL to **SYSTEM + Administrators** as `sshd` requires — otherwise the keys are silently ignored. Authorizing an admin account needs an **elevated** session. Use `-Scope User|Admin` to force the target, `-User <name>` for another account, or `-PublicKeyPath <file.pub>`.

On **Linux** the script appends to the target user's `~/.ssh/authorized_keys` with `700`/`600` perms (`--user <name>` + `sudo` to authorize for another account).

**Delete a key pair** (private + public + cert, and drop it from `ssh-agent`) with `remove-ssh-key.ps1` / `remove-ssh-key.sh`. Irreversible, so it lists the files and confirms first:

```powershell
.\remove-ssh-key.ps1            # -WhatIf to preview, -Confirm:$false to skip prompt, -All for every id_* pair
```
```bash
./remove-ssh-key.sh            # --yes to skip prompt, --all for every id_* pair
```

### Revoking access on the server

To manage which keys the **server** trusts (its `authorized_keys`, or the Windows admin file), use these — they resolve the right file, preserve its ACL/permissions, and confirm before deleting:

```powershell
.\list-authorized-keys.ps1                        # print authorized keys (index, type, fingerprint, comment)
.\remove-authorized-key.ps1 -Comment furka@laptop # revoke one (also -Index N / -Match <s> / -PublicKey "<line>")
.\remove-all-authorized-keys.ps1                  # revoke ALL keys (empties the file, keeps its ACL)
```
```bash
./list-authorized-keys.sh                         # print authorized keys
./remove-authorized-key.sh --comment furka@laptop # revoke one (also --index N / --match <s> / --key "<line>")
./remove-all-authorized-keys.sh                   # revoke ALL keys
```

(`list-authorized-keys` is read-only. `remove-authorized-key` with no selector also lists, as a convenience.)

No `sshd` restart is needed — it reads `authorized_keys` on each new connection, so a revoked key stops working immediately. (`remove-ssh-key` above deletes a *client's own* key pair; these remove *authorized* keys on a *server*.)

Once keys work you can harden the server by disabling password auth (`PasswordAuthentication no` in `sshd_config`) — do this only after confirming key login works, so you don't lock yourself out.

## Prerequisites

- Linux: root/sudo, a supported package manager.
- Windows: Administrator PowerShell, winget available.

## Verify

```bash
# on the machine running the server
ssh localhost
# from another machine
ssh <user>@<host-ip>
```
