#!/usr/bin/env bash
# Shared helpers: logging, change tracking, and file backup.
#
# Sourced by harden.sh and by the tests. Nothing here touches the system unless
# DRY_RUN is 0, which only harden.sh sets, and only when --apply was passed.

DRY_RUN="${DRY_RUN:-1}"
CHANGES_MADE=0
FINDINGS=0

# Colour is noise in CI logs and in redirected output. Decide before assigning:
# marking these readonly first and unsetting afterwards fails on every call and
# leaves the escape codes in place, which defeats the point.
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    C_RESET=$'\033[0m'
    C_DIM=$'\033[90m'
    C_RED=$'\033[31m'
    C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m'
    C_BOLD=$'\033[1m'
else
    C_RESET='' C_DIM='' C_RED='' C_GREEN='' C_YELLOW='' C_BOLD=''
fi
readonly C_RESET C_DIM C_RED C_GREEN C_YELLOW C_BOLD

log_section() { printf '\n%s%s%s\n' "$C_BOLD" "$1" "$C_RESET"; }
log_ok() { printf '  %s✓%s %s\n' "$C_GREEN" "$C_RESET" "$1"; }
log_info() { printf '  %s·%s %s\n' "$C_DIM" "$C_RESET" "$1"; }
log_warn() { printf '  %s!%s %s\n' "$C_YELLOW" "$C_RESET" "$1"; }
log_error() { printf '  %s✗%s %s\n' "$C_RED" "$C_RESET" "$1" >&2; }

# A control that is not satisfied. In audit mode this is the whole output; in
# apply mode it precedes the change.
finding() {
    FINDINGS=$((FINDINGS + 1))
    printf '  %s→%s %s\n' "$C_YELLOW" "$C_RESET" "$1"
}

changed() {
    CHANGES_MADE=$((CHANGES_MADE + 1))
    printf '  %s✓%s %s\n' "$C_GREEN" "$C_RESET" "$1"
}

die() {
    log_error "$1"
    exit "${2:-1}"
}

is_dry_run() { [[ "$DRY_RUN" == "1" ]]; }

require_root() {
    if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
        die "This must run as root. Re-run with sudo."
    fi
}

# Timestamped copy alongside the original, so a failed change can be reversed by
# hand without needing the repository.
backup_file() {
    local file="$1"
    [[ -f "$file" ]] || return 0
    local stamp
    stamp="$(date +%Y%m%d-%H%M%S)"
    local dest="${file}.bak-${stamp}"
    if is_dry_run; then
        log_info "would back up $file → $dest"
    else
        cp -p -- "$file" "$dest" || die "could not back up $file"
        log_info "backed up $file → $dest"
    fi
}

# Present on Debian/Ubuntu; the controls here assume apt and ufw.
detect_os() {
    if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        printf '%s %s' "${ID:-unknown}" "${VERSION_ID:-}"
    else
        printf 'unknown'
    fi
}

is_debian_like() {
    [[ -r /etc/os-release ]] || return 1
    grep -qiE '^(ID|ID_LIKE)=.*(debian|ubuntu)' /etc/os-release
}

have_cmd() { command -v "$1" >/dev/null 2>&1; }
