# SSH key authentication — step-by-step guide

How to set up **passwordless SSH login** using the helper scripts in this project, explained for both the **client** and the **server**, on **Windows** and **Linux**.

## The mental model (read this first)

SSH key auth uses a **key pair**:

- The **private key** stays on the **client** — the machine you sit at and connect *from*. Never copy or share it.
- The **public key** goes on the **server** — the machine you connect *to*. It's safe to paste anywhere.

> "Client" and "server" are **roles, not machines.** A PC can be both: your desktop connects *to* a Pi (desktop = client, Pi = server), and you might also SSH *into* the desktop (desktop = server). You do the client steps on whichever machine initiates the connection, and the server steps on whichever one accepts it.

The flow is always the same three steps:

1. **Client:** generate a key pair → get a public key.
2. **Server:** authorize that public key.
3. **Client:** connect — no password.

Prerequisite: OpenSSH is installed on both sides (`install.ps1` on Windows, `bootstrap.sh` on Linux). The server also needs its `sshd` service running — the installer does that and prints the connection details.

---

## Step 1 — Client: generate a key pair

Do this **once per client machine**. If you already have a key (`~/.ssh/id_ed25519`), skip to Step 2 and reuse it.

### Windows client

```powershell
cd C:\ftutil_repos\openssh\windows
.\new-ssh-key.ps1
```

- You'll be prompted for a passphrase (recommended — it encrypts the private key on disk). To skip it: `.\new-ssh-key.ps1 -NoPassphrase`.
- Creates `%USERPROFILE%\.ssh\id_ed25519` (private) and `id_ed25519.pub` (public).
- Does **not** need Administrator.

### Linux client

```bash
cd ~/ftutil_repos/openssh/linux
./new-ssh-key.sh
```

- Same idea; `--no-passphrase` to skip the prompt.
- Creates `~/.ssh/id_ed25519` and `id_ed25519.pub`.
- Run as your normal user (**not** `sudo`), so the key lands in your own home.

**Both scripts print the public key at the end** — a single line like:

```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... you@your-client
```

Copy that whole line. That's what you take to the server in Step 2.

They also print **this machine's own `user@address`** for each LAN and Tailscale IP — handy if this machine is *also* something you SSH into.

**Safe to re-run.** The script never clobbers an existing key:

- If a **private key already exists**, it is reused (not regenerated). Use `-Force` / `--force` to deliberately replace it.
- If the **private key exists but the `.pub` is missing**, the public key is re-derived from the private key and saved — so you always get your public key back.
- Reprint without any regeneration: `Get-Content $env:USERPROFILE\.ssh\id_ed25519.pub` (Windows) or `cat ~/.ssh/id_ed25519.pub` (Linux).

---

## Step 2 — Server: authorize the public key

Do this on the machine you want to **log in to**, once per client key you want to allow. Paste the public key line from Step 1.

### Linux server

```bash
cd ~/ftutil_repos/openssh/linux
./authorize-ssh-key.sh "ssh-ed25519 AAAAC3Nza... you@your-client"
```

- Appends the key to your `~/.ssh/authorized_keys` and sets `700`/`600` permissions.
- To authorize it for a **different** account: `sudo ./authorize-ssh-key.sh --user someone "ssh-... ..."`.

### Windows server

```powershell
cd C:\ftutil_repos\openssh\windows
.\authorize-ssh-key.ps1 "ssh-ed25519 AAAAC3Nza... you@your-client"
```

This is where Windows has a **non-obvious rule**, which the script handles for you:

- If the target account is a **standard user**, the key goes in `%USERPROFILE%\.ssh\authorized_keys` — no elevation needed.
- If the target account is an **Administrator** (most personal PCs), Windows OpenSSH ignores the per-user file and instead reads **one global file**: `C:\ProgramData\ssh\administrators_authorized_keys`. That file must be owned by and writable only by **Administrators/SYSTEM**, or `sshd` **silently refuses the key**. The script writes there and locks the ACL correctly — but writing it **requires an elevated (Run as administrator) PowerShell session**.

So on a typical admin PC: open PowerShell **as Administrator**, then run the command above. The script auto-detects admin membership; you can force it with `-Scope Admin` or `-Scope User`.

Useful options (both platforms):

| Goal | Windows | Linux |
|---|---|---|
| Read key from a file | `-PublicKeyPath C:\keys\laptop.pub` | `--file ~/laptop.pub` |
| Authorize another user | `-User bob` | `sudo ... --user bob` |
| Force per-user file | `-Scope User` | (default) |
| Force admin/global file | `-Scope Admin` | n/a |

Both scripts are **idempotent** — running them again with the same key does nothing (no duplicate lines).

---

## Step 3 — Client: connect

From the **client**, connect to the server's user + address. Get the exact address from the server's `connection-info` script (it lists LAN and Tailscale IPs):

```bash
ssh you@192.168.1.11        # LAN
ssh you@100.91.29.96        # Tailscale (works from anywhere on your tailnet)
```

- **First connection** asks you to trust the host key — type `yes`.
- If key auth worked, you land in a shell **without a password prompt**. (If it still asks for a password, key auth didn't take — see Troubleshooting.)
- If your private key has a passphrase, you'll be asked for **that** (unlocks the local key) — this is not the server password.

That's it. Repeat Step 2 on each server for each client key you want to allow.

---

## End-to-end example

Goal: log in from a **Windows laptop** (client) into a **Raspberry Pi** (server).

```powershell
# On the laptop (client), normal PowerShell:
cd C:\ftutil_repos\openssh\windows
.\new-ssh-key.ps1 -NoPassphrase
# copy the printed "ssh-ed25519 AAAA... furka@laptop" line
```

```bash
# On the Pi (server):
cd ~/ftutil_repos/openssh/linux
./authorize-ssh-key.sh "ssh-ed25519 AAAA... furka@laptop"
```

```powershell
# Back on the laptop:
ssh pi@192.168.1.50
# logs in, no password
```

Reverse direction (log in **to** the Windows laptop from the Pi)? Then the laptop is the *server*: generate a key on the Pi with `new-ssh-key.sh`, and authorize it on the laptop with `authorize-ssh-key.ps1` **as Administrator** (since your account is an admin).

---

## Optional: harden the server (after keys work)

Only once you've **confirmed key login works**, you can disable password logins so the server accepts keys only. Edit the server's `sshd_config`:

- Linux: `/etc/ssh/sshd_config`
- Windows: `C:\ProgramData\ssh\sshd_config`

Set:

```
PasswordAuthentication no
```

Then restart the service — Linux: `sudo systemctl restart ssh` (or `sshd`); Windows: `Restart-Service sshd`.

> Do this **last**, and keep an existing session open while you test a fresh one, so a mistake doesn't lock you out.

---

## Troubleshooting

| Symptom | Likely cause / fix |
|---|---|
| Still prompted for a password | Key not authorized on the server, or (Windows admin) it went to the per-user file instead of the global one — re-run `authorize-ssh-key.ps1` **elevated**. |
| `Permission denied (publickey)` | The client's private key doesn't match any authorized public key. Confirm you copied the right `.pub` line, and that the client uses that key (`ssh -i <path>`). |
| Windows admin key ignored | The global file's ACL is wrong. `authorize-ssh-key.ps1` fixes it; make sure you ran it elevated. |
| Wrong / changed host key warning | The server's identity changed (e.g. reinstalled). Remove the stale entry from the client's `~/.ssh/known_hosts`. |
| Which address / port? | Run `connection-info.ps1` / `connection-info.sh` on the **server**. |

See also: [`README.md`](README.md) (overview), `windows/RUNNING.md` and `linux/RUNNING.md` (exact run steps).
