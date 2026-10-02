#!/usr/bin/env bash
# Encrypt .env (ci password + JWT/updown secrets) to .env.age with the public
# keys in secrets/age-recipients.txt, so the secrets can live in git. Run on
# the server after creating or changing .env, then commit .env.age.
# Decrypting needs the private key, which is not on this machine
# (see secrets/README.md).
#
#   ./encrypt-env.sh          # needs: age (apt install age); no root
set -euo pipefail

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

command_exists age || die "age is required: sudo apt install age"
recipients="$LINUX_DIR/../../secrets/age-recipients.txt"
[[ -r "$ENV_FILE" ]] || die "no readable $ENV_FILE"
[[ -r "$recipients" ]] || die "missing $recipients"

out="$LINUX_DIR/.env.age"
# Encryption is randomized, so every run changes .env.age - only run (and
# commit) it when .env actually changed.
age -R "$recipients" -a -o "$out.tmp" "$ENV_FILE"
mv "$out.tmp" "$out"
log "Wrote $out for $(grep -c '^age1' "$recipients") key(s) - commit it"
