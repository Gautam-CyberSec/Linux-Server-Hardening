#!/usr/bin/env bash
#
# Ubuntu/Debian server hardening — SSH, firewall, accounts, automatic updates.
#
# Audits by default and changes nothing. Every change requires `apply`, and the
# one change that can lock you out of a server refuses to run unless key-based
# access is already proven to work.
#
#   ./harden.sh                     audit the current host
#   ./harden.sh apply               apply every control
#   ./harden.sh apply --only ssh    apply one control
#
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$HERE/lib/common.sh"
# shellcheck source=lib/sshd_config.sh
source "$HERE/lib/sshd_config.sh"

VERSION="1.0.0"
SSHD_CONFIG="${SSHD_CONFIG:-/etc/ssh/sshd_config}"
SSH_PORT=""
ALLOW_LOCKOUT=0
MODE="audit"
ONLY=""

ALL_CONTROLS="accounts ssh firewall updates"

usage() {
    cat <<EOF
${C_BOLD}harden.sh${C_RESET} $VERSION — Ubuntu/Debian server hardening

${C_BOLD}USAGE${C_RESET}
  ./harden.sh [audit|apply] [options]

${C_BOLD}MODES${C_RESET}
  audit          Report which controls are unmet. Changes nothing. (default)
  apply          Make the changes. Requires root.

${C_BOLD}OPTIONS${C_RESET}
  --only LIST    Comma-separated subset of: $ALL_CONTROLS
  --ssh-port N   Expected SSH port; the firewall rule follows it (default 22)
  --sshd-config PATH
                 Override the sshd_config path, mainly for testing
  --allow-password-lockout
                 Permit disabling password authentication even when no
                 authorised key was found. You can be locked out. Do not use
                 this over a connection you cannot afford to lose.
  -h, --help     This message

${C_BOLD}CONTROLS${C_RESET}
  accounts       A non-root sudo user exists and has an authorised key
  ssh            Root login off, password auth off, sane auth limits
  firewall       ufw default-deny inbound, allow outbound, SSH permitted
  updates        unattended-upgrades installed and enabled

${C_BOLD}SAFETY${C_RESET}
  Audit mode is the default and is read-only. In apply mode every file is
  backed up before it is edited, the candidate sshd_config is validated with
  \`sshd -t\` before the service is reloaded, and password authentication is
  never disabled unless a usable key is found first.
EOF
}

# ── argument parsing ─────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
    case "$1" in
        audit | apply) MODE="$1" ;;
        --only)
            ONLY="${2:-}"
            shift
            ;;
        --ssh-port)
            SSH_PORT="${2:-}"
            shift
            ;;
        --sshd-config)
            SSHD_CONFIG="${2:-}"
            shift
            ;;
        --allow-password-lockout) ALLOW_LOCKOUT=1 ;;
        -h | --help)
            usage
            exit 0
            ;;
        *) die "unknown argument: $1  (try --help)" 2 ;;
    esac
    shift
done

if [[ "$MODE" == "apply" ]]; then
    DRY_RUN=0
    require_root
else
    DRY_RUN=1
fi

selected() {
    [[ -z "$ONLY" ]] && return 0
    [[ ",$ONLY," == *",$1,"* ]]
}

# ── helpers ──────────────────────────────────────────────────────────────────

# The SSH port actually in force, so the firewall rule cannot be opened on the
# wrong one — the classic way to lock yourself out while "hardening".
effective_ssh_port() {
    local p
    if [[ -n "$SSH_PORT" ]]; then
        printf '%s' "$SSH_PORT"
        return
    fi
    p="$(sshd_get_option "$SSHD_CONFIG" Port 2>/dev/null)"
    printf '%s' "${p:-22}"
}

sudo_users() {
    local group
    for group in sudo admin wheel; do
        getent group "$group" 2>/dev/null | awk -F: '{print $4}' | tr ',' '\n'
    done | grep -v '^$' | sort -u
}

# A user with a non-empty authorized_keys is the evidence that disabling
# password authentication will not strand you.
user_has_authorized_key() {
    local user="$1" home
    home="$(getent passwd "$user" 2>/dev/null | cut -d: -f6)"
    [[ -n "$home" && -s "$home/.ssh/authorized_keys" ]]
}

any_sudo_user_has_key() {
    local u
    while read -r u; do
        [[ -n "$u" ]] || continue
        if user_has_authorized_key "$u"; then
            printf '%s' "$u"
            return 0
        fi
    done < <(sudo_users)
    return 1
}

# ── controls ─────────────────────────────────────────────────────────────────

control_accounts() {
    log_section "Accounts"

    local users key_holder
    users="$(sudo_users)"

    if [[ -z "$users" ]]; then
        finding "no non-root sudo user exists — create one before disabling root login"
        log_info "adduser <name> && usermod -aG sudo <name>"
        return
    fi
    log_ok "sudo users: $(printf '%s' "$users" | tr '\n' ' ')"

    if key_holder="$(any_sudo_user_has_key)"; then
        log_ok "authorised key present for '$key_holder'"
    else
        finding "no sudo user has an authorised key — key-based login is not yet possible"
        log_info "from your workstation: ssh-copy-id <user>@<host>"
    fi
}

control_ssh() {
    log_section "SSH"

    if [[ ! -f "$SSHD_CONFIG" ]]; then
        log_warn "no sshd_config at $SSHD_CONFIG — skipping"
        return
    fi

    # PermitRootLogin and the auth limits are safe to tighten unconditionally.
    local -a keys=(PermitRootLogin PermitEmptyPasswords X11Forwarding MaxAuthTries LoginGraceTime)
    local -a vals=(no no no 3 30)

    local i key want got backed_up=0
    for i in "${!keys[@]}"; do
        key="${keys[$i]}"
        want="${vals[$i]}"
        if sshd_option_is "$SSHD_CONFIG" "$key" "$want"; then
            log_ok "$key $want"
            continue
        fi
        got="$(sshd_get_option "$SSHD_CONFIG" "$key")"
        finding "$key is ${got:-unset}, should be $want"
        if ! is_dry_run; then
            [[ "$backed_up" -eq 1 ]] || {
                backup_file "$SSHD_CONFIG"
                backed_up=1
            }
            sshd_set_option "$SSHD_CONFIG" "$key" "$want" && changed "$key → $want"
        fi
    done

    # PasswordAuthentication is the one that strands you. It is gated on evidence
    # that key-based access already works.
    if sshd_option_is "$SSHD_CONFIG" PasswordAuthentication no; then
        log_ok "PasswordAuthentication no"
    else
        finding "PasswordAuthentication is enabled"
        local holder=""
        holder="$(any_sudo_user_has_key || true)"
        if [[ -z "$holder" && "$ALLOW_LOCKOUT" -eq 0 ]]; then
            log_warn "refusing to disable it: no authorised key found for any sudo user"
            log_info "add a key first, or re-run with --allow-password-lockout if you"
            log_info "have console access and accept the risk"
        elif ! is_dry_run; then
            [[ "$backed_up" -eq 1 ]] || {
                backup_file "$SSHD_CONFIG"
                backed_up=1
            }
            sshd_set_option "$SSHD_CONFIG" PasswordAuthentication no &&
                changed "PasswordAuthentication → no (key verified for '${holder:-override}')"
        fi
    fi

    # Never reload a config sshd would reject.
    if ! is_dry_run && [[ "$CHANGES_MADE" -gt 0 ]]; then
        local out rc
        out="$(sshd_config_is_valid "$SSHD_CONFIG")"
        rc=$?
        case "$rc" in
            0) log_ok "sshd validated the new configuration" ;;
            2) log_warn "sshd not available — configuration left in place, unverified" ;;
            *)
                log_error "sshd rejected the new configuration:"
                printf '%s\n' "$out" >&2
                die "restore the .bak file next to $SSHD_CONFIG before reconnecting"
                ;;
        esac
        if have_cmd systemctl && [[ "$rc" -eq 0 ]]; then
            systemctl reload ssh 2>/dev/null ||
                systemctl reload sshd 2>/dev/null ||
                log_warn "reload the SSH service manually to apply"
        fi
    fi
}

control_firewall() {
    log_section "Firewall"

    if ! have_cmd ufw; then
        finding "ufw is not installed"
        if ! is_dry_run && is_debian_like; then
            DEBIAN_FRONTEND=noninteractive apt-get install -y -qq ufw >/dev/null &&
                changed "installed ufw"
        else
            log_info "apt-get install ufw"
            return
        fi
    fi

    local port
    port="$(effective_ssh_port)"

    if ufw status 2>/dev/null | grep -qi '^Status: active'; then
        log_ok "ufw is active"
    else
        finding "ufw is inactive"
    fi

    if ufw status 2>/dev/null | grep -q "$port"; then
        log_ok "SSH port $port is allowed"
    else
        finding "no rule allows SSH on port $port"
    fi

    if is_dry_run; then
        log_info "would set: default deny incoming, default allow outgoing, allow $port/tcp"
        return
    fi

    # Order matters: allow SSH before enabling default-deny, or the enable step
    # drops the connection it is running over.
    ufw --force default deny incoming >/dev/null && changed "default deny incoming"
    ufw --force default allow outgoing >/dev/null && changed "default allow outgoing"
    ufw allow "$port/tcp" >/dev/null && changed "allow $port/tcp (SSH)"
    ufw --force enable >/dev/null && changed "ufw enabled"
}

control_updates() {
    log_section "Automatic updates"

    if ! is_debian_like; then
        log_warn "not a Debian-like system — skipping"
        return
    fi

    if dpkg-query -W -f='${Status}' unattended-upgrades 2>/dev/null | grep -q "install ok installed"; then
        log_ok "unattended-upgrades is installed"
    else
        finding "unattended-upgrades is not installed"
        if ! is_dry_run; then
            DEBIAN_FRONTEND=noninteractive apt-get install -y -qq unattended-upgrades >/dev/null &&
                changed "installed unattended-upgrades"
        else
            return
        fi
    fi

    local conf=/etc/apt/apt.conf.d/20auto-upgrades
    if [[ -f "$conf" ]] && grep -q 'Unattended-Upgrade "1"' "$conf"; then
        log_ok "unattended upgrades are enabled"
    else
        finding "unattended upgrades are not enabled"
        if ! is_dry_run; then
            backup_file "$conf"
            cat >"$conf" <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
            changed "enabled unattended upgrades"
        fi
    fi
}

# ── main ─────────────────────────────────────────────────────────────────────

printf '%sharden.sh %s%s  ·  %s  ·  mode: %s\n' \
    "$C_BOLD" "$VERSION" "$C_RESET" "$(detect_os)" "$MODE"

# Dispatched explicitly rather than by building the function name from a string:
# indirect calls hide every invocation from shellcheck, which then reports the
# entire body of the script as unreachable.
for control in $ALL_CONTROLS; do
    selected "$control" || continue
    case "$control" in
        accounts) control_accounts ;;
        ssh) control_ssh ;;
        firewall) control_firewall ;;
        updates) control_updates ;;
        *) die "unknown control: $control" ;;
    esac
done

log_section "Summary"
if is_dry_run; then
    if [[ "$FINDINGS" -eq 0 ]]; then
        log_ok "every selected control is already satisfied"
    else
        printf '  %d control(s) unmet. Re-run as: sudo ./harden.sh apply\n' "$FINDINGS"
    fi
else
    printf '  %d change(s) applied, %d finding(s) seen.\n' "$CHANGES_MADE" "$FINDINGS"
    [[ "$CHANGES_MADE" -gt 0 ]] &&
        log_warn "verify you can open a NEW ssh session before closing this one"
fi

# Non-zero on unmet controls in audit mode makes this usable as a CI gate.
if is_dry_run && [[ "$FINDINGS" -gt 0 ]]; then exit 1; fi
exit 0
