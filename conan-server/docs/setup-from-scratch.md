# Setup from scratch

From a blank SD card to a working, health-checked Conan remote. Expect about
30 minutes, most of it flashing and `apt`. Every step can be re-run safely.

Known-good versions (2026-10-02):

| Component | Version |
|---|---|
| Hardware | Raspberry Pi 5 Model B, 8 GB, 64 GB SD card |
| OS | Raspberry Pi OS (64-bit) Lite, 2026-06-18 image, Debian 13 *trixie*, kernel 6.18 |
| Docker Engine / Compose | 29.6.0 / v5.2.0 |
| Tailscale | 1.102.2 |
| conan-server / Python | 2.7.1 / 3.11 (`conan-server/versions.env`) |

## 1. Flash the OS

Raspberry Pi Imager → *Raspberry Pi OS Lite (64-bit)*. In the Imager's
customisation settings:

- hostname `ftbeepi`
- user `furkan`
- enable SSH with public-key auth (paste your `~/.ssh/id_ed25519.pub`)
- Wi-Fi if not using Ethernet

Boot it, then check you can connect: `ssh furkan@ftbeepi.local`.

```bash
sudo apt update && sudo apt full-upgrade -y
sudo apt install -y git curl
```

## 2. Tailscale

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up            # open the printed URL and approve the device
tailscale ip -4              # note it - it becomes CONAN_PUBLIC_HOSTNAME
```

In the Tailscale admin console:

- **Disable key expiry** for this device, or it drops off the tailnet after
  180 days.
- The IP stays stable for as long as the node exists. If you re-register
  the Pi, the IP changes and you must update `CONAN_PUBLIC_HOSTNAME` and the
  consumers' `CONAN_REMOTE_URL`. Using the MagicDNS name avoids that.
- For GitHub Actions, create an OAuth client allowed to create `tag:ci`
  nodes, and an ACL that lets `tag:ci` reach this host on port 9300 (see
  [clients.md](clients.md#github-actions)).

## 3. GitHub access from the Pi

`bootstrap.sh` reads the version pin from the private
`FurkanTuzemen/ConanAutomation` repo over SSH, and the repo itself is
cloned over SSH too:

```bash
ssh-keygen -t ed25519 -C "furkan@ftbeepi"     # if ~/.ssh/id_ed25519 doesn't exist yet
cat ~/.ssh/id_ed25519.pub                       # add at github.com/settings/keys
ssh -T git@github.com                           # "Hi FurkanTuzemen! ..."
```

Without GitHub access, bootstrap still works: it logs a warning and uses
`conan-server/versions.env` as committed. Clone over HTTPS in that case.

## 4. Clone and install Docker

```bash
git clone git@github.com:FurkanTuzemen/ftutil_repos.git ~/ftutil_repos
sudo ~/ftutil_repos/docker/linux/bootstrap.sh
cd ~/ftutil_repos/conan-server/linux
newgrp docker            # or log out/in, so `docker` works without sudo
```

## 5. Package storage

The default needs no setup: packages go in `/srv/conan-server-data` on the
SD card (ext4). Bootstrap creates the directory.

**Optional: a dedicated disk** for a large cache. Use ext4, not NTFS (see
[troubleshooting](troubleshooting.md#dirty-ntfs-volume)). Formatting
**erases** the partition:

```bash
sudo mkfs.ext4 -L conan /dev/sdX1 && sudo blkid /dev/sdX1    # note the UUID
sudo CONAN_DISK_UUID=<uuid> ./bootstrap.sh                   # fstab (nofail) + mount at /mnt/conan
```

If the disk already holds data, bootstrap leaves it untouched and only
creates `conan-server-data/` next to it.

## 6. Bootstrap

```bash
sudo ./bootstrap.sh
```

What it does:

1. Reads the Conan pin from ConanAutomation. If it differs from
   `conan-server/versions.env`, it rewrites that file; commit the change.
2. Creates the package directory. With a dedicated disk, it first adds the
   disk to `/etc/fstab` by UUID with `nofail` (backup:
   `/etc/fstab.bak.conan-server`) and mounts it.
3. On the first run, generates `.env` with a random `ci` password and fresh
   JWT and updown secrets, sets `CONAN_PUBLIC_HOSTNAME` to the Tailscale IP,
   and chmods it to 600.
4. Installs and enables `/etc/systemd/system/conan-server.service`.
5. Runs `docker compose up -d --build` and waits for `/v1/ping`.
6. Prints the connection info.

To restore an existing server instead of starting fresh, copy the backed-up
`.env` into `conan-server/linux/` and unpack the package archive **before**
this step. See [operations.md](operations.md#restore).

## 7. Verify

```bash
./doctor.sh                                                 # on the Pi: every check [ OK ]
CONAN_PASSWORD=... ./smoke-test.sh http://<tailscale-ip>:9300 ci   # from another machine
```

Then do a real round trip from a client ([clients.md](clients.md)), or
re-run the `conan-server-test` workflow in
[`conan_server_test`](https://github.com/FurkanTuzemen/conan_server_test).
It builds zlib, uploads it, wipes the cache, and downloads it back.

Finally, run `sudo reboot` and check `./doctor.sh` again. The server
must come back on its own.
