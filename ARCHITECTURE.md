# Architecture

Why this is a script rather than a checklist, and what was rejected on the way.

## Threat model

A small internet-facing Linux server: a VPS or EC2 instance running one
application, administered by one or two people. Not a fleet, not a regulated
environment.

The attacks that actually reach a box like this are unglamorous:

| Threat | Control |
|---|---|
| SSH password brute force | `PasswordAuthentication no`, `MaxAuthTries 3` |
| Direct root compromise | `PermitRootLogin no` + a sudo user |
| Exposed services nobody meant to publish | ufw default-deny inbound |
| Known CVEs left unpatched for months | `unattended-upgrades` |
| Credential-free accounts | `PermitEmptyPasswords no` |

Out of scope: a determined attacker with local access, supply-chain compromise
of the distribution, and anything requiring a kernel exploit. A hardening
baseline is a floor, not a ceiling.

## Audit and apply are separate modes

The first version applied changes immediately. That is the wrong default for a
tool people run on servers they cannot afford to break.

Audit is now the default, is read-only, and exits `1` when any control is unmet
— which makes it usable from cron or CI to detect drift. `apply` is a separate
word you have to type, and requires root.

The integration suite asserts that an audit run leaves `sshd_config` byte-for-byte
identical, because "read-only" is a claim worth testing rather than trusting.

## The lockout problem

Disabling `PasswordAuthentication` on a host where no SSH key works locks
everybody out permanently. On a VPS with console access that costs an hour; on a
box without it, the server is gone.

So that one directive is gated on evidence: a non-empty `authorized_keys`
belonging to a member of `sudo`, `admin` or `wheel`. No evidence, no change —
the script reports the finding and tells you to run `ssh-copy-id` first.

`--allow-password-lockout` exists because someone with serial console access has
a legitimate reason to override, and a tool that cannot be overridden gets
patched around. The flag is verbose on purpose.

Every other SSH directive tightens unconditionally, because none of them can
strand a user who already has key access.

## Reading sshd_config correctly

sshd honours the **first** occurrence of a directive and ignores later
duplicates. A tool that reports the last one will confidently disagree with the
running daemon.

So `sshd_get_option` returns the first uncommented match, and `sshd_set_option`
rewrites that occurrence in place while commenting out any later duplicates
rather than deleting them — the original intent stays visible in the file.

Two details that took a rewrite to get right:

- **`Match` blocks scope everything after them.** A `PasswordAuthentication`
  inside `Match User deploy` applies only to that user. Rewriting it as though
  it were global silently changes who the rule affects. The parser stops
  treating directives as global once it sees a `Match` line.
- **Position is preserved.** Appending to the end of the file would place the
  directive after any `Match` block, changing its meaning.

These functions take a file path and touch nothing else, which is what lets the
unit tests run the real implementation against fixtures — no root, no sshd, no
container.

## Ordering in the firewall control

`ufw --force enable` with a default-deny policy and no SSH rule drops the
connection it is running over.

The control therefore reads the effective `Port` from `sshd_config`, allows it,
and only then enables the firewall. Assuming port 22 is the specific mistake
this ordering exists to prevent.

## Validate before reload

An `sshd_config` that fails to parse takes SSH down when the service reloads.

Every edit is backed up to a timestamped `.bak-` file first. The candidate config
is then checked with `sshd -t`, and the service is reloaded only on success. If
sshd rejects it, the script aborts loudly and names the backup to restore.

Where `sshd` is unavailable — a container, a developer's Mac — validation returns
"unverifiable" rather than silently passing.

## Testing strategy

Three layers, because each catches something the others cannot:

| Layer | Runs | Catches |
|---|---|---|
| Unit (`tests/test_sshd_config.sh`) | Anywhere, no root | Parsing and editing logic: duplicates, comments, `Match` blocks, idempotency |
| Integration (`tests/integration.sh`) | Ubuntu 24.04 container | That it runs on the target OS, and that **real sshd accepts** the generated config |
| bash 3.2 (CI, macOS) | macOS runner | bash-4-only syntax that would break a contributor's local run |

The integration container is deliberately **not** `--privileged`. systemd and
netfilter are unavailable there, which keeps the tests honest about what can be
verified without a real init system rather than faking a pass.

## What is deliberately absent

- **Idempotent config management.** Ansible or Puppet does this better at fleet
  scale. This is for one server and no control plane.
- **A rollback command.** Timestamped backups plus `sshd -t` cover the realistic
  failure. A general rollback would need state tracking that this does not earn.
- **`fail2ban`.** Worthwhile, on the roadmap. Key-only authentication already
  removes most of what it defends against.
- **CIS Benchmark completeness.** The full benchmark is hundreds of controls.
  These four are the ones that matter on a single internet-facing box.
