# Contributing

Issues and pull requests are welcome.

## Before opening a pull request

```bash
make check          # shellcheck, shfmt and the unit tests
make integration    # the container suite, if you have Docker
```

CI runs both, plus the unit tests on macOS bash 3.2.

## Conventions

- **Portable bash.** Target bash 3.2, not 4+. No `${var,,}`, no associative
  arrays, no `readarray`. CI enforces this on a macOS runner.
- **Anything that can lock a user out needs a guard and a test.** The password
  authentication gate is the model: check for evidence, refuse without it, allow
  an explicit override, and assert all three in `tests/integration.sh`.
- **New controls are audit-first.** A control must report accurately in audit
  mode before it is allowed to change anything.
- **Config editing stays pure.** Functions in `lib/sshd_config.sh` take a file
  path and touch nothing else, so they remain testable without root.
- **Comments explain why.** The reasoning behind an ordering or a guard is worth
  committing; a restatement of the code is not.
- **No credentials, real hostnames, or real IP addresses** in any committed file.

## Adding a control

1. Write `control_<name>` in `harden.sh`, audit path first.
2. Add it to `ALL_CONTROLS` and to the dispatch `case`.
3. Document it in the README table and in `ARCHITECTURE.md`.
4. Add an assertion to `tests/integration.sh`.

## Reporting a security issue

Do not open a public issue — see [SECURITY.md](SECURITY.md).
