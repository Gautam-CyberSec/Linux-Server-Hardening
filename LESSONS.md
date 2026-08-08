# Engineering Decisions &amp; Lessons Learned

Mistakes made while turning a manual hardening lab into a tested script, and
what each one changed. Every entry actually happened during development.

---

## 1. The script used bash syntax the test machine did not have

**What happened.** The first run of the unit suite failed nine of sixteen tests
with `${key,,}: bad substitution`.

**Why.** `${var,,}` is bash 4. macOS ships bash **3.2** and has since 2007,
because bash moved to GPLv3. The code targeted the deployment platform, Ubuntu,
and quietly excluded anyone developing on a Mac — which included the machine it
was written on.

**Fix.** Lowercasing moved into `awk`'s `tolower()` and `tr`. CI now runs the
unit suite on a **macOS runner** as well as Linux, so the constraint is enforced
rather than remembered.

**Principle.** *Target the oldest runtime a contributor may have, not the newest
one you happen to be on.* And enforce it in CI — a portability rule nobody checks
is a rule that decays.

---

## 2. `NO_COLOR` did not disable colour, and printed twelve errors while not doing it

**What happened.** Running with `NO_COLOR=1` produced twelve lines of
`unset: C_RESET: cannot unset: readonly variable` — and the output still had
escape codes in it.

**Why.** The colour variables were declared `readonly`, then the no-colour branch
tried to `unset` and redeclare them. Both operations fail on a readonly variable.
The failure was non-fatal, so the script carried on with the escape codes intact:
the feature was broken *and* noisy, and the noise was the only visible symptom.

**Fix.** Decide first, assign once, mark readonly afterwards.

**Principle.** *Make the decision before the assignment, not after.* A
constant that needs reassigning was never a constant — and a non-fatal error in
a loop is how a broken feature hides in plain sight.

---

## 3. A test that asserted on the wrong output

**What happened.** The integration suite failed with
`FAIL detected the authorised key for the sudo user`. But the same run showed
`ok PasswordAuthentication set to no` — which the script only does *after*
verifying a key. The guard had worked correctly.

**Why.** The assertion grepped for a message emitted by the `accounts` control,
while the test ran `--only ssh`. It was reading output that control never
produced.

**Fix.** Assert on `key verified for 'deploy'`, which the `ssh` control emits
itself.

**Principle.** *Assert on output the code path under test actually produces.*
This one failed loudly and was easy to find. The same mistake in a
loosely-written assertion would have passed silently and reported a guard as
tested when it never was.

---

## 4. An environment artefact that looked like a defect

**What happened.** `sshd -t accepts the generated configuration` failed with
`Missing privilege separation directory: /run/sshd`.

**Why.** `sshd -t` refuses to run without that directory. It exists on a real
host; a container has to create it. Nothing was wrong with the generated config —
the validator could not start.

**Fix.** Create `/run/sshd` in the test image and in the test itself, with a
comment recording why it is there.

**Principle.** *Separate "the thing is broken" from "the harness cannot run the
check".* Both show up as a red test. Fixing the first when it is really the
second means changing working code to satisfy a broken measurement.

---

## 5. Dynamic dispatch made the linter blind

**What happened.** `shellcheck` reported that every control function in the
script was never invoked — eight SC2329 findings covering essentially the whole
program.

**Why.** Controls were called by building the function name from a string:
`"control_$control"`. shellcheck cannot resolve that, so it treated every
function body as unreachable and stopped analysing them.

**Fix.** An explicit `case` statement. Longer by six lines, and every invocation
is now visible to both the linter and a reader.

**Principle.** *Cleverness that hides code from your tools costs more than the
lines it saves.* Indirect dispatch silently disabled static analysis across the
entire script.

---

## 6. `a && b || c` is not if-then-else

**What happened.** shellcheck flagged twelve SC2015 warnings in the integration
suite, plus three SC2319 for reading `$?` after a `[[ ]]` test.

**Why.** In `cmd && ok "..." || fail "..."`, the failure branch also runs when
`ok` itself returns non-zero. It happened to be safe here because `ok` ends in a
successful `printf` — safe by accident, not by design. And `$?` after `[[ ]]`
reflects the test, which is easy to invalidate by inserting any command between
them.

**Fix.** A `check <description> <status>` helper taking an already-evaluated
status, with explicit `if` statements where a condition is being tested.

**Principle.** *A test harness that can silently report the wrong result is worse
than no harness.* Assertions are the one place to prefer the verbose,
unambiguous form.

---

## What this repository does differently as a result

- The unit suite runs on **macOS bash 3.2** in CI, so bash-4 syntax cannot return.
- Config editing is written as pure functions over a file path, which is what
  lets sixteen tests run with no root, no sshd and no container.
- The claim that audit mode is read-only is asserted by comparing the checksum of
  `sshd_config` before and after a run, rather than stated in the README.
- All three paths of the password-authentication guard — refusal, override, and
  verified key — are asserted, because a safety guard nobody exercises is
  decoration.
