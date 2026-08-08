#!/usr/bin/env bash
# Pure sshd_config manipulation.
#
# Every function here takes a file path and never touches the running system, so
# the tests exercise the real code against fixtures rather than a mock. This is
# the part most likely to lock someone out of a server, so it is also the part
# that carries the most tests.

# Read the effective value of a directive: the first uncommented occurrence,
# which is what sshd itself honours. Later duplicates are ignored by sshd, and a
# tool that reports the last one will disagree with reality.
sshd_get_option() {
    local file="$1" key="$2"
    [[ -f "$file" ]] || return 1
    # ${key,,} would be simpler but is bash 4+, and macOS still ships bash 3.2 —
    # the tests have to run wherever a contributor is, not only on the target.
    awk -v k="$key" '
        BEGIN { k = tolower(k) }
        { line=$0; sub(/^[ \t]+/,"",line) }
        line ~ /^#/ { next }
        {
            split(line, f, /[ \t]+/)
            if (tolower(f[1]) == k) { print f[2]; exit }
        }
    ' "$file"
}

# Set a directive idempotently.
#
# Rewrites the first active occurrence in place, preserving position so that any
# Match blocks further down keep their meaning. Comments out any later duplicates
# rather than deleting them, so the original intent stays visible. Appends only
# when the directive is absent entirely.
sshd_set_option() {
    local file="$1" key="$2" value="$3"
    [[ -f "$file" ]] || return 1

    local tmp
    tmp="$(mktemp)" || return 1

    KEY="$key" VALUE="$value" awk '
        BEGIN { key = ENVIRON["KEY"]; k = tolower(key); v = ENVIRON["VALUE"] }
        {
            raw = $0
            line = raw
            sub(/^[ \t]+/, "", line)

            # A Match block scopes everything after it; directives inside one must
            # not be rewritten as if they were global.
            if (line ~ /^[Mm]atch[ \t]/) { in_match = 1 }

            if (!in_match && line !~ /^#/) {
                split(line, f, /[ \t]+/)
                if (tolower(f[1]) == k) {
                    if (!done) { print key " " v; done = 1 }
                    else { print "# superseded by hardening: " raw }
                    next
                }
            }
            print raw
        }
        END { if (!done) print key " " v }
    ' "$file" >"$tmp" || {
        rm -f "$tmp"
        return 1
    }

    # Preserve ownership and mode of the original.
    if [[ -f "$file" ]]; then
        chmod --reference="$file" "$tmp" 2>/dev/null || chmod 0600 "$tmp"
    fi
    mv -- "$tmp" "$file"
}

# True when the directive already has exactly this value and no active duplicate
# could override it.
sshd_option_is() {
    local file="$1" key="$2" want="$3" got
    got="$(sshd_get_option "$file" "$key")" || return 1
    [[ -n "$got" ]] || return 1
    [[ "$(printf '%s' "$got" | tr '[:upper:]' '[:lower:]')" == "$(printf '%s' "$want" | tr '[:upper:]' '[:lower:]')" ]]
}

# Validate a candidate config without touching the running service. Returns
# non-zero and prints sshd's own diagnostics when the file would be rejected.
sshd_config_is_valid() {
    local file="$1"
    if command -v sshd >/dev/null 2>&1; then
        sshd -t -f "$file" 2>&1
        return $?
    fi
    # No sshd available (a container, or a Mac running the tests) — treat as
    # unverifiable rather than silently passing.
    return 2
}
