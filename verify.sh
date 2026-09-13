#!/usr/bin/env bash
# Canonical offline gate for system-monitoring-site.
#
# Scope: tree soundness only. Deliberately EXCLUDED because they are runtime
# questions, not repo questions:
#   * live Ollama reachability / model benchmarks (network + model-backed)
#   * the interactive setup wizard flow (needs a TTY)
#   * a running backend on :7788 or a served dashboard
#
# Every set-examining leg FAILS on zero files examined, so a coverage gap can
# never read as a silent pass.
set -uo pipefail
cd "$(dirname "$0")"

rc=0
RAN=0
_FINISHED=0
pass() { echo "  PASS  $1"; }
fail() { echo "  FAIL  $1"; rc=1; }
leg() { echo "== $1 =="; RAN=$((RAN + 1)); }
# Gate-integrity failures must NOT report through fail()/finish(): a mutation of
# finish() is exactly what they exist to catch, and a check that reports through
# the machinery it inspects can be silenced by mutating that machinery. Disarm
# the trap, own the exit status outright.
_die() { trap - EXIT; echo "FAIL(gate-integrity): $1"; exit 2; }

# Two-sided MEASURED execution pin. Below = the gate short-circuited (a planted
# `exit 0`, a bare `exit`, an inline `true && exit 0` — all exit 0, so only an
# EXECUTION floor can own them; an rc!=0 branch cannot fire). Above = the pin is
# STALE after a leg was added, and must fail LOUDLY naming the bump rather than
# silently un-flooring the newest leg.
LEG_PIN=6

finish() {
  local st=$?
  [ "$_FINISHED" = 0 ] || return
  _FINISHED=1
  if [ "$st" -ne 0 ] && [ "$rc" -eq 0 ]; then
    echo "  FAIL  gate terminated early with status $st before reaching the verdict"
    rc=1
  fi
  if [ "$RAN" -lt "$LEG_PIN" ]; then
    echo "  FAIL  EXECUTION pin: only $RAN of $LEG_PIN legs ran — the gate short-circuited"
    rc=1
  elif [ "$RAN" -gt "$LEG_PIN" ]; then
    echo "  FAIL  $RAN legs ran but LEG_PIN=$LEG_PIN is STALE — bump it to $RAN"
    rc=1
  fi
  echo ""
  if [ "$rc" -eq 0 ]; then echo "VERIFY: PASS"; else echo "VERIFY: FAIL"; fi
  exit "$rc"
}
trap finish EXIT

# ---- GATE INTEGRITY CHECKS BELOW ----
# Everything above this marker is the machinery under inspection; the checks
# below read ONLY that region, so a check cannot match its own text (a
# self-inspecting grep that matches its own line reports green over a gutted
# subject). The scoping anchor is itself falsifiable: if the marker is missing,
# sed returns the WHOLE file, BODY_LINES == FILE_LINES, and the first check
# fires.
leg "gate integrity"
BODY=$(sed -n '1,/^# ---- GATE INTEGRITY CHECKS BELOW ----$/p' "$0")
BODY_LINES=$(printf '%s\n' "$BODY" | wc -l | tr -d ' ')
FILE_LINES=$(wc -l < "$0" | tr -d ' ')
[ "$BODY_LINES" -gt 0 ] && [ "$BODY_LINES" -lt "$FILE_LINES" ] \
  || _die "scoping anchor did not match — BODY is $BODY_LINES of $FILE_LINES lines"
pass "scoping anchor scopes to the machinery ($BODY_LINES of $FILE_LINES lines)"
# grep -qF throughout: this machinery is metacharacter-heavy and hand-escaping it
# for ERE is how a check fails closed against its own healthy subject.
printf '%s\n' "$BODY" | grep -qF 'trap finish EXIT' || _die "EXIT trap not installed"
printf '%s\n' "$BODY" | grep -qF '_FINISHED=1' || _die "finish() re-entry latch missing"
printf '%s\n' "$BODY" | grep -qF '[ "$_FINISHED" = 0 ] || return' \
  || _die "finish() re-entry guard line missing (the latch assignment alone is not the guard)"
printf '%s\n' "$BODY" | grep -qE '^LEG_PIN=[0-9]+$' || _die "LEG_PIN not declared"
printf '%s\n' "$BODY" | grep -qF 'VERIFY: FAIL' || _die "finish() cannot report a FAIL verdict"
# Anchored ERE, not -qF: the comment above quotes this line, and a fixed-string
# match would match the explanation instead of the code (an anchored pattern
# excludes any #-leading line).
printf '%s\n' "$BODY" | grep -qE '^[[:space:]]*exit "\$rc"$' \
  || _die "finish() does not exit with the roll-up status"
printf '%s\n' "$BODY" | grep -qF 'RAN=$((RAN + 1))' \
  || _die "leg() does not increment the execution counter"
pass "gate machinery intact (trap, re-entry guard, pin, verdict, exit status, counter)"

leg "shell syntax"
n=0
while IFS= read -r f; do
  [ -f "$f" ] || continue
  n=$((n+1))
  if zsh -n "$f" 2>/dev/null || bash -n "$f" 2>/dev/null; then
    pass "syntax $f"
  else
    fail "syntax $f"
  fi
done < <(git ls-files '*.sh')
if [ "$n" -eq 0 ]; then fail "no shell files examined (coverage gap)"; else echo "  ($n shell files)"; fi

leg "python syntax"
n=0
while IFS= read -r f; do
  [ -f "$f" ] || continue
  n=$((n+1))
  if python3 -m py_compile "$f" 2>/dev/null; then pass "syntax $f"; else fail "syntax $f"; fi
done < <(git ls-files '*.py')
if [ "$n" -eq 0 ]; then fail "no python files examined (coverage gap)"; else echo "  ($n python files)"; fi

leg "json syntax"
n=0
while IFS= read -r f; do
  [ -f "$f" ] || continue
  n=$((n+1))
  if python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$f" 2>/dev/null; then
    pass "json $f"
  else
    fail "json $f"
  fi
done < <(git ls-files '*.json')
if [ "$n" -eq 0 ]; then fail "no json files examined (coverage gap)"; else echo "  ($n json files)"; fi

leg "dashboard/config coherence"
# data.js declares the backend port; backend/main.py binds it. A drift here
# means a dashboard that silently shows nothing.
port_js=$(grep -oE "backend:[^,]*" data.js | grep -oE '127\.0\.0\.1:[0-9]+' | grep -oE '[0-9]+$' || true)
# Host-agnostic on purpose: pinning this to 127.0.0.1 would make a
# bind-to-0.0.0.0 change fail HERE ("could not read the port") instead of on
# the loopback test that actually owns that invariant — a misattributed FAIL.
port_py=$(grep -oE "port = '[0-9.]+', [0-9]+" backend/main.py | grep -oE '[0-9]+$' || true)
if [ -z "$port_js" ] || [ -z "$port_py" ]; then
  fail "could not read backend port from both data.js and backend/main.py"
elif [ "$port_js" = "$port_py" ]; then
  pass "backend port agrees ($port_js)"
else
  fail "backend port drift: data.js=$port_js backend/main.py=$port_py"
fi

leg "test suite"
# Two-sided pin on the tracked suite-FILE count (pitfall 21g). The runner below
# invokes ONE hardcoded suite path, so both directions are invisible without it:
# delete tests/test_monitor.py and the whole suite vanishes; ADD tests/test_x.py
# and it is silently never run (pitfall 19 — an allowlist cannot see new tests).
# Below the pin = deletion. Above = the pin is STALE and the new suite is not
# wired into the runner; both are hard failures naming the exact fix.
SUITE_FILES_PIN=1
if git rev-parse --git-dir >/dev/null 2>&1; then
  suite_files=$(git ls-files 'tests/test_*.py' | wc -l | tr -d ' ')
  suite_mode="git"
else
  suite_files=$(ls tests/test_*.py 2>/dev/null | wc -l | tr -d ' ')
  suite_mode="glob"
fi
if [ "$suite_files" -lt "$SUITE_FILES_PIN" ]; then
  fail "only $suite_files suite files ($suite_mode), pin is $SUITE_FILES_PIN — a suite was deleted"
elif [ "$suite_files" -gt "$SUITE_FILES_PIN" ]; then
  fail "$suite_files suite files ($suite_mode) but SUITE_FILES_PIN=$SUITE_FILES_PIN is STALE — bump it to $suite_files AND wire the new suite into the runner below, or it never runs"
else
  pass "suite files pinned at $SUITE_FILES_PIN ($suite_mode)"
fi
out=$(python3 tests/test_monitor.py 2>&1)
status=$?
ran=$(echo "$out" | grep -oE '^Ran [0-9]+ test' | grep -oE '[0-9]+' || echo 0)
# Expected count DERIVED from the file, so a collection gap (a test file that
# stops being run) fails instead of passing quietly.
expected=$(grep -cE '^\s+def test_' tests/test_monitor.py)
skipped=$(echo "$out" | grep -oE 'skipped=[0-9]+' | grep -oE '[0-9]+' || echo 0)
# Floor of 20: an emptied test file makes BOTH `ran` and `expected` zero, so
# `ran < expected` is false and the gate would report a green suite that
# asserted nothing. Found by tools/mutation_proof.sh — the mutant survived.
if [ "$expected" -lt 20 ]; then
  fail "only $expected tests defined (suite was gutted; expected >= 20)"
elif [ "$status" -ne 0 ]; then
  fail "unit suite exited $status"
  echo "$out" | tail -30
elif [ "$ran" -lt "$expected" ]; then
  fail "unit suite ran $ran of $expected defined tests (collection gap)"
elif [ "${skipped:-0}" -ne 0 ]; then
  fail "unit suite skipped $skipped tests — a skip is not a pass"
else
  pass "unit suite $ran/$expected, 0 skipped"
fi

# No verdict here on purpose: finish() (the EXIT trap) owns the execution pin,
# the verdict line and the exit status, so they run on EVERY exit path — a
# bottom-placed roll-up is skipped entirely by any short-circuit above it.
