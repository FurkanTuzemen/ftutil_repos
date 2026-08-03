#!/usr/bin/env python3
"""Render ~/.conan_server/server.conf from environment variables, then exec
conan_server. All credentials/config come from the compose .env file, so the
image itself stays generic and rebuildable anywhere."""

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

    os.execvp("conan_server", ["conan_server"])


if __name__ == "__main__":
    main()
