#!/usr/bin/env bash
# Integration tests — run inside the Ubuntu container built from tests/Dockerfile.
#
# The unit tests prove the config editing is correct in isolation. These prove the
# script runs on the target distribution and, critically, that what it writes is
# accepted by the real sshd rather than merely matching our own expectations.
set -uo pipefail
export NO_COLOR=1

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"

PASS=0
FAIL=0
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Takes an already-evaluated exit status rather than chaining `a && ok || no`,
# which runs the failure branch whenever the success branch returns non-zero.
check() {
    local desc="$1" status="$2" detail="${3:-}"
    if [[ "$status" -eq 0 ]]; then
        PASS=$((PASS + 1))
        printf '  ok   %s\n' "$desc"
    else
        FAIL=$((FAIL + 1))
        printf '  FAIL %s\n' "$desc"
        [[ -n "$detail" ]] && printf '       %s\n' "$detail"
    fi
    return 0
}

printf '\n== environment ==\n'
# shellcheck disable=SC1091  # exists in the container, not on a dev machine
printf '  %s\n' "$(. /etc/os-release && printf '%s' "$PRETTY_NAME")"
printf '  bash %s\n' "$BASH_VERSION"
printf '  %s\n' "$(ssh -V 2>&1)"

# ── the script runs on a real Ubuntu ─────────────────────────────────────────

printf '\n== audit on a stock system ==\n'
out="$("$ROOT/harden.sh" audit 2>&1)"
rc=$?
if [[ "$rc" -eq 0 || "$rc" -eq 1 ]]; then s=0; else s=1; fi
check "audit completes with a defined exit code ($rc)" "$s" "$out"

for control in Accounts SSH Firewall "Automatic updates"; do
    grep -q "$control" <<<"$out"
    check "control ran: $control" $?
done

# Audit must never modify anything.
before="$(md5sum /etc/ssh/sshd_config | cut -d' ' -f1)"
"$ROOT/harden.sh" audit >/dev/null 2>&1
after="$(md5sum /etc/ssh/sshd_config | cut -d' ' -f1)"
if [[ "$before" == "$after" ]]; then s=0; else s=1; fi
check "audit left sshd_config untouched" "$s"

# ── applying to a real sshd_config ───────────────────────────────────────────

printf '\n== apply, then validate with sshd itself ==\n'
cp /etc/ssh/sshd_config "$WORK/sshd_config"
printf 'PermitRootLogin yes\nPasswordAuthentication yes\nX11Forwarding yes\n' >>"$WORK/sshd_config"

# Give a sudo user a key so the lockout guard is satisfied legitimately, which
# exercises the detection path rather than bypassing it.
useradd -m -s /bin/bash -G sudo deploy 2>/dev/null || true
install -d -m 0700 -o deploy -g deploy /home/deploy/.ssh
ssh-keygen -q -t ed25519 -N '' -f "$WORK/id"
install -m 0600 -o deploy -g deploy "$WORK/id.pub" /home/deploy/.ssh/authorized_keys

out="$("$ROOT/harden.sh" apply --only ssh --sshd-config "$WORK/sshd_config" 2>&1)"
printf '%s\n' "$out" | sed 's/^/    /'

grep -qE '^PermitRootLogin no$' "$WORK/sshd_config"
check "PermitRootLogin set to no" $?

grep -qE '^PasswordAuthentication no$' "$WORK/sshd_config"
check "PasswordAuthentication set to no" $?

# control_ssh reports the holder it verified. The "authorised key present"
# line belongs to control_accounts, which --only ssh does not run.
grep -q "key verified for 'deploy'" <<<"$out"
check "verified the sudo user's key before disabling password auth" $?

# sshd -t refuses to run without its privilege separation directory. It exists
# on a real host; a container has to create it, and its absence is an artefact
# of the test environment rather than anything wrong with the config.
mkdir -p /run/sshd

# The point of the whole exercise: does the real daemon accept what we wrote?
sshd -t -f "$WORK/sshd_config" 2>"$WORK/err"
check "sshd -t accepts the generated configuration" $? "$(cat "$WORK/err")"

compgen -G "$WORK/sshd_config.bak-*" >/dev/null
check "a timestamped backup was written" $?

# ── idempotency ──────────────────────────────────────────────────────────────

printf '\n== idempotency ==\n'
sum1="$(md5sum "$WORK/sshd_config" | cut -d' ' -f1)"
"$ROOT/harden.sh" apply --only ssh --sshd-config "$WORK/sshd_config" >/dev/null 2>&1
sum2="$(md5sum "$WORK/sshd_config" | cut -d' ' -f1)"
if [[ "$sum1" == "$sum2" ]]; then s=0; else s=1; fi
check "second apply changed nothing" "$s"

count="$(grep -cE '^PermitRootLogin ' "$WORK/sshd_config")"
if [[ "$count" == "1" ]]; then s=0; else s=1; fi
check "exactly one active PermitRootLogin remains (found $count)" "$s"

# ── the lockout guard ────────────────────────────────────────────────────────

printf '\n== lockout guard ==\n'
rm -f /home/deploy/.ssh/authorized_keys
cp /etc/ssh/sshd_config "$WORK/nokey"
printf 'PasswordAuthentication yes\n' >>"$WORK/nokey"

"$ROOT/harden.sh" apply --only ssh --sshd-config "$WORK/nokey" >/dev/null 2>&1
if grep -qE '^PasswordAuthentication no$' "$WORK/nokey"; then
    check "refused to disable password auth without a verified key" 1 \
        "password auth was disabled with no key present — lockout risk"
else
    check "refused to disable password auth without a verified key" 0
fi

"$ROOT/harden.sh" apply --only ssh --sshd-config "$WORK/nokey" --allow-password-lockout >/dev/null 2>&1
grep -qE '^PasswordAuthentication no$' "$WORK/nokey"
check "--allow-password-lockout overrides the guard" $?

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
