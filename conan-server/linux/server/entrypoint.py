#!/usr/bin/env python3
"""Render ~/.conan_server/server.conf from environment variables, then exec
gunicorn serving conan_server's app. All credentials/config come from the
compose .env file, so the image itself stays generic and rebuildable anywhere."""

import os
import sys

TEMPLATE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "server.conf.template")
CONF_DIR = os.path.expanduser("~/.conan_server")


def die(message):
    sys.exit(f"[entrypoint] {message}")


def parse_users(raw):
    """CONAN_SERVER_USERS is "name:password" pairs separated by ";"."""
    users = []
    for pair in raw.split(";"):
        pair = pair.strip()
        if not pair:
            continue
        if ":" not in pair:
            die(f"CONAN_SERVER_USERS entry {pair!r} is not in name:password form")
        name, password = pair.split(":", 1)
        if not name.strip() or not password:
            die(f"CONAN_SERVER_USERS entry {pair!r} has an empty name or password")
        users.append((name.strip(), password))
    if not users:
        die("CONAN_SERVER_USERS defined no users")
    return users


def main():
    env = os.environ.get
    for var in ("CONAN_SERVER_USERS", "CONAN_JWT_SECRET", "CONAN_UPDOWN_SECRET",
                "CONAN_PUBLIC_HOSTNAME"):
        if not env(var):
            die(f"missing required environment variable {var}")

    users = parse_users(env("CONAN_SERVER_USERS"))
    every_user = ",".join(name for name, _ in users)

    with open(TEMPLATE) as f:
        conf = f.read().format(
            jwt_secret=env("CONAN_JWT_SECRET"),
            updown_secret=env("CONAN_UPDOWN_SECRET"),
            host_name=env("CONAN_PUBLIC_HOSTNAME"),
            public_port=env("CONAN_PUBLIC_PORT") or "9300",
            write_users=env("CONAN_WRITE_USERS") or every_user,
            read_users=env("CONAN_READ_USERS") or "?",
            users_block="\n".join(f"{name}: {password}" for name, password in users),
        )

    os.makedirs(CONF_DIR, exist_ok=True)
    conf_path = os.path.join(CONF_DIR, "server.conf")
    with open(conf_path, "w") as f:
        f.write(conf)
    os.chmod(conf_path, 0o600)

    # Serve the same Bottle app conan_server builds, but with gunicorn instead of
    # conan_server's own WSGIRef server: that one handles a single request at a
    # time with a listen backlog of 5, so while it streams one large binary,
    # concurrent CI runners' connects overflow the backlog and time out.
    # --preload builds the app (and runs conan's config migration) once, before
    # forking workers.
    workers = env("CONAN_SERVER_WORKERS") or "2"
    threads = env("CONAN_SERVER_THREADS") or "8"
    os.execvp("gunicorn", [
        "gunicorn",
        "--bind", "0.0.0.0:9300",
        "--worker-class", "gthread",
        "--workers", workers,
        "--threads", threads,
        "--timeout", "300",
        "--backlog", "2048",
        "--preload",
        "--access-logfile", "-",
        "conans.server.server_launcher:app",
    ])


if __name__ == "__main__":
    main()
