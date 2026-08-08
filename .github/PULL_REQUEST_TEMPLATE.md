## What changed

<!-- One or two sentences. -->

## Why

<!-- The problem being solved. Link an issue if there is one. -->

## Checks

- [ ] `make check` passes (shellcheck, shfmt, unit tests)
- [ ] `make integration` passes, or CI will run it
- [ ] Targets bash 3.2 — no `${var,,}`, associative arrays, or `readarray`
- [ ] New behaviour has a test
- [ ] No credentials, real hostnames, or real IP addresses

## Lockout risk

<!-- Could this strand a user out of a server? If so, what guards it? -->

- [ ] No new way to lose access, or the change is gated and tested
