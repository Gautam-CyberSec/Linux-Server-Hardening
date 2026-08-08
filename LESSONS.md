# Engineering Decisions &amp; Lessons Learned

Mistakes made while turning a manual hardening lab into a tested script, and what
each one changed. Every entry below actually happened during development; none
are illustrative.

Each lesson records **Problem**, **Cause**, **Discovery**, **Fix** and the
**Engineering Principle** that now prevents it.

---

## 1. The script used bash syntax the development machine did not have

**Problem**
The first run of the unit suite failed nine of sixteen tests with
`${key,,}: bad substitution`.

**Cause**
`${var,,}` is bash 4. macOS ships bash **3.2** and has since 2007, because bash
moved to GPLv3. The code was written against the deployment target — Ubuntu, bash
5 — and quietly excluded anyone developing on a Mac, including the machine it was
written on.

**Discovery**
Immediately, on the first local execution of `tests/test_sshd_config.sh`. The
failure was loud and specific, which is the best case; the same assumption in
code without a test would have shipped.

**Fix**
Lowercasing moved into `awk`'s `tolower()` and `tr`. CI now runs the unit suite on
a **macOS runner** in addition to Linux, so the constraint is enforced rather than
remembered.

**Engineering Principle**
*Target the oldest runtime a contributor may have, not the newest one you happen
to be on — and enforce it in CI.* A portability rule nobody checks decays into a
comment.

---

## 2. `NO_COLOR` did not disable colour, and printed twelve errors while failing to

**Problem**
Running with `NO_COLOR=1` produced twelve lines of
`unset: C_RESET: cannot unset: readonly variable`, and the output still contained
ANSI escape codes.

**Cause**
The colour variables were declared `readonly`, and the no-colour branch then tried
to `unset` and redeclare them. Both operations fail on a readonly variable. The
failures were non-fatal, so the script continued with the escape codes intact —
the feature was broken *and* noisy, and only the noise was visible.

**Discovery**
Found while capturing genuine audit output for the README. The intent was to get
clean text to quote; the twelve error lines appeared instead. Documentation work
surfaced a code defect.

**Fix**
Decide the colour mode first, assign once, mark readonly afterwards.

**Engineering Principle**
*Make the decision before the assignment, not after.* A constant that needs
reassigning was never a constant — and a non-fatal error inside a branch is how a
broken feature hides in plain sight.

---

## 3. A test that asserted on output the tested path never produced

**Problem**
The integration suite failed with
`FAIL detected the authorised key for the sudo user`, while the same run showed
`ok PasswordAuthentication set to no` — which the script only does *after*
verifying a key. The guard had worked correctly; the test was wrong.

**Cause**
The assertion grepped for a message emitted by the `accounts` control, while the
test invoked `--only ssh`. It was searching output that control never generated.

**Discovery**
The integration job in CI, on the first push. Contradictory results in the same
log made it clear the guard was fine and the assertion was not.

**Fix**
Assert on `key verified for 'deploy'`, which the `ssh` control emits itself.

**Engineering Principle**
*Assert on output the code path under test actually produces.* This failure was
loud and easy to find. The same mistake in a looser assertion would have passed
silently and reported a safety guard as tested when it never was.

---

## 4. An environment artefact that looked like a defect

**Problem**
`sshd -t accepts the generated configuration` failed with
`Missing privilege separation directory: /run/sshd`.

**Cause**
`sshd -t` refuses to run without that directory. It exists on a real host; a
container must create it. Nothing was wrong with the generated configuration —
the validator could not start.

**Discovery**
The integration job in CI. The distinction was only visible because the assertion
captured and printed sshd's own stderr rather than just recording a pass or fail.

**Fix**
Create `/run/sshd` in the test image and again in the test, with a comment
recording that it is a container requirement rather than a product one.

**Engineering Principle**
*Separate "the thing is broken" from "the harness cannot run the check".* Both
appear as a red test. Fixing the first when it is really the second means changing
working code to satisfy a broken measurement — and capturing stderr is what makes
the difference visible.

---

## 5. Dynamic dispatch made the linter blind to the whole program

**Problem**
`shellcheck` reported eight SC2329 findings — every control function "never
invoked" — covering essentially the entire script.

**Cause**
Controls were called by building the function name from a string:
`"control_$control"`. shellcheck cannot resolve that, so it treated every function
body as unreachable and stopped analysing them.

**Discovery**
Local `shellcheck -x` run before the first commit. The finding looked like noise
at first; reading it properly showed static analysis had been silently disabled
across the file.

**Fix**
An explicit `case` statement. Six lines longer, and every invocation is now
visible to both the linter and a reader.

**Engineering Principle**
*Cleverness that hides code from your tools costs more than the lines it saves.*
Indirect dispatch turned off analysis for the entire script while the linter still
reported "success" at the summary level.

---

## 6. `a && b || c` is not if-then-else

**Problem**
`shellcheck` flagged twelve SC2015 warnings in the integration suite, plus three
SC2319 for reading `$?` immediately after a `[[ ]]` test.

**Cause**
In `cmd && ok "..." || fail "..."`, the failure branch also runs whenever `ok`
itself returns non-zero. It happened to be safe here because `ok` ends in a
successful `printf` — safe by accident rather than by design. Separately, `$?`
after `[[ ]]` reflects the test result and is invalidated by inserting any command
between them.

**Discovery**
Local `shellcheck` run. Both are informational-severity findings that are easy to
wave away; the reason not to is that the affected code is the test harness itself.

**Fix**
A `check <description> <status>` helper taking an already-evaluated status, with
explicit `if` statements wherever a condition is being tested.

**Engineering Principle**
*A test harness that can silently report the wrong result is worse than no
harness.* Assertions are the one place to prefer the verbose, unambiguous form
over the compact one.

---

## What this repository does differently as a result

- The unit suite runs on **macOS bash 3.2** in CI, so bash-4 syntax cannot return.
- Config editing is written as pure functions over a file path, which is what lets
  sixteen tests run with no root, no sshd and no container.
- The claim that audit mode is read-only is asserted by comparing the checksum of
  `sshd_config` before and after a run, rather than stated in the README.
- All three paths of the password-authentication guard — refusal, override, and
  verified key — are asserted, because a safety guard nobody exercises is
  decoration.
- Test assertions capture and print the underlying tool's stderr, so an
  environment problem can be told apart from a product defect.
