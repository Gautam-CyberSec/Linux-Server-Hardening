#!/usr/bin/env bash
# Unit tests for lib/sshd_config.sh.
#
# These run against real fixture files, not mocks, and need neither root nor a
# running sshd — so CI executes the same code path a server would.
set -uo pipefail

# shellcheck source-path=SCRIPTDIR/..
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/sshd_config.sh
source "$HERE/../lib/sshd_config.sh"

PASS=0
FAIL=0
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

check() {
    local name="$1" want="$2" got="$3"
    if [[ "$want" == "$got" ]]; then
        PASS=$((PASS + 1))
        printf '  ok   %s\n' "$name"
    else
        FAIL=$((FAIL + 1))
        printf '  FAIL %s\n       want: %q\n       got:  %q\n' "$name" "$want" "$got"
    fi
}

fixture() {
    local f="$WORK/sshd_config.$RANDOM"
    printf '%s\n' "$1" >"$f"
    printf '%s' "$f"
}

# ── reading ──────────────────────────────────────────────────────────────────

f="$(fixture 'PermitRootLogin yes
PasswordAuthentication yes')"
check "reads a plain directive" "yes" "$(sshd_get_option "$f" PermitRootLogin)"

f="$(fixture '#PermitRootLogin prohibit-password
PermitRootLogin no')"
check "ignores commented lines" "no" "$(sshd_get_option "$f" PermitRootLogin)"

f="$(fixture '   PermitRootLogin   yes')"
check "tolerates leading and inner whitespace" "yes" "$(sshd_get_option "$f" PermitRootLogin)"

f="$(fixture 'permitrootlogin yes')"
check "matches the key case-insensitively" "yes" "$(sshd_get_option "$f" PermitRootLogin)"

# sshd honours the FIRST occurrence, so anything reporting the last one lies.
f="$(fixture 'PermitRootLogin yes
PermitRootLogin no')"
check "returns the first of duplicates, as sshd does" "yes" "$(sshd_get_option "$f" PermitRootLogin)"

# ── writing ──────────────────────────────────────────────────────────────────

f="$(fixture 'PermitRootLogin yes')"
sshd_set_option "$f" PermitRootLogin no
check "rewrites an existing directive" "no" "$(sshd_get_option "$f" PermitRootLogin)"

f="$(fixture 'Port 22')"
sshd_set_option "$f" PermitRootLogin no
check "appends when absent" "no" "$(sshd_get_option "$f" PermitRootLogin)"

f="$(fixture '#PermitRootLogin yes
Port 22')"
sshd_set_option "$f" PermitRootLogin no
check "leaves the commented original in place" "1" \
    "$(grep -c '^#PermitRootLogin yes' "$f")"

f="$(fixture 'PermitRootLogin yes
Port 22
PermitRootLogin yes')"
sshd_set_option "$f" PermitRootLogin no
check "comments out later duplicates" "1" \
    "$(grep -c '^# superseded by hardening' "$f")"
check "leaves exactly one active directive" "1" \
    "$(grep -cE '^PermitRootLogin ' "$f")"

f="$(fixture 'PermitRootLogin no')"
sshd_set_option "$f" PermitRootLogin no
sshd_set_option "$f" PermitRootLogin no
check "is idempotent across repeated runs" "1" \
    "$(grep -cE '^PermitRootLogin ' "$f")"

# A directive inside a Match block applies only to that match. Rewriting it as if
# it were global changes who the rule affects.
f="$(fixture 'PasswordAuthentication yes
Match User deploy
    PasswordAuthentication yes')"
sshd_set_option "$f" PasswordAuthentication no
check "does not rewrite inside a Match block" "1" \
    "$(grep -cE '^[[:space:]]+PasswordAuthentication yes' "$f")"
check "still sets the global directive" "no" \
    "$(sshd_get_option "$f" PasswordAuthentication)"

f="$(fixture 'Port 22')"
sshd_set_option "$f" PermitRootLogin no
check "preserves unrelated lines" "1" "$(grep -c '^Port 22' "$f")"

# ── comparison ───────────────────────────────────────────────────────────────

f="$(fixture 'PermitRootLogin NO')"
if sshd_option_is "$f" PermitRootLogin no; then r=yes; else r=no; fi
check "compares values case-insensitively" "yes" "$r"

f="$(fixture 'Port 22')"
if sshd_option_is "$f" PermitRootLogin no; then r=yes; else r=no; fi
check "reports absent directive as unset" "no" "$r"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
