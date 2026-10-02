#!/usr/bin/env python3
"""Watch the Conan server from ANOTHER host and email when it breaks.

Runs from a systemd timer (every 5 min) on the monitor host. Each run:

  1. ssh to `sshHost` with a key that is locked to one forced command,
     linux/doctor.sh (see linux/authorize-monitor.sh). Exit 0 = healthy,
     1 = a check failed, 255/timeout = server unreachable. Use the LAN name
     here if the server has Tailscale SSH enabled: Tailscale intercepts ssh
     on its tailnet address and demands an interactive browser check.
  2. GET http://<target>:<port>/v1/ping from here - what clients see.

Alerting (state in /var/lib/conan-monitor/state.json):
  * ALERT after `failuresBeforeAlert` consecutive bad runs (debounces reboots
    and blips),
  * REMINDER every `reminderHours` while it stays bad,
  * RECOVERED once it is healthy again (only if an alert went out).
If sending fails the state is not advanced, so the next run retries.

Usage:
  conan-monitor.py              one check + alerting (what the timer runs)
  conan-monitor.py --dry-run    one check, print the result, no mail, no state
  conan-monitor.py --test-email send a test message and exit

Config: /etc/conan-monitor/config.json (see config.json.example). Never logs
the SMTP password.
"""
import argparse
import json
import os
import smtplib
import socket
import ssl
import subprocess
import sys
import urllib.request
from datetime import datetime, timezone
from email.message import EmailMessage
from email.utils import make_msgid
from pathlib import Path

CONFIG = Path(os.environ.get("CONAN_MONITOR_CONFIG", "/etc/conan-monitor/config.json"))
STATE = Path(os.environ.get("CONAN_MONITOR_STATE", "/var/lib/conan-monitor/state.json"))
RUNBOOK = "https://github.com/FurkanTuzemen/ftutil_repos/blob/main/conan-server/docs/troubleshooting.md"


def now():
    return datetime.now(timezone.utc)


def log(msg):
    print(msg, flush=True)


def load_config():
    cfg = json.loads(CONFIG.read_text())
    cfg.setdefault("sshUser", "furkan")
    cfg.setdefault("sshHost", cfg["target"])
    cfg.setdefault("sshKey", "/var/lib/conan-monitor/.ssh/id_ed25519")
    cfg.setdefault("port", 9300)
    cfg.setdefault("failuresBeforeAlert", 2)
    cfg.setdefault("reminderHours", 24)
    if "CHANGE_ME" in json.dumps(cfg):
        sys.exit(f"{CONFIG} still contains CHANGE_ME placeholders - fill it in first")
    return cfg


def check(cfg):
    """Return (status, details) with status in OK / FAIL / UNREACHABLE."""
    key = cfg["sshKey"]
    known_hosts = str(Path(key).parent / "known_hosts")
    cmd = ["ssh", "-i", key, "-o", "BatchMode=yes", "-o", "ConnectTimeout=15",
           "-o", "StrictHostKeyChecking=accept-new", "-o", f"UserKnownHostsFile={known_hosts}",
           f"{cfg['sshUser']}@{cfg['sshHost']}"]
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
        rc, doctor = p.returncode, (p.stdout + p.stderr).strip()
    except subprocess.TimeoutExpired:
        rc, doctor = 255, "ssh to the server timed out after 120 s"

    url = f"http://{cfg['target']}:{cfg['port']}/v1/ping"
    try:
        with urllib.request.urlopen(url, timeout=10) as r:
            http_ok, http = r.status == 200, f"{url} -> HTTP {r.status}"
    except Exception as e:  # noqa: BLE001 - any failure is "not reachable"
        http_ok, http = False, f"{url} -> {e}"

    if rc == 255:
        status = "UNREACHABLE"
    elif rc == 0 and http_ok:
        status = "OK"
    else:
        status = "FAIL"
        if rc == 0:
            doctor += "\n\n(doctor.sh passes ON the server, but the port is not reachable from the monitor host.)"
    return status, {"doctorExit": rc, "doctor": doctor, "http": http}


def send(cfg, subject, body):
    m = cfg["mail"]
    msg = EmailMessage()
    msg["From"] = m["from"]
    msg["To"] = m["to"]
    msg["Subject"] = subject
    msg["Message-ID"] = make_msgid(domain=m["from"].rsplit("@", 1)[-1].strip(">"))
    msg.set_content(body)
    with smtplib.SMTP_SSL(m["host"], int(m["port"]), context=ssl.create_default_context(), timeout=30) as s:
        s.login(m["user"], m["password"])
        s.send_message(msg)
    log(f"mail sent: {subject}")


def compose(cfg, kind, status, details, state):
    host = cfg["target"].split(".")[0]
    titles = {
        "ALERT": f"[conan-server] {status}: {host}",
        "REMINDER": f"[conan-server] still {status}: {host}",
        "RECOVERED": f"[conan-server] RECOVERED: {host}",
    }
    since = state.get("badSince") or "?"
    lines = [
        f"Conan server on {cfg['target']}: {kind}",
        "",
        f"Status:   {status}",
        f"Bad since: {since} (UTC)" if kind != "RECOVERED" else f"Was down since: {since} (UTC)",
        f"Checked:  {now().strftime('%Y-%m-%d %H:%M:%S')} UTC from {socket.gethostname()}",
        f"HTTP:     {details['http']}",
        "",
        "---- doctor.sh on the server ----",
        details["doctor"] or "(no output)",
        "",
        f"Runbook: {RUNBOOK}",
        "On the server: cd ~/ftutil_repos/conan-server/linux && ./doctor.sh",
    ]
    return titles[kind], "\n".join(lines) + "\n"


def load_state():
    try:
        return json.loads(STATE.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        return {"badStreak": 0, "alerted": False}


def save_state(state):
    tmp = STATE.with_suffix(".tmp")
    tmp.write_text(json.dumps(state, indent=2))
    tmp.replace(STATE)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--test-email", action="store_true")
    args = ap.parse_args()
    cfg = load_config()

    if args.test_email:
        send(cfg, f"[conan-server] test alert from {socket.gethostname()}",
             "Test message from conan-monitor. If you can read this, alert email works.\n\n"
             f"Watching: {cfg['target']}:{cfg['port']}\nRunbook: {RUNBOOK}\n")
        return 0

    status, details = check(cfg)
    log(f"status={status} doctorExit={details['doctorExit']} http=({details['http']})")
    if args.dry_run:
        print(details["doctor"])
        return 0 if status == "OK" else 1

    state = load_state()
    t = now()
    if status == "OK":
        if state.get("alerted"):
            send(cfg, *compose(cfg, "RECOVERED", status, details, state))
        save_state({"badStreak": 0, "alerted": False, "lastOk": t.isoformat()})
        return 0

    state["badStreak"] = state.get("badStreak", 0) + 1
    state.setdefault("badSince", t.strftime("%Y-%m-%d %H:%M:%S"))
    if not state.get("alerted") and state["badStreak"] >= cfg["failuresBeforeAlert"]:
        send(cfg, *compose(cfg, "ALERT", status, details, state))
        state.update(alerted=True, lastAlert=t.isoformat())
    elif state.get("alerted"):
        last = datetime.fromisoformat(state["lastAlert"])
        if (t - last).total_seconds() >= cfg["reminderHours"] * 3600:
            send(cfg, *compose(cfg, "REMINDER", status, details, state))
            state["lastAlert"] = t.isoformat()
    save_state(state)
    return 1


if __name__ == "__main__":
    sys.exit(main())
