#!/usr/bin/env bash
# Client-side check that a Conan remote is reachable and usable, using only
# curl (no Conan install needed). Run from any machine on the tailnet/LAN.
#
#   CONAN_PASSWORD=... ./smoke-test.sh http://100.85.113.90:9300 ci
#   ./smoke-test.sh http://ftbeepi:9300 ci          # prompts for password
#
# Checks: ping (no auth) -> login -> search -> that anonymous access is refused
# (CONAN_READ_USERS=? means authenticated users only).
set -euo pipefail

url="${1:?usage: $0 <remote-url> <user>}"; url="${url%/}"
user="${2:?usage: $0 <remote-url> <user>}"
password="${CONAN_PASSWORD:-}"
if [[ -z "$password" ]]; then
    read -rsp "Password for $user: " password; echo
fi

ok()  { printf '  [ OK ] %s\n' "$*"; }
bad() { printf '  [FAIL] %s\n' "$*"; exit 1; }

code="$(curl -s -m 10 -o /dev/null -w '%{http_code}' "$url/v1/ping" || true)"
if [[ "$code" == 200 ]]; then ok "ping $url"; else bad "ping $url -> HTTP ${code:-no answer} (server down, wrong address, or not on the tailnet?)"; fi

token="$(curl -fsS -m 10 -u "$user:$password" "$url/v2/users/authenticate" 2>/dev/null || true)"
if [[ -n "$token" ]]; then ok "login as $user"; else bad "login as $user rejected"; fi

result="$(curl -fsS -m 10 -H "Authorization: Bearer $token" "$url/v2/conans/search?q=*" || true)"
if [[ -n "$result" ]]; then ok "search: $result"; else bad "search failed"; fi

# Anonymous clients must not see packages. (On an empty server the search
# legitimately returns 200 with no results - nothing to permission-check.)
anon="$(curl -s -m 10 -w '\n%{http_code}' "$url/v2/conans/search?q=*" || true)"
anon_code="${anon##*$'\n'}"
if [[ "$anon_code" == 401 ]] || [[ "$anon" == *'"results": []'* ]]; then
    ok "anonymous clients see no packages (HTTP $anon_code)"
else
    printf '  [WARN] anonymous search returned HTTP %s with results - is CONAN_READ_USERS=* intended?\n' "$anon_code"
fi

echo "Remote is usable."
