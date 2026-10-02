# Troubleshooting

Start with `./doctor.sh` on the Pi (in `~/ftutil_repos/conan-server/linux`).
Alert emails from conan-monitor already include its full output. It checks the whole chain in
dependency order and prints the fix for every `[FAIL]`. The first failure is
usually the cause, and everything after it follows from it.

## Symptom → fix

| Symptom | Likely cause | Fix |
|---|---|---|
| Container `Exited (127)`, error `failed to fulfil mount request: open <data dir>: no such file or directory` | The data directory doesn't exist: a dedicated disk isn't mounted, or the directory was removed (by design; see `create_host_path: false`) | Fix the mount (rows below) or re-run `sudo ./bootstrap.sh`, then `sudo systemctl restart conan-server` |
| *(dedicated NTFS disk)* `systemctl --failed` shows a `mnt-*.mount`; `dmesg` shows `ntfs3(sda2): volume is dirty and "force" flag is not set!` | The NTFS volume was not unmounted cleanly (power loss, unplugged while mounted, or Windows hibernation / Fast Startup) | [Dirty NTFS volume](#dirty-ntfs-volume) |
| *(dedicated disk)* `doctor.sh`: disk UUID not connected | USB disk unplugged, or not powered | Reconnect it, check `lsblk`, then `sudo mount <mount point> && sudo systemctl restart conan-server` |
| *(dedicated disk)* Mount is read-only | The filesystem found errors and fell back to read-only | `chkdsk /f` on Windows, or `ntfsfix -d` as below |
| `conan remote login` → connection refused / timeout | The server is down, or the client isn't on the tailnet | `doctor.sh` on the Pi; `tailscale status` on the client |
| Login works, but `conan upload`/`install` hangs or fails on file transfer | `CONAN_PUBLIC_HOSTNAME` isn't reachable from the client (e.g. it's the LAN IP while the client is a CI runner on the tailnet) | Set it to the Tailscale IP or MagicDNS name in `.env`, then `docker compose up -d` |
| 401 on everything | Not logged in (`CONAN_READ_USERS=?` needs auth), or the JWT expired (120 min) | `conan remote login ftpi ci` |
| 403 on upload | The user isn't in `CONAN_WRITE_USERS` | Add the user in `.env`, then `docker compose up -d` |
| CI: `tailscale/github-action` fails | Expired or invalid OAuth client, or `tag:ci` missing from tagOwners | Recreate the OAuth client and update the `TS_OAUTH_*` secrets |
| CI: worked for months, now times out | The Pi's Tailscale key expired | Disable key expiry for the Pi in the admin console, then `sudo tailscale up` |
| `docker compose` errors `run bootstrap.sh - it copies versions.env into .env` | `.env` is missing the version keys | `sudo ./bootstrap.sh` |
| Build: `WARNING: no lock file for conan-server X` | The version was bumped without locking deps | `./lock-deps.sh`, then commit |
| Server came back after a reboot but the unit shows `failed` | The disk mounted late; the unit depends on the mount | `sudo systemctl restart conan-server`; check `journalctl -u conan-server -b` |

## Alerts (conan-monitor)

| Symptom | Fix |
|---|---|
| Email `[conan-server] FAIL: ftbeepi` | Read the `[FAIL]` lines in the email; they're from `doctor.sh` and include the fix. |
| Email `[conan-server] UNREACHABLE: ftbeepi` | ftbitpi can't ssh to ftbeepi: the Pi is off or hung, it's off the network, or ftbeepi.local doesn't resolve. If HTTP in the email is OK, the server works and only the monitor path is broken. |
| No emails at all, but you suspect a problem | On ftbitpi: `journalctl -u conan-monitor -n 20`, `systemctl list-timers conan-monitor.timer` |
| Monitor log: `ssh to the server timed out` | `sshHost` points to a Tailscale address with Tailscale SSH on. Use the LAN name (see `monitor/RUNNING.md`). |
| Monitor log: `550 This API key is not authorized to send emails from …` | `mail.from` must be on a domain the Resend key may send from (currently gorucusu.com). |

## Dirty NTFS volume

This only applies to packages on an NTFS disk, which was the setup until
2026-10-02. On ext4 (the SD card now, or a dedicated ext4 disk) it can't
happen. It's kept here for the history, and for whenever an NTFS disk is
mounted on a Pi.

Linux's `ntfs3` driver refuses to mount a volume whose dirty flag is set.
Because the fstab entry has `nofail`, the Pi still boots, but without the
disk, and the server can't start.

**Quick fix on the Pi** (what was done on 2026-10-02):

```bash
sudo ntfsfix -d /dev/disk/by-uuid/DE5ECE7A5ECE4B4B   # repairs basic inconsistencies, clears the dirty flag
sudo mount /mnt/expansion
sudo systemctl restart conan-server
./doctor.sh
```

`ntfsfix` is in the `ntfs-3g` package. It only fixes basic problems, such as
the `$MFTMirr` mismatch and the journal. It also marks the volume so that
Windows checks it at the next mount.

**Proper fix:** plug the disk into a Windows machine and run `chkdsk X: /f`.
If chkdsk answers `Access is denied` even from an elevated shell (this
happens in restricted or automated shells), use the Storage-service
equivalent: `Repair-Volume -DriveLetter X -Scan`. If that finds errors, run
`Repair-Volume -DriveLetter X -OfflineScanAndFix`.
Do this whenever convenient after a quick fix, especially because this disk
also holds personal data.

**To avoid it:**

- Shut the Pi down cleanly (`sudo poweroff`) before cutting power or
  unplugging the disk.
- When the disk is used on Windows, use *Safely Remove*. Turn off Fast Startup
  and hibernation on that PC, because both leave NTFS volumes in a "still in
  use" state.
- The systemd unit stops the container before the disk is unmounted, so a
  clean shutdown can't leave files open.
- To remove this failure mode entirely, keep packages on ext4. That is
  what the setup has done since 2026-10-02.

To check read-only without changing anything (safe on a dirty volume):

```bash
d=$(mktemp -d); sudo mount -t ntfs3 -o ro /dev/sda2 "$d" && ls "$d"/conan-server-data; sudo umount "$d"; rmdir "$d"
```

## Incident 2026-10-02: server down ~8 weeks (dirty NTFS volume)

**Impact:** The Conan remote was unavailable from 2026-08-03 ~23:40 UTC until
2026-10-02 17:46 UTC (20:46 TRT). No data was lost. CI jobs that used the cache would
have fallen back to building from source, or failed at `conan remote login`.

**Timeline** (UTC)

- 2026-08-03 17:25: Server deployed from `ftutil_repos/conan-server` and
  smoke-tested with `zlib/1.3@ft/rc1`.
- 2026-08-03 ~23:40: Last healthy ping. The Pi was then restarted or lost
  power without a clean unmount of the USB NTFS disk.
- On the next boot, `ntfs3` reported `volume is dirty and "force" flag is not
  set!` and `mnt-expansion.mount` failed. Thanks to `nofail` the Pi booted
  normally, so nothing visible happened.
- Docker's `unless-stopped` policy tried to start the container, and it failed
  with `failed to fulfil mount request: open /mnt/expansion/conan-server-data:
  no such file or directory` (exit 127). Docker doesn't retry this kind of
  failure. The container stayed `Exited`.
- 2026-10-02 ~17:20: Found during a manual check.
  - Read-only mount: data intact.
  - `ntfsfix -d` fixed the `$MFTMirr` mismatch and cleared the dirty flag.
  - Mount, `docker start`: healthy.
  - Verified from Windows over Tailscale: ping 200, `ci` login, search
    returns `zlib/1.3@ft/rc1`.

**Root cause:** An unclean shutdown left the NTFS volume dirty, and Linux
won't auto-mount a dirty NTFS volume.

**Why it went unnoticed for 8 weeks:** Nothing was watching. The failure was
quiet at every layer: the mount had `nofail`, the container start failure
was logged once, and no CI job ran against the cache in that period.

**What changed afterwards** (`ftutil_repos/conan-server`):

- `linux/systemd/conan-server.service`: starts the server only after the disk
  mounts, and stops it before unmount on shutdown.
- `linux/doctor.sh`: detects this exact chain (unmounted disk, dirty flag)
  and prints the fix.
- `bootstrap.sh` recognises a dirty volume when mounting fails and prints the
  `ntfsfix` command.
- Packages moved off the NTFS disk onto ext4: first the SD card, then a
  dedicated Samsung 1 TB ext4 disk at `/mnt/conan`. That removes this
  failure mode.
  The Seagate went back to Windows duty. A full online check there
  (`Repair-Volume -DriveLetter I -Scan`, the same scan chkdsk does) reported
  `NoErrorsFound`, and `fsutil dirty query` showed it not dirty, so no
  offline repair was needed. It's no longer mounted on the Pi (fstab entry
  removed).
- Alerting: `conan-server/monitor/` (conan-monitor) runs on ftbitpi every
  5 minutes. It runs `doctor.sh` over a restricted ssh key, pings the port,
  and emails furkantuzemen@gmail.com on failure, with a reminder every 24 h
  and a recovery email. Tested end to end on 2026-10-02: server stopped →
  ALERT after 2 runs → started → RECOVERED.
