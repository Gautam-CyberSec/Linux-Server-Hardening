# Security policy

## Reporting a vulnerability

Email [gautamdem@gmail.com](mailto:gautamdem@gmail.com). Please do not open a
public issue.

Include the configuration that triggers the problem and what an attacker gains.
Acknowledgement within 72 hours.

## What this script does with root

`apply` mode requires root and does exactly four privileged things:

| Action | Path |
|---|---|
| Edits SSH configuration | `/etc/ssh/sshd_config` (override with `--sshd-config`) |
| Configures the firewall | `ufw` via its own CLI |
| Installs packages | `ufw`, `unattended-upgrades` via `apt-get` |
| Writes apt configuration | `/etc/apt/apt.conf.d/20auto-upgrades` |

It does **not** fetch remote code, open a network listener, transmit anything
off the host, create or modify user accounts, or touch anything under `/home`
other than reading `authorized_keys` to check whether a key exists.

Audit mode is read-only. The integration suite asserts that an audit run leaves
`sshd_config` byte-for-byte unchanged.

## Controls in the script itself

| Control | Where |
|---|---|
| Audit is the default; changes need explicit `apply` | `harden.sh` |
| Password auth never disabled without a verified key | `control_ssh` |
| Firewall rule follows the real SSH port, not an assumed 22 | `effective_ssh_port` |
| Timestamped backup before every file edit | `backup_file` |
| `sshd -t` validation before any service reload | `sshd_config_is_valid` |
| Refuses to reload a config sshd rejects | `control_ssh` |

## Known risks

- **`--allow-password-lockout` can strand you.** It disables password
  authentication with no verified key present. Use it only with console access.
- **Backups sit next to the original.** `sshd_config.bak-*` is mode-preserved but
  lives in `/etc/ssh`. Remove old copies once a change is confirmed good.
- **A reload is not a restart.** Existing sessions survive; the check that
  matters is opening a *new* session before closing the current one.

## Scope of the lab material

`Report/` and `Screenshots/` document techniques exercised against a local
virtual machine owned by the author. Nothing there was run against a system the
author did not control.
