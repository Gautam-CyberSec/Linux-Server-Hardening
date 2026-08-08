# Changelog

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this
project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned
- `fail2ban` control
- `sysctl` kernel parameter hardening
- CIS Benchmark mapping per control
- JSON output for fleet reporting

## [1.0.0] — 2026-08-08

The manual lab became an executable, tested baseline.

### Added
- `harden.sh` with four controls: `accounts`, `ssh`, `firewall`, `updates`.
- Audit mode as the default — read-only, exits non-zero on unmet controls so it
  works as a drift gate.
- `lib/sshd_config.sh`: `sshd_config` parsing and editing that honours first-wins
  duplicate semantics and leaves `Match` blocks alone.
- 16 unit tests requiring neither root nor a running sshd.
- Integration suite against Ubuntu 24.04 validating output with real `sshd -t`.
- CI: shellcheck, shfmt, unit tests on Linux and macOS bash 3.2, container
  integration, and a link check that rejects `github.com/blob/` image URLs.

### Security
- Password authentication is never disabled without a verified authorised key;
  `--allow-password-lockout` is required to override.
- Firewall rule derives from the effective `Port` in `sshd_config`.
- Timestamped backup before every edit; `sshd -t` validation before reload.

### Fixed
- Every screenshot in the original report used a `github.com/.../blob/...` URL,
  which serves `text/html`. None of them had ever rendered. Now relative paths.
- An unterminated code fence and several typos in the original report.

[Unreleased]: https://github.com/Gautam-CyberSec/Linux-Server-Hardening/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/Gautam-CyberSec/Linux-Server-Hardening/releases/tag/v1.0.0
